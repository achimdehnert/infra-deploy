#!/usr/bin/env bash
# /opt/scripts/rotate-key.sh — Rotate a key in .env and reload only app containers
# Usage: rotate-key.sh <APP_PATH> <KEY_NAME> <NEW_VALUE>
#    or: rotate-key.sh <APP_PATH>                          (just reload, .env already updated)
#    or: rotate-key.sh --all <KEY_NAME> <NEW_VALUE>        (rotate in ALL apps)
#
# Examples:
#   rotate-key.sh /opt/writing-hub OPENAI_API_KEY sk-new-key-here
#   rotate-key.sh /opt/writing-hub                          # .env already edited manually
#   rotate-key.sh --all OPENAI_API_KEY sk-new-key-here      # rotate across all apps
#
# Key insight: `docker compose restart` does NOT re-read .env files.
# Only `docker compose up -d --force-recreate` picks up new env values.
# This script uses --no-deps to skip infra services (DB, Redis, etc).
set -euo pipefail

# Infra service patterns — these are NEVER recreated on key rotation
INFRA_PATTERN="(db|postgres|redis|cache|minio|rabbit|mailpit)"

rotate_app() {
  local APP_PATH="$1"
  local KEY_NAME="${2:-}"
  local NEW_VALUE="${3:-}"
  local APP_NAME=$(basename "$APP_PATH")

  [[ -d "$APP_PATH" ]] || { echo "SKIP: $APP_PATH not found"; return 1; }

  # Find compose file
  local COMPOSE_FILE=""
  if [[ -f "$APP_PATH/docker-compose.prod.yml" ]]; then
    COMPOSE_FILE="docker-compose.prod.yml"
  elif [[ -f "$APP_PATH/docker-compose.yml" ]]; then
    COMPOSE_FILE="docker-compose.yml"
  else
    echo "SKIP: $APP_NAME — no compose file"
    return 1
  fi

  # Find env file
  local ENV_FILE=""
  for f in "$APP_PATH/.env" "$APP_PATH/.env.prod"; do
    [[ -f "$f" ]] && ENV_FILE="$f" && break
  done

  # Step 1: Update key in .env (if key+value provided)
  if [[ -n "$KEY_NAME" && -n "$NEW_VALUE" ]]; then
    if [[ -z "$ENV_FILE" ]]; then
      echo "ERROR: $APP_NAME — no .env file found"
      return 1
    fi
    if grep -q "^${KEY_NAME}=" "$ENV_FILE"; then
      sed -i "s|^${KEY_NAME}=.*|${KEY_NAME}=${NEW_VALUE}|" "$ENV_FILE"
      echo "  ✅ Updated $KEY_NAME in $ENV_FILE"
    else
      echo "  ⏭️  $KEY_NAME not in $APP_NAME .env — skipping"
      return 0
    fi
  fi

  # Step 2: Identify app services (exclude infra)
  cd "$APP_PATH"
  local ALL_SERVICES=$(docker compose -f "$COMPOSE_FILE" config --services 2>/dev/null)
  local APP_SERVICES=""
  for svc in $ALL_SERVICES; do
    if ! echo "$svc" | grep -qiE "$INFRA_PATTERN"; then
      APP_SERVICES="$APP_SERVICES $svc"
    fi
  done

  if [[ -z "$APP_SERVICES" ]]; then
    echo "  ⚠️  $APP_NAME — no app services found"
    return 0
  fi

  # Step 3: Recreate only app services (DB/Redis stay running)
  echo "  🔄 Recreating:$APP_SERVICES"
  docker compose -f "$COMPOSE_FILE" up -d --force-recreate --no-deps $APP_SERVICES 2>&1 | grep -E "Recreat|Start|Running"

  # Step 4: Quick health check
  sleep 3
  local UNHEALTHY=$(docker compose -f "$COMPOSE_FILE" ps 2>/dev/null | grep -iE "unhealthy|exit" || true)
  if [[ -n "$UNHEALTHY" ]]; then
    echo "  ⚠️  $APP_NAME — unhealthy containers detected!"
    echo "$UNHEALTHY"
  else
    echo "  ✅ $APP_NAME — all containers healthy"
  fi
}

# --- Main ---
if [[ "${1:-}" == "--all" ]]; then
  KEY_NAME="${2:?KEY_NAME required for --all}"
  NEW_VALUE="${3:?NEW_VALUE required for --all}"
  echo "═══════════════════════════════════════════════"
  echo "Rotating $KEY_NAME across ALL apps"
  echo "═══════════════════════════════════════════════"
  for app_dir in /opt/*/; do
    [[ -f "$app_dir/docker-compose.prod.yml" || -f "$app_dir/docker-compose.yml" ]] || continue
    app=$(basename "$app_dir")
    echo ""
    echo "── $app ──"
    rotate_app "$app_dir" "$KEY_NAME" "$NEW_VALUE" || true
  done
  echo ""
  echo "═══════════════════════════════════════════════"
  echo "✅ Key rotation complete"
else
  APP_PATH="${1:?Usage: rotate-key.sh <APP_PATH> [KEY_NAME] [NEW_VALUE]}"
  rotate_app "$APP_PATH" "${2:-}" "${3:-}"
fi
