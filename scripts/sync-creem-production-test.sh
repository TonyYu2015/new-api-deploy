#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

ENV_FILE="${1:-${ENV_FILE:-.env.dev}}"
DEPLOY_HOST="${DEPLOY_HOST:-oracle}"
DEPLOY_PATH="${DEPLOY_PATH:-/opt/new-api-deploy}"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing env file: $ENV_FILE" >&2
  exit 1
fi

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
: "${CREEM_TEST_USER_EMAIL:=creem-test@ccaiservice.com}"

if [ -z "${CREEM_API_KEY:-}" ]; then
  echo "CREEM_API_KEY is required in $ENV_FILE" >&2
  exit 1
fi

if [ -z "${CREEM_WEBHOOK_SECRET:-}" ]; then
  echo "CREEM_WEBHOOK_SECRET is required in $ENV_FILE" >&2
  exit 1
fi

if [ -z "${CREEM_PRODUCT_ID:-}" ]; then
  echo "CREEM_PRODUCT_ID is required in $ENV_FILE" >&2
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

quota=$((CREEM_PRODUCT_PRICE * CREEM_QUOTA_PER_USD))
creem_products="[{\"name\":\"${CREEM_PRODUCT_NAME}\",\"productId\":\"${CREEM_PRODUCT_ID}\",\"price\":${CREEM_PRODUCT_PRICE},\"currency\":\"${CREEM_PRODUCT_CURRENCY}\",\"quota\":${quota}}]"

shell_quote() {
  printf "%q" "$1"
}

ssh "$DEPLOY_HOST" \
  "DEPLOY_PATH=$(shell_quote "$DEPLOY_PATH") CREEM_TEST_MODE=$(shell_quote "$CREEM_TEST_MODE") CREEM_API_KEY=$(shell_quote "$CREEM_API_KEY") CREEM_WEBHOOK_SECRET=$(shell_quote "$CREEM_WEBHOOK_SECRET") CREEM_PRODUCT_ID=$(shell_quote "$CREEM_PRODUCT_ID") CREEM_PRODUCT_NAME=$(shell_quote "$CREEM_PRODUCT_NAME") CREEM_PRODUCT_PRICE=$(shell_quote "$CREEM_PRODUCT_PRICE") CREEM_PRODUCT_CURRENCY=$(shell_quote "$CREEM_PRODUCT_CURRENCY") CREEM_QUOTA_PER_USD=$(shell_quote "$CREEM_QUOTA_PER_USD") CREEM_PRODUCTS=$(shell_quote "$creem_products") CREEM_TEST_USER_EMAIL=$(shell_quote "$CREEM_TEST_USER_EMAIL") bash -s" <<'REMOTE'
set -euo pipefail

cd "$DEPLOY_PATH"

BASE_ENV_FILE=".env.production"
LOCAL_ENV_FILE=".env.production.local"

if [ ! -f "$BASE_ENV_FILE" ]; then
  echo "Missing production env file: $DEPLOY_PATH/$BASE_ENV_FILE" >&2
  exit 1
fi

umask 077
touch "$LOCAL_ENV_FILE"
chmod 600 "$LOCAL_ENV_FILE"

env_quote() {
  printf "'%s'" "$(printf "%s" "$1" | sed "s/'/'\\\\''/g")"
}

set_env_value() {
  local key="$1"
  local value="$2"
  local quoted
  quoted="$(env_quote "$value")"
  if grep -q "^${key}=" "$LOCAL_ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${quoted}|" "$LOCAL_ENV_FILE"
  else
    printf "%s=%s\n" "$key" "$quoted" >> "$LOCAL_ENV_FILE"
  fi
}

sql_escape() {
  printf "%s" "$1" | sed "s/'/''/g"
}

set_env_value CREEM_TEST_MODE "$CREEM_TEST_MODE"
set_env_value CREEM_API_KEY "$CREEM_API_KEY"
set_env_value CREEM_WEBHOOK_SECRET "$CREEM_WEBHOOK_SECRET"
set_env_value CREEM_PRODUCT_ID "$CREEM_PRODUCT_ID"
set_env_value CREEM_PRODUCT_NAME "$CREEM_PRODUCT_NAME"
set_env_value CREEM_PRODUCT_PRICE "$CREEM_PRODUCT_PRICE"
set_env_value CREEM_PRODUCT_CURRENCY "$CREEM_PRODUCT_CURRENCY"
set_env_value CREEM_QUOTA_PER_USD "$CREEM_QUOTA_PER_USD"
set_env_value CREEM_TEST_USER_EMAIL "$CREEM_TEST_USER_EMAIL"

mysql_password="$(sed -n 's/^MYSQL_PASSWORD=//p' "$LOCAL_ENV_FILE" | tail -n 1)"
if [ -z "$mysql_password" ]; then
  mysql_password="$(sed -n 's/^MYSQL_PASSWORD=//p' "$BASE_ENV_FILE" | tail -n 1)"
fi
now="$(date +%s)"

creem_test_mode="$(sql_escape "$CREEM_TEST_MODE")"
creem_api_key="$(sql_escape "$CREEM_API_KEY")"
creem_webhook_secret="$(sql_escape "$CREEM_WEBHOOK_SECRET")"
creem_products="$(sql_escape "$CREEM_PRODUCTS")"
creem_test_user_email="$(sql_escape "$CREEM_TEST_USER_EMAIL")"

sudo docker compose --env-file "$BASE_ENV_FILE" --env-file "$LOCAL_ENV_FILE" exec -T mysql mysql -unew_api -p"$mysql_password" new_api -e "
insert into options (\`key\`, value) values
('CreemTestMode','$creem_test_mode'),
('CreemApiKey','$creem_api_key'),
('CreemWebhookSecret','$creem_webhook_secret'),
('CreemProducts','$creem_products'),
('payment_setting.compliance_confirmed','true'),
('payment_setting.compliance_terms_version','v1'),
('payment_setting.compliance_confirmed_at','$now'),
('payment_setting.compliance_confirmed_by','1')
on duplicate key update value=values(value);
update users
set email = '$creem_test_user_email'
where id = 1 and (email is null or email = '');
select \`key\`,
  case
    when \`key\` like '%Secret%' or \`key\` like '%ApiKey%' then concat(left(value,8),'...')
    else left(value,300)
  end as value
from options
where \`key\` like 'Creem%' or \`key\` like 'payment_setting.compliance%'
order by \`key\`;
select id, username, email from users where id = 1;
"
REMOTE

echo "Synced production Creem settings in test mode."
