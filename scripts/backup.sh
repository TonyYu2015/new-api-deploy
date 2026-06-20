#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -z "${ENV_FILE:-}" ]; then
  if [ -f .env ]; then
    ENV_FILE=.env
  elif [ -f .env.production ]; then
    ENV_FILE=.env.production
  else
    ENV_FILE=.env.development
  fi
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
mkdir -p backups

docker compose --env-file "$ENV_FILE" exec -T mysql sh -c 'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' > "backups/mysql-${timestamp}.sql"
tar -czf "backups/data-${timestamp}.tar.gz" data/new-api data/redis

echo "Created backups/mysql-${timestamp}.sql"
echo "Created backups/data-${timestamp}.tar.gz"
