# New API Deploy

Docker Compose deployment project for New API.

## Requirements

- Docker
- Docker Compose plugin

## Quick Start

```bash
cd /root/new-api-deploy
./scripts/gen-secrets.sh .env.dev
docker compose --env-file .env.dev --env-file .env.dev.local pull
docker compose --env-file .env.dev --env-file .env.dev.local up -d
```

Open:

```text
http://SERVER_IP:3101
https://SERVER_IP:3444
```

If this runs on a cloud server, make sure TCP ports `80` and `443` are allowed by the firewall/security group. The Oracle deploy script publishes Caddy on both ports and serves HTTPS for `ccaiservice.com` and `www.ccaiservice.com`.

## Environments

Three base env files are committed and contain no secrets:

- `.env.dev` — local development
- `.env.staging` — staging (`test.ccaiservice.com`)
- `.env.production` — Oracle production

Real secrets live in the gitignored `<base>.local` override, created by:

```bash
./scripts/gen-secrets.sh .env.dev
```

Layer both files for every Compose command:

```bash
docker compose --env-file .env.dev --env-file .env.dev.local up -d
```

Local development is managed directly with `docker compose`. Staging is managed by:

```bash
./scripts/deploy-staging.sh
```

Oracle production is managed by:

```bash
./scripts/deploy-oracle.sh
```

Do not copy local secrets to production. The deploy scripts migrate legacy
secrets into `<base>.local` and keep production data in the existing
`./data/*` paths.

Local development uses `caddy/Caddyfile.local` so it serves plain HTTP on the configured development port without requesting certificates for the production domain.

## Native Creem Billing

New API has built-in Creem settings. Configure these in the New API admin settings or in the `options` database table:

- `CreemTestMode`: use `true` for local/test mode.
- `CreemApiKey`: Creem API key for the matching test or production mode.
- `CreemWebhookSecret`: Creem webhook signing secret.
- `CreemProducts`: JSON array of top-up products.

Example local product shape:

```json
[{"name":"Test $5","productId":"prod_replace_me","price":5,"currency":"USD","quota":2500000}]
```

Use `/api/creem/webhook` as the webhook path. Keep the existing Stripe settings in place while adding Creem, unless you intentionally want to disable Stripe later.

For local development, fill the `CREEM_*` values in `.env.dev.local`, then run:

```bash
./scripts/sync-creem-local.sh
```

## Common Commands

```bash
# Start
docker compose --env-file .env.dev --env-file .env.dev.local up -d

# Stop
docker compose --env-file .env.dev --env-file .env.dev.local down

# View logs
docker compose --env-file .env.dev --env-file .env.dev.local logs -f new-api

# Upgrade image
docker compose --env-file .env.dev --env-file .env.dev.local pull new-api
docker compose --env-file .env.dev --env-file .env.dev.local up -d new-api
```

## Project Records

- Daily work completed, remaining issues, and next-day plans:
  [`WORKLOG.md`](WORKLOG.md)
- Cross-day task status and completion criteria: [`TODO.md`](TODO.md)
- Latest core-flow acceptance evidence:
  [`config/validation/2026-07-23-ccai8-core-flow.md`](config/validation/2026-07-23-ccai8-core-flow.md)
- Production-bound staging changes:
  [`config/production-rollout.md`](config/production-rollout.md)

Review and update the production rollout register before promoting staging
behavior to production.

Deployed Wallet and Profile behavior is covered by the Playwright suite in
[`ui-tests/`](ui-tests/README.md).

## Gateway Safeguards

The Compose environment enables IP-level API, web, and critical-operation rate
limits, a 10-minute streaming timeout, hourly channel tests and balance refresh,
and error logging. Apply authenticated per-user limits and the relay retry count
after the database is running:

```bash
./scripts/sync-gateway-safeguards.sh .env.dev
```

The production defaults allow 30 model requests per authenticated user per
minute and retry a failed relay once. `RELAY_TIMEOUT=0` intentionally avoids
disconnecting a billable non-streaming upstream request before it completes.

## Qubrid Pricing Template

The checked-in pricing template configures model metadata and New API billing
ratios using Qubrid's public serverless prices as the reference:

```bash
./scripts/sync-qubrid-pricing.sh .env.dev
```

This does not connect to Qubrid and does not require a Qubrid API key. Configure
your actual upstream channels separately and use the same model IDs. The script
enables the public pricing navigation item and configures input, output, and
cached-input rates. Models with context-based pricing tiers use the lowest tier
because standard New API ratios do not vary by context length.

## Upstream Channel Template

Fill these values in `.env.dev` (or `.env.production`) and keep
`UPSTREAM_API_KEY` in the matching `<base>.local` override:

```dotenv
UPSTREAM_CHANNEL_NAME=My Provider
UPSTREAM_MODEL_NAMES=model-one,model-two
UPSTREAM_BASE_URL=https://provider.example.com
UPSTREAM_API_KEY=replace_me
```

Then create or update the OpenAI-compatible New API channel:

```bash
./scripts/sync-model-channel.sh .env.dev
```

For production, run the same script with `.env.production` on the production
server. The API key stays in the ignored `.env.production.local` override.

## Data

Persistent data is stored under:

- `data/mysql`
- `data/redis`
- `data/new-api`

Back up this directory before upgrading or moving the service.

## Environment

Edit `.env.dev` locally or `.env.production` on Oracle for non-secret settings; put passwords, tokens, and keys in the matching `.env.*.local` override.

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

If you prefer explicit proxy image names instead, edit these variables in `.env.dev`:

```bash
NEW_API_IMAGE=docker.m.daocloud.io/calciumion/new-api:latest
MYSQL_IMAGE=docker.m.daocloud.io/mysql:8.4
REDIS_IMAGE=docker.m.daocloud.io/redis:7-alpine
```
