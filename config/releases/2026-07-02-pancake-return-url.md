# Production Release: Pancake Return URL

Release date: 2026-07-02

## Incident

After a successful Waffo Pancake payment, the hosted checkout did not return
the user to CCAI Service.

## Root Cause

`WaffoPancakeReturnURL` was only used when a Pancake product was originally
created. Runtime checkout sessions did not include `successUrl`, so changing
the New API setting did not update an existing Pancake product and could not
control the redirect for new checkout sessions.

The locked official SDK version, `waffo-pancake-sdk-go v0.3.1`, supports
`CreateCheckoutSessionParams.SuccessURL`.

## Fix

- Added `ReturnURL` to `WaffoPancakeCreateSessionParams`.
- Mapped it to the SDK checkout request `SuccessURL`.
- Passed `WaffoPancakeReturnURL` for wallet top-up checkout sessions.
- Passed `WaffoPancakeReturnURL` for subscription checkout sessions.
- Changed production return URL to
  `https://www.ccaiservice.com/wallet`.
- Changed staging return URL to
  `https://test.ccaiservice.com/wallet`.

Only checkout sessions created after this release contain the corrected
SuccessURL. Existing sessions are unchanged.

## Deployment

- Previous image: `ccai/new-api:rc15-ccai.1`
- Previous image ID:
  `sha256:fa7fe3cd4576bd55e26495c4b5b3524292b352eb658a40a0a362ad28feff33ba`
- New image: `ccai/new-api:rc15-ccai.2`
- New image ID:
  `sha256:c178c06729be6360d405b08db4789a8d9d0356ad1b3e280d9803434f49510777`
- `custom-new-api/Dockerfile` SHA-256:
  `e26a4228b7c8d416493ebf1b80696941c79cbcc6ade96f987a92ba40c0ce5559`
- `custom-new-api/ccai.patch` SHA-256:
  `1a3cb828c83487c0ac67093b0368a47bb9df77bd4019ae1c9f215e8b3f69ca5f`

MySQL and Redis were not restarted. The production application container was
recreated directly without a backup, following the user's standing deployment
instruction.

## Verification

- Staging `/api/status`: `v1.0.0-rc.15-ccai.2`.
- Staging checkout session creation succeeded.
- Staging checkout URL opened on `pancake.waffo.ai`.
- Production `/api/status`: `v1.0.0-rc.15-ccai.2`.
- Production option `WaffoPancakeReturnURL` is
  `https://www.ccaiservice.com/wallet`.
- Production Pancake credentials, Store ID, and Product ID remain configured.
- Production webhook endpoint returned `401 invalid signature` for an unsigned
  probe, confirming the endpoint is enabled, reachable, and enforcing
  signature verification.

At verification time, the latest production USD 10 order was still `pending`.
Two earlier USD 1 orders were `success`. Redirect behavior and webhook-driven
credit settlement are separate: the SuccessURL fix does not mark a pending
order as paid.

## Rollback

```bash
cd /opt/new-api-deploy
sed -i \
  's|^NEW_API_IMAGE=.*|NEW_API_IMAGE=ccai/new-api:rc15-ccai.1|' \
  .env.production
sudo docker compose --env-file .env.production up -d --no-deps new-api
```
