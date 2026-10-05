"""Stripe subscriptions: Checkout to subscribe, the Billing Portal to manage or
cancel, and webhooks to keep each user's access in sync.

Docs: https://docs.stripe.com/billing/subscriptions/build-subscriptions
"""

from __future__ import annotations

import hashlib
import hmac
import json
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Callable

from .db import ACCESS_STATUSES, Database, User

API_BASE = "https://api.stripe.com/v1"
WEBHOOK_TOLERANCE = 300  # seconds
SUBSCRIPTION_EVENTS = {
    "customer.subscription.created",
    "customer.subscription.updated",
    "customer.subscription.deleted",
    "customer.subscription.paused",
    "customer.subscription.resumed",
}
CHECKOUT_EVENTS = {"checkout.session.completed", "checkout.session.async_payment_succeeded"}


class StripeError(Exception):
    pass


class WebhookError(Exception):
    pass


Transport = Callable[[str, str, dict[str, str], bytes | None], tuple[int, bytes]]


def _urllib_transport(method: str, url: str, headers: dict[str, str], body: bytes | None) -> tuple[int, bytes]:
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


class Stripe:
    def __init__(
        self, secret_key: str, price_id: str, transport: Transport | None = None, premium_price_id: str = ""
    ):
        self.secret_key = secret_key
        self.price_id = price_id
        self.premium_price_id = premium_price_id
        self.transport = transport or _urllib_transport

    def _request(self, method: str, path: str, params: list[tuple[str, str]] | None = None) -> dict:
        headers = {"Authorization": f"Bearer {self.secret_key}"}
        body = None
        url = f"{API_BASE}{path}"
        if method == "POST":
            body = urllib.parse.urlencode(params or []).encode()
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        elif params:
            url += "?" + urllib.parse.urlencode(params)
        try:
            status, raw = self.transport(method, url, headers, body)
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            raise StripeError(f"Couldn't reach Stripe: {e}") from e
        try:
            data = json.loads(raw.decode("utf-8") or "{}")
        except ValueError:
            data = {}
        if status >= 400:
            message = (data.get("error") or {}).get("message") or f"HTTP {status}"
            raise StripeError(f"Stripe {method} {path}: {message}")
        return data

    def create_checkout_session(self, user: User, base_url: str, price_id: str | None = None) -> str:
        params = [
            ("mode", "subscription"),
            ("line_items[0][price]", price_id or self.price_id),
            ("line_items[0][quantity]", "1"),
            ("success_url", f"{base_url}/welcome?session_id={{CHECKOUT_SESSION_ID}}"),
            ("cancel_url", f"{base_url}/account"),
            ("client_reference_id", str(user.id)),
            ("allow_promotion_codes", "true"),
            ("metadata[user_id]", str(user.id)),
            ("subscription_data[metadata][user_id]", str(user.id)),
        ]
        if user.stripe_customer_id:
            params.append(("customer", user.stripe_customer_id))
        else:
            params.append(("customer_email", user.email))
        session = self._request("POST", "/checkout/sessions", params)
        if not session.get("url"):
            raise StripeError("Stripe didn't return a checkout URL")
        return session["url"]

    def create_portal_session(self, customer_id: str, return_url: str) -> str:
        session = self._request(
            "POST", "/billing_portal/sessions", [("customer", customer_id), ("return_url", return_url)]
        )
        if not session.get("url"):
            raise StripeError("Stripe didn't return a billing portal URL")
        return session["url"]

    def retrieve_checkout_session(self, session_id: str) -> dict:
        return self._request("GET", f"/checkout/sessions/{urllib.parse.quote(session_id, safe='')}")

    def retrieve_price(self, price_id: str) -> dict:
        return self._request("GET", f"/prices/{urllib.parse.quote(price_id, safe='')}")

    def retrieve_subscription(self, subscription_id: str) -> dict:
        return self._request("GET", f"/subscriptions/{urllib.parse.quote(subscription_id, safe='')}")

    def change_price(self, subscription_id: str, price_id: str) -> dict:
        """Move a subscription to another price, charging the prorated difference now.

        If the charge fails, Stripe leaves the subscription unchanged.
        """
        sub = self.retrieve_subscription(subscription_id)
        items = (sub.get("items") or {}).get("data") or []
        if not items:
            raise StripeError("Subscription has no items to change")
        return self._request("POST", f"/subscriptions/{urllib.parse.quote(subscription_id, safe='')}", [
            ("items[0][id]", items[0]["id"]),
            ("items[0][price]", price_id),
            ("proration_behavior", "always_invoice"),
            ("payment_behavior", "error_if_incomplete"),
        ])


