#!/usr/bin/env bash
set -euo pipefail

DEPLOY_PATH="${DEPLOY_PATH:-/opt/new-api-deploy}"
ENV_FILE="${ENV_FILE:-.env.staging}"

cd "$DEPLOY_PATH"

if [ ! -f "$ENV_FILE" ]; then
  echo "Base env file not found: $ENV_FILE" >&2
  exit 1
fi

# shellcheck source=lib/env.sh
. scripts/lib/env.sh

LOCAL_ENV_FILE="${ENV_FILE}.local"

# Preserve secrets already stored in the base env file (legacy layouts kept
# them there) before generating new ones.
if [ ! -f "$LOCAL_ENV_FILE" ] && [ -f "$ENV_FILE" ]; then
  umask 077
  : > "$LOCAL_ENV_FILE"
  chmod 600 "$LOCAL_ENV_FILE"
  for key in SESSION_SECRET CRYPTO_SECRET MYSQL_ROOT_PASSWORD MYSQL_PASSWORD REDIS_PASSWORD; do
    value="$(sed -n "s/^${key}=//p" "$ENV_FILE" | tail -n 1)"
    if [ -n "$value" ]; then
      printf '%s=%s\n' "$key" "$value" >> "$LOCAL_ENV_FILE"
    fi
  done
  echo "Migrated secrets from $ENV_FILE to $LOCAL_ENV_FILE"
fi

umask 077
touch "$LOCAL_ENV_FILE"
chmod 600 "$LOCAL_ENV_FILE"

set_secret() {
  local key="$1"
  local bytes="$2"
  local value

  if grep -q "^${key}=.\+" "$LOCAL_ENV_FILE"; then
    return 0
  fi

  value="$(openssl rand -hex "$bytes")"
  if grep -q "^${key}=" "$LOCAL_ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$LOCAL_ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$value" >> "$LOCAL_ENV_FILE"
  fi
}

set_secret MYSQL_PASSWORD 24
set_secret MYSQL_ROOT_PASSWORD 24
set_secret REDIS_PASSWORD 24
set_secret SESSION_SECRET 32
set_secret CRYPTO_SECRET 16

mapfile -t ENV_ARGS < <(env_args "$ENV_FILE")

new_api_data_dir="$(env_read NEW_API_DATA_DIR "$ENV_FILE")"
mysql_data_dir="$(env_read MYSQL_DATA_DIR "$ENV_FILE")"
redis_data_dir="$(env_read REDIS_DATA_DIR "$ENV_FILE")"

new_api_data_dir="${new_api_data_dir:-./data/staging/new-api}"
mysql_data_dir="${mysql_data_dir:-./data/staging/mysql}"
redis_data_dir="${redis_data_dir:-./data/staging/redis}"

sudo mkdir -p "$new_api_data_dir" "$mysql_data_dir" "$redis_data_dir"
sudo chown -R "$(id -u):$(id -g)" "$new_api_data_dir"
sudo chown -R 999:999 "$mysql_data_dir"
sudo chown -R 999:1000 "$redis_data_dir"

new_api_image="$(grep '^NEW_API_IMAGE=' "$ENV_FILE" | cut -d= -f2-)"
if [[ "$new_api_image" == ccai/new-api:* ]]; then
  sudo docker build \
    --file custom-new-api/Dockerfile \
    --tag "$new_api_image" \
    .
  sudo docker compose "${ENV_ARGS[@]}" pull nginx html-filter mysql redis
else
  sudo docker compose "${ENV_ARGS[@]}" pull
fi
sudo docker compose "${ENV_ARGS[@]}" up -d

# The html-filter nginx resolves the "new-api" upstream only when it starts,
# and Caddy resolves "html-filter" the same way. When the app container is
# recreated with a new IP both proxies keep the stale address and the site
# returns 502 until they restart, so recreate the proxy tier after the app.
sudo docker compose "${ENV_ARGS[@]}" up -d --force-recreate html-filter nginx

if sudo docker inspect new-api-nginx >/dev/null 2>&1; then
  sudo docker network connect new-api-staging_new-api-net new-api-nginx 2>/dev/null || true
fi

sudo docker compose "${ENV_ARGS[@]}" ps
