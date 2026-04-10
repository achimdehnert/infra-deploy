#!/usr/bin/env bash
# /opt/scripts/rotate-key.sh — Rotate API keys and reload containers safely
#
# Modes:
#   rotate-key.sh <APP_PATH>                                  Reload app containers (env already updated)
#   rotate-key.sh <APP_PATH> <KEY> <VALUE>                    Update key in app .env + reload
#   rotate-key.sh --all <KEY> <VALUE>                         Rotate key in ALL per-app .env files
#   rotate-key.sh --shared <KEY> <VALUE>                      Update key in shared-secrets + reload all dependent apps
#   rotate-key.sh --shared <KEY> --from-file /tmp/new_key     Read value from file (secure, no CLI args)
#   rotate-key.sh --shared-reload                             Reload all apps using shared-secrets (key already updated)
#   rotate-key.sh --dry-run --shared <KEY> <VALUE>            Show what would happen without executing
#
# ADR-159: Shared secrets live in /opt/shared-secrets/api-keys.env
#          Per-app secrets live in /opt/<app>/.env or .env.prod
#
# Key insight: `docker compose restart` does NOT re-read .env files.
# Only `docker compose up -d --force-recreate` picks up new env values.
# This script uses --no-deps to skip infra services (DB, Redis, etc).
set -euo pipefail

# --- Configuration ---
SHARED_SECRETS_FILE="/opt/shared-secrets/api-keys.env"
INFRA_PATTERN="(db|postgres|redis|cache|minio|rabbit|mailpit)"
DRY_RUN=false
ERRORS=0
RELOADED=0

# --- Helpers ---
log_info()  { echo "  $*"; }
log_ok()    { echo "  ✅ $*"; }
log_warn()  { echo "  ⚠️  $*"; }
log_skip()  { echo "  ⏭️  $*"; }
log_err()   { echo "  ❌ $*"; ERRORS=$((ERRORS + 1)); }

# Find compose file for an app directory
find_compose_file() {
  local app_path="$1"
  if [[ -f "$app_path/docker-compose.prod.yml" ]]; then
    echo "docker-compose.prod.yml"
  elif [[ -f "$app_path/docker-compose.yml" ]]; then
    echo "docker-compose.yml"
  fi
}

# Find env file for an app directory (.env or .env.prod)
find_env_file() {
  local app_path="$1"
  for f in "$app_path/.env" "$app_path/.env.prod"; do
    [[ -f "$f" ]] && echo "$f" && return
  done
}

# Check if an app uses shared-secrets in its compose file
uses_shared_secrets() {
  local app_path="$1"
  local compose_file
  compose_file=$(find_compose_file "$app_path")
  [[ -n "$compose_file" ]] && grep -q "shared-secrets" "$app_path/$compose_file" 2>/dev/null
}

# Recreate only app services (skip DB, Redis, etc.)
reload_app_services() {
  local APP_PATH="$1"
  local APP_NAME
  APP_NAME=$(basename "$APP_PATH")

  [[ -d "$APP_PATH" ]] || { log_skip "$APP_PATH not found"; return 1; }

  local COMPOSE_FILE
  COMPOSE_FILE=$(find_compose_file "$APP_PATH")
  [[ -n "$COMPOSE_FILE" ]] || { log_skip "$APP_NAME — no compose file"; return 1; }

  # Identify app services (exclude infra)
  cd "$APP_PATH"
  local ALL_SERVICES APP_SERVICES=""
  ALL_SERVICES=$(docker compose -f "$COMPOSE_FILE" config --services 2>/dev/null)
  for svc in $ALL_SERVICES; do
    if ! echo "$svc" | grep -qiE "$INFRA_PATTERN"; then
      APP_SERVICES="$APP_SERVICES $svc"
    fi
  done

  if [[ -z "${APP_SERVICES// /}" ]]; then
    log_warn "$APP_NAME — no app services found"
    return 0
  fi

  if $DRY_RUN; then
    log_info "[DRY-RUN] Would recreate:$APP_SERVICES"
    return 0
  fi

  # Recreate only app services (DB/Redis stay running)
  log_info "🔄 Recreating:$APP_SERVICES"
  docker compose -f "$COMPOSE_FILE" up -d --force-recreate --no-deps $APP_SERVICES 2>&1 \
    | grep -E "Recreat|Start|Running" || true
  RELOADED=$((RELOADED + 1))

  # Quick health check
  sleep 3
  local UNHEALTHY
  UNHEALTHY=$(docker compose -f "$COMPOSE_FILE" ps 2>/dev/null | grep -iE "unhealthy|exit" || true)
  if [[ -n "$UNHEALTHY" ]]; then
    log_warn "$APP_NAME — unhealthy containers:"
    echo "$UNHEALTHY"
  else
    log_ok "$APP_NAME — healthy"
  fi
}

