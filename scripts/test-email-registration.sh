#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

ENV_FILE="${ENV_FILE:-.env.dev}"
ORIGIN="${EMAIL_TEST_BASE_URL:-}"
PREFLIGHT_ONLY=false
REPORT_DIR="${EMAIL_TEST_REPORT_DIR:-.local-run}"

usage() {
  cat <<'EOF'
Usage: scripts/test-email-registration.sh [options]

Interactively validate the local email registration flow. The command pauses
for a test email address and its six-character hexadecimal verification code,
then continues
with registration, database verification, login, /api/user/self, and log checks.
If the email belongs to an existing ordinary test user whose username starts
with e2e_, the command can remove that user after explicit confirmation.

Options:
  --env-file FILE      Compose environment file (default: .env.dev)
  --base-url URL       Local HTTP origin (default: HTTP_PORT from env file)
  --preflight-only     Check services and configuration without sending email
  -h, --help           Show this help

Remote targets are refused unless ALLOW_REMOTE_EMAIL_TEST=true is explicitly
set. Passwords and verification codes are never printed or written to reports.
EOF
}

while (($# > 0)); do
  case "$1" in
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
    --preflight-only)
      PREFLIGHT_ONLY=true
      shift
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

[[ -f "$ENV_FILE" ]] || { echo "Environment file not found: $ENV_FILE" >&2; exit 1; }

# shellcheck source=lib/env.sh
. scripts/lib/env.sh

mapfile -t ENV_ARGS < <(env_args "$ENV_FILE")

for command_name in curl docker grep openssl python3; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "$command_name is required" >&2
    exit 1
  }
done

docker compose version >/dev/null 2>&1 || {
  echo "docker compose is required" >&2
  exit 1
}

read_env() {
  python3 -c '
import sys

key = sys.argv[1]
value = ""
for path in sys.argv[2:]:
    try:
        handle = open(path, encoding="utf-8")
    except FileNotFoundError:
        continue
    with handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            name, item = line.split("=", 1)
            if name.strip() != key:
                continue
            item = item.strip()
            if len(item) >= 2 and item[0] == item[-1] and item[0] in "\"\x27":
                item = item[1:-1]
            value = item
print(value)
' "$1" "$ENV_FILE" "${ENV_FILE}.local"
}

if [[ -z "$ORIGIN" ]]; then
  HTTP_PORT="$(read_env HTTP_PORT)"
  ORIGIN="http://127.0.0.1:${HTTP_PORT:-3101}"
fi
ORIGIN="${ORIGIN%/}"

case "$ORIGIN" in
  http://127.0.0.1:*|http://localhost:*|https://127.0.0.1:*|https://localhost:*) ;;
  *)
    if [[ "${ALLOW_REMOTE_EMAIL_TEST:-false}" != "true" ]]; then
      echo "Refusing to run email registration against a remote target: $ORIGIN" >&2
      echo "Set ALLOW_REMOTE_EMAIL_TEST=true only after confirming the target is safe." >&2
      exit 1
    fi
    ;;
esac

COMPOSE=(docker compose "${ENV_ARGS[@]}")
RUN_ID="$(date '+%Y%m%d-%H%M%S')"
RUN_STARTED_AT="$(date --iso-8601=seconds)"
TMP_DIR="$(mktemp -d)"
COOKIE_JAR="$TMP_DIR/cookies.txt"
REPORT_FILE="$REPORT_DIR/email-registration-$RUN_ID.md"
CURRENT_STEP="initialization"
umask 077
mkdir -p "$REPORT_DIR"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat >"$REPORT_FILE" <<EOF
# Email registration validation

- Run: $RUN_ID
- Started: $RUN_STARTED_AT
- Origin: $ORIGIN
- Environment file: $ENV_FILE
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
  printf '| %s | %s | %s | %s |\n' "$(date --iso-8601=seconds)" "$step" "$result" "$notes" >>"$REPORT_FILE"
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
  json_get "$1" message 2>/dev/null || printf 'Unknown API error'
}

api_request() {
  local output_file="$1"
  shift
  local http_status
  if ! http_status="$(curl --noproxy '*' --silent --show-error --max-time 30 \
      --output "$output_file" --write-out '%{http_code}' "$@")"; then
    return 1
  fi
  [[ "$http_status" =~ ^2[0-9][0-9]$ ]]
}

