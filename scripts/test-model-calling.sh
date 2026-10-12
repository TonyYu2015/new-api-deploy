#!/usr/bin/env bash
set -Eeuo pipefail
set +x

cd "$(dirname "$0")/.."

ENV_FILE="${ENV_FILE:-.env.dev}"
ORIGIN="${MODEL_TEST_BASE_URL:-}"
TARGET="${MODEL_TEST_TARGET:-local}"
STAGING_HOST="${MODEL_STAGING_HOST:-oracle}"
STAGING_PATH="${MODEL_STAGING_PATH:-/opt/new-api-deploy}"
STAGING_ENV_FILE="${MODEL_STAGING_ENV_FILE:-.env.staging}"
STAGING_AUTH_FILE="${MODEL_STAGING_AUTH_FILE:-ui-tests/.env.e2e}"
REPORT_DIR="${MODEL_TEST_REPORT_DIR:-.local-run}"
TEST_MODEL="${MODEL_TEST_MODEL:-qwen3.7-max}"
MAX_TOKENS="${MODEL_TEST_MAX_TOKENS:-16}"
REQUEST_TIMEOUT="${MODEL_TEST_REQUEST_TIMEOUT:-90}"
LOG_WAIT_SECONDS="${MODEL_TEST_LOG_WAIT_SECONDS:-15}"
PREFLIGHT_ONLY=false
TEST_ALL_MODELS=false
ASSUME_YES=false
ALLOW_ZERO_COST=false
USER_ID_OVERRIDE=""

usage() {
  cat <<'EOF'
Usage: scripts/test-model-calling.sh [options]

Interactively validate the complete model-calling flow:

  1. Check the service, channels, billing-log setting, and test user.
  2. Select one usable API Key that belongs to that exact test user.
  3. Retrieve /v1/models and confirm the primary model is available.
  4. Show the billable-call plan and wait for explicit confirmation.
  5. Validate each response, its request ID, consumption log, channel,
     token usage, and aggregate billing.
  6. Check application logs and write a redacted Markdown report.

Options:
  --target TARGET       local or staging (default: local)
  --env-file FILE       Local Compose env file (default: .env.dev)
  --base-url URL        Override the target API origin
  --auth-file FILE      Staging E2E metadata (default: ui-tests/.env.e2e)
  --staging-host HOST   SSH host for staging (default: oracle)
  --staging-path PATH   Remote deployment path (default: /opt/new-api-deploy)
  --user-id ID          Use a specific ordinary test user
  --model MODEL         Primary model (default: qwen3.7-max)
  --all-models          Test every model returned by /v1/models
  --max-tokens N        Maximum output tokens per request (default: 16)
  --request-timeout N   Per-request timeout in seconds (default: 90)
  --allow-zero-cost     Allow a successful call to have zero billed quota
  --preflight-only      Check prerequisites without billable model calls
  -y, --yes             Select defaults and confirm calls non-interactively
  -h, --help            Show this help

The API Key is read from the selected token record and placed in a protected
temporary header file. It is never printed, written to the report, exported,
or passed in a process command line. E2E_ACCESS_TOKEN is intentionally not
used because dashboard access tokens are not /v1 API Keys.
EOF
}

require_option_value() {
  local option="$1" count="$2"
  [[ "$count" -ge 2 ]] || {
    echo "$option requires a value" >&2
    exit 2
  }
}

while (($# > 0)); do
  case "$1" in
    --target)
      require_option_value "$1" "$#"
      TARGET="$2"
      shift 2
      ;;
    --env-file)
      require_option_value "$1" "$#"
      ENV_FILE="$2"
      shift 2
      ;;
    --base-url)
      require_option_value "$1" "$#"
      ORIGIN="$2"
      shift 2
      ;;
    --auth-file)
      require_option_value "$1" "$#"
      STAGING_AUTH_FILE="$2"
      shift 2
      ;;
    --staging-host)
      require_option_value "$1" "$#"
      STAGING_HOST="$2"
      shift 2
      ;;
    --staging-path)
      require_option_value "$1" "$#"
      STAGING_PATH="$2"
      shift 2
      ;;
    --user-id)
      require_option_value "$1" "$#"
      USER_ID_OVERRIDE="$2"
      shift 2
      ;;
    --model)
      require_option_value "$1" "$#"
      TEST_MODEL="$2"
      shift 2
      ;;
    --max-tokens)
      require_option_value "$1" "$#"
      MAX_TOKENS="$2"
      shift 2
      ;;
    --request-timeout)
      require_option_value "$1" "$#"
      REQUEST_TIMEOUT="$2"
      shift 2
      ;;
    --all-models)
      TEST_ALL_MODELS=true
      shift
      ;;
    --allow-zero-cost)
      ALLOW_ZERO_COST=true
      shift
      ;;
    --preflight-only)
      PREFLIGHT_ONLY=true
      shift
      ;;
    -y|--yes)
      ASSUME_YES=true
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

[[ "$TARGET" == "local" || "$TARGET" == "staging" ]] || {
  echo "Target must be local or staging" >&2
  exit 2
}
[[ -n "$TEST_MODEL" && "$TEST_MODEL" != *$'\n'* && "$TEST_MODEL" != *$'\r'* &&
   "$TEST_MODEL" != *$'\t'* ]] || {
  echo "--model must be a non-empty single-line value" >&2
  exit 2
}
[[ "$MAX_TOKENS" =~ ^[1-9][0-9]*$ && "$MAX_TOKENS" -le 256 ]] || {
  echo "--max-tokens must be between 1 and 256" >&2
  exit 2
}
[[ "$REQUEST_TIMEOUT" =~ ^[1-9][0-9]*$ && "$REQUEST_TIMEOUT" -le 900 ]] || {
  echo "--request-timeout must be between 1 and 900 seconds" >&2
  exit 2
}
[[ "$LOG_WAIT_SECONDS" =~ ^[1-9][0-9]*$ && "$LOG_WAIT_SECONDS" -le 120 ]] || {
  echo "MODEL_TEST_LOG_WAIT_SECONDS must be between 1 and 120" >&2
  exit 2
}
if [[ -n "$USER_ID_OVERRIDE" && ! "$USER_ID_OVERRIDE" =~ ^[1-9][0-9]*$ ]]; then
  echo "--user-id must be a positive integer" >&2
  exit 2
