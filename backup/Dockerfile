FROM alpine:latest

RUN apk add --no-cache \
    postgresql-client \
    aws-cli \
    bash \
    dcron \
    docker-cli

COPY entrypoint.sh /entrypoint.sh
COPY backup.sh /usr/local/bin/backup.sh
COPY restore.sh /usr/local/bin/restore.sh
COPY cleanup.sh /usr/local/bin/cleanup.sh

RUN chmod +x /entrypoint.sh /usr/local/bin/backup.sh /usr/local/bin/restore.sh /usr/local/bin/cleanup.sh

ENTRYPOINT ["/entrypoint.sh"]