db_query() {
  local sql="$1"
  printf '%s\n' "$sql" | "${COMPOSE[@]}" exec -T mysql sh -lc \
    'MYSQL_PWD="$MYSQL_PASSWORD" mysql -u"$MYSQL_USER" "$MYSQL_DATABASE" --batch --skip-column-names 2>/dev/null'
}

sql_escape() {
  printf '%s' "$1" | sed "s/'/''/g"
}

utf8_hex() {
  python3 -c 'import sys; print(sys.stdin.buffer.read().hex())'
}

related_user_count() {
  local user_id="$1"
  db_query "
SELECT
  (SELECT COUNT(*) FROM checkins WHERE user_id = $user_id) +
  (SELECT COUNT(*) FROM creem_orders WHERE user_id = $user_id) +
  (SELECT COUNT(*) FROM logs WHERE user_id = $user_id) +
  (SELECT COUNT(*) FROM midjourneys WHERE user_id = $user_id) +
  (SELECT COUNT(*) FROM passkey_credentials WHERE user_id = $user_id) +
  (SELECT COUNT(*) FROM quota_data WHERE user_id = $user_id) +
  (SELECT COUNT(*) FROM redemptions WHERE user_id = $user_id) +
  (SELECT COUNT(*) FROM subscription_orders WHERE user_id = $user_id) +
  (SELECT COUNT(*) FROM subscription_pre_consume_records WHERE user_id = $user_id) +
  (SELECT COUNT(*) FROM tasks WHERE user_id = $user_id) +
  (SELECT COUNT(*) FROM tokens WHERE user_id = $user_id) +
  (SELECT COUNT(*) FROM top_ups WHERE user_id = $user_id) +
  (SELECT COUNT(*) FROM two_fa_backup_codes WHERE user_id = $user_id) +
  (SELECT COUNT(*) FROM two_fas WHERE user_id = $user_id) +
  (SELECT COUNT(*) FROM user_oauth_bindings WHERE user_id = $user_id) +
  (SELECT COUNT(*) FROM user_subscriptions WHERE user_id = $user_id);
"
}

