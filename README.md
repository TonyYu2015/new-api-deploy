# New API Deploy

Docker Compose deployment project for New API.

## Requirements

- Docker
- Docker Compose plugin

## Quick Start

```bash
cd /root/new-api-deploy
cp .env.development.example .env.development
./scripts/gen-secrets.sh .env.development
docker compose --env-file .env.development pull
docker compose --env-file .env.development up -d
```

Open:

```text
http://SERVER_IP:3001
https://SERVER_IP:3443
```

If this runs on a cloud server, make sure TCP ports `80` and `443` are allowed by the firewall/security group. The Oracle deploy script publishes Caddy on both ports and serves HTTPS for `ccaiservice.com` and `www.ccaiservice.com`.

## Environments

Local development uses `.env.development`.

Oracle production uses `.env.production` and is managed by:

```bash
./scripts/deploy-oracle.sh
```

Do not copy local `.env` values to production. The deploy script creates `.env.production` on Oracle if needed and keeps production data in the existing `./data/*` paths.

## Common Commands

```bash
# Start
docker compose --env-file .env.development up -d

# Stop
docker compose --env-file .env.development down

# View logs
docker compose --env-file .env.development logs -f new-api

# Upgrade image
docker compose --env-file .env.development pull new-api
docker compose --env-file .env.development up -d new-api
```

## Data

Persistent data is stored under:

- `data/mysql`
- `data/redis`
- `data/new-api`

Back up this directory before upgrading or moving the service.

## Environment

Edit `.env.development` locally or `.env.production` on Oracle to change ports, image tags, database passwords, and secrets.

Use a pinned image tag in production instead of `latest` once you have verified a working version.

This project uses normal Docker Hub image names. Configure domestic Docker registry mirrors on the host, then run `docker compose pull`.

Current recommended `/etc/docker/daemon.json` shape:

```json
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.xuanyuan.me"
  ]
}
```

If you prefer explicit proxy image names instead, edit these variables in `.env`:

```bash
NEW_API_IMAGE=docker.m.daocloud.io/calciumion/new-api:latest
MYSQL_IMAGE=docker.m.daocloud.io/mysql:8.4
REDIS_IMAGE=docker.m.daocloud.io/redis:7-alpine
```
