#!/usr/bin/env bash
# db-backup.sh — PostgreSQL backup for a single platform service
# Usage: db-backup.sh <service>
# Example: db-backup.sh travel-beat
#
# Backups stored at: /opt/deploy/backups/<service>/<service>_YYYYMMDD_HHMMSS.sql.gz
# Retention: 7 days

set -euo pipefail

SERVICE="${1:?Usage: db-backup.sh <service>}"

BACKUP_BASE="/opt/deploy/backups"
STATE_DIR="/opt/deploy/production/.deployed"
LOG_FILE="${STATE_DIR}/deploy.log"
RETENTION_DAYS=7

# --- Service registry (mirrors ADR-021 §2.3) ---
# DB_CONTAINER: the docker container running postgres for this service
declare -A DB_CONTAINER=(
  [bfagent]="bfagent_db"
  [risk-hub]="risk_hub_db"
  [travel-beat]="travel_beat_db"
  [weltenhub]="bfagent_db"
  [dev-hub]="bfagent_db"
  [pptx-hub]="pptx_hub_db"
  [coach-hub]="coach_hub_db"
  [trading-hub]="trading_hub_db"
  [wedding-hub]="wedding_hub_db"
  [cad-hub]="cad_hub_db"
)

# DB_NAME: the actual database name inside postgres
declare -A DB_NAME=(
  [bfagent]="bfagent_prod"
  [risk-hub]="risk_hub"
  [travel-beat]="travel_beat"
  [weltenhub]="weltenhub"
  [dev-hub]="devhub_db"
  [pptx-hub]="pptx_hub"
  [coach-hub]="coach_hub"
  [trading-hub]="tradinghub_prod"
  [wedding-hub]="wedding_hub"
  [cad-hub]="cad_hub"
)

# DB_USER: the postgres user (from POSTGRES_USER env in each container)
declare -A DB_USER=(
  [bfagent]="bfagent"
  [risk-hub]="risk_hub"
  [travel-beat]="travelbeat"
  [weltenhub]="bfagent"
  [dev-hub]="bfagent"
  [pptx-hub]="pptx_hub"
  [coach-hub]="coach_hub"
  [trading-hub]="bfagent"
  [wedding-hub]="wedding_hub"
  [cad-hub]="postgres"
)

# --- Validate service ---
if [[ -z "${DB_CONTAINER[$SERVICE]:-}" ]]; then
  echo "ERROR: Unknown service '$SERVICE'. Valid: ${!DB_CONTAINER[*]}" >&2
  exit 1
fi

DB_CTR="${DB_CONTAINER[$SERVICE]}"
DB="${DB_NAME[$SERVICE]}"
DB_USR="${DB_USER[$SERVICE]}"
BACKUP_DIR="${BACKUP_BASE}/${SERVICE}"
TIMESTAMP=$(date -u +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/${SERVICE}_${TIMESTAMP}.sql.gz"

mkdir -p "$BACKUP_DIR" "$STATE_DIR"

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] START backup $SERVICE" >> "$LOG_FILE"
echo "Backing up $SERVICE ($DB) from $DB_CTR as $DB_USR to $BACKUP_FILE ..."

# --- Create backup ---
docker exec "$DB_CTR" pg_dump -U "$DB_USR" "$DB" | gzip > "$BACKUP_FILE"

# --- Verify backup is non-empty ---
if [[ ! -s "$BACKUP_FILE" ]]; then
  echo "ERROR: Backup file is empty: $BACKUP_FILE" >&2
  rm -f "$BACKUP_FILE"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] FAILED backup $SERVICE" >> "$LOG_FILE"
  exit 1
fi

BACKUP_SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
echo "Backup created: $BACKUP_FILE ($BACKUP_SIZE)"

# --- Cleanup old backups (retention) ---
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +${RETENTION_DAYS} -delete
echo "Cleaned up backups older than ${RETENTION_DAYS} days."

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] SUCCESS backup $SERVICE size=${BACKUP_SIZE}" >> "$LOG_FILE"
