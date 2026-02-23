#!/usr/bin/env bash
# health-check.sh — Health check for platform services
# Usage: health-check.sh [service]
# If service is empty, checks all services.
#
# Exit code: 0 = all healthy, 1 = one or more unhealthy

set -euo pipefail

SERVICE="${1:-}"

STATE_DIR="/opt/deploy/production/.deployed"
LOG_FILE="${STATE_DIR}/deploy.log"

# --- Service registry (mirrors ADR-021 §2.3) ---
declare -A HEALTH_URL=(
  [bfagent]="https://bfagent.iil.pet/healthz/"
  [risk-hub]="https://demo.schutztat.de/healthz/"
  [travel-beat]="https://drifttales.app/healthz/"
  [weltenhub]="https://weltenforger.com/healthz/"
  [dev-hub]="https://devhub.iil.pet/livez/"
)

declare -A LOCAL_PORT=(
  [bfagent]="8088"
  [risk-hub]="8090"
  [travel-beat]="8002"
  [weltenhub]="8081"
  [dev-hub]="8085"
)

mkdir -p "$STATE_DIR"

FAILED=()

check_service() {
  local svc="$1"
  local url="${HEALTH_URL[$svc]:-}"
  local port="${LOCAL_PORT[$svc]:-}"

  if [[ -z "$url" ]]; then
    echo "SKIP $svc (no health URL configured)"
    return 0
  fi

  # Try local port first (faster, no DNS)
  local local_ok=false
  if [[ -n "$port" ]]; then
    if curl -sf --max-time 5 "http://127.0.0.1:${port}/healthz/" > /dev/null 2>&1 || \
       curl -sf --max-time 5 "http://127.0.0.1:${port}/livez/" > /dev/null 2>&1; then
      local_ok=true
    fi
  fi

  if [[ "$local_ok" == "true" ]]; then
    echo "OK   $svc (local:$port)"
    return 0
  fi

  # Fallback: public URL
  if curl -sf --max-time 10 "$url" > /dev/null 2>&1; then
    echo "OK   $svc ($url)"
    return 0
  fi

  echo "FAIL $svc ($url)"
  return 1
}

# --- Run checks ---
if [[ -n "$SERVICE" ]]; then
  SERVICES=("$SERVICE")
else
  SERVICES=("${!HEALTH_URL[@]}")
fi

for svc in "${SERVICES[@]}"; do
  if ! check_service "$svc"; then
    FAILED+=("$svc")
  fi
done

# --- Summary ---
if [[ ${#FAILED[@]} -eq 0 ]]; then
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] HEALTH_CHECK OK services=${SERVICES[*]}" >> "$LOG_FILE"
  echo "All services healthy."
  exit 0
else
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] HEALTH_CHECK FAILED services=${FAILED[*]}" >> "$LOG_FILE"
  echo "UNHEALTHY: ${FAILED[*]}" >&2
  exit 1
fi
