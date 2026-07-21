# CCAI UI Tests

Playwright tests for the deployed staging UI. The suite refuses to target any
host other than `test.ccaiservice.com` unless explicitly overridden.

## Setup

```bash
cd ui-tests
npm install
npm run install:browsers
cp .env.e2e.example .env.e2e
```

Use a staging-only access token in `.env.e2e`. This preserves the account
password and does not test the sign-in flow. Export the settings before
running:

```bash
set -a
. ./.env.e2e
set +a
npm test
```

Do not use a production administrator account or production access token. The
test account needs access to Wallet and Profile but should not have production
payment credentials. Username/password login remains available as an optional
fallback.

## Commands

```bash
npm test
npm run test:desktop
npm run test:mobile
npm run test:visual:update
npm run test:visual
```

Review generated visual baselines before committing them. Functional tests do
not initiate payment or modify security settings.

For origin-only diagnostics, tunnel the staging HTTP port and use:

```bash
ssh -N -L 8080:127.0.0.1:3002 oracle
E2E_BASE_URL=http://127.0.0.1:8080 E2E_ALLOW_PRODUCTION=true npm test
```