fi

for command_name in curl grep awk sed python3; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "$command_name is required" >&2
    exit 1
  }
done

if [[ "$TARGET" == "local" ]]; then
  [[ -f "$ENV_FILE" ]] || {
    echo "Environment file not found: $ENV_FILE" >&2
    exit 1
  }
  command -v docker >/dev/null 2>&1 || {
    echo "docker is required" >&2
    exit 1
  }
  docker compose version >/dev/null 2>&1 || {
    echo "docker compose is required" >&2
    exit 1
  }
else
  [[ -f "$STAGING_AUTH_FILE" ]] || {
    echo "Staging auth file not found: $STAGING_AUTH_FILE" >&2
    exit 1
  }
  command -v ssh >/dev/null 2>&1 || {
    echo "ssh is required" >&2
    exit 1
  }
fi

# --------------- environment and report setup ---------------

read_env_from() {
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
' "$1" "${@:2}"
}

# shellcheck source=lib/env.sh
. scripts/lib/env.sh

mapfile -t ENV_ARGS < <(env_args "$ENV_FILE")

if [[ -z "$ORIGIN" ]]; then
  if [[ "$TARGET" == "local" ]]; then
    HTTP_PORT="$(read_env_from HTTP_PORT "$ENV_FILE" "${ENV_FILE}.local")"
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
    *)
      echo "Local target requires a localhost API origin" >&2
      exit 1
      ;;
  esac
  COMPOSE=(docker compose "${ENV_ARGS[@]}")
  ENV_LABEL="local ($ENV_FILE)"
else
  [[ "$ORIGIN" == "https://test.ccaiservice.com" ]] || {
    echo "Staging target is restricted to https://test.ccaiservice.com" >&2
    exit 1
  }
  STAGING_PATH_Q="$(printf '%q' "$STAGING_PATH")"
  STAGING_ENV_FILE_Q="$(printf '%q' "$STAGING_ENV_FILE")"
  REMOTE_COMPOSE="cd $STAGING_PATH_Q && sudo docker compose --env-file $STAGING_ENV_FILE_Q \$(test -f $STAGING_ENV_FILE_Q.local && printf -- '--env-file %s' $STAGING_ENV_FILE_Q.local)"
  ENV_LABEL="staging ($STAGING_HOST:$STAGING_PATH)"
fi

umask 077
RUN_ID="$(date '+%Y%m%d-%H%M%S')"
RUN_STARTED_AT="$(date --iso-8601=seconds)"
TMP_DIR="$(mktemp -d)"
REPORT_FILE="$REPORT_DIR/model-calling-$TARGET-$RUN_ID.md"
AUTH_HEADER_FILE="$TMP_DIR/api-key-header"
MODEL_NAMES_FILE="$TMP_DIR/model-names.txt"
TEST_MODELS_FILE="$TMP_DIR/test-models.txt"
USED_CHANNEL_IDS_FILE="$TMP_DIR/used-channel-ids.txt"
CURRENT_STEP="initialization"
STEP_STARTED_EPOCH="$(date +%s)"
LAST_HTTP_STATUS=""
unset API_KEY AUTH_HEADER TOKEN_KEY TOKEN_SECRET_ROW
mkdir -p "$REPORT_DIR"

cleanup() {
  local exit_code=$?
  rm -rf "$TMP_DIR"
  return "$exit_code"
}
trap cleanup EXIT

cat >"$REPORT_FILE" <<EOF
# Model-calling validation

- Run: $RUN_ID
- Started: $RUN_STARTED_AT
- Target: $ENV_LABEL
- Origin: $ORIGIN
- Primary model: $TEST_MODEL
- All models: $TEST_ALL_MODELS
- Max output tokens per call: $MAX_TOKENS
- Sensitive values: omitted

| Time | Duration | Step | Result | Notes |
|---|---:|---|---|---|
EOF

begin_step() {
  CURRENT_STEP="$1"
  STEP_STARTED_EPOCH="$(date +%s)"
}

report_step() {
  local step="$1" result="$2" notes="${3:-}" started="${4:-$STEP_STARTED_EPOCH}"
  local duration
  duration=$(( $(date +%s) - started ))
  notes="${notes//$'\n'/ }"
  notes="${notes//$'\r'/ }"
  notes="${notes//|/\\|}"
  printf '| %s | %ss | %s | %s | %s |\n' \
    "$(date --iso-8601=seconds)" "$duration" "$step" "$result" "$notes" >>"$REPORT_FILE"
}

die() {
  local message="$1"
  report_step "$CURRENT_STEP" "FAIL" "$message"
  echo "ERROR: $message" >&2
  echo "Report: $REPORT_FILE" >&2
  exit 1
}

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
  local since="$1" output_file="$2"
  if [[ "$TARGET" == "local" ]]; then
    "${COMPOSE[@]}" logs --no-color --since "$since" new-api >"$output_file" 2>&1
  else
    local since_q
    since_q="$(printf '%q' "$since")"
    ssh "$STAGING_HOST" "$REMOTE_COMPOSE logs --no-color --since $since_q new-api" \
      >"$output_file" 2>&1
  fi
}

