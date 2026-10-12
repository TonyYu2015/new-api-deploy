#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-.env.dev}"

if [ ! -f "$ENV_FILE" ]; then
  echo "Environment file not found: $ENV_FILE" >&2
  exit 1
fi

# shellcheck source=lib/env.sh
. scripts/lib/env.sh

mapfile -t ENV_ARGS < <(env_args "$ENV_FILE")

mysql_password="$(env_read MYSQL_PASSWORD "$ENV_FILE")"
mysql_user="$(env_read MYSQL_USER "$ENV_FILE")"
mysql_database="$(env_read MYSQL_DATABASE "$ENV_FILE")"

mysql_user="${mysql_user:-new_api}"
mysql_database="${mysql_database:-new_api}"

if [ -z "$mysql_password" ]; then
  echo "MYSQL_PASSWORD is required in $ENV_FILE or ${ENV_FILE}.local" >&2
  exit 1
fi

sql="
INSERT INTO options (\`key\`, value) VALUES
  ('ModelRequestRateLimitEnabled', 'true'),
  ('ModelRequestRateLimitDurationMinutes', '1'),
  ('ModelRequestRateLimitCount', '30'),
  ('ModelRequestRateLimitSuccessCount', '30'),
  ('RetryTimes', '1')
ON DUPLICATE KEY UPDATE value = VALUES(value);
"

docker compose "${ENV_ARGS[@]}" exec -T mysql \
  mysql "-u${mysql_user}" "-p${mysql_password}" "$mysql_database" \
  -e "$sql"

docker compose "${ENV_ARGS[@]}" restart new-api >/dev/null

echo "Gateway safeguards configured:"
echo "  authenticated user limit: 30 requests/minute"
echo "  failed relay retries: 1"
