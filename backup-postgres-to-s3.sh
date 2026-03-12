#!/bin/sh
set -e

# Database settings
DB_CONTAINER="${POSTGRES_CONTAINER:-medusa-postgres}"
DB_USER="${POSTGRES_USER:-citizix_user}"
DB_PASSWORD="${POSTGRES_PASSWORD:-S3cret}"
DB_NAME="${POSTGRES_DB:-medusa_db}"

# S3 settings
S3_BUCKET="${S3_BACKUP_BUCKET:-medusa-db-backups}"
S3_PATH="${S3_BACKUP_PATH:-postgres-backups}"

# Timestamped backup file
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="/tmp/${DB_NAME}_${TIMESTAMP}.sql.gz"

# AWS CLI endpoint argument (for LocalStack)
ENDPOINT_ARGS=""
if [ -n "$AWS_ENDPOINT_URL" ]; then
    ENDPOINT_ARGS="--endpoint-url $AWS_ENDPOINT_URL"
fi

# Helper to run aws with endpoint
aws_with_endpoint() {
    aws $ENDPOINT_ARGS "$@"
}

echo "[$(date)] Starting backup of database $DB_NAME from container $DB_CONTAINER"

# Dump database (compressed)
docker exec "$DB_CONTAINER" pg_dump -U "$DB_USER" "$DB_NAME" | gzip > "$BACKUP_FILE"
if [ ! -s "$BACKUP_FILE" ]; then
    echo "ERROR: Backup file is empty."
    exit 1
fi
echo "Backup created: $BACKUP_FILE ($(du -h "$BACKUP_FILE" | cut -f1))"

# Upload to S3
aws_with_endpoint s3 cp "$BACKUP_FILE" "s3://${S3_BUCKET}/${S3_PATH}/" --only-show-errors
if [ $? -eq 0 ]; then
    echo "Upload to S3 successful."
else
    echo "ERROR: Upload to S3 failed."
    exit 1
fi

# Remove local backup file
rm -f "$BACKUP_FILE"
echo "[$(date)] Backup completed successfully."