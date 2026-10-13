# Production Rollout Register

Last updated: 2026-10-13

Latest environment verification: 2026-10-13. Both staging and production were
queried on that date; both report `v1.0.0-rc.43-ccai.2`.

This file is the source of truth for changes validated in staging that must
later be promoted to production. Update the status and verification notes for
every production rollout.

Daily progress and next-day planning belong in [`WORKLOG.md`](../WORKLOG.md);
this register only tracks deployment state, promotion decisions, and rollback
evidence.

## Environment Baseline

| Environment | URL | New API image | Verified |
|---|---|---|---|
| Production | https://www.ccaiservice.com | `ccai/new-api:rc43-ccai.2` (`sha256:586d942b5e5d2e90a3990efc260302c909c06d5887c5fcce921bab42c2d02ca2`) | 2026-10-13 |
| Staging | https://test.ccaiservice.com | `ccai/new-api:rc43-ccai.2` (`sha256:586d942b5e5d2e90a3990efc260302c909c06d5887c5fcce921bab42c2d02ca2`) | 2026-10-13 |

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
| PAYMENT-003 | Display `Credit Card (Minimum USD 10)` on the production payment method | Not applicable | Reverted 2026-10-13 (see PAYMENT-008) |
| PAYMENT-004 | Pass the configured Pancake SuccessURL on every wallet and subscription checkout session | Applied | Applied |
| PAYMENT-005 | Refresh Wallet balance automatically after returning from Pancake checkout | Applied | Applied |
| PAYMENT-006 | Continue refreshing Wallet every 2 seconds until the credited balance is observed | Applied | Applied |
| PAYMENT-008 | Show the production Wallet payment method as `Waffo Pancake` instead of the production-only label `Credit Card (Minimum USD 10)` | Not applicable | Applied 2026-10-13 |

Payment credentials, webhook URLs, API keys, SMTP secrets, and database
contents must never be copied from staging to production as part of a UI
rollout.

`PAYMENT-008` reverts the production-only `PayMethods` label set by
`PAYMENT-003`. The Wallet renders one button per `pay_methods` entry using its
configured `name`, and `controller/topup.go` only appends the built-in
`Waffo Pancake` entry when `PayMethods` has no `waffo_pancake` entry of its own.
Staging and dev keep `PayMethods` empty, so they showed `Waffo Pancake` while
production showed the customized label. Production now uses
`[{"name":"Waffo Pancake","type":"waffo_pancake","color":"#F97316","min_topup":"10"}]`,
which renders identically to staging (default Waffo logo, same minimum). The
previous value is backed up at
`/opt/new-api-deploy/backups/prod-paymethods-20261013.txt`; no payment
credential, webhook, or checkout behaviour changed.

## Promoted to Production

| ID | Change | Staging | Production |
|---|---|---|---|
| PAYMENT-007 | Persist the checkout-time quota baseline across the hosted payment redirect so Wallet does not mistake a stale cached balance refresh for the current credit | Validated on `ccai.8` | Applied 2026-10-13 |
| PLATFORM-001 | Upgrade New API from `rc.15` to `rc.43`: rebase the four custom patches onto upstream `c6741c36`, rebuild `custom-new-api/Dockerfile` for the merged single-frontend (rsbuild) layout and the `relaykit` / `tokenkit` submodules | Validated on `rc43-ccai.1`, re-validated on `rc43-ccai.2` | Applied 2026-10-13 |

`PAYMENT-007` passed a complete staging sandbox payment on 2026-07-23. The
order moved from `pending` to `success`, quota increased by 5,000,000, Wallet
displayed `$150`, and both `payment_return` and the stored baseline were
cleared. It is included in the `rc43-ccai.2` image promoted on 2026-10-13; a
production Pancake payment has not been repeated on the new build.

`PLATFORM-001` was deployed to staging on 2026-10-12, re-validated as
`rc43-ccai.2` on 2026-10-13, and promoted to production on 2026-10-13 after a
verified production database backup. The rc.43 schema migration is
forward-only, so any rollback must restore that backup before running an older
image.

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