api_request() {
  local output_file="$1" headers_file="$2"
  shift 2
  local http_status
  : >"$headers_file"
  if ! http_status="$(curl --noproxy '*' --silent --show-error \
      --connect-timeout 10 --max-time "$REQUEST_TIMEOUT" \
      --dump-header "$headers_file" --output "$output_file" \
      --write-out '%{http_code}' "$@")"; then
    LAST_HTTP_STATUS="000"
    return 1
  fi
  LAST_HTTP_STATUS="$http_status"
  [[ "$http_status" =~ ^2[0-9][0-9]$ ]]
}

json_get() {
  local file="$1" path="$2"
  python3 - "$file" "$path" <<'PY'
import json
import re
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

api_error_summary() {
  local file="$1"
  python3 - "$file" <<'PY'
import json
import re
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        value = json.load(handle)
except Exception:
    print("invalid or non-JSON response")
    raise SystemExit

message = ""
if isinstance(value, dict):
    error = value.get("error")
    if isinstance(error, dict):
        message = str(error.get("message") or error.get("type") or "")
    elif error:
        message = str(error)
    message = message or str(value.get("message") or "")
message = re.sub(r"(?i)bearer\s+[A-Za-z0-9._~+/=-]+", "Bearer [REDACTED]", message)
message = re.sub(r"\bsk-[A-Za-z0-9._~+/=-]+", "sk-[REDACTED]", message)
message = " ".join(message.split())
print((message or "API returned an unspecified error")[:180])
PY
}

request_id_from_headers() {
  local headers_file="$1"
  awk 'BEGIN { IGNORECASE=1 }
    /^X-Oneapi-Request-Id:/ {
      sub(/^[^:]*:[[:space:]]*/, "")
      sub(/\r$/, "")
      value=$0
    }
    END { if (value != "") print value }
  ' "$headers_file"
}

latest_completed_email_user_id() {
  local report
  while IFS= read -r report; do
    if grep -q '| complete | PASS | Email registration flow completed for user ID ' "$report"; then
      sed -nE 's/.*Email registration flow completed for user ID ([0-9]+).*/\1/p' "$report" | head -1
      return
    fi
  done < <(find .local-run -maxdepth 1 -type f -name 'email-registration-*.md' 2>/dev/null | sort -r)
}

confirm_billable_calls() {
  local prompt="$1" answer
  if [[ "$ASSUME_YES" == "true" ]]; then
    return 0
  fi
  [[ -t 0 ]] || die "Billable calls require a terminal confirmation; rerun with --yes for automation"
  read -r -p "$prompt [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]] || die "Billable model calls were cancelled"
}

validate_chat_response() {
  local response_file="$1"
  python3 - "$response_file" <<'PY'
import json
import re
import sys

def compact(value):
    text = " ".join(str(value).replace("\t", " ").replace("\r", " ").replace("\n", " ").split())
    text = re.sub(r"(?i)bearer\s+[A-Za-z0-9._~+/=-]+", "Bearer [REDACTED]", text)
    return re.sub(r"\bsk-[A-Za-z0-9._~+/=-]+", "sk-[REDACTED]", text)

def text_length(value):
    if isinstance(value, str):
        return len(value.strip())
    if isinstance(value, list):
        return sum(text_length(item.get("text", "") if isinstance(item, dict) else item) for item in value)
    return 0

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        data = json.load(handle)
except Exception as exc:
    print("invalid JSON response: " + compact(exc)[:120])
    raise SystemExit(1)

if not isinstance(data, dict):
    print("response root is not an object")
    raise SystemExit(1)

error = data.get("error")
if error:
    if isinstance(error, dict):
        message = error.get("message") or error.get("type") or "API error"
    else:
        message = error
    print("API error: " + compact(message)[:160])
    raise SystemExit(1)

choices = data.get("choices")
if not isinstance(choices, list) or not choices:
    print("response has no choices")
    raise SystemExit(1)

first = choices[0] if isinstance(choices[0], dict) else {}
message = first.get("message") if isinstance(first.get("message"), dict) else {}
content_chars = text_length(message.get("content"))
reasoning_chars = text_length(message.get("reasoning_content")) + text_length(message.get("reasoning"))
tool_calls = message.get("tool_calls") if isinstance(message.get("tool_calls"), list) else []
if content_chars == 0 and reasoning_chars == 0 and not tool_calls:
    print("first choice contains no content, reasoning, or tool call")
    raise SystemExit(1)

usage = data.get("usage") if isinstance(data.get("usage"), dict) else {}
total_tokens = usage.get("total_tokens")
if not isinstance(total_tokens, int):
    prompt_tokens = usage.get("prompt_tokens", 0)
    completion_tokens = usage.get("completion_tokens", 0)
    if isinstance(prompt_tokens, int) and isinstance(completion_tokens, int):
        total_tokens = prompt_tokens + completion_tokens
if not isinstance(total_tokens, int) or total_tokens <= 0:
    print("response usage has no positive token count")
    raise SystemExit(1)

finish_reason = compact(first.get("finish_reason") or "unknown")[:40]
returned_model = compact(data.get("model") or "")[:100]
if not returned_model:
    print("response has no model identifier")
    raise SystemExit(1)
print("\t".join(map(str, [content_chars, reasoning_chars, len(tool_calls), total_tokens, finish_reason, returned_model])))
PY
}

wait_for_consume_log() {
  local request_id="$1" attempt row
  for ((attempt=1; attempt<=LOG_WAIT_SECONDS; attempt++)); do
    if row="$(db_query "
SELECT id, user_id, token_id, type, channel_id, model_name, quota,
       prompt_tokens, completion_tokens, request_id,
       CASE
         WHEN JSON_VALID(other) THEN COALESCE(
           NULLIF(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(other, '$.billing_source')), ''), 'null'),
           'wallet'
         )
         ELSE 'wallet'
       END AS billing_source
