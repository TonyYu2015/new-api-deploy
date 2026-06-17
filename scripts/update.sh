#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

docker compose pull new-api
docker compose up -d new-api
docker compose logs --tail=80 new-api