# Update a key in a specific env file
update_key_in_file() {
  local ENV_FILE="$1"
  local KEY_NAME="$2"
  local NEW_VALUE="$3"

  if ! grep -q "^${KEY_NAME}=" "$ENV_FILE" 2>/dev/null; then
    return 1  # key not present
  fi

  if $DRY_RUN; then
    log_info "[DRY-RUN] Would update $KEY_NAME in $ENV_FILE"
  else
    sed -i "s|^${KEY_NAME}=.*|${KEY_NAME}=${NEW_VALUE}|" "$ENV_FILE"
    log_ok "Updated $KEY_NAME in $ENV_FILE"
  fi
  return 0
}

# Read value from file (--from-file support)
read_value_from_file() {
  local filepath="$1"
  [[ -f "$filepath" ]] || { echo "ERROR: File not found: $filepath" >&2; exit 1; }
  tr -d '\n' < "$filepath"
}

# --- Mode: Single app ---
mode_single_app() {
  local APP_PATH="$1"
  local KEY_NAME="${2:-}"
  local NEW_VALUE="${3:-}"
  local APP_NAME
  APP_NAME=$(basename "$APP_PATH")

  echo "── $APP_NAME ──"

  # If key+value provided, update per-app .env
  if [[ -n "$KEY_NAME" && -n "$NEW_VALUE" ]]; then
    local ENV_FILE
    ENV_FILE=$(find_env_file "$APP_PATH")
    if [[ -z "$ENV_FILE" ]]; then
      log_err "$APP_NAME — no .env file found"
      return 1
    fi
    if ! update_key_in_file "$ENV_FILE" "$KEY_NAME" "$NEW_VALUE"; then
      log_skip "$KEY_NAME not in $APP_NAME .env"
      return 0
    fi
  fi

  reload_app_services "$APP_PATH"
}

# --- Mode: All per-app .env files ---
mode_all_apps() {
  local KEY_NAME="$1"
  local NEW_VALUE="$2"

  echo "═══════════════════════════════════════════════"
  echo "Rotating $KEY_NAME across ALL per-app .env files"
  echo "═══════════════════════════════════════════════"

  for app_dir in /opt/*/; do
    [[ -n "$(find_compose_file "$app_dir")" ]] || continue
    local app
    app=$(basename "$app_dir")
    echo ""
    echo "── $app ──"
    local ENV_FILE
    ENV_FILE=$(find_env_file "$app_dir")
    if [[ -n "$ENV_FILE" ]] && grep -q "^${KEY_NAME}=" "$ENV_FILE" 2>/dev/null; then
      update_key_in_file "$ENV_FILE" "$KEY_NAME" "$NEW_VALUE"
      reload_app_services "$app_dir" || true
    else
      log_skip "$KEY_NAME not in $app"
    fi
  done

  print_summary "$KEY_NAME"
}

# --- Mode: Shared secrets (ADR-159) ---
mode_shared() {
  local KEY_NAME="$1"
  local NEW_VALUE="$2"

  echo "═══════════════════════════════════════════════"
  echo "Rotating SHARED secret: $KEY_NAME (ADR-159)"
  echo "Target: $SHARED_SECRETS_FILE"
  echo "═══════════════════════════════════════════════"

  # Verify shared secrets file exists
  if [[ ! -f "$SHARED_SECRETS_FILE" ]]; then
    log_err "$SHARED_SECRETS_FILE not found"
    exit 1
  fi

  # Update key in shared secrets
  if ! update_key_in_file "$SHARED_SECRETS_FILE" "$KEY_NAME" "$NEW_VALUE"; then
    log_err "$KEY_NAME not found in $SHARED_SECRETS_FILE"
    echo ""
    echo "Available keys:"
    grep "^[A-Z]" "$SHARED_SECRETS_FILE" | cut -d= -f1 | sed 's/^/  - /'
    exit 1
  fi

  echo ""
  echo "Reloading all apps that reference shared-secrets..."
  mode_shared_reload
}

# --- Mode: Shared reload (all apps using shared-secrets) ---
mode_shared_reload() {
  local found=0

  for app_dir in /opt/*/; do
    uses_shared_secrets "$app_dir" || continue
    local app
    app=$(basename "$app_dir")
    found=$((found + 1))
    echo ""
    echo "── $app ──"
    reload_app_services "$app_dir" || true
  done

  if [[ $found -eq 0 ]]; then
    log_warn "No apps reference $SHARED_SECRETS_FILE"
  fi

  print_summary "shared-secrets"
}

