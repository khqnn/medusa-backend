#!/bin/bash
set -e

# Load environment variables
POSTGRES_CONTAINER=${POSTGRES_CONTAINER:-medusa-postgres}
POSTGRES_USER=${POSTGRES_USER:-citizix_user}
POSTGRES_DB=${POSTGRES_DB:-medusa_db}
USE_S3_BACKUP=${USE_S3_BACKUP:-false}
LOCAL_BACKUP_DIR=${LOCAL_BACKUP_DIR:-/backups}
STATIC_BACKUP_SOURCE=${STATIC_BACKUP_SOURCE:-/static}
BACKUP_ENABLED=${BACKUP_ENABLED:-true}

if [ "$BACKUP_ENABLED" != "true" ]; then
    echo "Backups are disabled. Exiting."
    exit 0
fi

# Create timestamp for backup
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/tmp/backup_${TIMESTAMP}"
mkdir -p "$BACKUP_DIR"

# Function to test S3 connectivity
test_s3_connection() {
    echo "Testing S3 connectivity..."
    if [ -n "$AWS_ENDPOINT_URL" ]; then
        ENDPOINT_ARG="--endpoint-url $AWS_ENDPOINT_URL"
    fi
    # Attempt to list the bucket (works even if empty)
    if aws s3 ls "s3://${S3_BACKUP_BUCKET}" $ENDPOINT_ARG > /dev/null 2>&1; then
        echo "S3 connection successful."
        return 0
    else
        echo "ERROR: S3 connection failed."
        return 1
    fi
}

# Determine backup destination and test connection if S3
if [ "$USE_S3_BACKUP" = "true" ]; then
    if [ -z "$S3_BACKUP_BUCKET" ]; then
        echo "ERROR: USE_S3_BACKUP is true but S3_BACKUP_BUCKET is not set."
        exit 1
    fi
    # Test S3 connectivity before proceeding
    if ! test_s3_connection; then
        echo "S3 connection failed. Backup aborted."
        exit 1
    fi
    DESTINATION="s3"
else
    DESTINATION="local"
    # Ensure local backup directory exists
    mkdir -p "$LOCAL_BACKUP_DIR"
fi

echo "Starting backup at $(date)"

# 1. Dump database
echo "Dumping database..."
docker exec "$POSTGRES_CONTAINER" pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" > "$BACKUP_DIR/db.sql"
if [ $? -ne 0 ]; then
    echo "Error: Database dump failed"
    exit 1
fi
gzip "$BACKUP_DIR/db.sql"
echo "Database dump completed."

# 2. Copy static files if directory exists and is not empty
if [ -d "$STATIC_BACKUP_SOURCE" ] && [ -n "$(ls -A $STATIC_BACKUP_SOURCE 2>/dev/null)" ]; then
    echo "Copying static files..."
    mkdir -p "$BACKUP_DIR/static"
    # Copy contents of source into static/ (not the source directory itself)
    cp -r "$STATIC_BACKUP_SOURCE"/* "$BACKUP_DIR/static/" 2>/dev/null || true
    echo "Static files copied."
else
    echo "No static files to backup (directory empty or missing)."
fi

# 3. Archive the backup directory
echo "Archiving backup..."
(cd /tmp && tar czf "backup_${TIMESTAMP}.tar.gz" "backup_${TIMESTAMP}")
ARCHIVE="/tmp/backup_${TIMESTAMP}.tar.gz"
BACKUP_NAME="backup_${TIMESTAMP}.tar.gz"

# 4. Upload or move to destination
if [ "$DESTINATION" = "s3" ]; then
    echo "Uploading to S3..."
    if [ -n "$AWS_ENDPOINT_URL" ]; then
        ENDPOINT_ARG="--endpoint-url $AWS_ENDPOINT_URL"
    fi
    aws s3 cp "$ARCHIVE" "s3://${S3_BACKUP_BUCKET}/${S3_BACKUP_PATH}/${BACKUP_NAME}" $ENDPOINT_ARG
    if [ $? -eq 0 ]; then
        echo "Upload successful."
    else
        echo "ERROR: Upload to S3 failed."
        exit 1
    fi
else
    echo "Saving backup locally..."
    cp "$ARCHIVE" "$LOCAL_BACKUP_DIR/$BACKUP_NAME"
    echo "Local backup saved at $LOCAL_BACKUP_DIR/$BACKUP_NAME"
fi

# Clean up temporary files
rm -rf "$BACKUP_DIR" "$ARCHIVE"

# Clean up old backups (if local) - this runs after each backup
if [ "$DESTINATION" = "local" ] && [ -n "$CLEANUP_AFTER" ]; then
    echo "Cleaning up old local backups (older than $CLEANUP_AFTER)..."
    find "$LOCAL_BACKUP_DIR" -name "backup_*.tar.gz" -type f -mtime +${CLEANUP_AFTER%d} -delete
fi

echo "Backup completed successfully at $(date)"