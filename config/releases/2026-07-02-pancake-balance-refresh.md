# Production Release: Pancake Balance Refresh

Release date: 2026-07-02

## Incident

After Pancake redirected a user back to Wallet, the displayed balance remained
stale until the browser was manually refreshed.

## Root Cause

The return page fetched the user balance before the asynchronous Pancake
webhook finished crediting the order. Wallet performed only its normal
one-time user fetch, so the later database update was not reflected in the
already-rendered page.

## Fix

- Pancake SuccessURL now includes `payment_return=pancake`.
- Wallet detects that marker after navigation.
- Wallet refreshes the user balance immediately.
- If the balance is still unchanged, Wallet retries every 2 seconds.
- Polling stops when quota changes or after 15 attempts (about 30 seconds).
- The marker is removed from the browser URL when polling finishes.

Configured URLs:

- Production:
  `https://www.ccaiservice.com/wallet?payment_return=pancake`
- Staging:
  `https://test.ccaiservice.com/wallet?payment_return=pancake`

Only checkout sessions created with the updated SuccessURL carry the marker.

## Deployment

- Previous image: `ccai/new-api:rc15-ccai.2`
- Previous image ID:
  `sha256:c178c06729be6360d405b08db4789a8d9d0356ad1b3e280d9803434f49510777`
- New image: `ccai/new-api:rc15-ccai.3`
- New image ID:
  `sha256:4fd78027ba29c760469a738fbe42e44d38c764292f8909cb83325d69110aaff9`
- `custom-new-api/Dockerfile` SHA-256:
  `2a75e0235448b8f02cb6b4e46ffb6997a87441c59e202c8cc45f20ac2cf6ff30`
- `custom-new-api/ccai.patch` SHA-256:
  `cf936228d152e8ed01708fe2dc69262bfc995bf424a23e2c07f7bfde1c2aabbc`
- Wallet test SHA-256:
  `6f5c5d777ab888c7236bf90ecf33b48fdbc433fc2dbb3a94330d8d6c30c1a971`

MySQL and Redis were not restarted. The production application container was
recreated directly without a backup, following the user's standing deployment
instruction.

## Verification

- Staging version reports `v1.0.0-rc.15-ccai.3`.
- Staging Playwright test confirmed a Pancake return triggers another balance
  request when quota has not changed.
- Production version reports `v1.0.0-rc.15-ccai.3`.
- Production Playwright test confirmed either an immediate quota refresh
  clears the marker or polling continues.
- No payment was initiated by the balance-refresh tests.

## Rollback

```bash
cd /opt/new-api-deploy
sed -i \
  's|^NEW_API_IMAGE=.*|NEW_API_IMAGE=ccai/new-api:rc15-ccai.2|' \
  .env.production
sudo docker compose --env-file .env.production up -d --no-deps new-api
```
