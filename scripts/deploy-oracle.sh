#!/usr/bin/env bash
set -euo pipefail

DEPLOY_HOST="${DEPLOY_HOST:-oracle}"
DEPLOY_PATH="${DEPLOY_PATH:-/opt/new-api-deploy}"
GIT_REPO="${GIT_REPO:-$(git config --get remote.origin.url)}"
GIT_REF="${GIT_REF:-$(git branch --show-current)}"

if [ -z "$GIT_REPO" ] || [ -z "$GIT_REF" ]; then
  echo "GIT_REPO and GIT_REF are required."
  exit 1
fi

ssh -o BatchMode=yes -o ConnectTimeout=10 "$DEPLOY_HOST" "echo connected >/dev/null"

ssh -t "$DEPLOY_HOST" \
  "DEPLOY_PATH='$DEPLOY_PATH' GIT_REPO='$GIT_REPO' GIT_REF='$GIT_REF' bash -s" <<'REMOTE'
set -euo pipefail

stop_compose_project() {
  local path="$1"
  if [ -d "$path" ]; then
    cd "$path"
    if [ -f docker-compose.yml ] || [ -f compose.yml ]; then
      sudo docker compose down || true
    fi
  fi
}

echo "Stopping old LiteLLM deployments..."
stop_compose_project /opt/litellm-registry
stop_compose_project /home/ubuntu/litellm-registry
stop_compose_project /home/ubuntu/litellm-registry/litellm-deploy

sudo docker stop litellm-nginx litellm-registry litellm-proxy litellm-postgres 2>/dev/null || true
sudo docker rm litellm-nginx litellm-registry litellm-proxy litellm-postgres 2>/dev/null || true

echo "Preparing $DEPLOY_PATH..."
sudo mkdir -p "$DEPLOY_PATH"
sudo chown "$(id -un):$(id -gn)" "$DEPLOY_PATH"

if [ ! -d "$DEPLOY_PATH/.git" ]; then
  if find "$DEPLOY_PATH" -mindepth 1 -maxdepth 1 | grep -q .; then
    legacy_path="${DEPLOY_PATH}.legacy.$(date +%Y%m%d%H%M%S)"
    sudo mkdir -p "$legacy_path"
    sudo find "$DEPLOY_PATH" -mindepth 1 -maxdepth 1 -exec mv -t "$legacy_path" {} + 2>/dev/null || true
  fi
  git clone --branch "$GIT_REF" "$GIT_REPO" "$DEPLOY_PATH"
else
  cd "$DEPLOY_PATH"
  git remote set-url origin "$GIT_REPO"
  git fetch --prune origin "$GIT_REF"
  git checkout -B "$GIT_REF" "origin/$GIT_REF"
  git reset --hard "origin/$GIT_REF"
fi

cd "$DEPLOY_PATH"

ENV_FILE=".env.production"

if [ ! -f "$ENV_FILE" ]; then
  if [ -f .env ]; then
    cp .env "$ENV_FILE"
  else
    cp .env.production.example "$ENV_FILE"
    ./scripts/gen-secrets.sh "$ENV_FILE"
  fi
fi

if grep -q '^HTTP_PORT=' "$ENV_FILE"; then
  sed -i 's/^HTTP_PORT=.*/HTTP_PORT=80/' "$ENV_FILE"
else
  echo 'HTTP_PORT=80' >> "$ENV_FILE"
fi

if grep -q '^HTTPS_PORT=' "$ENV_FILE"; then
  sed -i 's/^HTTPS_PORT=.*/HTTPS_PORT=443/' "$ENV_FILE"
else
  echo 'HTTPS_PORT=443' >> "$ENV_FILE"
fi

set_env_default() {
  local key="$1"
  local value="$2"
  if ! grep -q "^${key}=" "$ENV_FILE"; then
    echo "${key}=${value}" >> "$ENV_FILE"
  fi
}

set_env_default CADDY_IMAGE caddy:2.8-alpine
set_env_default NGINX_IMAGE nginx:1.27-alpine
set_env_default COMPOSE_PROJECT_NAME new-api-deploy
set_env_default APP_CONTAINER_NAME new-api
set_env_default CADDY_CONTAINER_NAME new-api-nginx
set_env_default HTML_FILTER_CONTAINER_NAME new-api-html-filter
set_env_default MYSQL_CONTAINER_NAME new-api-mysql
set_env_default REDIS_CONTAINER_NAME new-api-redis
set_env_default NEW_API_DATA_DIR ./data/new-api
set_env_default MYSQL_DATA_DIR ./data/mysql
set_env_default REDIS_DATA_DIR ./data/redis

sudo docker compose --env-file "$ENV_FILE" pull
sudo docker compose --env-file "$ENV_FILE" up -d
sudo docker compose --env-file "$ENV_FILE" ps
REMOTE

echo "Oracle deployment finished."
