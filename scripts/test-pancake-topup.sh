#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

ENV_FILE="${ENV_FILE:-.env.development}"
ORIGIN="${PANCAKE_TEST_BASE_URL:-}"
TARGET="${PANCAKE_TEST_TARGET:-local}"
STAGING_HOST="${PANCAKE_STAGING_HOST:-oracle}"
STAGING_PATH="${PANCAKE_STAGING_PATH:-/opt/new-api-deploy}"
STAGING_ENV_FILE="${PANCAKE_STAGING_ENV_FILE:-.env.staging}"
STAGING_AUTH_FILE="${PANCAKE_STAGING_AUTH_FILE:-ui-tests/.env.e2e}"
PREFLIGHT_ONLY=false
REPORT_DIR="${PANCAKE_TEST_REPORT_DIR:-.local-run}"
POLL_TIMEOUT="${PANCAKE_POLL_TIMEOUT:-900}"
POLL_INTERVAL="${PANCAKE_POLL_INTERVAL:-2}"

usage() {
  cat <<'EOF'
Usage: scripts/test-pancake-topup.sh [options]

Interactively validate the Waffo Pancake sandbox top-up flow. Local mode is
limited to configuration preflight. Staging mode keeps the API, database,
webhook, order, and UI return in test.ccaiservice.com for full validation.

Options:
  --target TARGET      local or staging (default: local)
  --env-file FILE      Local Compose env file (default: .env.development)
  --base-url URL       Override the target API origin
  --auth-file FILE     Staging E2E credentials (default: ui-tests/.env.e2e)
  --staging-host HOST  SSH host for staging (default: oracle)
  --staging-path PATH  Remote deployment path (default: /opt/new-api-deploy)
  --preflight-only     Validate configuration without creating an order
  --poll-timeout SEC   Payment polling timeout (default: 900)
  -h, --help           Show this help

Run the complete flow with: scripts/test-pancake-topup.sh --target staging
Staging credentials are read without being displayed or copied into reports.
EOF
}

