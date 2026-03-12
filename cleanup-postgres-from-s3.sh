#!/bin/sh
set -e


AGE="$CLEANUP_AFTER"

# Convert age to seconds using date
case "$AGE" in
    *s) seconds="${AGE%s}" ;;
    *m) seconds="$(( ${AGE%m} * 60 ))" ;;
    *h) seconds="$(( ${AGE%h} * 3600 ))" ;;
    *d) seconds="$(( ${AGE%d} * 86400 ))" ;;
    *) echo "Invalid age format. Use e.g., 3600s, 30m, 12h, 7d"; exit 1 ;;
esac

# Validate that seconds is a positive integer
if ! [ "$seconds" -gt 0 ] 2>/dev/null; then
    echo "Invalid age value."
    exit 1
fi

# S3 settings
S3_BUCKET="${S3_BACKUP_BUCKET:-medusa-db-backups}"
S3_PATH="${S3_BACKUP_PATH:-postgres-backups}"

# AWS CLI endpoint argument
ENDPOINT_ARGS=""
if [ -n "$AWS_ENDPOINT_URL" ]; then
    ENDPOINT_ARGS="--endpoint-url $AWS_ENDPOINT_URL"
fi

aws_with_endpoint() {
    aws $ENDPOINT_ARGS "$@"
}

echo "[$(date)] Removing backups older than $AGE ($seconds seconds) from s3://${S3_BUCKET}/${S3_PATH}/"

# Compute cutoff timestamp (seconds since epoch)
now=$(date -u +%s)
cutoff=$((now - seconds))

deleted_count=0
aws_with_endpoint s3 ls "s3://${S3_BUCKET}/${S3_PATH}/" | while read -r line; do
    # line format: "2026-03-11 06:55:28      32730 medusa_db_20260311_015528.sql.gz"
    createDate=$(echo "$line" | awk '{print $1" "$2}')
    # Convert to seconds since epoch
    createDateTs=$(date -u -d "$createDate" +%s 2>/dev/null)
    if [ -n "$createDateTs" ] && [ "$createDateTs" -lt "$cutoff" ]; then
        fileName=$(echo "$line" | awk '{print $4}')
        if [ -n "$fileName" ]; then
            echo "Deleting $fileName"
            aws_with_endpoint s3 rm "s3://${S3_BUCKET}/${S3_PATH}/$fileName"
            deleted_count=$((deleted_count + 1))
        fi
    fi
done

echo "[$(date)] Cleanup completed. Deleted $deleted_count file(s)."