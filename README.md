# Medusa Backend with Docker & Automated Backups

This repository provides a Dockerized setup for a **MedusaJS backend** with PostgreSQL, Redis, and an automated backup service that can store backups locally or in an S3-compatible bucket. It also includes a custom route to serve uploaded images when using local file storage.

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
- (Optional) [AWS CLI](https://aws.amazon.com/cli/) if using S3 backups

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

### Database & Redis

| Variable                         | Description                                                       |
|----------------------------------|-------------------------------------------------------------------|
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` / `POSTGRES_HOST` / `POSTGRES_PORT` | PostgreSQL credentials and database name.          |
| `DATABASE_URL`                   | Full PostgreSQL connection string used by Medusa.                 |
| `REDIS_URL`                      | Redis connection string.                                           |
| `JWT_SECRET` / `COOKIE_SECRET`   | Secrets for authentication and sessions.                           |

### File Storage (Images)

| Variable                         | Description                                                       |
|----------------------------------|-------------------------------------------------------------------|
| `USE_S3_FILES`                   | `true` to store images in S3, `false` for local filesystem.       |
| `BACKEND_URL`                    | Public URL of the backend (e.g., `http://your-server:9000`). Used to generate image URLs when `USE_S3_FILES=false`. |
| `S3_FILE_URL` / `S3_IMAGE_BUCKET`| S3 bucket and URL for image storage (only when `USE_S3_FILES=true`). |
| `AWS_*` credentials              | Required when using S3 for images or backups.                     |

### Backup

| Variable                         | Description                                                       |
|----------------------------------|-------------------------------------------------------------------|
| `BACKUP_ENABLED`                 | `true` to enable scheduled backups, `false` to disable.           |
| `USE_S3_BACKUP`                  | `true` to store backups in S3, `false` to store them locally in `./backup_data`. |
| `BACKUP_SCHEDULE`                | Cron schedule for backups (default: `0 2 * * *`).                 |
| `CLEANUP_AFTER`                  | Retention period for local backups (e.g., `7d`).                  |
| `S3_BACKUP_BUCKET` / `S3_BACKUP_PATH` | S3 bucket and folder for backups (only when `USE_S3_BACKUP=true`). |
| `AWS_*` credentials              | Required for S3 backups.                                          |

> **Important:** For local image storage (`USE_S3_FILES=false`), Medusa saves files in `/app/static`. A custom Express route serves them at `/static`. Ensure `BACKEND_URL` includes the correct public hostname and port.

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
| Restore a specific backup file              | `docker exec -it medusa-backup /usr/local/bin/restore.sh -f backup_*.tar.gz`  |
| Manually trigger a backup                   | `docker exec -it medusa-backup /usr/local/bin/backup.sh`                      |
| Check backup logs                           | `docker logs medusa-backup`                                                   |


> **Note:** When restoring, the script will first reset the database (terminate connections, drop, recreate) and then restore the static files to the backend container's `/app/static` directory. The static files are only restored if they were included in the backup.

---

## 📂 Backup Service

The `backup` container runs a cron job defined by `BACKUP_SCHEDULE`. The job executes `backup.sh`, which:

1. Dumps the PostgreSQL database.
2. Copies static files (if any) from the volume mounted at `/static`.
3. Archives the dump and static files into a `.tar.gz`.
4. Stores the archive either locally (in `./backup_data`) or uploads it to S3 (if `USE_S3_BACKUP=true`).

A separate `restore.sh` script can list, download, and restore a backup (database + static files).

---

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
- When using local file storage, the static files are persisted in `./static_data`. The backup service reads this volume (read‑only) and includes it in backups.
- To change the backup schedule, edit `BACKUP_SCHEDULE` in `.env.production`. The backup container must be restarted to apply the change.

---

## ❓ Troubleshooting

- **Database connection errors** – Ensure `DATABASE_URL` is correct and PostgreSQL is healthy (`docker logs medusa-postgres`).
- **Image upload fails with permission denied** – The host directory `./static_data` must be writable by the container user (UID 1000). Run `sudo chown -R 1000:1000 static_data` or `chmod -R 777 static_data`.
- **Image URLs show localhost** – Set `BACKEND_URL` in `.env.production` to the server's public address.
- **CORS errors** – Add the frontend origin (e.g., `http://your-server:9000`) to `ADMIN_CORS`, `STORE_CORS`, and `AUTH_CORS` in `.env.production`.
- **Backup fails with "No static files"** – This is normal if no files are stored locally (e.g., when using S3 for images). The script will skip static files and only backup the database.
- **Restore fails because database is in use** – The restore script terminates connections automatically, but if you have long‑running queries, it may need a few retries.