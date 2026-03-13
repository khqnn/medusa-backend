#!/bin/sh
set -e

echo "Waiting for database to be ready..."
while ! nc -z "$POSTGRES_HOST" "$POSTGRES_PORT"; do
  sleep 1
done
echo "Database is ready."


# Debug: test direct connection with node
echo "Testing direct database connection..."
node -e "
const { Client } = require('pg');
const client = new Client({ connectionString: process.env.DATABASE_URL });
client.connect()
  .then(() => {
    console.log('✅ Direct connection successful!');
    return client.end();
  })
  .catch(err => {
    console.error('❌ Direct connection failed:', err.message);
    process.exit(1);
  });
"

# Run migrations (always safe)
echo "Running migrations..."
yarn medusa db:migrate


echo "Starting server..."
exec "$@"