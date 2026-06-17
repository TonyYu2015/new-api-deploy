# New API Deploy

Docker Compose deployment project for New API.

## Requirements

- Docker
- Docker Compose plugin

## Quick Start

```bash
cd /root/new-api-deploy
cp .env.example .env
./scripts/gen-secrets.sh
docker compose pull
docker compose up -d
```

Open:

```text
http://SERVER_IP:3001
```

If this runs on a cloud server, make sure TCP port `3001` is allowed by the firewall/security group. For production, put Nginx/Caddy in front of it and serve HTTPS on `443`.

## Common Commands

```bash
# Start
docker compose up -d

# Stop
docker compose down

# View logs
docker compose logs -f new-api

# Upgrade image
docker compose pull new-api
docker compose up -d new-api
```

## Stripe Top-up

This deployment includes a separate one-time top-up service for usage-based billing.

Flow:

1. User opens `/stripe/`.
2. User enters their New API access token and selects a one-time amount.
3. Stripe Checkout collects payment.
4. Stripe webhook calls `/stripe/webhook`.
5. The service updates `top_ups` and increments `users.quota`.

Required `.env` values:

```bash
STRIPE_SECRET_KEY=sk_live_or_test_xxx
STRIPE_WEBHOOK_SECRET=whsec_xxx
STRIPE_SUCCESS_URL=https://your-domain.example/stripe/success
STRIPE_CANCEL_URL=https://your-domain.example/stripe/cancel
TOPUP_QUOTA_PER_USD=500000
TOPUP_ALLOWED_AMOUNTS=5,10,20,50,100
```

Create the Stripe webhook endpoint:

```text
https://your-domain.example/stripe/webhook
```

Subscribe at minimum to:

- `checkout.session.completed`
- `checkout.session.expired`
- `payment_intent.payment_failed`

Leave `STRIPE_SECRET_KEY` empty to keep checkout disabled while the service and routing are still deployed.

## Data

Persistent data is stored under:

- `data/mysql`
- `data/redis`
- `data/new-api`

Back up this directory before upgrading or moving the service.

## Environment

Edit `.env` to change ports, image tags, database passwords, and secrets.

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
