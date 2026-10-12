#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-.env.dev}"
FOOTER_FILE="${2:-config/footer.html}"

if [ ! -f "$ENV_FILE" ]; then
  echo "Environment file not found: $ENV_FILE" >&2
  exit 1
fi

if [ ! -f "$FOOTER_FILE" ]; then
  echo "Footer file not found: $FOOTER_FILE" >&2
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

footer_base64="$(base64 -w 0 "$FOOTER_FILE")"

docker compose "${ENV_ARGS[@]}" exec -T mysql \
  mysql "--user=${mysql_user}" "--password=${mysql_password}" "$mysql_database" \
  -e "INSERT INTO options (\`key\`, value) VALUES ('Footer', CONVERT(FROM_BASE64('${footer_base64}') USING utf8mb4)) ON DUPLICATE KEY UPDATE value = VALUES(value);" \
  >/dev/null

docker compose "${ENV_ARGS[@]}" restart new-api >/dev/null

echo "Site footer synchronized from $FOOTER_FILE"