FROM logs
WHERE request_id = '$request_id'
  AND type = 2
ORDER BY id DESC
LIMIT 1;
" 2>/dev/null)" && [[ -n "$row" ]]; then
      printf '%s' "$row"
      return 0
    fi
    sleep 1
  done
  return 1
}

# --------------- step 1: service preflight ---------------

begin_step "service preflight"
echo "[1/7] Checking $TARGET service, channels, and billing-log configuration..."

STATUS_RESPONSE="$TMP_DIR/status.json"
STATUS_HEADERS="$TMP_DIR/status.headers"
if ! api_request "$STATUS_RESPONSE" "$STATUS_HEADERS" "$ORIGIN/api/status"; then
  die "Cannot reach $ORIGIN/api/status (HTTP $LAST_HTTP_STATUS)"
fi
json_success "$STATUS_RESPONSE" || die "Status API returned failure: $(api_error_summary "$STATUS_RESPONSE")"

VERSION="$(json_get "$STATUS_RESPONSE" data.version 2>/dev/null || true)"
QUOTA_PER_UNIT="$(json_get "$STATUS_RESPONSE" data.quota_per_unit 2>/dev/null || true)"
BATCH_UPDATE_ENABLED="$(json_get "$STATUS_RESPONSE" data.enable_batch_update 2>/dev/null || true)"
BATCH_UPDATE_ENABLED="${BATCH_UPDATE_ENABLED:-false}"
[[ "$QUOTA_PER_UNIT" =~ ^[1-9][0-9]*$ ]] || die "Status API returned an invalid quota_per_unit"

if ! ENABLED_CHANNEL_COUNT="$(db_query "SELECT COUNT(*) FROM channels WHERE status = 1;")"; then
  die "Unable to query enabled channels"
fi
[[ "$ENABLED_CHANNEL_COUNT" =~ ^[1-9][0-9]*$ ]] || die "No enabled channels found in the database"

