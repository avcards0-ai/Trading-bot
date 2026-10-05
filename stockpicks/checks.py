"""`python -m stockpicks check`: confirm every part of the site is set up.

The server also runs these checks when it starts and prints them to its log,
so on a host like Render you can read the results in the Logs tab.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass

from .billing import Stripe, StripeError
from .config import Settings
from .net import FetchError, Http
from .sources import sec
from .sources.prices import fetch_prices

LOCAL_HOSTS = ("http://localhost", "http://127.0.0.1", "http://0.0.0.0")


@dataclass
class Check:
    name: str
    ok: bool | None  # True = good, False = must fix, None = optional or not done yet
    detail: str


def _storage(settings: Settings) -> Check:
    try:
        os.makedirs(settings.data_dir, exist_ok=True)
        probe = os.path.join(settings.data_dir, ".write-test")
        with open(probe, "w", encoding="utf-8") as fh:
            fh.write("ok")
        os.unlink(probe)
    except OSError as e:
        return Check("Storage", False, f"Can't write to DATA_DIR ({settings.data_dir}): {e}")
    return Check("Storage", True, f"Saving accounts and picks in {os.path.abspath(settings.data_dir)}")


def _address(settings: Settings) -> Check:
    url = settings.base_url
    if url.startswith("https://"):
        return Check("Web address", True, url)
    if url.startswith(LOCAL_HOSTS):
        return Check("Web address", None, f"{url} is fine on your computer. Online, set BASE_URL to your https:// address.")
    return Check("Web address", False, f"BASE_URL is {url}. It must start with https:// so logins and payments are secure.")


def _sec(settings: Settings, http: Http | None) -> Check:
    if "@" not in settings.sec_user_agent:
        return Check(
            "SEC data", False,
            "Set SEC_USER_AGENT to your site name and email, e.g. 'LongHold you@example.com'. The SEC requires it.",
        )
    http = http or Http(settings.sec_user_agent, retries=1)
    try:
        companies = sec.parse_ticker_map(http.get_json(sec.TICKERS_URL))
    except FetchError as e:
        return Check("SEC data", False, f"Couldn't reach SEC EDGAR: {e}")
    return Check("SEC data", True, f"Connected to SEC EDGAR ({len(companies):,} companies listed)")


def _prices(settings: Settings, http: Http | None) -> Check:
    http = http or Http(retries=1)
    try:
        prices = fetch_prices(["AAPL", "MSFT"], settings.price_source, http, settings.finnhub_api_key, log=lambda m: None)
    except ValueError as e:
        return Check("Share prices", False, str(e))
    if not prices:
        hint = (
            "Get a free key at https://finnhub.io, then set PRICE_SOURCE=finnhub and FINNHUB_API_KEY."
            if settings.price_source == "stooq"
            else "Check FINNHUB_API_KEY."
        )
        return Check("Share prices", False, f"{settings.price_source} didn't return any prices. {hint}")
    sample = ", ".join(f"{t} ${p:,.2f}" for t, p in sorted(prices.items()))
    return Check("Share prices", True, f"{settings.price_source} is working ({sample})")


def _picks(settings: Settings) -> Check:
    try:
        with open(settings.picks_path, encoding="utf-8") as fh:
            data = json.load(fh)
    except FileNotFoundError:
        return Check("Stock analysis", None, "Not run yet. The server runs it at startup (1-3 minutes), or run: python -m stockpicks refresh")
    except ValueError:
        return Check("Stock analysis", False, f"{settings.picks_path} is damaged. Run: python -m stockpicks refresh")
    return Check(
        "Stock analysis", True,
        f"Last run {data.get('as_of')}: {data.get('covered')} companies scored, {data.get('picks_count')} picks",
    )


def _price_check(name: str, variable: str, price_id: str, stripe: Stripe, mode: str) -> Check:
    try:
        price = stripe.retrieve_price(price_id)
    except StripeError as e:
        return Check(name, False, f"Stripe rejected the key or {variable}: {e}")
    recurring = price.get("recurring") or {}
    if not recurring:
        return Check(name, False, f"{variable} is a one-time price. Create a recurring (monthly) price instead.")
    if not price.get("active", True):
        return Check(name, False, f"The {variable} price is archived. Use an active price.")
    amount = (price.get("unit_amount") or 0) / 100
    currency = (price.get("currency") or "usd").upper()
    return Check(name, True, f"Charging {amount:,.2f} {currency} per {recurring.get('interval', 'month')}, {mode}")


def _stripe(settings: Settings, stripe: Stripe | None) -> list[Check]:
    if not settings.stripe_enabled:
        return [Check(
            "Payments", None,
            "Stripe isn't set up yet, so visitors can sign up but can't pay. Add STRIPE_SECRET_KEY and STRIPE_PRICE_ID.",
        )]
    stripe = stripe or Stripe(settings.stripe_secret_key, settings.stripe_price_id)
    mode = "TEST mode (use card 4242 4242 4242 4242)" if settings.stripe_secret_key.startswith(("sk_test", "rk_test")) else "LIVE mode"
    checks = [_price_check("Payments", "STRIPE_PRICE_ID", settings.stripe_price_id, stripe, mode)]
    if settings.premium_offered:
        if settings.stripe_premium_price_id.startswith("price_"):
            checks.append(_price_check("Premium plan", "STRIPE_PREMIUM_PRICE_ID", settings.stripe_premium_price_id, stripe, mode))
        else:
            checks.append(Check(
                "Premium plan", False,
                f"Create a {settings.premium_price_label} monthly price in Stripe and set STRIPE_PREMIUM_PRICE_ID, "
                "or set PREMIUM_PICKS_COUNT=0 to offer only one plan.",
            ))
    if settings.stripe_webhook_secret.startswith("whsec_"):
        checks.append(Check("Payment updates", True, f"Webhook secret set. Stripe should send events to {settings.base_url}/stripe/webhook"))
    else:
        checks.append(Check(
            "Payment updates", False,
            f"Add a Stripe webhook for {settings.base_url}/stripe/webhook and set STRIPE_WEBHOOK_SECRET (starts with whsec_). "
            "Without it, cancellations and failed payments won't remove access.",
        ))
    return checks


def _email(settings: Settings) -> Check:
    if settings.email_enabled:
        return Check("Password-reset email", True, f"Sending through {settings.smtp_host}")
    if settings.support_email:
        return Check("Password-reset email", None, f"No SMTP set, so the reset page asks people to email {settings.support_email}")
    return Check("Password-reset email", None, "No SMTP or SUPPORT_EMAIL set, so people who forget their password can't reach you.")


def run_checks(
    settings: Settings,
    sec_http: Http | None = None,
    price_http: Http | None = None,
    stripe: Stripe | None = None,
) -> list[Check]:
    return [
        _storage(settings),
        _address(settings),
        _sec(settings, sec_http),
        _prices(settings, price_http),
        _picks(settings),
        *_stripe(settings, stripe),
        _email(settings),
    ]


def format_checks(checks: list[Check]) -> str:
    marks = {True: "[ok]  ", False: "[FIX] ", None: "[--]  "}
    lines = [f"{marks[c.ok]}{c.name}: {c.detail}" for c in checks]
    problems = sum(1 for c in checks if c.ok is False)
    lines.append("All set." if not problems else f"{problems} thing(s) to fix, marked [FIX].")
    return "\n".join(lines)