delete_existing_test_user() {
  local user_id="$1"
  local username="$2"
  local email_hex="$3"
  local sql_username
  local result
  local deleted_users
  local deleted_related
  local remaining_users
  local remaining_related

  [[ "$user_id" =~ ^[1-9][0-9]*$ ]] || return 1
  [[ "$username" == e2e_* ]] || return 1
  sql_username="$(sql_escape "$username")"

  if ! result="$(db_query "
START TRANSACTION;
SET @target_id = $user_id;
SET @target_username = '$sql_username';
SET @target_email = CONVERT(0x$email_hex USING utf8mb4) COLLATE utf8mb4_unicode_ci;
SET @safe_target = (
  SELECT COUNT(*)
  FROM users
  WHERE id = @target_id
    AND username = @target_username
    AND LEFT(username, 4) = 'e2e_'
    AND role = 1
    AND email = @target_email
    AND NOT EXISTS (
      SELECT 1 FROM users AS invitee WHERE invitee.inviter_id = @target_id
    )
);
SET @deleted_related = 0;

DELETE FROM checkins WHERE user_id = @target_id AND @safe_target = 1;
SET @deleted_related = @deleted_related + ROW_COUNT();
DELETE FROM creem_orders WHERE user_id = @target_id AND @safe_target = 1;
SET @deleted_related = @deleted_related + ROW_COUNT();
DELETE FROM logs WHERE user_id = @target_id AND @safe_target = 1;
SET @deleted_related = @deleted_related + ROW_COUNT();
DELETE FROM midjourneys WHERE user_id = @target_id AND @safe_target = 1;
SET @deleted_related = @deleted_related + ROW_COUNT();
DELETE FROM passkey_credentials WHERE user_id = @target_id AND @safe_target = 1;
SET @deleted_related = @deleted_related + ROW_COUNT();
DELETE FROM quota_data WHERE user_id = @target_id AND @safe_target = 1;
SET @deleted_related = @deleted_related + ROW_COUNT();
DELETE FROM redemptions WHERE user_id = @target_id AND @safe_target = 1;
SET @deleted_related = @deleted_related + ROW_COUNT();
DELETE FROM subscription_orders WHERE user_id = @target_id AND @safe_target = 1;
SET @deleted_related = @deleted_related + ROW_COUNT();
DELETE FROM subscription_pre_consume_records WHERE user_id = @target_id AND @safe_target = 1;
SET @deleted_related = @deleted_related + ROW_COUNT();
DELETE FROM tasks WHERE user_id = @target_id AND @safe_target = 1;
SET @deleted_related = @deleted_related + ROW_COUNT();
DELETE FROM tokens WHERE user_id = @target_id AND @safe_target = 1;
SET @deleted_related = @deleted_related + ROW_COUNT();
DELETE FROM top_ups WHERE user_id = @target_id AND @safe_target = 1;
SET @deleted_related = @deleted_related + ROW_COUNT();
DELETE FROM two_fa_backup_codes WHERE user_id = @target_id AND @safe_target = 1;
SET @deleted_related = @deleted_related + ROW_COUNT();
DELETE FROM two_fas WHERE user_id = @target_id AND @safe_target = 1;
SET @deleted_related = @deleted_related + ROW_COUNT();
DELETE FROM user_oauth_bindings WHERE user_id = @target_id AND @safe_target = 1;
SET @deleted_related = @deleted_related + ROW_COUNT();
DELETE FROM user_subscriptions WHERE user_id = @target_id AND @safe_target = 1;
SET @deleted_related = @deleted_related + ROW_COUNT();

DELETE FROM users
WHERE id = @target_id
  AND username = @target_username
  AND @safe_target = 1;
SET @deleted_users = ROW_COUNT();
COMMIT;

SELECT
  @deleted_users,
  @deleted_related,
  (SELECT COUNT(*) FROM users WHERE id = @target_id OR username = @target_username),
  (SELECT COUNT(*) FROM checkins WHERE user_id = @target_id) +
  (SELECT COUNT(*) FROM creem_orders WHERE user_id = @target_id) +
  (SELECT COUNT(*) FROM logs WHERE user_id = @target_id) +
  (SELECT COUNT(*) FROM midjourneys WHERE user_id = @target_id) +
  (SELECT COUNT(*) FROM passkey_credentials WHERE user_id = @target_id) +
  (SELECT COUNT(*) FROM quota_data WHERE user_id = @target_id) +
  (SELECT COUNT(*) FROM redemptions WHERE user_id = @target_id) +
  (SELECT COUNT(*) FROM subscription_orders WHERE user_id = @target_id) +
  (SELECT COUNT(*) FROM subscription_pre_consume_records WHERE user_id = @target_id) +
  (SELECT COUNT(*) FROM tasks WHERE user_id = @target_id) +
  (SELECT COUNT(*) FROM tokens WHERE user_id = @target_id) +
  (SELECT COUNT(*) FROM top_ups WHERE user_id = @target_id) +
  (SELECT COUNT(*) FROM two_fa_backup_codes WHERE user_id = @target_id) +
  (SELECT COUNT(*) FROM two_fas WHERE user_id = @target_id) +
  (SELECT COUNT(*) FROM user_oauth_bindings WHERE user_id = @target_id) +
  (SELECT COUNT(*) FROM user_subscriptions WHERE user_id = @target_id);
")"; then
    return 1
  fi

  IFS=$'\t' read -r deleted_users deleted_related remaining_users remaining_related <<<"$result"
  [[ "$deleted_users" == "1" && "$remaining_users" == "0" && "$remaining_related" == "0" ]] || return 1
  printf '%s' "$deleted_related"
}

require_true_status_flag() {
  local response_file="$1"
  local flag="$2"
  local value
  value="$(json_get "$response_file" "data.$flag" 2>/dev/null || true)"
  [[ "$value" == "true" ]] || die "Required status flag is not enabled: $flag"
}

CURRENT_STEP="preflight"
echo "[1/7] Checking local services and registration configuration..."
STATUS_RESPONSE="$TMP_DIR/status.json"
api_request "$STATUS_RESPONSE" "$ORIGIN/api/status" || die "Cannot reach $ORIGIN/api/status"
json_success "$STATUS_RESPONSE" || die "Status API returned failure: $(json_message "$STATUS_RESPONSE")"

require_true_status_flag "$STATUS_RESPONSE" email_verification
require_true_status_flag "$STATUS_RESPONSE" register_enabled
require_true_status_flag "$STATUS_RESPONSE" password_register_enabled
require_true_status_flag "$STATUS_RESPONSE" password_login_enabled

TURNSTILE_ENABLED="$(json_get "$STATUS_RESPONSE" data.turnstile_check 2>/dev/null || true)"
[[ "$TURNSTILE_ENABLED" == "false" ]] || die "Turnstile is enabled; this CLI does not bypass interactive CAPTCHA"

