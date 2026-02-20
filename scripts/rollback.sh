#!/usr/bin/env bash
# rollback.sh — Explicit rollback for a single platform service
# Usage: rollback.sh <service> [target_tag]
# If target_tag is empty, rolls back to the previous tag stored in state dir.
#
# State dir: /opt/deploy/production/.deployed/

set -euo pipefail

SERVICE="${1:?Usage: rollback.sh <service> [target_tag]}"
TARGET_TAG="${2:-}"

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
TAG_FILE="${STATE_DIR}/${SERVICE}.tag"
PREV_TAG_FILE="${STATE_DIR}/${SERVICE}.tag.prev"

mkdir -p "$STATE_DIR"

# --- Determine rollback target ---
if [[ -n "$TARGET_TAG" ]]; then
  ROLLBACK_TO="$TARGET_TAG"
elif [[ -f "$PREV_TAG_FILE" ]]; then
  ROLLBACK_TO=$(cat "$PREV_TAG_FILE")
else
  echo "ERROR: No previous tag found for $SERVICE and no target_tag specified." >&2
  exit 1
fi

CURRENT_TAG="unknown"
if [[ -f "$TAG_FILE" ]]; then
  CURRENT_TAG=$(cat "$TAG_FILE")
fi

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] START rollback $SERVICE $CURRENT_TAG -> $ROLLBACK_TO" >> "$LOG_FILE"
echo "Rolling back $SERVICE from $CURRENT_TAG to $ROLLBACK_TO ..."

# --- Pull rollback image and restart ---
cd "$DEPLOY_DIR"
export IMAGE_TAG="$ROLLBACK_TO"
docker compose -f "$COMPOSE" pull "$WEB_SVC" || true
docker compose -f "$COMPOSE" up -d --force-recreate "$WEB_SVC"

# --- Update state ---
echo "$ROLLBACK_TO" > "$TAG_FILE"
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] SUCCESS rollback $SERVICE $CURRENT_TAG -> $ROLLBACK_TO" >> "$LOG_FILE"
echo "Rollback of $SERVICE to $ROLLBACK_TO succeeded."
