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

# Move legacy secrets out of the tracked env file before it is reset to the
# committed, secret-free version.
migrate_legacy_secrets() {
  local base="$1"
  local local_file="${base}.local"
  local key value

  [ -f "$base" ] || return 0
  [ -f "$local_file" ] && return 0

  umask 077
  : > "$local_file"
  chmod 600 "$local_file"
  for key in SESSION_SECRET CRYPTO_SECRET MYSQL_ROOT_PASSWORD MYSQL_PASSWORD REDIS_PASSWORD; do
    value="$(sed -n "s/^${key}=//p" "$base" | tail -n 1)"
    if [ -n "$value" ]; then
      printf '%s=%s\n' "$key" "$value" >> "$local_file"
    fi
  done
  echo "Migrated secrets from $base to $local_file"
}

if [ -d "$DEPLOY_PATH/.git" ]; then
  ( cd "$DEPLOY_PATH" && migrate_legacy_secrets .env.production ) || true
fi

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
  echo "Base env file not found: $ENV_FILE" >&2
  exit 1
fi

umask 077
touch "${ENV_FILE}.local"
chmod 600 "${ENV_FILE}.local"

if ! grep -q '^MYSQL_PASSWORD=.\+' "${ENV_FILE}.local"; then
  ./scripts/gen-secrets.sh "$ENV_FILE"
fi

# shellcheck source=lib/env.sh
. scripts/lib/env.sh

mapfile -t ENV_ARGS < <(env_args "$ENV_FILE")

sudo docker compose "${ENV_ARGS[@]}" pull
sudo docker compose "${ENV_ARGS[@]}" up -d
if sudo docker network inspect new-api-staging_new-api-net >/dev/null 2>&1; then
  sudo docker network connect new-api-staging_new-api-net new-api-nginx 2>/dev/null || true
fi
if [ -x scripts/sync-gateway-safeguards.sh ]; then
  ./scripts/sync-gateway-safeguards.sh "$ENV_FILE"
fi
sudo docker compose "${ENV_ARGS[@]}" ps
REMOTE

echo "Oracle deployment finished."
