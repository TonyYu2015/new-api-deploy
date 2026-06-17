import json
import os
import time
import uuid
from decimal import Decimal, ROUND_HALF_UP
from typing import Any

import pymysql
import stripe
from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from pydantic import BaseModel, Field


MYSQL_HOST = os.getenv("MYSQL_HOST", "mysql")
MYSQL_PORT = int(os.getenv("MYSQL_PORT", "3306"))
MYSQL_DATABASE = os.getenv("MYSQL_DATABASE", "new_api")
MYSQL_USER = os.getenv("MYSQL_USER", "new_api")
MYSQL_PASSWORD = os.getenv("MYSQL_PASSWORD", "")

STRIPE_SECRET_KEY = os.getenv("STRIPE_SECRET_KEY", "")
STRIPE_WEBHOOK_SECRET = os.getenv("STRIPE_WEBHOOK_SECRET", "")
STRIPE_CURRENCY = os.getenv("STRIPE_CURRENCY", "usd").lower()
STRIPE_SUCCESS_URL = os.getenv("STRIPE_SUCCESS_URL", "http://localhost:3001/stripe/success")
STRIPE_CANCEL_URL = os.getenv("STRIPE_CANCEL_URL", "http://localhost:3001/stripe/cancel")

TOPUP_QUOTA_PER_USD = Decimal(os.getenv("TOPUP_QUOTA_PER_USD", "500000"))
TOPUP_MIN_USD = Decimal(os.getenv("TOPUP_MIN_USD", "5"))
TOPUP_MAX_USD = Decimal(os.getenv("TOPUP_MAX_USD", "500"))
TOPUP_ALLOWED_AMOUNTS = {
    Decimal(item.strip())
    for item in os.getenv("TOPUP_ALLOWED_AMOUNTS", "5,10,20,50,100").split(",")
    if item.strip()
}

stripe.api_key = STRIPE_SECRET_KEY
app = FastAPI(title="New API Stripe Top-up")


class CheckoutRequest(BaseModel):
    amount_usd: Decimal = Field(gt=0)


def db():
    return pymysql.connect(
        host=MYSQL_HOST,
        port=MYSQL_PORT,
        user=MYSQL_USER,
        password=MYSQL_PASSWORD,
        database=MYSQL_DATABASE,
        charset="utf8mb4",
        autocommit=False,
        cursorclass=pymysql.cursors.DictCursor,
    )


def now_ts() -> int:
    return int(time.time())


def quota_for_usd(amount_usd: Decimal) -> int:
    return int((amount_usd * TOPUP_QUOTA_PER_USD).to_integral_value(rounding=ROUND_HALF_UP))


def cents_for_usd(amount_usd: Decimal) -> int:
    return int((amount_usd * Decimal("100")).to_integral_value(rounding=ROUND_HALF_UP))


def get_bearer_user(authorization: str | None) -> dict[str, Any]:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Missing Bearer token")
    token = authorization.split(None, 1)[1].strip()
    if not token:
        raise HTTPException(status_code=401, detail="Missing Bearer token")

    with db() as conn, conn.cursor() as cur:
        cur.execute(
            "select id, username, display_name, email, status from users where access_token=%s and deleted_at is null limit 1",
            (token,),
        )
        user = cur.fetchone()
    if not user or int(user.get("status") or 0) != 1:
        raise HTTPException(status_code=401, detail="Invalid or disabled token")
    return user


def validate_amount(amount_usd: Decimal) -> Decimal:
    amount = amount_usd.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    if amount < TOPUP_MIN_USD or amount > TOPUP_MAX_USD:
        raise HTTPException(status_code=400, detail=f"Amount must be between {TOPUP_MIN_USD} and {TOPUP_MAX_USD} USD")
    if TOPUP_ALLOWED_AMOUNTS and amount not in TOPUP_ALLOWED_AMOUNTS:
        allowed = ", ".join(str(x) for x in sorted(TOPUP_ALLOWED_AMOUNTS))
        raise HTTPException(status_code=400, detail=f"Amount must be one of: {allowed}")
    return amount


@app.get("/health")
def health():
    return {"ok": True}


