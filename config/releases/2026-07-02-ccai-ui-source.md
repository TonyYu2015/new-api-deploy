# Production Release: CCAI UI Source Image

Release date: 2026-07-02

## Deployment

- Production URL: `https://www.ccaiservice.com`
- Previous version: `v1.0.0-rc.13`
- Previous image:
  `calciumion/new-api@sha256:8979ca863c28e7b0b00f5014e1bead6866ff0bc24d68597f23186fd1e6b3b913`
- Previous image ID:
  `sha256:635eed2055d514c6290c732522becb1b9d9d653c4afcd1f0915c5ebe9ff9d94c`
- New version: `v1.0.0-rc.15-ccai.1`
- New image: `ccai/new-api:rc15-ccai.1`
- New image ID:
  `sha256:fa7fe3cd4576bd55e26495c4b5b3524292b352eb658a40a0a362ad28feff33ba`
- Upstream repository: `QuantumNous/new-api`
- Upstream commit: `69b0f0b56f528efa292a2893feb0c55c37399f4b`
- Production was upgraded from upstream rc.13 to rc.15 as part of this release.
- The user explicitly requested a direct overwrite without a database or
  configuration backup.

Only `.env.production` key `NEW_API_IMAGE` was changed. The `new-api`
application container was recreated. MySQL, Redis, Caddy, and Nginx were not
restarted.

## Source Artifacts

| Artifact | SHA-256 |
|---|---|
| `custom-new-api/Dockerfile` | `f2b6668737fda5e5097dd3d5f016072f99cd9b47e57a4aa5edfa46d4252dac82` |
| `custom-new-api/ccai.patch` | `59250ba1ed217eb06f12181aaaed3f14f087baaf78e2c73373d55571709c71f9` |
| `nginx/staging-conf.d/default.conf` | `2e039fff3f6d895a7085590271866a4683f2039e15d10fdc39535b9f16b64e6e` |
| `ui-tests/playwright.config.ts` | `4d30b5b2bb28ee8827924f511699a6fc492e3a9c240f25c23ccbbf989e25f3b3` |

The source patch changes these upstream files:

- `web/default/src/features/wallet/index.tsx`
- `web/default/src/features/wallet/components/recharge-form-card.tsx`
- `web/default/src/features/profile/index.tsx`
- `web/default/src/features/profile/components/profile-header.tsx`
- `web/default/src/features/profile/components/profile-security-card.tsx`
- `web/default/src/features/profile/components/tabs/notification-tab.tsx`

## User-visible Changes

- Wallet preset amount heading and buttons removed.
- Wallet retains Custom Amount and configured payment methods.
- Custom Amount can be cleared without restoring `1` or showing `0`.
- Redemption Code and Referral Program removed from Wallet.
- Profile balance, usage, and request statistics removed.
- Profile sidebar configuration, check-in, Passkey, and 2FA cards removed.
- Profile Access Token action removed; API Keys remains available.
- Profile notification UI retains only Email and quota threshold.
- Webhook, Bark, Gotify, upstream model notifications, unpriced model
  acceptance, and IP recording controls removed.
- Profile content uses a single responsive column.

The hidden backend APIs and existing historical data were not deleted.
Saving notification settings sets the notification method to Email while
retaining the hidden stored field values.

## Explicitly Unchanged

- Production payment credentials, webhook secrets, and return URLs.
- Pancake configuration and minimum recharge configuration.
- Model channels, model pricing, API keys, and upstream credentials.
- SMTP settings and email verification requirement.
- Legal pages and footer contact information.
- Production MySQL and Redis data.

## Verification

- `/api/status`: HTTP 200, version `v1.0.0-rc.15-ccai.1`.
- Production frontend references `index.24f655bf0d.js`.
- Legacy `ccai-ui.js` runtime injection is absent.
- Production Tony account ID 2 remained active; password and token were not
  reset.
- `/api/user/self`: HTTP 200 with Tony's existing token.
- `/api/user/topup/info`: HTTP 200 with Tony's existing token.
- Desktop and mobile Wallet/Profile functional Playwright assertions passed.
- One desktop Profile initial navigation timed out; the configured retry
  passed. No functional assertion failed.
- Visual snapshot tests were opt-in and skipped.

## Rollback

The previous image remains identified above. To roll back the application:

```bash
cd /opt/new-api-deploy
sed -i \
  's|^NEW_API_IMAGE=.*|NEW_API_IMAGE=calciumion/new-api@sha256:8979ca863c28e7b0b00f5014e1bead6866ff0bc24d68597f23186fd1e6b3b913|' \
  .env.production
sudo docker compose --env-file .env.production up -d --no-deps new-api
```

No database backup exists for this release. The rc.15 application ran its
normal database migration at startup, so an application-only rollback does
not reverse schema changes.
