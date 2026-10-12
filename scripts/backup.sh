#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck source=lib/env.sh
. scripts/lib/env.sh

ENV_FILE="${ENV_FILE:-.env.dev}"
if [ ! -f "$ENV_FILE" ]; then
  echo "Environment file not found: $ENV_FILE" >&2
  exit 1
fi

mapfile -t ENV_ARGS < <(env_args "$ENV_FILE")

new_api_data_dir="$(env_read NEW_API_DATA_DIR "$ENV_FILE")"
redis_data_dir="$(env_read REDIS_DATA_DIR "$ENV_FILE")"

timestamp="$(date +%Y%m%d-%H%M%S)"
mkdir -p backups

docker compose "${ENV_ARGS[@]}" exec -T mysql sh -c 'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' > "backups/mysql-${timestamp}.sql"
tar -czf "backups/data-${timestamp}.tar.gz" "${new_api_data_dir:-./data/new-api}" "${redis_data_dir:-./data/redis}"

echo "Created backups/mysql-${timestamp}.sql"
echo "Created backups/data-${timestamp}.tar.gz"
