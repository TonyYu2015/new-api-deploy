#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
  cp .env.example .env
fi

replace_value() {
  local key="$1"
  local value="$2"
  sed -i "s|^${key}=.*|${key}=${value}|" .env
}

random_hex() {
  openssl rand -hex 32
}

replace_value "SESSION_SECRET" "$(random_hex)"
replace_value "CRYPTO_SECRET" "$(random_hex)"
replace_value "MYSQL_ROOT_PASSWORD" "$(random_hex)"
replace_value "MYSQL_PASSWORD" "$(random_hex)"
replace_value "REDIS_PASSWORD" "$(random_hex)"

echo "Updated .env with generated secrets."

