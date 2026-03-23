#!/bin/bash
set -e

# Load environment variables
POSTGRES_CONTAINER=${POSTGRES_CONTAINER:-medusa-postgres}
BACKEND_CONTAINER=${BACKEND_CONTAINER:-medusa-backend}
POSTGRES_USER=${POSTGRES_USER:-citizix_user}
POSTGRES_DB=${POSTGRES_DB:-medusa_db}
USE_S3_BACKUP=${USE_S3_BACKUP:-false}
LOCAL_BACKUP_DIR=${LOCAL_BACKUP_DIR:-/backups}
STATIC_BACKUP_TARGET=${STATIC_BACKUP_TARGET:-/app/static}    # ✅ changed from /static to /app/static
BACKUP_ENABLED=${BACKUP_ENABLED:-true}

if [ "$BACKUP_ENABLED" != "true" ]; then
    echo "Backups are disabled. Cannot restore."
    exit 1
fi

# Helper to list backups
list_backups() {
    if [ "$USE_S3_BACKUP" = "true" ]; then
        if [ -n "$AWS_ENDPOINT_URL" ]; then
            ENDPOINT_ARG="--endpoint-url $AWS_ENDPOINT_URL"
        fi
        aws s3 ls "s3://${S3_BACKUP_BUCKET}/${S3_BACKUP_PATH}/" $ENDPOINT_ARG | awk '{print $4}'
    else
        ls -1 "$LOCAL_BACKUP_DIR"/backup_*.tar.gz 2>/dev/null | xargs -n1 basename
    fi
}

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -l, --list               List available backups"
    echo "  --latest                 Restore the latest backup"
    echo "  -f, --file FILENAME      Restore a specific backup file"
    echo "  -h, --help               Show this help"
    exit 0
}

LATEST=false
SPECIFIC_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--list)
            list_backups
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
    BACKUP_NAME="$SPECIFIC_FILE"
elif [ "$LATEST" = true ]; then
    echo "Finding latest backup..."
    if [ "$USE_S3_BACKUP" = "true" ]; then
        if [ -n "$AWS_ENDPOINT_URL" ]; then
            ENDPOINT_ARG="--endpoint-url $AWS_ENDPOINT_URL"
        fi
        BACKUP_NAME=$(aws s3 ls "s3://${S3_BACKUP_BUCKET}/${S3_BACKUP_PATH}/" $ENDPOINT_ARG | sort -r | head -1 | awk '{print $4}')
    else
        BACKUP_NAME=$(ls -1 "$LOCAL_BACKUP_DIR"/backup_*.tar.gz 2>/dev/null | sort -r | head -1 | xargs -n1 basename)
    fi
    if [ -z "$BACKUP_NAME" ]; then
        echo "No backups found."
        exit 1
    fi
else
    echo "Available backups:"
    list_backups
    echo ""
    read -p "Enter backup filename to restore (or 'q' to quit): " BACKUP_NAME
    if [[ "$BACKUP_NAME" == "q" ]]; then
        exit 0
    fi
fi

if [ -z "$BACKUP_NAME" ]; then
    echo "No backup file specified."
    exit 1
fi

echo "Restoring backup: $BACKUP_NAME"

# Create temp directory
TEMP_DIR=$(mktemp -d)

# Download backup
if [ "$USE_S3_BACKUP" = "true" ]; then
    echo "Downloading from S3..."
    if [ -n "$AWS_ENDPOINT_URL" ]; then
        ENDPOINT_ARG="--endpoint-url $AWS_ENDPOINT_URL"
    fi
    aws s3 cp "s3://${S3_BACKUP_BUCKET}/${S3_BACKUP_PATH}/${BACKUP_NAME}" "$TEMP_DIR/$BACKUP_NAME" $ENDPOINT_ARG
else
    echo "Copying from local backup directory..."
    cp "$LOCAL_BACKUP_DIR/$BACKUP_NAME" "$TEMP_DIR/"
fi

# Extract
cd "$TEMP_DIR"
tar xzf "$BACKUP_NAME"
EXTRACTED_DIR=$(ls -d backup_*/ 2>/dev/null | head -1)
if [ -z "$EXTRACTED_DIR" ]; then
    echo "Error: Extracted backup does not contain expected directory."
    exit 1
fi
cd "$EXTRACTED_DIR"

# Confirm with user
echo ""
echo "This will OVERWRITE the database '$POSTGRES_DB' and static files (if any) in container '$POSTGRES_CONTAINER'."
read -p "Are you sure? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Restore cancelled."
    rm -rf "$TEMP_DIR"
    exit 0
fi

# Reset database: terminate connections, drop, recreate
echo "Resetting database..."
docker exec -i "$POSTGRES_CONTAINER" psql -U "$POSTGRES_USER" -d postgres <<EOF
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$POSTGRES_DB' AND pid <> pg_backend_pid();
DROP DATABASE IF EXISTS "$POSTGRES_DB";
CREATE DATABASE "$POSTGRES_DB";
EOF

# Restore database
echo "Restoring database..."
gunzip -c db.sql.gz | docker exec -i "$POSTGRES_CONTAINER" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"
if [ $? -ne 0 ]; then
    echo "Error: Database restore failed"
    exit 1
fi
echo "Database restored."

# Restore static files if present
if [ -d "static" ] && [ "$(ls -A static)" ]; then
    echo "Restoring static files..."
    # Ensure target directory exists in the backend container
    docker exec "$BACKEND_CONTAINER" mkdir -p "$STATIC_BACKUP_TARGET" 2>/dev/null || true
    # Copy files into the backend container
    docker cp static/. "$BACKEND_CONTAINER:$STATIC_BACKUP_TARGET/"
    echo "Static files restored."
else
    echo "No static files in backup or static directory empty."
fi

# Clean up
rm -rf "$TEMP_DIR"

echo "✅ Restore completed successfully."