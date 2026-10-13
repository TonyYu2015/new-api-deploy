# Production Rollout Register

Last updated: 2026-10-12

Latest environment verification: 2026-10-12 (staging upgraded to
`rc43-ccai.1`). Production was not re-queried, so its row below is the latest
recorded production state rather than a fresh runtime check.

This file is the source of truth for changes validated in staging that must
later be promoted to production. Update the status and verification notes for
every production rollout.

Daily progress and next-day planning belong in [`WORKLOG.md`](../WORKLOG.md);
this register only tracks deployment state, promotion decisions, and rollback
evidence.

## Environment Baseline

| Environment | URL | New API image | Verified |
|---|---|---|---|
| Production | https://www.ccaiservice.com | `ccai/new-api:rc15-ccai.4` (`sha256:30aa44e51a97dc9e76ae5e2ec64612197f520adc6272ebc1dc82bd0ad4624a1e`) | 2026-07-02 |
| Staging | https://test.ccaiservice.com | `ccai/new-api:rc43-ccai.1` (`sha256:c4d4b130c5d70d1eb298a8393d306956a61d7aa96571165ea97e44910301bb33`) | 2026-10-12 |

Do not replace either digest with `latest`. A version change must be tested in
staging and recorded here before production is changed.

## UI Release Changes

All entries below were deployed to production on 2026-07-02.

| ID | Page | Required behavior | Staging | Production |
|---|---|---|---|---|
| UI-WALLET-001 | `/wallet` | Hide the preset amount heading and all preset amount buttons; retain Custom Amount | Deployed | Applied |
| UI-WALLET-002 | `/wallet` | Hide the Redemption Code section | Deployed | Applied |
| UI-WALLET-003 | `/wallet` | Hide the Referral Program card | Deployed | Applied |
| UI-WALLET-004 | `/wallet` | Allow Custom Amount to be cleared completely without restoring `1` or displaying `0` | Deployed | Applied |
| UI-PROFILE-001 | `/profile` | Hide Current Balance, Total Usage, and API Requests because they duplicate Wallet/Dashboard | Deployed | Applied |
| UI-PROFILE-002 | `/profile` | Hide Sidebar Personal Settings | Deployed | Applied |
| UI-PROFILE-003 | `/profile` | Hide Access Token; users should use API Keys instead | Deployed | Applied |
| UI-PROFILE-004 | `/profile` | Hide Webhook, Bark, and Gotify notification methods; retain Email | Deployed | Applied |
| UI-PROFILE-005 | `/profile` | Hide Receive Upstream Model Update Notifications | Deployed | Applied |
| UI-PROFILE-006 | `/profile` | Hide Accept Unpriced Models | Deployed | Applied |
| UI-PROFILE-007 | `/profile` | Hide Record IP Address | Deployed | Applied |
| UI-PROFILE-008 | `/profile` | Hide Passkey Login | Deployed | Applied |
| UI-PROFILE-009 | `/profile` | Hide Two-Factor Authentication | Deployed | Applied |
| UI-PROFILE-010 | `/profile` | Reflow the remaining profile content to one responsive column | Deployed | Applied |
| UI-PROFILE-011 | `/profile` | Hide the Check-in Calendar card | Deployed | Applied |

Current staging implementation is built by `custom-new-api/Dockerfile` from
`custom-new-api/ccai.patch`, `custom-new-api/waffo-pancake-min-topup.patch`,
and `custom-new-api/pancake-balance-baseline.patch`.

The corresponding backend APIs and historical data are not deleted or
disabled.

## Already Applied