MISSING_SMTP_OPTIONS="$(db_query '
SELECT `key`
FROM options
WHERE `key` IN ("SMTPServer", "SMTPPort", "SMTPAccount", "SMTPToken", "SMTPFrom")
  AND (value IS NULL OR LENGTH(value) = 0)
ORDER BY `key`;
' || true)"
[[ -z "$MISSING_SMTP_OPTIONS" ]] || die "Missing SMTP options: $(printf '%s' "$MISSING_SMTP_OPTIONS" | paste -sd, -)"

SMTP_OPTION_COUNT="$(db_query '
SELECT COUNT(*)
FROM options
WHERE `key` IN ("SMTPServer", "SMTPPort", "SMTPAccount", "SMTPToken", "SMTPFrom");
' || true)"
[[ "$SMTP_OPTION_COUNT" == "5" ]] || die "One or more required SMTP options do not exist"

VERSION="$(json_get "$STATUS_RESPONSE" data.version 2>/dev/null || true)"
report_step "$CURRENT_STEP" "PASS" "Registration and SMTP prerequisites are enabled; version $VERSION"
echo "      Preflight passed (version $VERSION)."

if [[ "$PREFLIGHT_ONLY" == "true" ]]; then
  echo "Preflight completed without sending email or creating a user."
  echo "Report: $REPORT_FILE"
  exit 0
fi

[[ -t 0 ]] || die "Interactive input requires a terminal"

USERNAME="$(printf 'e2e_%s_%04d' "$(date '+%m%d%H%M%S')" "$((RANDOM % 10000))")"
PASSWORD="$(openssl rand -hex 10)"
SQL_USERNAME="$(sql_escape "$USERNAME")"
if ! USERNAME_COUNT="$(db_query "SELECT COUNT(*) FROM users WHERE username = '$SQL_USERNAME';")"; then
  die "Unable to check whether the generated test username already exists"
fi
[[ "$USERNAME_COUNT" == "0" ]] || die "Generated test username already exists; rerun the command"

