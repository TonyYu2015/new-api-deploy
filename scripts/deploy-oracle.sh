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

if [ ! -f .env ]; then
  cp .env.example .env
  ./scripts/gen-secrets.sh
fi

if grep -q '^NEW_API_PORT=' .env; then
  sed -i 's/^NEW_API_PORT=.*/NEW_API_PORT=80/' .env
else
  echo 'NEW_API_PORT=80' >> .env
fi

set_env_default() {
  local key="$1"
  local value="$2"
  if ! grep -q "^${key}=" .env; then
    echo "${key}=${value}" >> .env
  fi
}

set_env_default NGINX_IMAGE nginx:1.27-alpine
set_env_default STRIPE_SECRET_KEY ''
set_env_default STRIPE_WEBHOOK_SECRET ''
set_env_default STRIPE_CURRENCY usd
set_env_default STRIPE_SUCCESS_URL 'http://144.24.26.129/stripe/success'
set_env_default STRIPE_CANCEL_URL 'http://144.24.26.129/stripe/cancel'
set_env_default TOPUP_QUOTA_PER_USD 500000
set_env_default TOPUP_MIN_USD 5
set_env_default TOPUP_MAX_USD 500
set_env_default TOPUP_ALLOWED_AMOUNTS '5,10,20,50,100'

sudo docker compose pull
sudo docker compose up -d
sudo docker compose ps
REMOTE

echo "Oracle deployment finished."
