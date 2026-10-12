# Production Release: Wait Until Credited

Release date: 2026-07-02

## Change

The previous post-payment Wallet behavior stopped checking the balance after
15 attempts (about 30 seconds). The polling limit was removed at the user's
request.

When `payment_return=pancake` is present, Wallet now:

- refreshes the user balance immediately;
- retries every 2 seconds while the credited quota is unchanged;
- continues without a time limit while the user remains on the page;
- stops and removes the URL marker only after quota changes;
- stops requests when the user leaves or unmounts the Wallet page.

Transient API failures do not end the wait; the next request is still
scheduled.

## Deployment

- Previous image: `ccai/new-api:rc15-ccai.3`
- Previous image ID:
  `sha256:4fd78027ba29c760469a738fbe42e44d38c764292f8909cb83325d69110aaff9`
- New image: `ccai/new-api:rc15-ccai.4`
- New image ID:
  `sha256:30aa44e51a97dc9e76ae5e2ec64612197f520adc6272ebc1dc82bd0ad4624a1e`
- `custom-new-api/Dockerfile` SHA-256:
  `ff8f787b01842765d74e9ca4fa16400ef4842fdaa15be5f584dedc242df0c12a`
- `custom-new-api/ccai.patch` SHA-256:
  `c7f56715744675754211244f7f1eaf864ad36d34702d59c6e25dc205b63fe0e7`
- Wallet test SHA-256:
  `acaea23391386dc6e59b8efba4585ddabe0ba55120aa9a5705a56d9347f8c5fd`

MySQL and Redis were not restarted. The production application container was
recreated directly without a backup.

## Verification

- Staging version reports `v1.0.0-rc.15-ccai.4`.
- The staging browser test confirmed polling was still active after 31 seconds,
  beyond the removed legacy limit.
- Production version reports `v1.0.0-rc.15-ccai.4`.
- No payment was initiated by the polling test.

## Next Session

Continue on 2026-07-03 with a real staging payment:

1. Complete a Pancake test payment and return to `/wallet`.
2. Confirm the page keeps polling while the order is pending.
3. Confirm the displayed balance updates without a manual refresh after the
   webhook credits the account.
4. Confirm polling stops and `payment_return=pancake` is removed from the URL.
5. If crediting does not occur, compare the Pancake order status, webhook
   delivery response, and the matching New API top-up record before changing
   the frontend again.

## 2026-07-03 Follow-up

- Confirmed the hosted checkout displays `Test Mode` and states that no real
  payment will be processed.
- Completed Waffo sandbox Visa success simulations for USD 10.
- Confirmed the matching staging `top_ups` rows changed from `pending` to
  `success`; one observed webhook completion took 17 seconds.
- Re-ran the Wallet return polling test after removing its redundant initial
  navigation. It passed in 39.6 seconds and continued beyond the old 30-second
  limit.
- Restricted Playwright API authorization injection to the configured staging
  origin. The previous broad `**/api/**` route could attach the staging token
  to matching third-party checkout requests.
- Waffo's sandbox `Quick Fill` control was intermittent under headless
  automation. Payment success and webhook crediting were verified, but the
  final `Done` click and return URL cleanup still require one manual browser
  confirmation.

Before the next authenticated browser run, rotate the staging E2E access token
and update `ui-tests/.env.e2e`.

## Rollback

```bash
cd /opt/new-api-deploy
sed -i \
  's|^NEW_API_IMAGE=.*|NEW_API_IMAGE=ccai/new-api:rc15-ccai.3|' \
  .env.production
sudo docker compose --env-file .env.production up -d --no-deps new-api
```