### 2026-10-13: rc43-ccai.2

- Conflict review of the custom patches against upstream rc.43 restored two
  upstream capabilities that the patches had replaced:
  the admin-configurable **Custom Home Page** branch in
  `web/src/features/home/index.tsx`, and the upstream implementation of
  `web/src/components/layout/components/public-header.tsx`, so
  admin-configured dynamic navigation links keep precedence.
- All four patches are documented in `custom-new-api/README.md`.
- Staging `/api/status` reported `v1.0.0-rc.43-ccai.2` on both the internal
  port and the public hostname; the homepage returned HTTP 200 and the served
  bundle contains the restored Custom Home Page branch.
- The staging image ID was
  `sha256:586d942b5e5d2e90a3990efc260302c909c06d5887c5fcce921bab42c2d02ca2`.
- Pre-deploy database backup:
  `/opt/new-api-deploy/backups/staging-ccai1-db-20261013-030946.sql.gz`
  (765 KB, gzip verified).
- The deploy recreated the proxy tier (`html-filter`, `nginx`) after the app
  container, as intended by the deploy-script fix; no 502 was observed.
- Row counts after deploy: users=13, channels=5, tokens=1, top_ups=20,
  options=75. No `fatal`, `panic` or `error` entries in the application log.
- Comprehensive desktop and mobile UI regression, model relay and Pancake
  payment re-validation remain pending on this build.

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

## Production Validation

### 2026-10-13: production rc43-ccai.2

- Promoted `ccai/new-api:rc43-ccai.2` to production (previously `rc15-ccai.4`)
  after backing up the production database and `nginx/conf.d/default.conf`.
- Pre-rollout database backup:
  `/opt/new-api-deploy/backups/prod-rc15-db-20261013-032305.sql.gz`
  (821 KB, gzip verified, 29 tables).
- `new-api` was recreated with the new image and restarted by the
  gateway-safeguards step; `mysql` and `redis` were recreated with their
  existing data volumes preserved. The proxy tier (`html-filter`, `nginx`) was
  recreated to clear cached upstream DNS.
- Public `/api/status` and the internal listener both reported
  `v1.0.0-rc.43-ccai.2`; the homepage returned HTTP 200.
- The startup log showed `database migration started` and
  `New API v1.0.0-rc.43-ccai.2 started`, with no `fatal`, `panic` or `error`
  entries.
- Data after migration: users=54, channels=5, tokens=27, top_ups=9,
  logs=12383, options=71; the `abilities` routing table kept 10 models.
- Registration, email verification and password-login flags were unchanged.
- Not yet repeated on this build: a real production model call, a production
  Pancake payment, and manual Wallet / Profile UI review.

## Rollback

Before any production promotion, capture and verify the actual running image
and database backup. The current production fallback is
`ccai/new-api:rc15-ccai.4`
(`sha256:30aa44e51a97dc9e76ae5e2ec64612197f520adc6272ebc1dc82bd0ad4624a1e`),
which is still present on the host. Because the rc.43 schema migration is
forward-only, a rollback must first restore
`/opt/new-api-deploy/backups/prod-rc15-db-20261013-032305.sql.gz`; running the
older image against the migrated schema is not supported.

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
| 2026-10-13 | PLATFORM-001 | Staging validated | Rebuilt as `rc43-ccai.2` after restoring the upstream Custom Home Page and navigation behaviour; staging re-verified. |
| 2026-10-13 | PLATFORM-001 | Applied | Promoted `rc43-ccai.2` to production after a verified database backup; production had been `rc15-ccai.4`. |
| 2026-10-13 | PAYMENT-007 | Applied | Included in the production `rc43-ccai.2` rollout; a production payment was not re-run on this build. |
| 2026-10-13 | PAYMENT-003, PAYMENT-008 | Applied | Reverted the production-only payment-method label so production matches staging and dev; previous value backed up under `/opt/new-api-deploy/backups/`. |