while (($# > 0)); do
  case "$1" in
    --target)
      [[ $# -ge 2 ]] || { echo "--target requires a value" >&2; exit 2; }
      TARGET="$2"
      shift 2
      ;;
    --env-file)
      [[ $# -ge 2 ]] || { echo "--env-file requires a value" >&2; exit 2; }
      ENV_FILE="$2"
      shift 2
      ;;
    --base-url)
      [[ $# -ge 2 ]] || { echo "--base-url requires a value" >&2; exit 2; }
      ORIGIN="$2"
      shift 2
      ;;
    --auth-file)
      [[ $# -ge 2 ]] || { echo "--auth-file requires a value" >&2; exit 2; }
      STAGING_AUTH_FILE="$2"
      shift 2
      ;;
    --staging-host)
      [[ $# -ge 2 ]] || { echo "--staging-host requires a value" >&2; exit 2; }
      STAGING_HOST="$2"
      shift 2
      ;;
    --staging-path)
      [[ $# -ge 2 ]] || { echo "--staging-path requires a value" >&2; exit 2; }
      STAGING_PATH="$2"
      shift 2
      ;;
    --preflight-only)
      PREFLIGHT_ONLY=true
      shift
      ;;
    --poll-timeout)
      [[ $# -ge 2 ]] || { echo "--poll-timeout requires a value" >&2; exit 2; }
      POLL_TIMEOUT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ "$TARGET" == "local" || "$TARGET" == "staging" ]] || {
  echo "Target must be local or staging" >&2
  exit 2
}
if [[ "$TARGET" == "local" && "$PREFLIGHT_ONLY" != "true" ]]; then
  echo "Local target supports preflight only because Pancake cannot deliver its webhook to localhost." >&2
  echo "Use --preflight-only locally or --target staging for the complete payment flow." >&2
  exit 1
fi
[[ "$POLL_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || { echo "Poll timeout must be a positive integer" >&2; exit 2; }
[[ "$POLL_INTERVAL" =~ ^[1-9][0-9]*$ ]] || { echo "Poll interval must be a positive integer" >&2; exit 2; }

for command_name in curl grep openssl python3; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "$command_name is required" >&2
    exit 1
  }
done

if [[ "$TARGET" == "local" ]]; then
  [[ -f "$ENV_FILE" ]] || { echo "Environment file not found: $ENV_FILE" >&2; exit 1; }
  command -v docker >/dev/null 2>&1 || { echo "docker is required" >&2; exit 1; }
  docker compose version >/dev/null 2>&1 || { echo "docker compose is required" >&2; exit 1; }
else
  [[ -f "$STAGING_AUTH_FILE" ]] || { echo "Staging auth file not found: $STAGING_AUTH_FILE" >&2; exit 1; }
  command -v ssh >/dev/null 2>&1 || { echo "ssh is required" >&2; exit 1; }
fi

read_env_from() {
  python3 -c '
import sys

key = sys.argv[1]
with open(sys.argv[2], encoding="utf-8") as handle:
    for raw_line in handle:
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        name, value = line.split("=", 1)
        if name.strip() != key:
            continue
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"\x27":
            value = value[1:-1]
        print(value)
        break
' "$1" "$2"
}

if [[ -z "$ORIGIN" ]]; then
  if [[ "$TARGET" == "local" ]]; then
    HTTP_PORT="$(read_env_from HTTP_PORT "$ENV_FILE")"
    ORIGIN="http://127.0.0.1:${HTTP_PORT:-3101}"
  else
    ORIGIN="$(read_env_from E2E_BASE_URL "$STAGING_AUTH_FILE")"
    ORIGIN="${ORIGIN:-https://test.ccaiservice.com}"
  fi
fi
ORIGIN="${ORIGIN%/}"

if [[ "$TARGET" == "local" ]]; then
  case "$ORIGIN" in
    http://127.0.0.1:*|http://localhost:*|https://127.0.0.1:*|https://localhost:*) ;;
    *) echo "Local target requires a localhost API origin" >&2; exit 1 ;;
  esac
  COMPOSE=(docker compose --env-file "$ENV_FILE")
  ENVIRONMENT_LABEL="local ($ENV_FILE)"
else
  [[ "$ORIGIN" == "https://test.ccaiservice.com" ]] || {
    echo "Staging target is restricted to https://test.ccaiservice.com" >&2
    exit 1
  }
  STAGING_PATH_Q="$(printf '%q' "$STAGING_PATH")"
  STAGING_ENV_FILE_Q="$(printf '%q' "$STAGING_ENV_FILE")"
  REMOTE_COMPOSE="cd $STAGING_PATH_Q && sudo docker compose --env-file $STAGING_ENV_FILE_Q"
  ENVIRONMENT_LABEL="staging ($STAGING_HOST:$STAGING_PATH)"
fi

RUN_ID="$(date '+%Y%m%d-%H%M%S')"
RUN_STARTED_AT="$(date --iso-8601=seconds)"
TMP_DIR="$(mktemp -d)"
REPORT_FILE="$REPORT_DIR/pancake-topup-$TARGET-$RUN_ID.md"
AUTH_CONFIG="$TMP_DIR/curl-auth.conf"
CURRENT_STEP="initialization"
TEMP_ACCESS_TOKEN=""
TEMP_ACCESS_TOKEN_CREATED=false
TARGET_USER_ID=""
umask 077
mkdir -p "$REPORT_DIR"

db_query() {
  local sql="$1"
  if [[ "$TARGET" == "local" ]]; then
    printf '%s\n' "$sql" | "${COMPOSE[@]}" exec -T mysql sh -lc \
      'MYSQL_PWD="$MYSQL_PASSWORD" mysql -u"$MYSQL_USER" "$MYSQL_DATABASE" --batch --skip-column-names 2>/dev/null'
  else
    printf '%s\n' "$sql" | ssh "$STAGING_HOST" \
      "$REMOTE_COMPOSE exec -T mysql sh -lc 'MYSQL_PWD=\"\$MYSQL_PASSWORD\" mysql -u\"\$MYSQL_USER\" \"\$MYSQL_DATABASE\" --batch --skip-column-names 2>/dev/null'"
  fi
}

app_logs_since() {
  local since="$1"
  local output_file="$2"
  if [[ "$TARGET" == "local" ]]; then
    "${COMPOSE[@]}" logs --no-color --since "$since" new-api >"$output_file" 2>&1
  else
    local since_q
    since_q="$(printf '%q' "$since")"
    ssh "$STAGING_HOST" "$REMOTE_COMPOSE logs --no-color --since $since_q new-api" \
      >"$output_file" 2>&1
  fi
}

cleanup() {
  local exit_code=$?
  set +e
  if [[ "$TEMP_ACCESS_TOKEN_CREATED" == "true" &&
        "$TARGET_USER_ID" =~ ^[1-9][0-9]*$ &&
        "$TEMP_ACCESS_TOKEN" =~ ^[0-9a-f]{32}$ ]]; then
    db_query "
UPDATE users
SET access_token = NULL
WHERE id = $TARGET_USER_ID
  AND access_token = '$TEMP_ACCESS_TOKEN';
" >/dev/null 2>&1
  fi
  rm -rf "$TMP_DIR"
  return "$exit_code"
}
trap cleanup EXIT

cat >"$REPORT_FILE" <<EOF
# Waffo Pancake top-up validation

- Run: $RUN_ID
- Started: $RUN_STARTED_AT
- Target: $ENVIRONMENT_LABEL
- Origin: $ORIGIN
- Sensitive values: omitted

| Time | Step | Result | Notes |
|---|---|---|---|
EOF

report_step() {
  local step="$1"
  local result="$2"
  local notes="${3:-}"
  notes="${notes//$'\n'/ }"
  notes="${notes//|/\\|}"
  printf '| %s | %s | %s | %s |\n' \
    "$(date --iso-8601=seconds)" "$step" "$result" "$notes" >>"$REPORT_FILE"
}

die() {
  local message="$1"
  report_step "$CURRENT_STEP" "FAIL" "$message"
  echo "ERROR: $message" >&2
  echo "Report: $REPORT_FILE" >&2
  exit 1
}

json_get() {
  local file="$1"
  local path="$2"
  python3 - "$file" "$path" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
for part in sys.argv[2].split("."):
    if not part:
        continue
    if not isinstance(value, dict) or part not in value:
        raise SystemExit(3)
    value = value[part]
if isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    print("")
elif isinstance(value, (dict, list)):
    print(json.dumps(value, ensure_ascii=False, separators=(",", ":")))
else:
    print(value)
PY
}

json_success() {
  [[ "$(json_get "$1" success 2>/dev/null || true)" == "true" ]]
}

json_message() {
  local message
  message="$(json_get "$1" message 2>/dev/null || true)"
  if [[ -z "$message" || "$message" == "error" ]]; then
    message="$(json_get "$1" data 2>/dev/null || true)"
  fi
  [[ -n "$message" ]] && printf '%s' "$message" || printf 'Unknown API error'
}

api_request() {
  local output_file="$1"
  shift
  local http_status
  if ! http_status="$(curl --noproxy '*' --silent --show-error --max-time 45 \
      --output "$output_file" --write-out '%{http_code}' "$@")"; then
    return 1
  fi
  [[ "$http_status" =~ ^2[0-9][0-9]$ ]]
}

sql_escape() {
  printf '%s' "$1" | sed "s/'/''/g"
}

utf8_hex() {
  python3 -c 'import sys; print(sys.stdin.buffer.read().hex())'
}

latest_completed_email_user_id() {
  local report
  while IFS= read -r report; do
    if grep -q '| complete | PASS | Email registration flow completed for user ID ' "$report"; then
      sed -nE 's/.*Email registration flow completed for user ID ([0-9]+).*/\1/p' "$report" | head -1
      return
    fi
  done < <(find .local-run -maxdepth 1 -type f -name 'email-registration-*.md' | sort -r)
}

CURRENT_STEP="service preflight"
echo "[1/8] Checking $TARGET services and Pancake configuration..."
STATUS_RESPONSE="$TMP_DIR/status.json"
api_request "$STATUS_RESPONSE" "$ORIGIN/api/status" || die "Cannot reach $ORIGIN/api/status"
json_success "$STATUS_RESPONSE" || die "Status API returned failure: $(json_message "$STATUS_RESPONSE")"
VERSION="$(json_get "$STATUS_RESPONSE" data.version 2>/dev/null || true)"
QUOTA_PER_UNIT="$(json_get "$STATUS_RESPONSE" data.quota_per_unit 2>/dev/null || true)"
[[ "$QUOTA_PER_UNIT" =~ ^[1-9][0-9]*$ ]] || die "Status API returned an invalid quota_per_unit"

MISSING_PANCAKE_OPTIONS="$(db_query '
SELECT `key`
FROM options
WHERE `key` IN (
  "WaffoPancakeMerchantID", "WaffoPancakePrivateKey",
  "WaffoPancakeReturnURL", "WaffoPancakeStoreID",
  "WaffoPancakeProductID", "WaffoPancakeMinTopUp"
)
  AND (value IS NULL OR LENGTH(value) = 0)
ORDER BY `key`;
' || true)"
[[ -z "$MISSING_PANCAKE_OPTIONS" ]] || \
  die "Missing Pancake options: $(printf '%s' "$MISSING_PANCAKE_OPTIONS" | paste -sd, -)"

PANCAKE_OPTION_COUNT="$(db_query '
SELECT COUNT(*)
FROM options
WHERE `key` IN (
  "WaffoPancakeMerchantID", "WaffoPancakePrivateKey",
  "WaffoPancakeReturnURL", "WaffoPancakeStoreID",
  "WaffoPancakeProductID", "WaffoPancakeMinTopUp"
);
' || true)"
[[ "$PANCAKE_OPTION_COUNT" == "6" ]] || die "One or more required Pancake options do not exist"

COMPLIANCE_STATE="$(db_query '
SELECT CONCAT(
  COALESCE(MAX(CASE WHEN `key`="payment_setting.compliance_confirmed" THEN value END), ""),
  ":",
  COALESCE(MAX(CASE WHEN `key`="payment_setting.compliance_terms_version" THEN value END), "")
)
FROM options;
' || true)"
[[ "$COMPLIANCE_STATE" == "true:v1" ]] || die "Payment compliance confirmation is not current"

RETURN_URL="$(db_query 'SELECT value FROM options WHERE `key`="WaffoPancakeReturnURL" LIMIT 1;' || true)"
[[ "$RETURN_URL" == http://* || "$RETURN_URL" == https://* ]] || die "Pancake return URL is invalid"
if [[ "$RETURN_URL" == *"www.ccaiservice.com"* ]]; then
  die "Pancake return URL points to production; refusing sandbox validation"
fi
RETURN_HOST="$(python3 -c 'import sys,urllib.parse; print(urllib.parse.urlparse(sys.argv[1]).netloc)' "$RETURN_URL")"
ORIGIN_HOST="$(python3 -c 'import sys,urllib.parse; print(urllib.parse.urlparse(sys.argv[1]).netloc)' "$ORIGIN")"
if [[ "$TARGET" == "staging" && "$RETURN_HOST" != "$ORIGIN_HOST" ]]; then
  die "Pancake return host $RETURN_HOST does not match staging API host $ORIGIN_HOST"
fi
report_step "$CURRENT_STEP" "PASS" "Pancake options and compliance are configured; version $VERSION; return host $RETURN_HOST"
echo "      Configuration preflight passed (version $VERSION, return host $RETURN_HOST)."

CURRENT_STEP="test user selection"
if [[ "$TARGET" == "staging" ]]; then
  TARGET_USER_ID="$(read_env_from E2E_USER_ID "$STAGING_AUTH_FILE")"
  AUTH_ACCESS_TOKEN="$(read_env_from E2E_ACCESS_TOKEN "$STAGING_AUTH_FILE")"
  [[ "$TARGET_USER_ID" =~ ^[1-9][0-9]*$ ]] || die "E2E_USER_ID is missing or invalid in $STAGING_AUTH_FILE"
  [[ -n "$AUTH_ACCESS_TOKEN" ]] || die "E2E_ACCESS_TOKEN is missing in $STAGING_AUTH_FILE"
  if ! TARGET_USER_ROW="$(db_query "
SELECT username, quota,
       IF(email IS NULL OR email='', 'missing', 'set')
FROM users
WHERE id=$TARGET_USER_ID
  AND deleted_at IS NULL
  AND role=1
  AND status=1
LIMIT 1;
")"; then
    die "Unable to query the configured staging test user"
  fi
  [[ -n "$TARGET_USER_ROW" ]] || die "Configured staging user is not an active ordinary test user"
  IFS=$'\t' read -r TARGET_USERNAME INITIAL_QUOTA EMAIL_STATE <<<"$TARGET_USER_ROW"
else
  DEFAULT_USER_ID="$(latest_completed_email_user_id || true)"
  [[ "$DEFAULT_USER_ID" =~ ^[1-9][0-9]*$ ]] || die "No completed local email-registration test user was found"
  TARGET_USER_ID="$DEFAULT_USER_ID"
  if ! TARGET_USER_ROW="$(db_query "
SELECT username, quota,
       IF(email IS NULL OR email='', 'missing', 'set'),
       IF(access_token IS NULL OR access_token='', 'missing', 'set')
FROM users
WHERE id=$TARGET_USER_ID
  AND deleted_at IS NULL
  AND role=1
  AND status=1
  AND username LIKE 'e2e\\_%'
LIMIT 1;
")"; then
    die "Unable to query the selected local test user"
  fi
  [[ -n "$TARGET_USER_ROW" ]] || die "Selected user is not an active ordinary e2e_ test user"
  IFS=$'\t' read -r TARGET_USERNAME INITIAL_QUOTA EMAIL_STATE ACCESS_TOKEN_STATE <<<"$TARGET_USER_ROW"
  [[ "$ACCESS_TOKEN_STATE" == "missing" ]] || die "Selected local test user already has an access token; refusing to overwrite it"

  TEMP_ACCESS_TOKEN="$(openssl rand -hex 16)"
  TOKEN_UPDATE_RESULT="$(db_query "
UPDATE users
SET access_token='$TEMP_ACCESS_TOKEN'
WHERE id=$TARGET_USER_ID
  AND (access_token IS NULL OR access_token='');
SELECT ROW_COUNT();
")"
  [[ "$TOKEN_UPDATE_RESULT" == "1" ]] || die "Unable to assign a temporary local access token safely"
  TEMP_ACCESS_TOKEN_CREATED=true
  AUTH_ACCESS_TOKEN="$TEMP_ACCESS_TOKEN"
fi

[[ "$EMAIL_STATE" == "set" ]] || die "Selected test user does not have a registered email"
[[ "$INITIAL_QUOTA" =~ ^[0-9]+$ ]] || die "Selected test user has an invalid quota"

cat >"$AUTH_CONFIG" <<EOF
header = "Authorization: Bearer $AUTH_ACCESS_TOKEN"
header = "New-Api-User: $TARGET_USER_ID"
EOF
chmod 600 "$AUTH_CONFIG"
unset AUTH_ACCESS_TOKEN

SELF_RESPONSE="$TMP_DIR/self.json"
if ! api_request "$SELF_RESPONSE" --config "$AUTH_CONFIG" "$ORIGIN/api/user/self"; then
  die "Test authentication failed: $(json_message "$SELF_RESPONSE")"
fi
json_success "$SELF_RESPONSE" || die "Test authentication failed: $(json_message "$SELF_RESPONSE")"
SELF_USER_ID="$(json_get "$SELF_RESPONSE" data.id 2>/dev/null || true)"
[[ "$SELF_USER_ID" == "$TARGET_USER_ID" ]] || die "Authenticated user ID does not match the selected user"
report_step "$CURRENT_STEP" "PASS" "Authenticated $TARGET ordinary test user $TARGET_USERNAME (ID $TARGET_USER_ID)"
echo "[2/8] Test user authentication passed (ID $TARGET_USER_ID)."

CURRENT_STEP="top-up information"
TOPUP_INFO="$TMP_DIR/topup-info.json"
if ! api_request "$TOPUP_INFO" --config "$AUTH_CONFIG" "$ORIGIN/api/user/topup/info"; then
  die "Top-up information request failed: $(json_message "$TOPUP_INFO")"
fi
json_success "$TOPUP_INFO" || die "Top-up information returned failure: $(json_message "$TOPUP_INFO")"
PANCAKE_ENABLED="$(json_get "$TOPUP_INFO" data.enable_waffo_pancake_topup 2>/dev/null || true)"
CREEM_ENABLED="$(json_get "$TOPUP_INFO" data.enable_creem_topup 2>/dev/null || true)"
MIN_TOPUP="$(json_get "$TOPUP_INFO" data.waffo_pancake_min_topup 2>/dev/null || true)"
COMPLIANCE_CONFIRMED="$(json_get "$TOPUP_INFO" data.payment_compliance_confirmed 2>/dev/null || true)"
[[ "$PANCAKE_ENABLED" == "true" ]] || die "enable_waffo_pancake_topup is not true"
[[ "$COMPLIANCE_CONFIRMED" == "true" ]] || die "Payment compliance is not confirmed by the API"
[[ "$MIN_TOPUP" =~ ^[1-9][0-9]*$ ]] || die "Pancake minimum top-up amount is invalid"

if [[ "$CREEM_ENABLED" == "true" ]]; then
  report_step "$CURRENT_STEP" "WARN" "Legacy Creem top-up is still enabled"
  echo "WARNING: Legacy Creem top-up is still enabled; the target state expects it disabled." >&2
  if [[ "$PREFLIGHT_ONLY" != "true" ]]; then
    read -r -p "Continue testing Pancake anyway? [y/N]: " CREEM_CHOICE
    [[ "$CREEM_CHOICE" =~ ^[Yy]$ ]] || die "Stopped because legacy Creem remains enabled"
  fi
else
  report_step "$CURRENT_STEP" "PASS" "Pancake enabled; legacy Creem disabled; minimum amount $MIN_TOPUP"
fi
echo "[3/8] Pancake is enabled; minimum top-up amount is $MIN_TOPUP."

if [[ "$PREFLIGHT_ONLY" == "true" ]]; then
  echo "Preflight completed without creating a checkout or payment order."
  echo "Report: $REPORT_FILE"
  exit 0
fi

[[ -t 0 ]] || die "Interactive input requires a terminal"

CURRENT_STEP="sandbox confirmation"
echo
echo "Configured return host: $RETURN_HOST"
echo "Before creating an order, confirm that the Pancake merchant is in test mode"
echo "and its /test webhook is routed to the environment under validation."
read -r -p "Type 'sandbox' to confirm: " SANDBOX_CONFIRMATION
[[ "$SANDBOX_CONFIRMATION" == "sandbox" ]] || die "Sandbox and webhook routing were not confirmed"
report_step "$CURRENT_STEP" "PASS" "Operator confirmed sandbox mode and test webhook routing"

CURRENT_STEP="amount calculation"
read -r -p "Top-up amount [$MIN_TOPUP]: " TOPUP_AMOUNT
TOPUP_AMOUNT="${TOPUP_AMOUNT:-$MIN_TOPUP}"
[[ "$TOPUP_AMOUNT" =~ ^[1-9][0-9]*$ ]] || die "Top-up amount must be a positive integer"
(( TOPUP_AMOUNT >= MIN_TOPUP )) || die "Top-up amount cannot be lower than $MIN_TOPUP"
AMOUNT_PAYLOAD="$TMP_DIR/amount.json"
printf '{"amount":%s}\n' "$TOPUP_AMOUNT" >"$AMOUNT_PAYLOAD"
AMOUNT_RESPONSE="$TMP_DIR/amount-response.json"
if ! api_request "$AMOUNT_RESPONSE" --config "$AUTH_CONFIG" \
    --header 'Content-Type: application/json' --data-binary "@$AMOUNT_PAYLOAD" \
    "$ORIGIN/api/user/waffo-pancake/amount"; then
  die "Pancake amount calculation request failed: $(json_message "$AMOUNT_RESPONSE")"
fi
[[ "$(json_get "$AMOUNT_RESPONSE" message 2>/dev/null || true)" == "success" ]] || \
  die "Pancake amount calculation failed: $(json_message "$AMOUNT_RESPONSE")"
PAY_MONEY="$(json_get "$AMOUNT_RESPONSE" data 2>/dev/null || true)"
[[ "$PAY_MONEY" =~ ^[0-9]+([.][0-9]{1,2})?$ ]] || die "Pancake returned an invalid payment amount"
report_step "$CURRENT_STEP" "PASS" "Top-up amount $TOPUP_AMOUNT calculated as payment amount $PAY_MONEY"
echo "[4/8] Payment amount: $PAY_MONEY"

CURRENT_STEP="checkout creation"
read -r -p "Create this Pancake sandbox checkout? [y/N]: " CREATE_CHOICE
[[ "$CREATE_CHOICE" =~ ^[Yy]$ ]] || die "Checkout creation cancelled"
QUOTA_BEFORE="$(db_query "SELECT quota FROM users WHERE id=$TARGET_USER_ID;")"
ORDER_COUNT_BEFORE="$(db_query "SELECT COUNT(*) FROM top_ups WHERE user_id=$TARGET_USER_ID;")"
CHECKOUT_RESPONSE="$TMP_DIR/checkout-response.json"
if ! api_request "$CHECKOUT_RESPONSE" --config "$AUTH_CONFIG" \
    --header 'Content-Type: application/json' --data-binary "@$AMOUNT_PAYLOAD" \
    "$ORIGIN/api/user/waffo-pancake/pay"; then
  die "Pancake checkout request failed: $(json_message "$CHECKOUT_RESPONSE")"
fi
[[ "$(json_get "$CHECKOUT_RESPONSE" message 2>/dev/null || true)" == "success" ]] || \
  die "Pancake checkout creation failed: $(json_message "$CHECKOUT_RESPONSE")"
CHECKOUT_URL="$(json_get "$CHECKOUT_RESPONSE" data.checkout_url 2>/dev/null || true)"
ORDER_ID="$(json_get "$CHECKOUT_RESPONSE" data.order_id 2>/dev/null || true)"
[[ "$CHECKOUT_URL" == https://* ]] || die "Checkout URL is missing or is not HTTPS"
[[ "$ORDER_ID" == WAFFO_PANCAKE-* ]] || die "Pancake returned an invalid order ID"
ORDER_ID_HEX="$(printf '%s' "$ORDER_ID" | utf8_hex)"

if ! ORDER_ROW="$(db_query "
SELECT user_id, amount, money, payment_method, payment_provider, status
FROM top_ups
WHERE trade_no=CONVERT(0x$ORDER_ID_HEX USING utf8mb4) COLLATE utf8mb4_unicode_ci
LIMIT 1;
")"; then
  die "Unable to query the newly created top-up order"
fi
IFS=$'\t' read -r \
  ORDER_USER_ID ORDER_AMOUNT ORDER_MONEY ORDER_METHOD ORDER_PROVIDER ORDER_STATUS \
  <<<"$ORDER_ROW"
[[ "$ORDER_USER_ID" == "$TARGET_USER_ID" ]] || die "Top-up order belongs to an unexpected user"
[[ "$ORDER_METHOD" == "waffo_pancake" && "$ORDER_PROVIDER" == "waffo_pancake" ]] || \
  die "Top-up order payment method/provider is incorrect"
[[ "$ORDER_STATUS" == "pending" ]] || die "New top-up order is not pending"
ORDER_COUNT_AFTER="$(db_query "SELECT COUNT(*) FROM top_ups WHERE user_id=$TARGET_USER_ID;")"
[[ "$ORDER_COUNT_AFTER" == "$((ORDER_COUNT_BEFORE + 1))" ]] || die "Unexpected number of top-up records was created"
report_step "$CURRENT_STEP" "PASS" "Created pending Pancake order $ORDER_ID for payment amount $ORDER_MONEY"
echo "[5/8] Pending order created: $ORDER_ID"

CURRENT_STEP="operator payment"
echo
echo "Open this checkout URL and complete the sandbox payment:"
echo "$CHECKOUT_URL"
echo
read -r -p "After completing payment, press Enter to start automatic verification (or type cancel): " PAYMENT_INPUT
[[ "$PAYMENT_INPUT" != "cancel" ]] || die "Operator cancelled before payment verification"
report_step "$CURRENT_STEP" "PASS" "Operator indicated that sandbox checkout was completed"

CURRENT_STEP="payment polling"
echo "[6/8] Waiting for webhook credit (timeout ${POLL_TIMEOUT}s)..."
POLL_STARTED="$(date +%s)"
LAST_PROGRESS=0
FINAL_ORDER_STATUS="pending"
while true; do
  POLL_NOW="$(date +%s)"
  POLL_ELAPSED=$((POLL_NOW - POLL_STARTED))
  if (( POLL_ELAPSED >= POLL_TIMEOUT )); then
    die "Timed out waiting for order $ORDER_ID to leave pending status"
  fi
  if ! POLL_ROW="$(db_query "
SELECT status, complete_time, money, amount
FROM top_ups
WHERE trade_no=CONVERT(0x$ORDER_ID_HEX USING utf8mb4) COLLATE utf8mb4_unicode_ci
LIMIT 1;
")"; then
    die "Unable to poll the Pancake order"
  fi
  IFS=$'\t' read -r FINAL_ORDER_STATUS COMPLETE_TIME FINAL_MONEY FINAL_AMOUNT <<<"$POLL_ROW"
  case "$FINAL_ORDER_STATUS" in
    success) break ;;
    failed) die "Pancake order changed to failed" ;;
    pending) ;;
    *) die "Pancake order has unexpected status: $FINAL_ORDER_STATUS" ;;
  esac
  if (( POLL_ELAPSED - LAST_PROGRESS >= 15 )); then
    echo "      Still pending after ${POLL_ELAPSED}s..."
    LAST_PROGRESS="$POLL_ELAPSED"
  fi
  sleep "$POLL_INTERVAL"
done
[[ "$COMPLETE_TIME" =~ ^[1-9][0-9]*$ ]] || die "Successful order has no completion time"
report_step "$CURRENT_STEP" "PASS" "Order changed from pending to success after ${POLL_ELAPSED}s"

CURRENT_STEP="quota verification"
QUOTA_AFTER="$(db_query "SELECT quota FROM users WHERE id=$TARGET_USER_ID;")"
[[ "$QUOTA_BEFORE" =~ ^[0-9]+$ && "$QUOTA_AFTER" =~ ^[0-9]+$ && "$FINAL_AMOUNT" =~ ^[1-9][0-9]*$ ]] || \
  die "Quota or credited amount is invalid"
EXPECTED_QUOTA_DELTA=$((FINAL_AMOUNT * QUOTA_PER_UNIT))
ACTUAL_QUOTA_DELTA=$((QUOTA_AFTER - QUOTA_BEFORE))
[[ "$ACTUAL_QUOTA_DELTA" == "$EXPECTED_QUOTA_DELTA" ]] || \
  die "Quota increase $ACTUAL_QUOTA_DELTA does not match expected $EXPECTED_QUOTA_DELTA"

SELF_AFTER_RESPONSE="$TMP_DIR/self-after.json"
if ! api_request "$SELF_AFTER_RESPONSE" --config "$AUTH_CONFIG" "$ORIGIN/api/user/self"; then
  die "Post-payment /api/user/self request failed: $(json_message "$SELF_AFTER_RESPONSE")"
fi
SELF_QUOTA_AFTER="$(json_get "$SELF_AFTER_RESPONSE" data.quota 2>/dev/null || true)"
[[ "$SELF_QUOTA_AFTER" == "$QUOTA_AFTER" ]] || die "Post-payment API quota does not match the database"
report_step "$CURRENT_STEP" "PASS" "User quota increased by $ACTUAL_QUOTA_DELTA and API/database values match"
echo "[7/8] Order and quota verification passed."

CURRENT_STEP="webhook and log verification"
APP_LOG="$TMP_DIR/new-api.log"
app_logs_since "$RUN_STARTED_AT" "$APP_LOG" || \
  die "Unable to read new-api logs"
grep -Fq "Waffo Pancake webhook 验签成功" "$APP_LOG" || die "Webhook signature success was not found in application logs"
grep -Fq "Waffo Pancake 充值成功 trade_no=$ORDER_ID" "$APP_LOG" || die "Order credit success was not found in application logs"
SEVERE_ERROR_COUNT="$(
  (grep -Ei 'panic|fatal|http[^0-9]{0,8}500|status[^0-9]{0,4}500' "$APP_LOG" || true) | wc -l
)"
[[ "$SEVERE_ERROR_COUNT" == "0" ]] || die "Application log contains $SEVERE_ERROR_COUNT possible severe errors"
report_step "$CURRENT_STEP" "PASS" "Webhook signature, order credit, and severe-error log checks passed"

CURRENT_STEP="return UI confirmation"
echo
echo "      Verifying the Wallet return with the same staging test user..."
PLAYWRIGHT_BIN="$PWD/ui-tests/node_modules/.bin/playwright"
[[ -x "$PLAYWRIGHT_BIN" ]] || \
  die "Playwright is not installed; run npm install and npm run install:browsers in ui-tests"

EXPECTED_BALANCE="$(python3 - "$QUOTA_AFTER" "$QUOTA_PER_UNIT" <<'PY'
import sys

quota = int(sys.argv[1])
quota_per_unit = int(sys.argv[2])
amount = quota / quota_per_unit
if amount.is_integer():
    print(f"${int(amount):,}")
else:
    print(f"${amount:,.4f}".rstrip("0").rstrip("."))
PY
)"
UI_ACCESS_TOKEN="$(read_env_from E2E_ACCESS_TOKEN "$STAGING_AUTH_FILE")"
[[ -n "$UI_ACCESS_TOKEN" ]] || die "E2E_ACCESS_TOKEN is missing for the UI check"

if ! (
  cd ui-tests
  E2E_BASE_URL="$ORIGIN" \
  E2E_USER_ID="$TARGET_USER_ID" \
  E2E_ACCESS_TOKEN="$UI_ACCESS_TOKEN" \
  E2E_PANCAKE_QUOTA_BEFORE="$QUOTA_BEFORE" \
  E2E_PANCAKE_QUOTA_AFTER="$QUOTA_AFTER" \
  E2E_PANCAKE_EXPECTED_BALANCE="$EXPECTED_BALANCE" \
    ./node_modules/.bin/playwright test tests/wallet.spec.ts \
      --project=desktop \
      --grep "shows the credited balance for a CLI-created Pancake order" \
      --reporter=list
); then
  unset UI_ACCESS_TOKEN
  die "Automated Wallet return-page validation failed"
fi
unset UI_ACCESS_TOKEN
report_step "$CURRENT_STEP" "PASS" \
  "Same-user Wallet return removed the marker and displayed credited balance $EXPECTED_BALANCE"

CURRENT_STEP="complete"
report_step "$CURRENT_STEP" "PASS" "Pancake sandbox top-up flow completed for order $ORDER_ID"
echo "[8/8] Pancake sandbox top-up flow passed."
echo "Order ID: $ORDER_ID"
echo "Report: $REPORT_FILE"
