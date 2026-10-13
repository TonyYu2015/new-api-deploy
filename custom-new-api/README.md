# CCAI New API Image

This image applies CCAI product decisions on top of an exact upstream
`QuantumNous/new-api` commit. The commit and the version suffix are pinned in
`Dockerfile`; the single rsbuild frontend is built first and embedded into the
Go binary.

The patches are applied in the order listed below and must be rebased on every
upstream upgrade. `Dockerfile` runs `git apply --check` before `git apply`, so
a patch that no longer applies fails the build.

## 1. `ccai.patch` — branding, streamlined console, Pancake return URL

Backend (3 files, +3 lines):

- `service/waffo_pancake.go` adds `ReturnURL` to the checkout-session params and
  forwards it as the Pancake `SuccessURL`.
- `controller/topup_waffo_pancake.go` and
  `controller/subscription_payment_waffo_pancake.go` pass
  `setting.WaffoPancakeReturnURL`, so both wallet top-ups and subscription
  payments return to the configured page.

Frontend:

- `web/index.html` — document title and meta title become `CCAI Service`.
- `web/src/features/home/` — the upstream marketing landing
  (`Stats` / `Features` / `HowItWorks` / `CTA` / `Footer`) is replaced by the
  CCAI hero. The upstream **Custom Home Page** feature (admin-configured URL /
  HTML / Markdown, with iframe theme and language sync) is preserved and still
  takes precedence when content is configured.
- `web/src/components/layout/components/public-layout.tsx` renders one public
  footer for every public page (home, pricing, legal documents): the
  operator-configured `footer_html` (System Settings → Site → Footer) plus the
  upstream `LegalLinks` component — now exported from `footer.tsx` — which links
  the User Agreement and Privacy Policy when those documents are enabled. The
  CCAI home no longer renders its own footer, so both the configured footer
  content and the legal links stay reachable.
- `web/src/features/profile/` — single-column layout; hides the balance / usage
  / request header, sidebar personal settings, Access Token, non-email
  notification methods (Webhook / Bark / Gotify), upstream model update
  notifications, Accept Unpriced Models, Record IP Address, Passkey, 2FA and the
  check-in calendar.
- `web/src/features/wallet/` — hides preset amounts, the redemption-code section
  and the referral / affiliate card (the quota-transfer dialog is only reachable
  from that card, so it goes with it); keeps Custom Amount and the configured
  payment methods, and allows the amount to be cleared completely.

## 2. `waffo-pancake-min-topup.patch` — expose the Pancake minimum top-up

Adds `WaffoPancakeMinTopUp` to the billing types, defaults, section registry and
payment schema, and renders a `Minimum top-up (USD)` input in the Waffo Pancake
admin section. The backend support (option storage, `waffo_pancake_min_topup` in
`/api/user/topup/info`, and the amount check in `controller/topup_waffo_pancake.go`)
is upstream and unchanged; this patch only surfaces the field in the admin UI.

## 3. `pancake-balance-baseline.patch` — wait for the current credit

Stores the checkout-time quota in `sessionStorage` under
`waffo_pancake_quota_before_payment` before a Pancake payment and, after the
hosted redirect, keeps refreshing Wallet until quota exceeds that baseline before
clearing `payment_return`. Without it a stale cached balance could stop the
refresh before the credit arrived. Covered by `ui-tests/tests/wallet.spec.ts`.

## 4. `tiered-price-summary.patch` — show concrete tier prices

In the admin model-pricing list, expression-billed models now show the first
tier's `Input $x` / `Output $y` next to `Tiered pricing · N tiers` instead of the
tier count alone.

## Upstream conflicts

The patches are reviewed against the pinned upstream commit. Two patches used to
replace upstream behaviour; they were corrected so the upstream capability is
kept while the CCAI product decisions remain:

- `web/src/features/home/index.tsx` no longer drops the Custom Home Page branch.
  The CCAI hero is only the default shown when no custom home page content is
  configured.
- `web/src/components/layout/components/public-header.tsx` is left at the
  upstream implementation, so admin-configured dynamic navigation links keep
  precedence over any page-level `navLinks` prop.
- The public footer is no longer a CCAI-only replacement. `PublicLayout` owns
  the footer and reuses the upstream `LegalLinks` (`footer.tsx`), so the
  admin-configured `footer_html` and the User Agreement / Privacy Policy links
  stay on every public page instead of being dropped with the upstream `Footer`.

The following removals are intentional CCAI product decisions and were kept.
Their backend APIs, settings and stored data are untouched, so upstream features
can be re-enabled by dropping the corresponding patch hunks:

- Wallet: preset amounts, redemption codes, referral / affiliate card and the
  quota-transfer dialog.
- Profile: statistics header, Access Token, Webhook / Bark / Gotify notification
  methods, upstream model update notifications, Accept Unpriced Models, Record IP
  Address, Passkey, 2FA, sidebar personal settings, check-in calendar.
- Home: upstream marketing sections and the Hero docs button (the `docs_link`
  setting is still honoured by the navigation).

## Build

From the repository root:

```bash
docker build --file custom-new-api/Dockerfile --tag ccai/new-api:rc43-ccai.3 .
```

After staging validation, record the resulting immutable digest in
`config/production-rollout.md` before promoting it. The rc.43 database migration
is forward-only, so back up the target database before deploying a new image.