| ID | Change | Staging | Production |
|---|---|---|---|
| INFRA-001 | Use versioned New API images and record the verified image ID | Applied | Applied |
| AUTH-001 | Require email verification for registration | Applied | Applied |
| PAYMENT-001 | Disable Creem checkout | Applied | Applied |
| PAYMENT-002 | Keep Pancake test and production return URLs environment-specific | Applied | Applied |
| PAYMENT-003 | Display `Credit Card (Minimum USD 10)` on the production payment method | Not applicable | Applied |
| PAYMENT-004 | Pass the configured Pancake SuccessURL on every wallet and subscription checkout session | Applied | Applied |
| PAYMENT-005 | Refresh Wallet balance automatically after returning from Pancake checkout | Applied | Applied |
| PAYMENT-006 | Continue refreshing Wallet every 2 seconds until the credited balance is observed | Applied | Applied |

Payment credentials, webhook URLs, API keys, SMTP secrets, and database
contents must never be copied from staging to production as part of a UI
rollout.

## Validated in Staging, Pending Production

| ID | Change | Staging | Production |
|---|---|---|---|
| PAYMENT-007 | Persist the checkout-time quota baseline across the hosted payment redirect so Wallet does not mistake a stale cached balance refresh for the current credit | Validated on `ccai.8` | Pending |
| PLATFORM-001 | Upgrade New API from `rc.15` to `rc.43`: rebase the four custom patches onto upstream `c6741c36`, rebuild `custom-new-api/Dockerfile` for the merged single-frontend (rsbuild) layout and the `relaykit` / `tokenkit` submodules | Validated on `rc43-ccai.1` | Pending |

`PAYMENT-007` passed a complete staging sandbox payment on 2026-07-23. The
order moved from `pending` to `success`, quota increased by 5,000,000, Wallet
displayed `$150`, and both `payment_return` and the stored baseline were
cleared. This validation does not authorize or imply a production deployment.

`PLATFORM-001` was deployed to staging on 2026-10-12 with a verified
pre-upgrade database backup. The rc.43 schema migration is forward-only, so a
production promotion must back up the production database first, and any
rollback must restore that backup before running an older image.

## Production Rollout Procedure

1. Back up the production database and `nginx/conf.d/default.conf`.
2. Confirm production is still running the pinned production image digest.
3. Build `custom-new-api/Dockerfile` from the reviewed upstream commit and
   verify the resulting image ID.
4. Set production `NEW_API_IMAGE` to the reviewed custom image.
5. Recreate only the New API application container; do not restart MySQL.
6. Verify `/wallet` and `/profile` with a normal production user.
7. Confirm `/api/status`, model relay, login, email verification, and Pancake
   checkout still work.
8. Mark every promoted row as `Applied` and record the rollout date below.

## Acceptance Checklist

- Wallet shows only Custom Amount and the enabled payment method.
- Wallet does not show preset amounts, Redemption Code, or Referral Program.
- Profile does not duplicate balance or usage statistics.
- Profile keeps account identity, Email, language, password, and Delete Account.
- API Keys remains available and functional.
- Mobile and desktop layouts contain no empty columns or visible gaps.
- Production payment and webhook configuration is unchanged.
- Pancake return handling waits for quota to exceed the checkout-time baseline
  before clearing `payment_return`.

Automated coverage for these checks lives in `ui-tests/`. Run both desktop and
mobile Playwright projects against staging before promoting any pending row.

## Staging Validation

### 2026-10-12: rc43-ccai.1

- Staging `/api/status` reported `v1.0.0-rc.43-ccai.1` on both the internal
  port and the public hostname.
- The staging image ID was
  `sha256:c4d4b130c5d70d1eb298a8393d306956a61d7aa96571165ea97e44910301bb33`.
- Pre-upgrade database backup:
  `/opt/new-api-deploy/backups/staging-rc15-db-20261012-134549.sql.gz`
  (752 KB, gzip verified, 29 tables). The rc.43 migration is forward-only, so
  rolling the image back alone is not sufficient.
- `new-api`, `mysql` and `redis` were recreated with the existing data volumes
  preserved; the proxy tier (`html-filter`, `nginx`) was recreated to clear a
  stale upstream DNS cache that returned 502 after the app IP changed.
