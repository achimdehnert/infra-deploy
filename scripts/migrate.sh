#!/usr/bin/env bash
# migrate.sh — Run Django migrations for a single platform service
# Usage: migrate.sh <service>
# Example: migrate.sh travel-beat
#
# Requires: /opt/<service>/docker-compose.prod.yml on server
# State dir: /opt/deploy/production/.deployed/

set -euo pipefail

SERVICE="${1:?Usage: migrate.sh <service>}"

STATE_DIR="/opt/deploy/production/.deployed"
LOG_FILE="${STATE_DIR}/deploy.log"

# --- Service registry (mirrors ADR-021 §2.3) ---
declare -A DEPLOY_PATH=(
  [bfagent]="/opt/bfagent-app"
  [risk-hub]="/opt/risk-hub"
  [travel-beat]="/opt/travel-beat"
  [weltenhub]="/opt/weltenhub"
  [pptx-hub]="/opt/pptx-hub"
  [dev-hub]="/opt/dev-hub"
)

declare -A WEB_SERVICE=(
  [bfagent]="bfagent-web"
  [risk-hub]="risk-hub-web"
  [travel-beat]="web"
  [weltenhub]="weltenhub-web"
  [pptx-hub]="web"
  [dev-hub]="devhub-web"
)

declare -A COMPOSE_FILE=(
  [bfagent]="docker-compose.prod.yml"
  [risk-hub]="docker-compose.prod.yml"
  [travel-beat]="deploy/docker-compose.prod.yml"
  [weltenhub]="docker-compose.prod.yml"
  [pptx-hub]="docker-compose.prod.yml"
  [dev-hub]="docker-compose.prod.yml"
)

# --- Validate service ---
if [[ -z "${DEPLOY_PATH[$SERVICE]:-}" ]]; then
  echo "ERROR: Unknown service '$SERVICE'. Valid: ${!DEPLOY_PATH[*]}" >&2
  exit 1
fi

DEPLOY_DIR="${DEPLOY_PATH[$SERVICE]}"
WEB_SVC="${WEB_SERVICE[$SERVICE]}"
COMPOSE="${COMPOSE_FILE[$SERVICE]}"

mkdir -p "$STATE_DIR"

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] START migrate $SERVICE" >> "$LOG_FILE"
echo "Running migrations for $SERVICE ..."

cd "$DEPLOY_DIR"
docker compose -f "$COMPOSE" run --rm "$WEB_SVC" python manage.py migrate --noinput

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] SUCCESS migrate $SERVICE" >> "$LOG_FILE"
echo "Migrations for $SERVICE completed successfully."
