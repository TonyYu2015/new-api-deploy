#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-.env.dev}"
CATALOG_FILE="${QUBRID_PRICING_FILE:-config/qubrid-pricing.json}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required" >&2
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Environment file not found: $ENV_FILE" >&2
  exit 1
fi

if [[ ! -f "$CATALOG_FILE" ]]; then
  echo "Catalog file not found: $CATALOG_FILE" >&2
  exit 1
fi

# shellcheck source=lib/env.sh
. scripts/lib/env.sh

mapfile -t ENV_ARGS < <(env_args "$ENV_FILE")

python3 -c '
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    catalog = json.load(handle)
assert isinstance(catalog["models"], list) and catalog["models"]
for model in catalog["models"]:
    assert isinstance(model["id"], str) and model["id"]
    assert model["input_per_1m"] > 0
    assert model["output_per_1m"] > 0
' "$CATALOG_FILE"

model_ratio="$(
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps({m["id"]:m["input_per_1m"]/2 for m in d["models"]},separators=(",",":")))' "$CATALOG_FILE"
)"
completion_ratio="$(
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps({m["id"]:m["output_per_1m"]/m["input_per_1m"] for m in d["models"]},separators=(",",":")))' "$CATALOG_FILE"
)"
cache_ratio="$(
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps({m["id"]:m["cached_input_per_1m"]/m["input_per_1m"] for m in d["models"] if m.get("cached_input_per_1m") is not None},separators=(",",":")))' "$CATALOG_FILE"
)"
mysql_exec() {
  docker compose "${ENV_ARGS[@]}" exec -T mysql sh -lc \
    'mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"' <<<"$1"
}

sql_quote() {
  printf '%s' "$1" | sed "s/'/''/g"
}

upsert_option() {
  local key value
  key="$(sql_quote "$1")"
  value="$(sql_quote "$2")"
  mysql_exec "
    INSERT INTO options (\`key\`, value)
    VALUES ('$key', '$value')
    ON DUPLICATE KEY UPDATE value = VALUES(value);
  "
}

upsert_option "ModelRatio" "$model_ratio"
upsert_option "CompletionRatio" "$completion_ratio"
upsert_option "CacheRatio" "$cache_ratio"
upsert_option "ExposeRatioEnabled" "true"

header_nav="$(
  mysql_exec "SELECT value FROM options WHERE \`key\` = 'HeaderNavModules' LIMIT 1;" |
    tail -n +2
)"
if [[ -z "$header_nav" ]] || ! python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1 <<<"$header_nav"; then
  header_nav='{"home":true,"console":true,"pricing":{"enabled":true,"requireAuth":false},"docs":false,"about":false}'
else
  header_nav="$(python3 -c 'import json,sys; d=json.load(sys.stdin); d["pricing"]={"enabled":True,"requireAuth":False}; print(json.dumps(d,separators=(",",":")))' <<<"$header_nav")"
fi
upsert_option "HeaderNavModules" "$header_nav"

while IFS=$'\t' read -r id description tags; do
  id="$(sql_quote "$id")"
  description="$(sql_quote "$description")"
  tags="$(sql_quote "$tags")"
  mysql_exec "
    UPDATE models
    SET description = '$description',
        tags = '$tags',
        status = 1,
        sync_official = 0,
        updated_time = UNIX_TIMESTAMP()
    WHERE model_name = '$id' AND deleted_at IS NULL;

    INSERT INTO models (
      model_name, description, tags, status, sync_official,
      created_time, updated_time
    )
    SELECT
      '$id', '$description', '$tags', 1, 0,
      UNIX_TIMESTAMP(), UNIX_TIMESTAMP()
    WHERE NOT EXISTS (
      SELECT 1 FROM models
      WHERE model_name = '$id' AND deleted_at IS NULL
    );
  "
done < <(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); [print(m["id"],m["description"],m["tags"],sep="\t") for m in d["models"]]' "$CATALOG_FILE")

docker compose "${ENV_ARGS[@]}" restart new-api >/dev/null
echo "Configured Qubrid-based pricing for $(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1])).get("models", [])))' "$CATALOG_FILE") models."
echo "No Qubrid API key or channel is required."
