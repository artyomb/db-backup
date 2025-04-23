#!/bin/bash

if [ -z "$DB_URL" ]; then
  echo "Error: DB_URL environment variable is not set"
  exit 1
fi

echo "Starting PostgreSQL backup script"
echo "Backup interval: $BACKUP_INTERVAL minutes"
echo "Database: $(echo $DB_URL | awk -F'/' '{print $NF}')"
[ -n "$TABLES" ] && echo "Tables: $TABLES"

DB_NAME=$(echo "$DB_URL" | awk -F'/' '{print $NF}' | awk -F'?' '{print $1}')
TIMESTAMP=$(date -u +"%Y%m%d_%H%M%S")
BACKUP_FILE="/backups/${DB_NAME}_${TIMESTAMP}.sql"

DUMP_CMD="pg_dump --dbname=\"$DB_URL\""
[ -n "$TABLES" ] && DUMP_CMD="$DUMP_CMD --table=\"$(echo $TABLES | sed 's/ /" --table="/g')\""

echo "$(date) - Creating backup..."
if ! eval "$DUMP_CMD" > "$BACKUP_FILE"; then
  echo "$(date) - Backup creation failed!" >&2
  [ -f "$BACKUP_FILE" ] && rm "$BACKUP_FILE"
  exit 1
fi

echo "$(date) - Compressing backup..."
if ! gzip -f "$BACKUP_FILE"; then
  echo "$(date) - Backup compression failed!" >&2
  [ -f "$BACKUP_FILE" ] && rm "$BACKUP_FILE"
  [ -f "${BACKUP_FILE}.gz" ] && rm "${BACKUP_FILE}.gz"
  exit 1
fi

echo "$(date) - Backup complete: ${BACKUP_FILE}.gz"