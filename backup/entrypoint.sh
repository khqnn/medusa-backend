#!/bin/sh
set -e

# Start cron if backups are enabled
if [ "$BACKUP_ENABLED" = "true" ]; then
    SCHEDULE=${BACKUP_SCHEDULE:-"0 2 * * *"}
    echo "$SCHEDULE /usr/local/bin/backup.sh >> /var/log/backup.log 2>&1" > /etc/crontabs/root
    touch /var/log/backup.log
    echo "Cron job scheduled: $SCHEDULE"
    crond -f -l 2
else
    echo "Backups are disabled (BACKUP_ENABLED=false). Exiting."
    sleep infinity
fi