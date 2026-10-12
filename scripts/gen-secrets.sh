#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

ENV_FILE="${1:-${ENV_FILE:-}}"

if [ -z "$ENV_FILE" ]; then
  echo "Usage: scripts/gen-secrets.sh <env-file>" >&2
  echo "Supported environments: .env.dev, .env.staging, .env.production" >&2
  exit 2
fi

case "$ENV_FILE" in
  .env.dev|.env.staging|.env.production)
    ;;
  *)
    echo "Unsupported env file: $ENV_FILE" >&2
    echo "Use one of: .env.dev, .env.staging, .env.production" >&2
    exit 1
    ;;
esac

if [ ! -f "$ENV_FILE" ]; then
  echo "Base env file not found: $ENV_FILE" >&2
  exit 1
fi

LOCAL_ENV_FILE="${ENV_FILE}.local"
umask 077
touch "$LOCAL_ENV_FILE"
chmod 600 "$LOCAL_ENV_FILE"

random_hex() {
  openssl rand -hex 32
}

# Generate a secret only when the local override does not already set one.
ensure_secret() {
  local key="$1"
  local value

  if grep -q "^${key}=.\+" "$LOCAL_ENV_FILE"; then
    return 0
  fi

  value="$(random_hex)"
  if grep -q "^${key}=" "$LOCAL_ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$LOCAL_ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$value" >> "$LOCAL_ENV_FILE"
  fi
}

ensure_secret SESSION_SECRET
ensure_secret CRYPTO_SECRET
ensure_secret MYSQL_ROOT_PASSWORD
ensure_secret MYSQL_PASSWORD
ensure_secret REDIS_PASSWORD

echo "Updated $LOCAL_ENV_FILE; existing secrets were kept."
