#!/usr/bin/env bash
# deploy.sh — Atomic deploy for a single platform service
# Usage: deploy.sh <service> <image_tag> <has_migrations>
# Example: deploy.sh travel-beat latest false
#
# Requires: /opt/<service>/docker-compose.prod.yml and .env.prod on server
# State dir: /opt/deploy/production/.deployed/

set -euo pipefail

SERVICE="${1:?Usage: deploy.sh <service> <image_tag> <has_migrations>}"
IMAGE_TAG="${2:-latest}"
HAS_MIGRATIONS="${3:-false}"

STATE_DIR="/opt/deploy/production/.deployed"
LOG_FILE="${STATE_DIR}/deploy.log"

# --- Service registry (mirrors ADR-021 §2.3) ---
declare -A DEPLOY_PATH=(
  [bfagent]="/opt/bfagent-app"
  [risk-hub]="/opt/risk-hub"
  [travel-beat]="/opt/travel-beat"
  [weltenhub]="/opt/weltenhub"
  [dev-hub]="/opt/dev-hub"
  [pptx-hub]="/opt/pptx-hub"
  [coach-hub]="/opt/coach-hub"
  [trading-hub]="/opt/trading-hub"
  [wedding-hub]="/opt/wedding-hub"
  [cad-hub]="/opt/cad-hub"
  [writing-hub]="/opt/writing-hub"
)

# WEB_SERVICE: the compose service name for the web container
declare -A WEB_SERVICE=(
  [bfagent]="bfagent-web"
  [risk-hub]="risk-hub-web"
  [travel-beat]="travel-beat-web"
  [weltenhub]="weltenhub-web"
  [dev-hub]="devhub-web"
  [pptx-hub]="pptx-hub-web"
  [coach-hub]="coach-hub-web"
  [trading-hub]="trading-hub-web"
  [wedding-hub]="wedding-hub-web"
  [cad-hub]="web"
  [writing-hub]="writing_hub_web"
)

# HEALTH_URL: public URL for post-deploy health check
declare -A HEALTH_URL=(
  [bfagent]="https://bfagent.iil.pet/healthz/"
  [risk-hub]="https://demo.schutztat.de/health/"
  [travel-beat]="https://drifttales.com/health/"
  [weltenhub]="https://weltenforger.com/health/"
  [dev-hub]="https://devhub.iil.pet/livez/"
  [pptx-hub]="https://prezimo.com/livez/"
  [coach-hub]="http://127.0.0.1:8007/livez/"
  [trading-hub]="https://trading-hub.iil.pet/livez/"
  [wedding-hub]="https://wedding-hub.iil.pet/livez/"
  [cad-hub]="https://nl2cad.de/livez/"
  [writing-hub]="https://writing.iil.pet/health/"
)

declare -A COMPOSE_FILE=(
  [bfagent]="docker-compose.prod.yml"
  [risk-hub]="docker-compose.prod.yml"
  [travel-beat]="docker-compose.prod.yml"
  [weltenhub]="docker-compose.prod.yml"
  [dev-hub]="docker-compose.prod.yml"
  [pptx-hub]="docker-compose.prod.yml"
  [coach-hub]="docker-compose.prod.yml"
  [trading-hub]="docker-compose.prod.yml"
  [wedding-hub]="docker-compose.prod.yml"
  [cad-hub]="docker-compose.prod.yml"
  [writing-hub]="docker-compose.prod.yml"
)

# --- Validate service ---
if [[ -z "${DEPLOY_PATH[$SERVICE]:-}" ]]; then
  echo "ERROR: Unknown service '$SERVICE'. Valid: ${!DEPLOY_PATH[*]}" >&2
  exit 1
fi

DEPLOY_DIR="${DEPLOY_PATH[$SERVICE]}"
WEB_SVC="${WEB_SERVICE[$SERVICE]}"
HEALTH="${HEALTH_URL[$SERVICE]}"
COMPOSE="${COMPOSE_FILE[$SERVICE]}"
TAG_FILE="${STATE_DIR}/${SERVICE}.tag"
PREV_TAG_FILE="${STATE_DIR}/${SERVICE}.tag.prev"

mkdir -p "$STATE_DIR"

# --- Save current tag for rollback ---
OLD_TAG="unknown"
if [[ -f "$TAG_FILE" ]]; then
  OLD_TAG=$(cat "$TAG_FILE")
  cp "$TAG_FILE" "$PREV_TAG_FILE"
fi

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] START deploy $SERVICE $OLD_TAG -> $IMAGE_TAG" >> "$LOG_FILE"

# --- Pull new image ---
echo "Pulling ghcr.io/achimdehnert/${SERVICE}:${IMAGE_TAG} ..."
cd "$DEPLOY_DIR"
docker compose -f "$COMPOSE" pull "$WEB_SVC"

# --- Run migrations if requested ---
if [[ "$HAS_MIGRATIONS" == "true" ]]; then
  echo "Running migrations for $SERVICE ..."
  docker compose -f "$COMPOSE" run --rm "$WEB_SVC" python manage.py migrate --noinput
fi

# --- Deploy ---
echo "Starting $WEB_SVC ..."
docker compose -f "$COMPOSE" up -d --force-recreate "$WEB_SVC"

# --- Health check ---
HEALTH_RETRIES=12
HEALTH_INTERVAL=5
HEALTH_OK=false

echo "Health check: $HEALTH"
for i in $(seq 1 $HEALTH_RETRIES); do
  if curl -sf "$HEALTH" > /dev/null 2>&1; then
    HEALTH_OK=true
    break
  fi
  echo "Health check $i/$HEALTH_RETRIES failed, retrying in ${HEALTH_INTERVAL}s ..."
  sleep "$HEALTH_INTERVAL"
done

if [[ "$HEALTH_OK" == "true" ]]; then
  echo "$IMAGE_TAG" > "$TAG_FILE"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] SUCCESS deploy $SERVICE $OLD_TAG -> $IMAGE_TAG" >> "$LOG_FILE"
  echo "Deploy of $SERVICE:$IMAGE_TAG succeeded."
else
  echo "Health check failed after $HEALTH_RETRIES attempts. Rolling back to $OLD_TAG ..." >&2
  if [[ "$OLD_TAG" != "unknown" ]]; then
    docker compose -f "$COMPOSE" pull "$WEB_SVC" || true
    docker compose -f "$COMPOSE" up -d --force-recreate "$WEB_SVC" || true
  fi
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ROLLBACK deploy $SERVICE $IMAGE_TAG -> $OLD_TAG" >> "$LOG_FILE"
  echo "ERROR: Deploy of $SERVICE:$IMAGE_TAG failed. Rolled back to $OLD_TAG." >&2
  exit 1
fi
