#!/usr/bin/env bash
# db-backup.sh — PostgreSQL backup for a single platform service
# Usage: db-backup.sh <service>
# Example: db-backup.sh travel-beat
#
# Backups stored at: /opt/deploy/backups/<service>/<service>_YYYYMMDD_HHMMSS.sql.gz
# Retention: 7 days

set -euo pipefail

SERVICE="${1:?Usage: db-backup.sh <service>}"

BACKUP_BASE="/mnt/HC_Volume_105908261/deploy-backups"
STATE_DIR="/opt/deploy/production/.deployed"
LOG_FILE="${STATE_DIR}/deploy.log"
RETENTION_DAYS=7
# Platten-Floor (platform#2284 K3, Owner-Go 2026-08-25): unter dieser Grenze wird
# NICHT geschrieben. Ein Dump, der die Platte fuellt, ist schlimmer als ein
# fehlender Dump — er reisst die laufenden Dienste mit. Der Speicher-Vorlauf-
# Melder (platform 0.7.18) warnt sieben Tage vorher; dies ist die letzte Sperre.
# Env-Override nur fuer die Positivkontrolle (MIN_FREE_BYTES=<riesig> => Exit 2).
MIN_FREE_BYTES="${MIN_FREE_BYTES:-$((15 * 1024 * 1024 * 1024))}"

# --- Service registry (mirrors ADR-021 §2.3) ---
# DB_CONTAINER: the docker container running postgres for this service
declare -A DB_CONTAINER=(
  [bfagent]="bfagent_db"
  [risk-hub]="risk_hub_db"
  [travel-beat]="travel_beat_db"
  [weltenhub]="bfagent_db"
  [dev-hub]="devhub_db"
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
  [dev-hub]="devhub"
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
mkdir -p "$BACKUP_BASE"
FREE_BYTES=$(df -B1 --output=avail "$BACKUP_BASE" 2>/dev/null | tail -1 | tr -d ' ')
if [[ -z "$FREE_BYTES" ]] || (( FREE_BYTES < MIN_FREE_BYTES )); then
  echo "ABBRUCH: $(( ${FREE_BYTES:-0} / 1024 / 1024 / 1024 )) GB frei unter $BACKUP_BASE, Floor $(( MIN_FREE_BYTES / 1024 / 1024 / 1024 )) GB — kein Dump, Platte wuerde volllaufen." >&2
  exit 2
fi

# --- Container muss laufen: ein gestoppter/eingefrorener Dienst ist ein lauter SKIP,
# kein leeres 20-Byte-gzip (Befund 2026-08-24: 7 von 9 "gruenen" Dumps waren leer,
# weil pg_dump gegen gestoppte Container lief und der Workflow-Loop Fehler schluckte).
if ! docker ps --format '{{.Names}}' | grep -qx "$DB_CTR"; then
  echo "SKIP $SERVICE: DB-Container '$DB_CTR' laeuft nicht (gestoppt/eingefroren/archiviert)"
  exit 0
fi

TIMESTAMP=$(date -u +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/${SERVICE}_${TIMESTAMP}.sql.gz"

mkdir -p "$BACKUP_DIR" "$STATE_DIR"

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] START backup $SERVICE" >> "$LOG_FILE"
echo "Backing up $SERVICE ($DB) from $DB_CTR as $DB_USR to $BACKUP_FILE ..."

# --- Create backup ---
docker exec "$DB_CTR" pg_dump -U "$DB_USR" "$DB" | gzip > "$BACKUP_FILE"

# Zwischengroesse pruefen, nicht nur Exit-Code: ein leeres gzip ist 20 Bytes gross
# und sieht im Verzeichnis wie ein Backup aus.
BYTES=$(stat -c%s "$BACKUP_FILE")
if [ "$BYTES" -lt 1024 ]; then
  echo "ERROR: Dump fuer $SERVICE verdaechtig klein (${BYTES} Bytes) — als Fehlschlag gewertet" >&2
  rm -f "$BACKUP_FILE"
  exit 1
fi

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
