#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:-ccai/new-api:rc15-ccai.9}"

docker build \
  --network host \
  --file custom-new-api/Dockerfile \
  --tag "$IMAGE" \
  .

docker image inspect "$IMAGE" --format '{{.Id}}'
