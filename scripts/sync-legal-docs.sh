#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-.env.dev}"
PRIVACY_FILE="${2:-config/privacy-policy.md}"
TERMS_FILE="${3:-config/terms-of-service.md}"

if [ ! -f "$ENV_FILE" ]; then
  echo "Environment file not found: $ENV_FILE" >&2
  exit 1
fi

if [ ! -f "$PRIVACY_FILE" ]; then
  echo "Privacy policy not found: $PRIVACY_FILE" >&2
  exit 1
fi

if [ ! -f "$TERMS_FILE" ]; then
  echo "Terms of service not found: $TERMS_FILE" >&2
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

privacy_base64="$(base64 -w 0 "$PRIVACY_FILE")"
terms_base64="$(base64 -w 0 "$TERMS_FILE")"

docker compose "${ENV_ARGS[@]}" exec -T mysql \
  mysql "--user=${mysql_user}" "--password=${mysql_password}" "$mysql_database" \
  -e "DELETE FROM options WHERE \`key\` IN ('PrivacyPolicy', 'UserAgreement'); INSERT INTO options (\`key\`, value) VALUES ('legal.privacy_policy', CONVERT(FROM_BASE64('${privacy_base64}') USING utf8mb4)), ('legal.user_agreement', CONVERT(FROM_BASE64('${terms_base64}') USING utf8mb4)) ON DUPLICATE KEY UPDATE value = VALUES(value);" \
  >/dev/null

docker compose "${ENV_ARGS[@]}" restart new-api >/dev/null

echo "Legal documents synchronized:"
echo "  privacy policy: $PRIVACY_FILE"
echo "  terms of service: $TERMS_FILE"
