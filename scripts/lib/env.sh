#!/usr/bin/env bash
# Shared handling for the committed base env files and their gitignored
# "<base>.local" secret overrides.
#
# Base files (.env.dev, .env.staging, .env.production) are committed and hold no
# secrets. Real secrets live in <base>.local, which is gitignored. Layer both to
# get the effective configuration:
#
#   docker compose --env-file .env.dev --env-file .env.dev.local up -d

# env_args BASE -> print "--env-file BASE [--env-file BASE.local]" as tokens.
env_args() {
  local base="$1"
  local local_file="${base}.local"
  printf '%s\n' --env-file "$base"
  if [ -f "$local_file" ]; then
    printf '%s\n' --env-file "$local_file"
  fi
}

# env_read KEY BASE -> value from BASE, overridden by BASE.local (last wins).
env_read() {
  local key="$1" base="$2"
  local local_file="${base}.local"
  {
    [ -f "$base" ] && sed -n "s/^${key}=//p" "$base"
    [ -f "$local_file" ] && sed -n "s/^${key}=//p" "$local_file"
  } | tail -n 1
}