EMAIL=""
while true; do
  CURRENT_STEP="email input"
  echo
  read -r -p "Test email address: " EMAIL
  if [[ ${#EMAIL} -gt 50 || ! "$EMAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; then
    echo "Invalid email format. Enter an address up to 50 characters." >&2
    continue
  fi

  EMAIL_HEX="$(printf '%s' "$EMAIL" | utf8_hex)"
  if ! EMAIL_COUNT="$(db_query "
SELECT COUNT(*)
FROM users
WHERE email = CONVERT(0x$EMAIL_HEX USING utf8mb4) COLLATE utf8mb4_unicode_ci;
")"; then
    die "Unable to check whether the test email is already registered"
  fi
  if [[ "$EMAIL_COUNT" != "0" ]]; then
    if [[ "$EMAIL_COUNT" != "1" ]]; then
      echo "Multiple user records use that email. Refusing automatic cleanup; use another test address." >&2
      continue
    fi

    if ! EXISTING_USER_ROW="$(db_query "
SELECT id, username, role, status,
       IF(deleted_at IS NULL, 'active', 'soft-deleted')
FROM users
WHERE email = CONVERT(0x$EMAIL_HEX USING utf8mb4) COLLATE utf8mb4_unicode_ci
LIMIT 1;
")"; then
      die "Unable to inspect the existing user for this email"
    fi
    IFS=$'\t' read -r \
      EXISTING_USER_ID EXISTING_USERNAME EXISTING_ROLE EXISTING_STATUS EXISTING_STATE \
      <<<"$EXISTING_USER_ROW"

    if [[ ! "$EXISTING_USER_ID" =~ ^[1-9][0-9]*$ ||
          "$EXISTING_USERNAME" != e2e_* ||
          "$EXISTING_ROLE" != "1" ]]; then
      echo "That email belongs to a protected non-test account. Automatic deletion is refused." >&2
      continue
    fi

    if ! INVITEE_COUNT="$(db_query "SELECT COUNT(*) FROM users WHERE inviter_id = $EXISTING_USER_ID;")"; then
      die "Unable to check whether the existing test user has invited users"
    fi
    if [[ "$INVITEE_COUNT" != "0" ]]; then
      echo "That test user has invited users. Automatic deletion is refused." >&2
      continue
    fi
    if ! EXISTING_RELATED_COUNT="$(related_user_count "$EXISTING_USER_ID")"; then
      die "Unable to inspect records related to the existing test user"
    fi

    echo "Existing test user found:"
    echo "  User ID: $EXISTING_USER_ID"
    echo "  Username: $EXISTING_USERNAME"
    echo "  State: $EXISTING_STATE (status $EXISTING_STATUS)"
    echo "  Related records to remove: $EXISTING_RELATED_COUNT"
    read -r -p "Delete this test user and continue registration? [y/N]: " DELETE_CHOICE
    if [[ ! "$DELETE_CHOICE" =~ ^[Yy]$ ]]; then
      echo "Deletion cancelled. Enter another test email."
      continue
    fi

    CURRENT_STEP="cleanup existing test user"
    if ! DELETED_RELATED_COUNT="$(
      delete_existing_test_user "$EXISTING_USER_ID" "$EXISTING_USERNAME" "$EMAIL_HEX"
    )"; then
      die "The existing test user could not be deleted safely"
    fi
    report_step "$CURRENT_STEP" "PASS" \
      "Deleted test user ID $EXISTING_USER_ID and $DELETED_RELATED_COUNT related records"
    echo "Existing test user deleted. Continuing registration with the same email."
  fi

  CURRENT_STEP="send verification email"
  echo "[2/7] Sending a verification code..."
  VERIFICATION_RESPONSE="$TMP_DIR/verification.json"
  if ! api_request "$VERIFICATION_RESPONSE" --get \
      --data-urlencode "email=$EMAIL" \
      --data-urlencode "turnstile=" \
      "$ORIGIN/api/verification"; then
    echo "Verification request failed. Check the address and SMTP service, then try again." >&2
    continue
  fi
  if ! json_success "$VERIFICATION_RESPONSE"; then
    echo "Verification email was rejected: $(json_message "$VERIFICATION_RESPONSE")" >&2
    continue
  fi
  break
done
report_step "$CURRENT_STEP" "PASS" "Verification email accepted for delivery"

CURRENT_STEP="register user"
echo "      Email accepted. Check the inbox for the six-character code (0-9, a-f)."
while true; do
  VERIFICATION_CODE=""
  read -r -s -p "Verification code: " VERIFICATION_CODE
  echo
  VERIFICATION_CODE="${VERIFICATION_CODE,,}"
  if [[ ! "$VERIFICATION_CODE" =~ ^[0-9a-f]{6}$ ]]; then
    echo "The verification code must contain exactly six hexadecimal characters (0-9, a-f)." >&2
    continue
  fi

  REGISTER_PAYLOAD="$TMP_DIR/register.json"
  printf '%s\0%s\0%s\0%s\0' \
    "$USERNAME" "$PASSWORD" "$EMAIL" "$VERIFICATION_CODE" | \
    python3 -c '
import json
import sys

parts = sys.stdin.buffer.read().split(b"\0")
username, password, email, code = (part.decode("utf-8") for part in parts[:4])
json.dump({
    "username": username,
    "password": password,
    "email": email,
    "verification_code": code,
    "aff_code": "",
}, sys.stdout, ensure_ascii=False)
' >"$REGISTER_PAYLOAD"

  REGISTER_RESPONSE="$TMP_DIR/register-response.json"
  api_request "$REGISTER_RESPONSE" \
    --header 'Content-Type: application/json' \
    --data-binary "@$REGISTER_PAYLOAD" \
    "$ORIGIN/api/user/register?turnstile=" || die "Registration request failed"

  if json_success "$REGISTER_RESPONSE"; then
    break
  fi
  REGISTER_MESSAGE="$(json_message "$REGISTER_RESPONSE")"
  if printf '%s' "$REGISTER_MESSAGE" | grep -Eqi 'verification|验证码'; then
    echo "Registration was rejected: $REGISTER_MESSAGE" >&2
    echo "Enter the code again, or press Ctrl-C to stop." >&2
    continue
  fi
  die "Registration was rejected: $REGISTER_MESSAGE"
done
unset VERIFICATION_CODE
rm -f "$REGISTER_PAYLOAD"
report_step "$CURRENT_STEP" "PASS" "Test user registered as $USERNAME"
echo "[3/7] Registration succeeded for test user $USERNAME."

CURRENT_STEP="database verification"
if ! DB_ROW="$(db_query "
SELECT id, username, email, role, status
FROM users
WHERE username = '$SQL_USERNAME'
ORDER BY id DESC
LIMIT 1;
")"; then
  die "Unable to query the registered user from the database"
fi
[[ -n "$DB_ROW" ]] || die "Registered user was not found in the database"
IFS=$'\t' read -r USER_ID DB_USERNAME DB_EMAIL DB_ROLE DB_STATUS <<<"$DB_ROW"
[[ "$DB_USERNAME" == "$USERNAME" ]] || die "Database username does not match"
[[ "$DB_EMAIL" == "$EMAIL" ]] || die "Registration email was not persisted correctly"
[[ "$DB_STATUS" == "1" ]] || die "Registered user is not enabled"
report_step "$CURRENT_STEP" "PASS" "User ID $USER_ID has the expected username, email, role, and status"
echo "[4/7] Database verification passed (user ID $USER_ID)."

CURRENT_STEP="login"
LOGIN_PAYLOAD="$TMP_DIR/login.json"
printf '%s\0%s\0' "$USERNAME" "$PASSWORD" | python3 -c '
import json
import sys

parts = sys.stdin.buffer.read().split(b"\0")
username, password = (part.decode("utf-8") for part in parts[:2])
json.dump({"username": username, "password": password}, sys.stdout)
' >"$LOGIN_PAYLOAD"
LOGIN_RESPONSE="$TMP_DIR/login-response.json"
api_request "$LOGIN_RESPONSE" \
  --cookie-jar "$COOKIE_JAR" \
  --header 'Content-Type: application/json' \
  --data-binary "@$LOGIN_PAYLOAD" \
  "$ORIGIN/api/user/login?turnstile=" || die "Login request failed"
rm -f "$LOGIN_PAYLOAD"
json_success "$LOGIN_RESPONSE" || die "Login failed: $(json_message "$LOGIN_RESPONSE")"
LOGIN_USER_ID="$(json_get "$LOGIN_RESPONSE" data.id 2>/dev/null || true)"
[[ "$LOGIN_USER_ID" == "$USER_ID" ]] || die "Login returned an unexpected user ID"
report_step "$CURRENT_STEP" "PASS" "Password login succeeded for user ID $USER_ID"
echo "[5/7] Password login passed."

CURRENT_STEP="self API verification"
SELF_RESPONSE="$TMP_DIR/self-response.json"
if ! api_request "$SELF_RESPONSE" \
  --cookie "$COOKIE_JAR" \
  --header "New-Api-User: $USER_ID" \
  "$ORIGIN/api/user/self"; then
  die "/api/user/self request failed: $(json_message "$SELF_RESPONSE")"
fi
json_success "$SELF_RESPONSE" || die "/api/user/self returned failure: $(json_message "$SELF_RESPONSE")"
SELF_USER_ID="$(json_get "$SELF_RESPONSE" data.id 2>/dev/null || true)"
SELF_USERNAME="$(json_get "$SELF_RESPONSE" data.username 2>/dev/null || true)"
SELF_EMAIL="$(json_get "$SELF_RESPONSE" data.email 2>/dev/null || true)"
[[ "$SELF_USER_ID" == "$USER_ID" ]] || die "/api/user/self returned an unexpected user ID"
[[ "$SELF_USERNAME" == "$USERNAME" ]] || die "/api/user/self returned an unexpected username"
[[ "$SELF_EMAIL" == "$EMAIL" ]] || die "/api/user/self returned an unexpected email"
report_step "$CURRENT_STEP" "PASS" "/api/user/self matches the registered database user"
echo "[6/7] Authenticated user lookup passed."

CURRENT_STEP="application log verification"
APP_LOG="$TMP_DIR/new-api.log"
"${COMPOSE[@]}" logs --no-color --since "$RUN_STARTED_AT" new-api >"$APP_LOG" 2>&1 || \
  die "Unable to read new-api logs"
ERROR_COUNT="$(
  (grep -Ei \
    'panic|fatal|http[^0-9]{0,8}500|status[^0-9]{0,4}500' \
    "$APP_LOG" || true) | wc -l
)"
if [[ "$ERROR_COUNT" != "0" ]]; then
  die "Application log contains $ERROR_COUNT possible severe error entries since the test started"
fi
report_step "$CURRENT_STEP" "PASS" "No panic, fatal, or HTTP 500 entries detected"
echo "[7/7] Application log check passed."

CURRENT_STEP="complete"
report_step "$CURRENT_STEP" "PASS" "Email registration flow completed for user ID $USER_ID"
unset PASSWORD EMAIL DB_EMAIL SELF_EMAIL

echo
echo "Email registration flow passed."
echo "Test username: $USERNAME"
echo "Test user ID: $USER_ID"
echo "The test user was retained for follow-up validation."
echo "Report: $REPORT_FILE"
