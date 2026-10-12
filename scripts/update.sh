#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck source=lib/env.sh
. scripts/lib/env.sh

ENV_FILE="${ENV_FILE:-.env.dev}"
if [ ! -f "$ENV_FILE" ]; then
  echo "Environment file not found: $ENV_FILE" >&2
  exit 1
fi

mapfile -t ENV_ARGS < <(env_args "$ENV_FILE")

docker compose "${ENV_ARGS[@]}" pull new-api
docker compose "${ENV_ARGS[@]}" up -d new-api
docker compose "${ENV_ARGS[@]}" logs --tail=80 new-api
