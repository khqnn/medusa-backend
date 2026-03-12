# Medusa Backend with Docker & Automated Backups

This repository provides a complete Dockerized setup for a **MedusaJS backend** with PostgreSQL, Redis, and an automated backup service. It includes:

- Multi‑stage Dockerfile for an optimized Medusa production image.
- Docker Compose configuration for PostgreSQL, Redis, and the Medusa backend.
- A dedicated **backup service** that periodically creates database dumps, uploads them to **AWS S3** (or LocalStack), and cleans up old backups.
- Restore script to recover the database from a backup.

---

## 📦 Architecture

| Service   | Description                                                                 |
|-----------|-----------------------------------------------------------------------------|
| `postgres`| PostgreSQL 14 database (data persisted in `./postgre_data`).                |
| `redis`   | Redis 7 (used by Medusa for caching and jobs).                              |
| `backend` | Medusa backend built from `./medusa-store-backend` using the provided Dockerfile.|
| `backup`  | Alpine‑based container running cron jobs for backup, cleanup, and restore.  |

All services share a common network and read configuration from a `.env.production` file.

---

## 🚀 Getting Started

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/) & [Docker Compose](https://docs.docker.com/compose/install/)
- (Optional) [AWS CLI](https://aws.amazon.com/cli/) if using real S3
- (Optional) [awslocal](https://github.com/localstack/awscli-local) if testing with LocalStack

### 1. Clone & Prepare Environment

```bash
git clone <your-repo>
cd <repo-directory>
```

Create a `.env.production` file from the template:

```bash
cp .env.template .env.production
```

Edit `.env.production` with your actual values (see [Configuration](#configuration) below).

### 2. Build and Start

```bash
docker-compose up -d
```

This starts all containers in detached mode. Follow logs with:

```bash
docker-compose logs -f
```

### 3. Create an Admin User

The backend is running on `http://localhost:9000`. Create your first admin user:

```bash
docker exec -it medusa-backend sh
yarn medusa user -e admin@example.com -p yourpassword
exit
```

Now you can log in at `http://localhost:9000/app`.

---

## 🔧 Configuration

All sensitive settings are managed via environment variables in `.env.production`.  
Key variables:

| Variable                         | Description                                                       |
|----------------------------------|-------------------------------------------------------------------|
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` | PostgreSQL credentials and database name.          |
| `DATABASE_URL`                   | Full PostgreSQL connection string used by Medusa.                 |
| `REDIS_URL`                      | Redis connection string.                                           |
| `JWT_SECRET` / `COOKIE_SECRET`   | Secrets for authentication and sessions.                           |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | AWS credentials for S3 backup storage.                  |
| `AWS_REGION`                      | Region of your S3 bucket (e.g., `us-east-1`).                     |
| `S3_BACKUP_BUCKET`                | S3 bucket name for backups (default: `medusa-db-backups`).        |
| `S3_BACKUP_PATH`                  | Folder inside the bucket (default: `postgres-backups`).           |
| `AWS_ENDPOINT_URL`                 | **Optional**: Custom endpoint (for LocalStack or other S3‑compatible services). |
| `S3_FILE_URL`                      | Used by Medusa file plugin for image uploads (e.g., Supabase).    |
| `S3_IMAGE_BUCKET`                  | Bucket for Medusa product images.                                 |

> **Important:** For **production AWS S3**, leave `AWS_ENDPOINT_URL` **empty**.  
> For **LocalStack** testing, set `AWS_ENDPOINT_URL=http://host.docker.internal:4566`.

---

## 📂 Backup Service

The `backup` container runs three scripts:

- **`backup.sh`** – Creates a compressed `pg_dump` of the database and uploads it to S3.
- **`cleanup.sh`** – Deletes backups older than a specified age (e.g., `20m`, `12h`, `7d`).
- **`restore.sh`** – Lists, downloads, and restores a backup, completely resetting the database first.

### Cron Schedule

In `docker-compose.yml`, two cron jobs are defined inside the `backup` container:

```cron
*/5 * * * * . /root/env.sh && /usr/local/bin/backup.sh       # every 5 minutes
*/10 * * * * . /root/env.sh && /usr/local/bin/cleanup.sh     # every 10 minutes
```

To change the frequency, edit the `entrypoint` section of the `backup` service. The cleanup age is controlled by the environment variable `CLEANUP_AFTER` (e.g., `20m`). Supported suffixes: `s` (seconds), `m` (minutes), `h` (hours), `d` (days).

---

## 🛠️ Useful Commands

### Container Management

| Action                          | Command                               |
|----------------------------------|---------------------------------------|
| Start all services               | `docker-compose up -d`                |
| Stop all services                | `docker-compose down`                 |
| Stop and remove volumes          | `docker-compose down -v`              |
| View logs (all)                  | `docker-compose logs -f`               |
| View logs (specific service)     | `docker-compose logs -f backend`       |
| Rebuild a service                | `docker-compose up -d --build backend` |
| Enter backend container          | `docker exec -it medusa-backend sh`    |
| Enter backup container           | `docker exec -it medusa-backup sh`     |

### Medusa Backend

| Action                              | Command (inside backend container)            |
|-------------------------------------|-----------------------------------------------|
| Create admin user                   | `yarn medusa user -e email -p password`       |
| Run database migrations             | `yarn medusa db:migrate`                       |
| Seed database (if needed)           | `yarn medusa seed`                             |
| Start server manually               | `yarn start`                                   |

### Backup & Restore

| Action                                      | Command (from host)                                                           |
|---------------------------------------------|-------------------------------------------------------------------------------|
| List available backups                      | `docker exec -it medusa-backup /usr/local/bin/restore.sh --list`              |
| Restore the latest backup                   | `docker exec -it medusa-backup /usr/local/bin/restore.sh --latest`            |
| Restore a specific backup file              | `docker exec -it medusa-backup /usr/local/bin/restore.sh -f filename.sql.gz`  |
| Manually trigger a backup                   | `docker exec -it medusa-backup /usr/local/bin/backup.sh`                      |
| Manually trigger cleanup (older than 20m)   | `docker exec -it medusa-backup /usr/local/bin/cleanup.sh`                     |
| Check backup logs                           | `docker logs medusa-backup`                                                   |

### S3 / LocalStack Operations

If using **LocalStack**, first set `AWS_ENDPOINT_URL` in `.env.production` and create the bucket:

```bash
# Create backup bucket
awslocal s3 mb s3://medusa-db-backups

# List backups
awslocal s3 ls s3://medusa-db-backups/postgres-backups/
```

If using **real AWS**, omit the `--endpoint-url` or use normal `aws` commands.

---

## 🧪 Testing with LocalStack

To test backups locally without real AWS:

1. **Start LocalStack** (e.g., add to `docker-compose.yml` or run separately).
2. In `.env.production`, set:
   ```ini
   AWS_ENDPOINT_URL=http://host.docker.internal:4566
   AWS_ACCESS_KEY_ID=fake
   AWS_SECRET_ACCESS_KEY=fake
   AWS_REGION=us-east-1
   ```
3. Create the bucket:
   ```bash
   awslocal s3 mb s3://medusa-db-backups
   ```
4. Run the stack and watch backups appear:
   ```bash
   docker-compose up -d
   docker-compose logs -f backup
   ```
5. Verify backups:
   ```bash
   awslocal s3 ls s3://medusa-db-backups/postgres-backups/
   ```

---

## 📝 Notes

- The `postgres` data is stored in `./postgre_data` – **backup this directory separately** if you need point‑in‑time recovery without backups.
- The backend runs as a non‑root user (`medusa`) for security.
- The `entrypoint.sh` of the backend waits for PostgreSQL, tests the connection, and runs migrations on every start.
- For file uploads (product images), Medusa is configured via the `@medusajs/file-s3` plugin. The endpoint and credentials are taken from the same `.env.production` file.
- To change the backup schedule, edit the `cron` lines in the `backup` service’s `entrypoint` and recreate the container:  
  ```bash
  docker-compose up -d --no-deps --build backup
  ```

---

## ❓ Troubleshooting

- **Database connection errors** – Ensure `DATABASE_URL` is correct and PostgreSQL is healthy (`docker logs medusa-postgres`).
- **SSL errors with S3** – If using LocalStack or a custom endpoint, set `AWS_ENDPOINT_URL` and use `http://` (not `https://`). For real AWS, never set `AWS_ENDPOINT_URL`.
- **Backup fails with “Unable to locate credentials”** – Verify AWS variables are set in `.env.production` and passed to the backup container (check with `docker exec medusa-backup env`).
- **Restore fails because database is in use** – The restore script terminates connections automatically, but if you have long‑running queries, it may need a few retries.