- Row counts after migration: users=12, channels=5, tokens=1, top_ups=19,
  options=72. The homepage returned HTTP 200 and the application log had no
  `fatal`, `panic` or `error` entries.
- Comprehensive desktop and mobile UI regression, model relay and Pancake
  payment re-validation remain pending on this build.

### 2026-07-23: ccai.8

- Staging `/api/status` reported `v1.0.0-rc.15-ccai.8`.
- The staging image ID was
  `sha256:877cf60757072a3f69f04b1d7941c8aa38c15eb9d2dc143e9e3efa0b946cc8f1`.
- Pancake preflight confirmed the sandbox configuration, `/test` webhook,
  minimum amount 10, staging return host, and disabled legacy Creem checkout.
- A complete minimum-amount sandbox payment passed: webhook verification,
  order settlement, quota credit, Wallet balance refresh, and return marker
  cleanup were all verified.
- Strict local model validation passed 7/7 configured models across 5 enabled
  channels, with 7 exact consumption-log matches and 828 quota reconciled.
- Comprehensive desktop and mobile UI regression remains pending; the
  Pancake return path received targeted desktop validation.
- Pancake webhook receive logs may contain a complete signature and request
  body. Log redaction is a recorded follow-up before final rollout.

### 2026-07-02: ccai.1

Validated on 2026-07-02 with the Tony staging account:

- Custom image and both frontend variants built successfully.
- Public `/api/status` reports `v1.0.0-rc.15-ccai.1`.
- Desktop and mobile Profile and Wallet functional assertions passed.
- One public desktop Wallet navigation timed out on its first attempt; the
  configured network retry passed in 8 seconds. No functional assertion failed.
- Visual snapshot tests remain opt-in and were skipped.

## Rollback

Before any production promotion, capture and verify the actual running image
and database backup. The latest recorded production fallback is
`ccai/new-api:rc15-ccai.4` at the digest shown in the environment baseline.
Recreate only the `new-api` application container unless the reviewed rollout
explicitly requires another component.

For staging `ccai.8`, the previous `ccai.7` image
`sha256:910e1bfc2107e8a727aeddf1b0db7f525cf25ace5dac198f661bd1273996d681`
and the deployment backup at
`/opt/new-api-deploy/backups/ccai8-deploy-20260723-stage3` were retained.

For the 2026-10-12 staging upgrade to `rc43-ccai.1`, the previous
`ccai/new-api:rc15-ccai.8`
(`sha256:877cf60757072a3f69f04b1d7941c8aa38c15eb9d2dc143e9e3efa0b946cc8f1`)
image remains on the host. Because the rc.43 schema migration is forward-only,
a rollback must first restore
`/opt/new-api-deploy/backups/staging-rc15-db-20261012-134549.sql.gz`.

## Rollout History

| Date | IDs | Result | Notes |
|---|---|---|---|
| 2026-07-02 | UI-WALLET-001..004, UI-PROFILE-001..011 | Applied | Direct production overwrite requested; no backup created. See `config/releases/2026-07-02-ccai-ui-source.md`. |
| 2026-07-02 | PAYMENT-004 | Applied | Checkout-level SuccessURL fix deployed as ccai.2. See `config/releases/2026-07-02-pancake-return-url.md`. |
| 2026-07-02 | PAYMENT-005 | Applied | Wallet post-payment balance refresh deployed as ccai.3. See `config/releases/2026-07-02-pancake-balance-refresh.md`. |
| 2026-07-02 | PAYMENT-006 | Applied | Removed the 30-second polling limit in ccai.4. See `config/releases/2026-07-02-pancake-wait-until-credited.md`. |
| 2026-07-23 | PAYMENT-007 | Staging validated | Complete Pancake sandbox payment and Wallet return verification passed on ccai.8; production remains pending. |
| 2026-10-12 | PLATFORM-001 | Staging validated | Upgraded staging to `rc43-ccai.1` after a verified pre-upgrade database backup; production remains on `rc15-ccai.4`. |
