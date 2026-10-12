#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

ENV_FILE="${1:-${ENV_FILE:-.env.dev}}"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing env file: $ENV_FILE" >&2
  exit 1
fi

# shellcheck source=lib/env.sh
. scripts/lib/env.sh

mapfile -t ENV_ARGS < <(env_args "$ENV_FILE")

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
if [ -f "${ENV_FILE}.local" ]; then
  # shellcheck disable=SC1090
  . "${ENV_FILE}.local"
fi
set +a

: "${CREEM_TEST_MODE:=true}"
: "${CREEM_PRODUCT_NAME:=Test \$5}"
: "${CREEM_PRODUCT_PRICE:=5}"
: "${CREEM_PRODUCT_CURRENCY:=USD}"
: "${CREEM_QUOTA_PER_USD:=500000}"
: "${CREEM_TEST_USER_EMAIL:=admin@example.com}"

if [ -z "${CREEM_API_KEY:-}" ]; then
  echo "CREEM_API_KEY is required in $ENV_FILE or ${ENV_FILE}.local" >&2
  exit 1
fi

if [ -z "${CREEM_WEBHOOK_SECRET:-}" ]; then
  echo "CREEM_WEBHOOK_SECRET is required in $ENV_FILE or ${ENV_FILE}.local" >&2
  exit 1
fi

if [ -z "${CREEM_PRODUCT_ID:-}" ]; then
  echo "CREEM_PRODUCT_ID is required in $ENV_FILE before Creem top-up can be enabled" >&2
  exit 1
fi

case "$CREEM_PRODUCT_PRICE" in
  ''|*[!0-9]*)
    echo "CREEM_PRODUCT_PRICE must be a whole number" >&2
    exit 1
    ;;
esac

case "$CREEM_QUOTA_PER_USD" in
  ''|*[!0-9]*)
    echo "CREEM_QUOTA_PER_USD must be a whole number" >&2
    exit 1
    ;;
esac

mysql_password="$(env_read MYSQL_PASSWORD "$ENV_FILE")"
quota=$((CREEM_PRODUCT_PRICE * CREEM_QUOTA_PER_USD))
creem_products="[{\"name\":\"${CREEM_PRODUCT_NAME}\",\"productId\":\"${CREEM_PRODUCT_ID}\",\"price\":${CREEM_PRODUCT_PRICE},\"currency\":\"${CREEM_PRODUCT_CURRENCY}\",\"quota\":${quota}}]"

sql_escape() {
  printf "%s" "$1" | sed "s/'/''/g"
}

creem_test_mode="$(sql_escape "$CREEM_TEST_MODE")"
creem_api_key="$(sql_escape "$CREEM_API_KEY")"
creem_webhook_secret="$(sql_escape "$CREEM_WEBHOOK_SECRET")"
creem_products="$(sql_escape "$creem_products")"
creem_test_user_email="$(sql_escape "$CREEM_TEST_USER_EMAIL")"

docker compose "${ENV_ARGS[@]}" exec -T mysql mysql -unew_api -p"$mysql_password" new_api -e "
insert into options (\`key\`, value) values
('CreemTestMode','$creem_test_mode'),
('CreemApiKey','$creem_api_key'),
('CreemWebhookSecret','$creem_webhook_secret'),
('CreemProducts','$creem_products')
on duplicate key update value=values(value);
select \`key\`,
  case
    when \`key\` like '%Secret%' or \`key\` like '%ApiKey%' then concat(left(value,8),'...')
    else value
  end as value
from options
where \`key\` like 'Creem%'
order by \`key\`;
update users
set email = '$creem_test_user_email'
where id = 1 and (email is null or email = '');
"

echo "Synced native Creem settings from $ENV_FILE."
