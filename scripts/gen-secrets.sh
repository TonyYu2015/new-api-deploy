#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

ENV_FILE="${1:-${ENV_FILE:-.env}}"

if [ ! -f "$ENV_FILE" ]; then
  case "$ENV_FILE" in
    .env.production)
      cp .env.production.example "$ENV_FILE"
      ;;
    .env.development)
      cp .env.development.example "$ENV_FILE"
      ;;
    *)
      cp .env.example "$ENV_FILE"
      ;;
  esac
fi

replace_value() {
  local key="$1"
  local value="$2"
  sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
}

random_hex() {
  openssl rand -hex 32
}

replace_value "SESSION_SECRET" "$(random_hex)"
replace_value "CRYPTO_SECRET" "$(random_hex)"
replace_value "MYSQL_ROOT_PASSWORD" "$(random_hex)"
replace_value "MYSQL_PASSWORD" "$(random_hex)"
replace_value "REDIS_PASSWORD" "$(random_hex)"

echo "Updated $ENV_FILE with generated secrets."
