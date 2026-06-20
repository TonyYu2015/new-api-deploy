#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -z "${ENV_FILE:-}" ]; then
  if [ -f .env ]; then
    ENV_FILE=.env
  elif [ -f .env.production ]; then
    ENV_FILE=.env.production
  else
    ENV_FILE=.env.development
  fi
fi

docker compose --env-file "$ENV_FILE" pull new-api
docker compose --env-file "$ENV_FILE" up -d new-api
docker compose --env-file "$ENV_FILE" logs --tail=80 new-api
