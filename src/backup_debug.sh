#!/bin/bash

if [ -z "$DB_URL" ]; then
  echo "Error: DB_URL environment variable is not set"
  exit 1
fi

if ! [[ "$BACKUP_INTERVAL" =~ ^[0-9]+$ ]]; then
  echo "Error: BACKUP_INTERVAL must be a number"
  exit 1
fi

echo "Starting PostgreSQL backup script"
echo "Backup interval: $BACKUP_INTERVAL minutes"
echo "Database: $(echo $DB_URL | awk -F'/' '{print $NF}')"
[ -n "$TABLES" ] && echo "Tables: $TABLES"

while true; do
  DB_NAME=$(echo "$DB_URL" | awk -F'/' '{print $NF}' | awk -F'?' '{print $1}')
  TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
  BACKUP_FILE="./backups/${DB_NAME}_${TIMESTAMP}.sql"

  DUMP_CMD="pg_dump --dbname=\"$DB_URL\""
  [ -n "$TABLES" ] && DUMP_CMD="$DUMP_CMD --table=\"$(echo $TABLES | sed 's/ /" --table="/g')\""

  if eval "$DUMP_CMD" | gzip -9 > "$BACKUP_FILE"; then
    echo "$(date) - Backup successfully created (size: $(du -h "$BACKUP_FILE" | cut -f1))"
  else
    echo "$(date) - Backup failed!" >&2
    [ -f "$BACKUP_FILE" ] && rm "$BACKUP_FILE"
  fi

  echo "$(date) - Creating backup..."
  eval "$DUMP_CMD" > "$BACKUP_FILE"

  echo "$(date) - Compressing backup..."
  gzip -f "$BACKUP_FILE"

  echo "$(date) - Backup complete: ${BACKUP_FILE}.gz"

  sleep $((BACKUP_INTERVAL * 60))
done