@app.get("/", response_class=HTMLResponse)
def topup_page():
    amounts = "".join(
        f'<button type="button" data-amount="{amount}">${amount}</button>'
        for amount in sorted(TOPUP_ALLOWED_AMOUNTS)
    )
    return f"""<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Top up</title>
    <style>
      body {{ font-family: system-ui, sans-serif; max-width: 560px; margin: 48px auto; padding: 0 16px; }}
      input, button {{ font: inherit; padding: 10px 12px; margin: 6px 0; }}
      input {{ width: 100%; box-sizing: border-box; }}
      .amounts button {{ margin-right: 8px; }}
      #error {{ color: #b00020; }}
    </style>
  </head>
  <body>
    <h1>Top up balance</h1>
    <p>Paste your New API access token and choose a one-time top-up amount.</p>
    <label>Access token</label>
    <input id="token" type="password" autocomplete="off">
    <div class="amounts">{amounts}</div>
    <p id="error"></p>
    <script>
      async function checkout(amount) {{
        const token = document.getElementById('token').value.trim();
        if (!token) {{ document.getElementById('error').textContent = 'Access token is required.'; return; }}
        const res = await fetch('/stripe/api/checkout', {{
          method: 'POST',
          headers: {{ 'content-type': 'application/json', 'authorization': 'Bearer ' + token }},
          body: JSON.stringify({{ amount_usd: amount }})
        }});
        const data = await res.json();
        if (!res.ok) {{ document.getElementById('error').textContent = data.detail || 'Checkout failed.'; return; }}
        location.href = data.checkout_url;
      }}
      document.querySelectorAll('button[data-amount]').forEach((button) => {{
        button.addEventListener('click', () => checkout(button.dataset.amount));
      }});
    </script>
  </body>
</html>"""


@app.get("/success", response_class=HTMLResponse)
def success():
    return "<h1>Payment received</h1><p>Your balance will update shortly.</p>"


@app.get("/cancel", response_class=HTMLResponse)
def cancel():
    return "<h1>Payment canceled</h1><p>No charge was made.</p>"


@app.post("/api/checkout")
def create_checkout(payload: CheckoutRequest, authorization: str | None = Header(default=None)):
    if not STRIPE_SECRET_KEY:
        raise HTTPException(status_code=503, detail="Stripe is not configured")

    user = get_bearer_user(authorization)
    amount_usd = validate_amount(payload.amount_usd)
    quota_amount = quota_for_usd(amount_usd)
    trade_no = f"stripe_topup_{uuid.uuid4().hex}"

    with db() as conn, conn.cursor() as cur:
        cur.execute(
            """
            insert into top_ups
              (user_id, amount, money, trade_no, payment_method, payment_provider, create_time, status)
            values (%s, %s, %s, %s, 'checkout', 'stripe', %s, 'pending')
            """,
            (user["id"], quota_amount, float(amount_usd), trade_no, now_ts()),
        )
        conn.commit()

    session = stripe.checkout.Session.create(
        mode="payment",
        line_items=[
            {
                "price_data": {
                    "currency": STRIPE_CURRENCY,
                    "product_data": {"name": f"New API top-up ${amount_usd}"},
                    "unit_amount": cents_for_usd(amount_usd),
                },
                "quantity": 1,
            }
        ],
        success_url=STRIPE_SUCCESS_URL,
        cancel_url=STRIPE_CANCEL_URL,
        client_reference_id=trade_no,
        customer_email=user.get("email") or None,
        metadata={
            "trade_no": trade_no,
            "user_id": str(user["id"]),
            "quota_amount": str(quota_amount),
            "amount_usd": str(amount_usd),
        },
    )
    return {"checkout_url": session.url, "trade_no": trade_no, "quota_amount": quota_amount}


@app.post("/webhook")
async def webhook(request: Request, stripe_signature: str | None = Header(default=None)):
    if not STRIPE_WEBHOOK_SECRET:
        raise HTTPException(status_code=503, detail="Stripe webhook is not configured")

    body = await request.body()
    try:
        event = stripe.Webhook.construct_event(body, stripe_signature, STRIPE_WEBHOOK_SECRET)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    event_type = event.get("type")
    obj = event.get("data", {}).get("object", {})
    if event_type == "checkout.session.completed":
        metadata = obj.get("metadata") or {}
        trade_no = metadata.get("trade_no") or obj.get("client_reference_id")
        if trade_no:
            apply_topup(trade_no, obj)
    elif event_type in {"checkout.session.expired", "payment_intent.payment_failed"}:
        metadata = obj.get("metadata") or {}
        trade_no = metadata.get("trade_no") or obj.get("client_reference_id")
        if trade_no:
            mark_topup_failed(trade_no, obj)

    return {"received": True}


def apply_topup(trade_no: str, payload: dict[str, Any]) -> None:
    with db() as conn, conn.cursor() as cur:
        cur.execute("select * from top_ups where trade_no=%s for update", (trade_no,))
        topup = cur.fetchone()
        if not topup:
            conn.rollback()
            return
        if topup.get("status") == "success":
            conn.commit()
            return
        cur.execute("update users set quota = quota + %s where id=%s", (topup["amount"], topup["user_id"]))
        cur.execute(
            "update top_ups set status='success', complete_time=%s where trade_no=%s",
            (now_ts(), trade_no),
        )
        conn.commit()


def mark_topup_failed(trade_no: str, payload: dict[str, Any]) -> None:
    with db() as conn, conn.cursor() as cur:
        cur.execute(
            "update top_ups set status='failed', complete_time=%s where trade_no=%s and status <> 'success'",
            (now_ts(), trade_no),
        )
        conn.commit()