if ! LOG_CONSUME_ENABLED="$(db_query "
SELECT COALESCE(
  (SELECT value FROM options WHERE \`key\` = 'LogConsumeEnabled' LIMIT 1),
  'true'
);
")"; then
  die "Unable to query LogConsumeEnabled"
fi
LOG_CONSUME_ENABLED="${LOG_CONSUME_ENABLED,,}"
[[ "$LOG_CONSUME_ENABLED" == "true" || "$LOG_CONSUME_ENABLED" == "1" ]] || \
  die "Consumption logging is disabled; enable LogConsumeEnabled before billing validation"

report_step "$CURRENT_STEP" "PASS" \
  "Version $VERSION; $ENABLED_CHANNEL_COUNT enabled channel(s); quota_per_unit $QUOTA_PER_UNIT; consumption logs enabled; batch updates $BATCH_UPDATE_ENABLED"
echo "      Preflight passed (version $VERSION, $ENABLED_CHANNEL_COUNT enabled channels)."

if [[ "$PREFLIGHT_ONLY" == "true" ]]; then
  begin_step "complete"
  report_step "$CURRENT_STEP" "PASS" "Preflight completed without billable model calls"
  echo "Preflight completed without billable model calls."
  echo "Report: $REPORT_FILE"
  exit 0
fi

# --------------- step 2: exact test user and token ---------------

begin_step "test user and API key"
echo "[2/7] Selecting an ordinary test user and one of that user's API Keys..."

if [[ -n "$USER_ID_OVERRIDE" ]]; then
  DEFAULT_USER_ID="$USER_ID_OVERRIDE"
elif [[ "$TARGET" == "staging" ]]; then
  DEFAULT_USER_ID="$(read_env_from E2E_USER_ID "$STAGING_AUTH_FILE")"
else
  DEFAULT_USER_ID="$(latest_completed_email_user_id || true)"
  if [[ ! "$DEFAULT_USER_ID" =~ ^[1-9][0-9]*$ ]]; then
    DEFAULT_USER_ID="$(db_query "
SELECT id
FROM users
WHERE deleted_at IS NULL AND status = 1 AND role = 1 AND username LIKE 'e2e\\_%'
ORDER BY id DESC
LIMIT 1;
" || true)"
  fi
fi
[[ "$DEFAULT_USER_ID" =~ ^[1-9][0-9]*$ ]] || \
  die "No default test user was found; provide --user-id with an ordinary test user"

TARGET_USER_ID="$DEFAULT_USER_ID"
if [[ "$ASSUME_YES" != "true" ]]; then
  [[ -t 0 ]] || die "Interactive user selection requires a terminal; rerun with --yes for automation"
  read -r -p "Test user ID [$DEFAULT_USER_ID]: " ENTERED_USER_ID
  if [[ -n "$ENTERED_USER_ID" ]]; then
    [[ "$ENTERED_USER_ID" =~ ^[1-9][0-9]*$ ]] || die "Test user ID must be a positive integer"
    TARGET_USER_ID="$ENTERED_USER_ID"
  fi
fi

USER_FILTER="id = $TARGET_USER_ID AND deleted_at IS NULL AND status = 1 AND role = 1"
if [[ "$TARGET" == "local" ]]; then
  USER_FILTER="$USER_FILTER AND username LIKE 'e2e\\_%'"
fi
if ! TARGET_USER_ROW="$(db_query "
SELECT username, quota, used_quota
FROM users
WHERE $USER_FILTER
LIMIT 1;
")"; then
  die "Unable to query test user ID $TARGET_USER_ID"
fi
[[ -n "$TARGET_USER_ROW" ]] || die "User ID $TARGET_USER_ID is not an active ordinary test user"
IFS=$'\t' read -r TARGET_USERNAME USER_QUOTA_BEFORE USER_USED_BEFORE <<<"$TARGET_USER_ROW"
[[ "$USER_QUOTA_BEFORE" =~ ^[0-9]+$ && "$USER_USED_BEFORE" =~ ^[0-9]+$ ]] || \
  die "Test user quota fields are invalid"
[[ "$USER_QUOTA_BEFORE" -gt 0 ]] || die "Test user has no available quota"

if ! TOKEN_CANDIDATES="$(db_query "
SELECT id,
       LEFT(REPLACE(REPLACE(COALESCE(NULLIF(name, ''), '(unnamed)'), CHAR(9), ' '), CHAR(10), ' '), 50),
       IF(unlimited_quota = 1, 'unlimited', CONCAT('remaining=', remain_quota)),
       used_quota
FROM tokens
WHERE user_id = $TARGET_USER_ID
  AND deleted_at IS NULL
  AND status = 1
  AND (expired_time = -1 OR expired_time > UNIX_TIMESTAMP())
  AND (unlimited_quota = 1 OR remain_quota > 0)
  AND \`key\` IS NOT NULL
  AND LENGTH(\`key\`) >= 8
ORDER BY id DESC;
")"; then
  die "Unable to query API Keys for test user ID $TARGET_USER_ID"
fi
[[ -n "$TOKEN_CANDIDATES" ]] || \
  die "Test user has no usable API Key; create one in the API Keys page and rerun"

echo "      Available API Keys for $TARGET_USERNAME (keys are not displayed):"
printf '%s\n' "$TOKEN_CANDIDATES" | awk -F '\t' \
  '{ printf "        ID %-6s  %-32s  %-20s  used=%s\n", $1, $2, $3, $4 }'

DEFAULT_TOKEN_ID="$(printf '%s\n' "$TOKEN_CANDIDATES" | awk -F '\t' 'NR == 1 { print $1 }')"
TOKEN_DB_ID="$DEFAULT_TOKEN_ID"
if [[ "$ASSUME_YES" != "true" ]]; then
  read -r -p "API Key record ID [$DEFAULT_TOKEN_ID]: " ENTERED_TOKEN_ID
  [[ -z "$ENTERED_TOKEN_ID" || "$ENTERED_TOKEN_ID" =~ ^[1-9][0-9]*$ ]] || \
    die "API Key record ID must be a positive integer"
  TOKEN_DB_ID="${ENTERED_TOKEN_ID:-$DEFAULT_TOKEN_ID}"
fi
if ! printf '%s\n' "$TOKEN_CANDIDATES" | awk -F '\t' -v wanted="$TOKEN_DB_ID" \
    '$1 == wanted { found=1 } END { exit(found ? 0 : 1) }'; then
  die "API Key record ID $TOKEN_DB_ID is not one of the displayed usable keys"
fi

if ! TOKEN_SECRET_ROW="$(db_query "
SELECT id, \`key\`,
       LEFT(REPLACE(REPLACE(COALESCE(NULLIF(name, ''), '(unnamed)'), CHAR(9), ' '), CHAR(10), ' '), 50),
       used_quota
FROM tokens
WHERE id = $TOKEN_DB_ID
  AND user_id = $TARGET_USER_ID
  AND deleted_at IS NULL
  AND status = 1
  AND (expired_time = -1 OR expired_time > UNIX_TIMESTAMP())
  AND (unlimited_quota = 1 OR remain_quota > 0)
LIMIT 1;
")"; then
  die "Unable to retrieve the selected API Key"
fi
IFS=$'\t' read -r VERIFIED_TOKEN_ID TOKEN_KEY TOKEN_NAME TOKEN_USED_BEFORE <<<"$TOKEN_SECRET_ROW"
[[ "$VERIFIED_TOKEN_ID" == "$TOKEN_DB_ID" ]] || die "Selected API Key changed during validation"
[[ "$TOKEN_KEY" =~ ^[A-Za-z0-9._~+/=-]{8,128}$ ]] || die "Selected API Key has an unexpected format"
[[ "$TOKEN_USED_BEFORE" =~ ^[0-9]+$ ]] || die "Selected API Key has an invalid used_quota"

printf 'Authorization: Bearer sk-%s\n' "$TOKEN_KEY" >"$AUTH_HEADER_FILE"
chmod 600 "$AUTH_HEADER_FILE"
unset TOKEN_KEY TOKEN_SECRET_ROW

report_step "$CURRENT_STEP" "PASS" \
  "Selected user $TARGET_USERNAME (ID $TARGET_USER_ID) and owned API Key '$TOKEN_NAME' (record ID $TOKEN_DB_ID)"
echo "      Selected API Key record $TOKEN_DB_ID; ownership and usability verified."

# --------------- step 3: authenticated model list ---------------

begin_step "model list"
echo "[3/7] Retrieving and validating $ORIGIN/v1/models..."

MODELS_RESPONSE="$TMP_DIR/models.json"
MODELS_HEADERS="$TMP_DIR/models.headers"
if ! api_request "$MODELS_RESPONSE" "$MODELS_HEADERS" \
    --header "@$AUTH_HEADER_FILE" "$ORIGIN/v1/models"; then
  die "Model list request failed with HTTP $LAST_HTTP_STATUS: $(api_error_summary "$MODELS_RESPONSE")"
fi

if ! MODEL_COUNT="$(python3 - "$MODELS_RESPONSE" "$MODEL_NAMES_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    response = json.load(handle)
data = response.get("data") if isinstance(response, dict) else None
if not isinstance(data, list):
    raise SystemExit("model-list response data is not an array")
names = []
for item in data:
    name = item.get("id", "") if isinstance(item, dict) else ""
    if not isinstance(name, str) or not name or any(ord(char) < 32 for char in name):
        raise SystemExit("model-list response contains an invalid model ID")
    if name not in names:
        names.append(name)
if not names:
    raise SystemExit("model list is empty")
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    handle.write("\n".join(names) + "\n")
print(len(names))
PY
)"; then
  die "Model list response format is invalid"
fi
grep -Fqx "$TEST_MODEL" "$MODEL_NAMES_FILE" || \
  die "Primary model '$TEST_MODEL' was not found in the model list"

{
  printf '%s\n' "$TEST_MODEL"
  if [[ "$TEST_ALL_MODELS" == "true" ]]; then
    grep -Fvx "$TEST_MODEL" "$MODEL_NAMES_FILE" || true
  fi
} >"$TEST_MODELS_FILE"
PLANNED_CALLS="$(wc -l <"$TEST_MODELS_FILE" | tr -d ' ')"

report_step "$CURRENT_STEP" "PASS" \
  "Retrieved $MODEL_COUNT unique model(s); primary '$TEST_MODEL' is available; planned calls $PLANNED_CALLS"
echo "      Retrieved $MODEL_COUNT models. Planned billable calls: $PLANNED_CALLS."

# --------------- step 4: explicit billing confirmation ---------------

begin_step "billable-call confirmation"
echo "[4/7] Review the model-call plan:"
echo "      Target: $ENV_LABEL"
echo "      User: $TARGET_USERNAME (ID $TARGET_USER_ID)"
echo "      API Key record: $TOKEN_DB_ID"
echo "      Calls: $PLANNED_CALLS"
echo "      Max output tokens per call: $MAX_TOKENS"
echo "      Models:"
sed 's/^/        - /' "$TEST_MODELS_FILE"
confirm_billable_calls "Send these billable test calls?"
report_step "$CURRENT_STEP" "PASS" "Billable-call plan confirmed for $PLANNED_CALLS request(s)"

# --------------- step 5: response and per-request billing checks ---------------

begin_step "model calls"
echo "[5/7] Calling models and validating responses plus exact consumption logs..."

MODEL_TOTAL=0
MODEL_PASSED=0
MODEL_FAILED=0
EXPECTED_QUOTA_TOTAL=0
EXPECTED_WALLET_QUOTA_TOTAL=0
: >"$USED_CHANNEL_IDS_FILE"

while IFS= read -r model_name; do
  [[ -n "$model_name" ]] || continue
  MODEL_TOTAL=$((MODEL_TOTAL + 1))
  MODEL_STARTED="$(date +%s)"
  SAFE_INDEX="$(printf '%03d' "$MODEL_TOTAL")"
  PAYLOAD_FILE="$TMP_DIR/chat-$SAFE_INDEX.json"
  RESPONSE_FILE="$TMP_DIR/chat-$SAFE_INDEX-response.json"
  HEADERS_FILE="$TMP_DIR/chat-$SAFE_INDEX.headers"

  python3 - "$model_name" "$MAX_TOKENS" >"$PAYLOAD_FILE" <<'PY'
import json
import sys

json.dump({
    "model": sys.argv[1],
    "messages": [{"role": "user", "content": "Reply with only OK."}],
    "max_tokens": int(sys.argv[2]),
    "stream": False,
}, sys.stdout, ensure_ascii=False)
PY

  MODEL_FAILURE=""
  VALIDATION=""
  REQUEST_ID=""
  LOG_ROW=""
  if ! api_request "$RESPONSE_FILE" "$HEADERS_FILE" \
      --header "@$AUTH_HEADER_FILE" \
      --header 'Content-Type: application/json' \
      --data-binary "@$PAYLOAD_FILE" \
      "$ORIGIN/v1/chat/completions"; then
    MODEL_FAILURE="HTTP $LAST_HTTP_STATUS: $(api_error_summary "$RESPONSE_FILE")"
  elif ! VALIDATION="$(validate_chat_response "$RESPONSE_FILE" 2>&1)"; then
    MODEL_FAILURE="$VALIDATION"
  else
    REQUEST_ID="$(request_id_from_headers "$HEADERS_FILE")"
    if [[ ! "$REQUEST_ID" =~ ^[A-Za-z0-9._:-]{8,128}$ ]]; then
      MODEL_FAILURE="response is missing a valid X-Oneapi-Request-Id header"
    elif ! LOG_ROW="$(wait_for_consume_log "$REQUEST_ID")"; then
      MODEL_FAILURE="no consumption log appeared for request ID $REQUEST_ID within ${LOG_WAIT_SECONDS}s"
    fi
  fi

  if [[ -z "$MODEL_FAILURE" ]]; then
    IFS=$'\t' read -r \
      CONTENT_CHARS REASONING_CHARS TOOL_CALLS USAGE_TOTAL FINISH_REASON RETURNED_MODEL \
      <<<"$VALIDATION"
    IFS=$'\t' read -r \
      LOG_ID LOG_USER_ID LOG_TOKEN_ID LOG_TYPE LOG_CHANNEL_ID LOG_MODEL_NAME LOG_QUOTA \
      LOG_PROMPT_TOKENS LOG_COMPLETION_TOKENS LOG_REQUEST_ID LOG_BILLING_SOURCE <<<"$LOG_ROW"

    if [[ "$LOG_USER_ID" != "$TARGET_USER_ID" ]]; then
      MODEL_FAILURE="consumption log belongs to user $LOG_USER_ID instead of $TARGET_USER_ID"
    elif [[ "$LOG_TOKEN_ID" != "$TOKEN_DB_ID" ]]; then
      MODEL_FAILURE="consumption log belongs to API Key record $LOG_TOKEN_ID instead of $TOKEN_DB_ID"
    elif [[ "$LOG_TYPE" != "2" ]]; then
      MODEL_FAILURE="request log type is $LOG_TYPE instead of consumption type 2"
    elif [[ ! "$LOG_CHANNEL_ID" =~ ^[1-9][0-9]*$ ]]; then
      MODEL_FAILURE="consumption log has no valid channel ID"
    elif [[ "$LOG_MODEL_NAME" != "$model_name" ]]; then
      MODEL_FAILURE="consumption log model '$LOG_MODEL_NAME' does not match '$model_name'"
    elif [[ "$LOG_REQUEST_ID" != "$REQUEST_ID" ]]; then
      MODEL_FAILURE="consumption log request ID does not match the response"
    elif [[ "$LOG_BILLING_SOURCE" != "wallet" && "$LOG_BILLING_SOURCE" != "subscription" ]]; then
      MODEL_FAILURE="consumption log has an unknown billing source '$LOG_BILLING_SOURCE'"
    elif [[ ! "$LOG_QUOTA" =~ ^[0-9]+$ ]]; then
      MODEL_FAILURE="consumption log has an invalid quota"
    elif [[ "$ALLOW_ZERO_COST" != "true" && "$LOG_QUOTA" -eq 0 ]]; then
      MODEL_FAILURE="consumption log quota is zero (use --allow-zero-cost only for an intentionally free model)"
    elif [[ ! "$LOG_PROMPT_TOKENS" =~ ^[0-9]+$ || ! "$LOG_COMPLETION_TOKENS" =~ ^[0-9]+$ ||
            $((LOG_PROMPT_TOKENS + LOG_COMPLETION_TOKENS)) -le 0 ]]; then
      MODEL_FAILURE="consumption log has no positive token usage"
    elif [[ $((LOG_PROMPT_TOKENS + LOG_COMPLETION_TOKENS)) -ne "$USAGE_TOTAL" ]]; then
      MODEL_FAILURE="response usage $USAGE_TOTAL does not match consumption-log tokens $((LOG_PROMPT_TOKENS + LOG_COMPLETION_TOKENS))"
    fi
  fi

  if [[ -z "$MODEL_FAILURE" ]]; then
    MODEL_PASSED=$((MODEL_PASSED + 1))
    EXPECTED_QUOTA_TOTAL=$((EXPECTED_QUOTA_TOTAL + LOG_QUOTA))
    if [[ "$LOG_BILLING_SOURCE" == "wallet" ]]; then
      EXPECTED_WALLET_QUOTA_TOTAL=$((EXPECTED_WALLET_QUOTA_TOTAL + LOG_QUOTA))
    fi
    printf '%s\n' "$LOG_CHANNEL_ID" >>"$USED_CHANNEL_IDS_FILE"
    report_step "model: $model_name" "PASS" \
      "HTTP 2xx; request $REQUEST_ID; usage $USAGE_TOTAL tokens; billed $LOG_QUOTA quota from $LOG_BILLING_SOURCE; channel $LOG_CHANNEL_ID; log $LOG_ID" \
      "$MODEL_STARTED"
    printf '      PASS  %-28s usage=%-6s quota=%-8s source=%-12s channel=%s\n' \
      "$model_name" "$USAGE_TOTAL" "$LOG_QUOTA" "$LOG_BILLING_SOURCE" "$LOG_CHANNEL_ID"
  else
    MODEL_FAILED=$((MODEL_FAILED + 1))
    MODEL_FAILURE="${MODEL_FAILURE//$'\n'/ }"
    MODEL_FAILURE="${MODEL_FAILURE//$'\r'/ }"
    report_step "model: $model_name" "FAIL" "${MODEL_FAILURE:0:220}" "$MODEL_STARTED"
    printf '      FAIL  %-28s %s\n' "$model_name" "${MODEL_FAILURE:0:180}" >&2
  fi
done <"$TEST_MODELS_FILE"

USED_CHANNEL_COUNT="$(sort -nu "$USED_CHANNEL_IDS_FILE" 2>/dev/null | sed '/^$/d' | wc -l)"
USED_CHANNEL_LIST="$(sort -nu "$USED_CHANNEL_IDS_FILE" 2>/dev/null | paste -sd, -)"
USED_CHANNEL_LIST="${USED_CHANNEL_LIST:-none}"
report_step "$CURRENT_STEP" "$([[ "$MODEL_FAILED" -eq 0 ]] && printf PASS || printf FAIL)" \
  "$MODEL_PASSED/$MODEL_TOTAL model call(s) passed strict response and per-request billing validation; exercised $USED_CHANNEL_COUNT channel(s): $USED_CHANNEL_LIST"

# --------------- step 6: aggregate billing consistency ---------------

begin_step "aggregate billing"
echo "[6/7] Checking aggregate token and user billing counters..."

BILLING_FAILURE=""
COUNTERS_MATCH=false
COUNTER_ROW=""
for ((attempt=1; attempt<=LOG_WAIT_SECONDS; attempt++)); do
  if COUNTER_ROW="$(db_query "
SELECT tokens.used_quota, users.quota, users.used_quota
FROM tokens
JOIN users ON users.id = tokens.user_id
WHERE tokens.id = $TOKEN_DB_ID
  AND tokens.user_id = $TARGET_USER_ID
  AND tokens.deleted_at IS NULL
  AND users.deleted_at IS NULL
LIMIT 1;
" 2>/dev/null)" && [[ -n "$COUNTER_ROW" ]]; then
    IFS=$'\t' read -r TOKEN_USED_AFTER USER_QUOTA_AFTER USER_USED_AFTER <<<"$COUNTER_ROW"
    if [[ "$TOKEN_USED_AFTER" =~ ^[0-9]+$ && "$USER_QUOTA_AFTER" =~ ^[0-9]+$ &&
          "$USER_USED_AFTER" =~ ^[0-9]+$ ]]; then
      TOKEN_USED_DELTA=$((TOKEN_USED_AFTER - TOKEN_USED_BEFORE))
      USER_USED_DELTA=$((USER_USED_AFTER - USER_USED_BEFORE))
      USER_QUOTA_DELTA=$((USER_QUOTA_BEFORE - USER_QUOTA_AFTER))
      if [[ "$TOKEN_USED_DELTA" -eq "$EXPECTED_QUOTA_TOTAL" &&
            "$USER_USED_DELTA" -eq "$EXPECTED_QUOTA_TOTAL" &&
            "$USER_QUOTA_DELTA" -eq "$EXPECTED_WALLET_QUOTA_TOTAL" ]]; then
        COUNTERS_MATCH=true
        break
      fi
    fi
  fi
  sleep 1
done

[[ -n "$COUNTER_ROW" ]] || die "Unable to read post-call billing counters"
[[ "${TOKEN_USED_AFTER:-}" =~ ^[0-9]+$ && "${USER_QUOTA_AFTER:-}" =~ ^[0-9]+$ &&
   "${USER_USED_AFTER:-}" =~ ^[0-9]+$ ]] || die "Post-call billing counters are invalid"

if [[ "$COUNTERS_MATCH" != "true" ]]; then
  if [[ "$TOKEN_USED_DELTA" -ne "$EXPECTED_QUOTA_TOTAL" ]]; then
    BILLING_FAILURE="API Key used_quota delta $TOKEN_USED_DELTA does not equal matched-log quota $EXPECTED_QUOTA_TOTAL"
  elif [[ "$USER_USED_DELTA" -ne "$EXPECTED_QUOTA_TOTAL" ]]; then
    BILLING_FAILURE="user used_quota delta $USER_USED_DELTA does not equal matched-log quota $EXPECTED_QUOTA_TOTAL"
  else
    BILLING_FAILURE="wallet quota delta $USER_QUOTA_DELTA does not equal wallet-billed log quota $EXPECTED_WALLET_QUOTA_TOTAL"
  fi
fi

if [[ -n "$BILLING_FAILURE" ]]; then
  report_step "$CURRENT_STEP" "FAIL" "$BILLING_FAILURE; concurrent use of the selected API Key can invalidate this check"
  echo "      FAIL: $BILLING_FAILURE" >&2
else
  report_step "$CURRENT_STEP" "PASS" \
    "Matched logs, API Key used_quota, and user used_quota agree at $EXPECTED_QUOTA_TOTAL; wallet quota agrees at $EXPECTED_WALLET_QUOTA_TOTAL"
  echo "      Billing counters agree: $EXPECTED_QUOTA_TOTAL total quota ($EXPECTED_WALLET_QUOTA_TOTAL wallet)."
fi

# --------------- step 7: application log verification ---------------

begin_step "application log verification"
echo "[7/7] Checking application logs since the validation started..."

APP_LOG="$TMP_DIR/new-api.log"
app_logs_since "$RUN_STARTED_AT" "$APP_LOG" || die "Unable to read new-api logs"
SEVERE_COUNT="$(
  (grep -Eai \
    'panic|fatal|\|[[:space:]]*500[[:space:]]*\||HTTP/[0-9.]+[[:space:]]+500|status[^0-9]{0,8}500|"status"[[:space:]]*:[[:space:]]*500' \
    "$APP_LOG" || true) | wc -l
)"

if [[ "$SEVERE_COUNT" == "0" ]]; then
  report_step "$CURRENT_STEP" "PASS" "No panic, fatal, or recognized HTTP 500 entries detected"
  echo "      Application log check passed."
else
  report_step "$CURRENT_STEP" "FAIL" \
    "Detected $SEVERE_COUNT possible panic, fatal, or HTTP 500 log entries; raw logs are intentionally omitted"
  echo "      FAIL: detected $SEVERE_COUNT possible severe application log entries." >&2
fi

# --------------- final result ---------------

begin_step "complete"
FINAL_FAILURES=0
[[ "$MODEL_FAILED" -eq 0 ]] || FINAL_FAILURES=$((FINAL_FAILURES + 1))
[[ -z "$BILLING_FAILURE" ]] || FINAL_FAILURES=$((FINAL_FAILURES + 1))
[[ "$SEVERE_COUNT" == "0" ]] || FINAL_FAILURES=$((FINAL_FAILURES + 1))

if [[ "$FINAL_FAILURES" -ne 0 ]]; then
  report_step "$CURRENT_STEP" "FAIL" \
    "$MODEL_PASSED/$MODEL_TOTAL models passed across $USED_CHANNEL_COUNT channel(s); billing quota $EXPECTED_QUOTA_TOTAL; $FINAL_FAILURES validation area(s) failed"
  echo
  echo "Model-calling flow failed."
  echo "Models passed: $MODEL_PASSED/$MODEL_TOTAL"
  echo "Report: $REPORT_FILE"
  exit 1
fi

report_step "$CURRENT_STEP" "PASS" \
  "$MODEL_PASSED/$MODEL_TOTAL models passed across $USED_CHANNEL_COUNT channel(s); exact consumption logs and $EXPECTED_QUOTA_TOTAL quota verified"

echo
echo "Model-calling flow passed."
echo "Models passed: $MODEL_PASSED/$MODEL_TOTAL"
echo "Channels exercised: $USED_CHANNEL_COUNT ($USED_CHANNEL_LIST)"
echo "Verified billed quota: $EXPECTED_QUOTA_TOTAL"
echo "Report: $REPORT_FILE"
