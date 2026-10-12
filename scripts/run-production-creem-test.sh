#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

ENV_FILE="${1:-${ENV_FILE:-.env.dev}}"
DEPLOY_HOST="${DEPLOY_HOST:-oracle}"
DEPLOY_PATH="${DEPLOY_PATH:-/opt/new-api-deploy}"
PUBLIC_ORIGIN="${PUBLIC_ORIGIN:-https://www.ccaiservice.com}"

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

if [ -z "${CREEM_PRODUCT_ID:-}" ]; then
  echo "CREEM_PRODUCT_ID is required in $ENV_FILE" >&2
  exit 1
fi

shell_quote() {
  printf "%q" "$1"
}

ssh "$DEPLOY_HOST" \
  "DEPLOY_PATH=$(shell_quote "$DEPLOY_PATH") PUBLIC_ORIGIN=$(shell_quote "$PUBLIC_ORIGIN") CREEM_PRODUCT_ID=$(shell_quote "$CREEM_PRODUCT_ID") bash -s" <<'REMOTE'
set -euo pipefail

cd "$DEPLOY_PATH"

mysql_password="$(sed -n 's/^MYSQL_PASSWORD=//p' .env.production.local 2>/dev/null | tail -n 1)"
if [ -z "$mysql_password" ]; then
  mysql_password="$(sed -n 's/^MYSQL_PASSWORD=//p' .env.production | tail -n 1)"
fi
new_token="$(openssl rand -hex 16)"

compose_args=(--env-file .env.production)
if [ -f .env.production.local ]; then
  compose_args+=(--env-file .env.production.local)
fi

sudo docker compose "${compose_args[@]}" exec -T mysql mysql -unew_api -p"$mysql_password" new_api -e "
update users
set access_token = '$new_token'
where id = 1;
select id, username, email, concat(left(access_token,6),'...') as access_token
from users
where id = 1;
" < /dev/null

token="$new_token"

try_topup_info() {
  local label="$1"
  shift
  echo "AUTH:$label topup-info"
  curl -sS "$@" "$PUBLIC_ORIGIN/api/user/topup/info" | head -c 1200
  echo
}

try_checkout() {
  local label="$1"
  shift
  echo "AUTH:$label checkout"
  curl -sS "$@" \
    -H 'Content-Type: application/json' \
    -d "{\"product_id\":\"$CREEM_PRODUCT_ID\",\"payment_method\":\"creem\"}" \
    "$PUBLIC_ORIGIN/api/user/creem/pay" | head -c 2000
  echo
}

try_topup_info bearer -H "Authorization: Bearer $token" -H "New-Api-User: 1"
try_topup_info x-api-key -H "X-Api-Key: $token"
try_topup_info new-api-token -H "New-Api-Token: $token"

try_checkout bearer -H "Authorization: Bearer $token" -H "New-Api-User: 1"
REMOTE
