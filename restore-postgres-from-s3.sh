#!/bin/bash
set -e

# ------------------ CONFIGURATION ------------------
# These can be overridden by environment variables
S3_BUCKET="${S3_BACKUP_BUCKET:-medusa-db-backups}"
S3_PATH="${S3_BACKUP_PATH:-postgres-backups}"
AWS_ENDPOINT_URL="${AWS_ENDPOINT_URL:-}"   # set to http://localhost:4566 for LocalStack
DB_CONTAINER="${POSTGRES_CONTAINER:-medusa-postgres}"
DB_USER="${POSTGRES_USER:-citizix_user}"
DB_PASSWORD="${POSTGRES_PASSWORD:-S3cret}"
DB_NAME="${POSTGRES_DB:-medusa_db}"

# ------------------ FUNCTIONS ------------------
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -l, --list               List available backups"
    echo "  --latest                  Restore the latest backup"
    echo "  -f, --file FILENAME       Restore a specific backup file"
    echo "  -h, --help                Show this help"
    exit 0
}

aws_with_endpoint() {
    if [ -n "$AWS_ENDPOINT_URL" ]; then
        aws --endpoint-url "$AWS_ENDPOINT_URL" "$@"
    else
        aws "$@"
    fi
}

# Function to drop and recreate the database
reset_database() {
    echo "Resetting database $DB_NAME..."

    # Terminate all connections to the target database
    docker exec -e PGPASSWORD="$DB_PASSWORD" "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -c "
        SELECT pg_terminate_backend(pid)
        FROM pg_stat_activity
        WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();
    " > /dev/null 2>&1 || true

    # Drop the database if it exists
    docker exec -e PGPASSWORD="$DB_PASSWORD" "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS \"$DB_NAME\";"

    # Create a fresh database
    docker exec -e PGPASSWORD="$DB_PASSWORD" "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -c "CREATE DATABASE \"$DB_NAME\";"

    echo "Database reset complete."
}

# ------------------ MAIN ------------------
# Parse arguments
LATEST=false
SPECIFIC_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--list)
            echo "Listing backups in s3://${S3_BUCKET}/${S3_PATH}/"
            aws_with_endpoint s3 ls "s3://${S3_BUCKET}/${S3_PATH}/"
            exit 0
            ;;
        --latest)
            LATEST=true
            shift
            ;;
        -f|--file)
            SPECIFIC_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Determine which backup to restore
if [ -n "$SPECIFIC_FILE" ]; then
    BACKUP_FILE="$SPECIFIC_FILE"
elif [ "$LATEST" = true ]; then
    echo "Finding latest backup..."
    LATEST_FILE=$(aws_with_endpoint s3 ls "s3://${S3_BUCKET}/${S3_PATH}/" | sort -k1,2 | tail -n1 | awk '{print $4}')
    if [ -z "$LATEST_FILE" ]; then
        echo "No backups found."
        exit 1
    fi
    BACKUP_FILE="$LATEST_FILE"
else
    # No option: show list and prompt
    echo "Available backups:"
    aws_with_endpoint s3 ls "s3://${S3_BUCKET}/${S3_PATH}/"
    echo ""
    read -p "Enter backup filename to restore (or 'q' to quit): " BACKUP_FILE
    if [[ "$BACKUP_FILE" == "q" ]]; then
        exit 0
    fi
fi

if [ -z "$BACKUP_FILE" ]; then
    echo "No backup file specified."
    exit 1
fi

echo "Restoring backup: $BACKUP_FILE"

# Create temp directory
TMP_DIR=$(mktemp -d)
TMP_FILE="${TMP_DIR}/${BACKUP_FILE}"

# Download from S3
echo "Downloading from S3..."
aws_with_endpoint s3 cp "s3://${S3_BUCKET}/${S3_PATH}/${BACKUP_FILE}" "$TMP_FILE"

# Confirm with user
echo ""
echo "This will OVERWRITE the database '$DB_NAME' in container '$DB_CONTAINER'."
read -p "Are you sure? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Restore cancelled."
    rm -rf "$TMP_DIR"
    exit 0
fi

# Reset the database (drop, recreate, terminate connections)
reset_database

# Restore the database from backup
echo "Restoring database from backup..."
if [[ "$BACKUP_FILE" == *.gz ]]; then
    gunzip -c "$TMP_FILE" | docker exec -i -e PGPASSWORD="$DB_PASSWORD" "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME"
else
    docker exec -i -e PGPASSWORD="$DB_PASSWORD" "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" < "$TMP_FILE"
fi

if [ $? -eq 0 ]; then
    echo "✅ Restore completed successfully."
else
    echo "❌ Restore failed."
    exit 1
fi

# Clean up
rm -rf "$TMP_DIR"