def verify_webhook(payload: bytes, signature_header: str, secret: str, now: float | None = None) -> dict:
    """Check the Stripe-Signature header and return the parsed event."""
    if not secret:
        raise WebhookError("STRIPE_WEBHOOK_SECRET is not set")
    timestamp, signatures = None, []
    for part in (signature_header or "").split(","):
        key, _, value = part.strip().partition("=")
        if key == "t":
            timestamp = value
        elif key == "v1":
            signatures.append(value)
    if not timestamp or not signatures:
        raise WebhookError("missing signature")
    try:
        age = (time.time() if now is None else now) - int(timestamp)
    except ValueError as e:
        raise WebhookError("bad timestamp") from e
    if abs(age) > WEBHOOK_TOLERANCE:
        raise WebhookError("timestamp outside tolerance")
    expected = hmac.new(secret.encode(), f"{timestamp}.".encode() + payload, hashlib.sha256).hexdigest()
    if not any(hmac.compare_digest(expected, s) for s in signatures):
        raise WebhookError("signature mismatch")
    try:
        return json.loads(payload.decode("utf-8"))
    except ValueError as e:
        raise WebhookError("invalid JSON") from e


def _period_end(sub: dict) -> int | None:
    # Newer API versions moved current_period_end from the subscription to its items.
    if sub.get("current_period_end"):
        return int(sub["current_period_end"])
    items = (sub.get("items") or {}).get("data") or []
    ends = [int(i["current_period_end"]) for i in items if i.get("current_period_end")]
    return max(ends) if ends else None


def plan_for(sub: dict, premium_price_id: str) -> str:
    """"premium" if the subscription is for the Premium price, else "basic"."""
    for item in (sub.get("items") or {}).get("data") or []:
        price = item.get("price") or item.get("plan") or {}
        price_id = price.get("id") if isinstance(price, dict) else price
        if premium_price_id and price_id == premium_price_id:
            return "premium"
    return "basic"


def apply_subscription(
    db: Database, user_id: int, sub: dict, customer_id: str | None, premium_price_id: str = ""
) -> None:
    status = sub.get("status") or "none"
    db.update_subscription(
        user_id,
        customer_id=customer_id or sub.get("customer"),
        subscription_id=sub.get("id"),
        status=status,
        current_period_end=_period_end(sub),
        cancel_at_period_end=bool(sub.get("cancel_at_period_end")),
        plan=plan_for(sub, premium_price_id),
    )


def _user_id(value: Any) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def sync_checkout_session(db: Database, stripe: Stripe, session: dict, expect_user: int | None = None) -> bool:
    """Grant access from a completed Checkout Session. Returns True if access was granted.

    Used by the webhook and by the /welcome page, so access starts even if the
    webhook is slow.
    """
    if session.get("mode") != "subscription" or session.get("status") not in (None, "complete"):
        return False
    user_id = _user_id(session.get("client_reference_id")) or _user_id((session.get("metadata") or {}).get("user_id"))
    if user_id is None or (expect_user is not None and user_id != expect_user):
        return False
    if db.get_user(user_id) is None:
        return False
    sub = session.get("subscription")
    if isinstance(sub, str):
        sub = stripe.retrieve_subscription(sub)
    if not isinstance(sub, dict):
        return False
    apply_subscription(db, user_id, sub, session.get("customer"), stripe.premium_price_id)
    return (sub.get("status") or "") in ("active", "trialing")


def handle_event(db: Database, stripe: Stripe, event: dict) -> str:
    """Apply one webhook event. Returns a short description for the log."""
    event_id = event.get("id") or ""
    if event_id and db.event_seen(event_id):
        return "duplicate"
    kind = event.get("type") or ""
    obj = (event.get("data") or {}).get("object") or {}

    if kind in CHECKOUT_EVENTS:
        result = "granted" if sync_checkout_session(db, stripe, obj) else "checkout ignored"
    elif kind in SUBSCRIPTION_EVENTS:
        user = db.get_user_by_customer(obj.get("customer") or "")
        if user is None:
            user = db.get_user(_user_id((obj.get("metadata") or {}).get("user_id")) or 0)
        if user is None:
            result = "no matching user"
        elif (
            user.stripe_subscription_id
            and obj.get("id") != user.stripe_subscription_id
            and user.subscription_status in ACCESS_STATUSES
            and obj.get("status") not in ACCESS_STATUSES
        ):
            # An old subscription ending must not cut off the one they pay for now.
            result = "old subscription ignored"
        else:
            # Events can arrive out of order, so read the subscription's current state.
            sub = obj
            if kind != "customer.subscription.deleted" and obj.get("id"):
                sub = stripe.retrieve_subscription(obj["id"])
            apply_subscription(db, user.id, sub, obj.get("customer"), stripe.premium_price_id)
            result = f"subscription {sub.get('status')}"
    else:
        result = "ignored"

    if event_id:
        db.mark_event(event_id)
    return result
