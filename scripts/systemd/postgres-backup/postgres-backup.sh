#!/usr/bin/env bash
set -Eeuo pipefail

ENV_FILE="/mnt/tank/data/code/source/Self-Hosted-Infrastructure/private/.env"

if [[ ! -r "$ENV_FILE" ]]; then
    echo "ERROR: Cannot read environment file: $ENV_FILE"
    exit 1
fi

source "$ENV_FILE"

CONTAINER="postgres"

# Only write to the actual mounted NFS share.
if ! mountpoint -q "$DATABASE_BACKUP_DIR"; then
    echo "ERROR: $DATABASE_BACKUP_DIR is not mounted. Aborting."
    exit 1
fi

# Ensure the expected container is running.
if ! docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -qx true; then
    echo "ERROR: PostgreSQL container '$CONTAINER' is not running."
    exit 1
fi

umask 077
mkdir -p "$POSTGRES_BACKUP_DIR"

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
TEMP_DIR=$(mktemp -d "$POSTGRES_BACKUP_DIR/.tmp-${TIMESTAMP}.XXXXXX")
FINAL_DIR="$POSTGRES_BACKUP_DIR/$TIMESTAMP"

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

echo "Starting PostgreSQL backup: $TIMESTAMP"

# Back up PostgreSQL roles and other global objects.
docker exec -u postgres "$CONTAINER" \
    pg_dumpall --globals-only > "$TEMP_DIR/globals.sql"

# Discover and back up every non-template database.
DATABASES=$(docker exec -u postgres "$CONTAINER" \
    psql -Atqc "SELECT datname FROM pg_database WHERE datallowconn AND NOT datistemplate ORDER BY datname")

while IFS= read -r DATABASE; do
    [[ -z "$DATABASE" ]] && continue

    echo "Backing up database: $DATABASE"

    docker exec -u postgres "$CONTAINER" \
        pg_dump -Fc --no-owner --no-acl --dbname="$DATABASE" \
        > "$TEMP_DIR/${DATABASE}.dump"
done <<< "$DATABASES"

# Publish the backup only after every dump succeeds.
mv "$TEMP_DIR" "$FINAL_DIR"
trap - EXIT

echo "Backup completed: $FINAL_DIR"

# Validate retention setting
if [[ ! "$POSTGRES_BACKUP_RETENTION" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: Invalid PostgreSQL backup retention value."
    exit 1
fi

# Find completed backups, oldest first
mapfile -t BACKUPS < <(
    find "$POSTGRES_BACKUP_DIR" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -name '20??-??-??_??-??-??' \
        -printf '%f\n' |
    sort
)

# Prune oldest backups until below retention limit
while (( ${#BACKUPS[@]} > POSTGRES_BACKUP_RETENTION )); do
    OLDEST="${BACKUPS[0]}"

    echo "Pruning oldest backup: $OLDEST"

    rm -rf -- "$POSTGRES_BACKUP_DIR/$OLDEST"

    BACKUPS=("${BACKUPS[@]:1}")
done