# --- Summary ---
print_summary() {
  local context="${1:-}"
  echo ""
  echo "═══════════════════════════════════════════════"
  if [[ $ERRORS -gt 0 ]]; then
    echo "⚠️  Done ($context) — $RELOADED reloaded, $ERRORS errors"
  else
    echo "✅ Done ($context) — $RELOADED apps reloaded, 0 errors"
  fi
  echo "═══════════════════════════════════════════════"
}

# --- Main ---
# Parse --dry-run flag
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "🏜️  DRY-RUN MODE — no changes will be made"
  echo ""
  shift
fi

case "${1:-}" in
  --shared)
    KEY_NAME="${2:?Usage: rotate-key.sh --shared <KEY> <VALUE|--from-file PATH>}"
    if [[ "${3:-}" == "--from-file" ]]; then
      NEW_VALUE=$(read_value_from_file "${4:?--from-file requires a file path}")
    else
      NEW_VALUE="${3:?Usage: rotate-key.sh --shared <KEY> <VALUE|--from-file PATH>}"
    fi
    mode_shared "$KEY_NAME" "$NEW_VALUE"
    ;;
  --shared-reload)
    echo "═══════════════════════════════════════════════"
    echo "Reloading all apps using shared-secrets (ADR-159)"
    echo "═══════════════════════════════════════════════"
    mode_shared_reload
    ;;
  --all)
    KEY_NAME="${2:?Usage: rotate-key.sh --all <KEY> <VALUE>}"
    NEW_VALUE="${3:?Usage: rotate-key.sh --all <KEY> <VALUE>}"
    mode_all_apps "$KEY_NAME" "$NEW_VALUE"
    ;;
  --help|-h)
    head -12 "$0" | tail -11
    echo ""
    echo "Shared secrets file: $SHARED_SECRETS_FILE"
    echo "Apps using shared-secrets:"
    for d in /opt/*/; do
      uses_shared_secrets "$d" && echo "  - $(basename "$d")"
    done 2>/dev/null || true
    ;;
  /opt/*)
    mode_single_app "$@"
    ;;
  *)
    echo "Usage: rotate-key.sh [--dry-run] <MODE>"
    echo ""
    echo "  <APP_PATH>                          Reload app containers"
    echo "  <APP_PATH> <KEY> <VALUE>            Update per-app .env + reload"
    echo "  --all <KEY> <VALUE>                 Rotate in ALL per-app .env files"
    echo "  --shared <KEY> <VALUE>              Update shared-secrets + reload dependent apps"
    echo "  --shared <KEY> --from-file <PATH>   Read value from file (secure)"
    echo "  --shared-reload                     Reload all shared-secrets apps"
    echo "  --dry-run ...                       Preview without executing"
    echo "  --help                              Show help + list dependent apps"
    exit 1
    ;;
esac
