# CCAI New API Image

This image is built from the exact upstream commit recorded in `Dockerfile`.
`ccai.patch` contains the CCAI-specific Wallet and Profile changes.
`pancake-balance-baseline.patch` keeps the checkout-time quota baseline across
the hosted payment redirect so Wallet waits for the current credit.

Build from the repository root:

```bash
docker build -f custom-new-api/Dockerfile -t ccai/new-api:rc15-ccai.8 .
```

After validation, record the resulting immutable digest in
`config/production-rollout.md` before promoting it.
