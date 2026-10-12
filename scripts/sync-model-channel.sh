#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-.env.dev}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Environment file not found: $ENV_FILE" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required" >&2
  exit 1
fi

# shellcheck source=lib/env.sh
. scripts/lib/env.sh

mapfile -t ENV_ARGS < <(env_args "$ENV_FILE")

# Read KEY from the base env file with the <base>.local override applied.
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
            if name.strip() == key:
                item = item.strip()
                if len(item) >= 2 and item[0] == item[-1] and item[0] in "\"'\''":
                    item = item[1:-1]
                value = item
print(value)
' "$1" "$ENV_FILE" "${ENV_FILE}.local"
}

CHANNEL_NAME="$(read_env UPSTREAM_CHANNEL_NAME)"
MODEL_NAMES="$(read_env UPSTREAM_MODEL_NAMES)"
BASE_URL="$(read_env UPSTREAM_BASE_URL)"
API_KEY="$(read_env UPSTREAM_API_KEY)"

[[ -n "$CHANNEL_NAME" ]] || { echo "UPSTREAM_CHANNEL_NAME is empty in $ENV_FILE" >&2; exit 1; }
[[ -n "$MODEL_NAMES" ]] || { echo "UPSTREAM_MODEL_NAMES is empty in $ENV_FILE" >&2; exit 1; }
[[ -n "$BASE_URL" ]] || { echo "UPSTREAM_BASE_URL is empty in $ENV_FILE" >&2; exit 1; }
[[ -n "$API_KEY" ]] || { echo "UPSTREAM_API_KEY is empty in $ENV_FILE" >&2; exit 1; }

if [[ "$BASE_URL" != http://* && "$BASE_URL" != https://* ]]; then
  echo "UPSTREAM_BASE_URL must start with http:// or https://" >&2
  exit 1
fi

MODEL_NAMES="$(
  python3 -c '
import sys

models = [item.strip() for item in sys.argv[1].split(",") if item.strip()]
if not models:
    raise SystemExit("UPSTREAM_MODEL_NAMES must contain at least one model")
print(",".join(dict.fromkeys(models)))
' "$MODEL_NAMES"
)"

sql_quote() {
  printf '%s' "$1" | sed "s/'/''/g"
}

channel_name="$(sql_quote "$CHANNEL_NAME")"
model_names="$(sql_quote "$MODEL_NAMES")"
base_url="$(sql_quote "${BASE_URL%/}")"
api_key="$(sql_quote "$API_KEY")"

docker compose "${ENV_ARGS[@]}" exec -T mysql sh -lc \
  'mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"' <<SQL
UPDATE channels
SET type = 1,
    \`key\` = '$api_key',
    status = 1,
    base_url = '$base_url',
    models = '$model_names',
    weight = 1,
    auto_ban = 1
WHERE name = '$channel_name';

INSERT INTO channels (
  type, \`key\`, status, name, weight, created_time, base_url,
  models, \`group\`, priority, auto_ban
)
SELECT
  1, '$api_key', 1, '$channel_name', 1, UNIX_TIMESTAMP(),
  '$base_url', '$model_names', 'default', 0, 1
WHERE NOT EXISTS (
  SELECT 1 FROM channels WHERE name = '$channel_name'
);
SQL

docker compose "${ENV_ARGS[@]}" restart new-api >/dev/null

echo "Configured channel: $CHANNEL_NAME"
echo "Base URL: $BASE_URL"
echo "Models: $MODEL_NAMES"
