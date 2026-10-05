"""The website, as a plain WSGI app (runs on wsgiref, waitress, gunicorn, ...)."""

from __future__ import annotations

import hmac
import json
import os
import re
import secrets
import threading
import time
import traceback
import urllib.parse
from collections import defaultdict, deque
from http.cookies import CookieError, SimpleCookie
from typing import Callable, Iterable

from . import pages
from .billing import Stripe, StripeError, WebhookError, handle_event, sync_checkout_session, verify_webhook
from .config import PACKAGE_DIR, Settings
from .db import Database, User
from .mailer import send_email

MAX_BODY = 1_000_000
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
TICKER_RE = re.compile(r"^[A-Z0-9\-]{1,10}$")
STATUS_TEXT = {
    200: "OK", 303: "See Other", 400: "Bad Request", 403: "Forbidden", 404: "Not Found",
    405: "Method Not Allowed", 413: "Payload Too Large", 429: "Too Many Requests",
    500: "Internal Server Error", 502: "Bad Gateway",
}


class Request:
    def __init__(self, environ: dict):
        self.environ = environ
        self.method = environ.get("REQUEST_METHOD", "GET").upper()
        self.path = environ.get("PATH_INFO") or "/"
        self.query = urllib.parse.parse_qs(environ.get("QUERY_STRING", ""))
        self._body: bytes | None = None
        self._form: dict[str, str] | None = None
        self.cookies: dict[str, str] = {}
        try:
            jar = SimpleCookie(environ.get("HTTP_COOKIE", ""))
            self.cookies = {k: m.value for k, m in jar.items()}
        except CookieError:
            pass

    def arg(self, name: str) -> str:
        return (self.query.get(name) or [""])[0]

    def body(self) -> bytes:
        if self._body is None:
            try:
                length = int(self.environ.get("CONTENT_LENGTH") or 0)
            except ValueError:
                length = 0
            if length > MAX_BODY:
                raise HttpError(413, "That request is too large.")
            self._body = self.environ["wsgi.input"].read(length) if length > 0 else b""
        return self._body

    @property
    def form(self) -> dict[str, str]:
        if self._form is None:
            parsed = urllib.parse.parse_qs(self.body().decode("utf-8", errors="replace"))
            self._form = {k: v[0] for k, v in parsed.items()}
        return self._form

    @property
    def client_ip(self) -> str:
        """Best guess at the visitor's address, used only for rate limiting.

        Hosts fronted by Cloudflare (Render among them) pass the visitor in
        True-Client-IP or CF-Connecting-IP. Behind a plain reverse proxy the
        right-most X-Forwarded-For entry is the one the proxy added.
        """
        for header in ("HTTP_TRUE_CLIENT_IP", "HTTP_CF_CONNECTING_IP"):
            if self.environ.get(header):
                return self.environ[header].strip()
        forwarded = self.environ.get("HTTP_X_FORWARDED_FOR", "")
        if forwarded:
            return forwarded.split(",")[-1].strip()
        return self.environ.get("REMOTE_ADDR", "")


class Response:
    def __init__(self, body: str | bytes = "", status: int = 200, content_type: str = "text/html; charset=utf-8"):
        self.body = body.encode("utf-8") if isinstance(body, str) else body
        self.status = status
        self.headers: list[tuple[str, str]] = [("Content-Type", content_type)]

    @classmethod
    def redirect(cls, location: str, status: int = 303) -> "Response":
        r = cls(b"", status)
        r.headers.append(("Location", location))
        return r

    def set_cookie(self, name: str, value: str, *, max_age: int | None, secure: bool, http_only: bool = True) -> None:
        parts = [f"{name}={value}", "Path=/", "SameSite=Lax"]
        if max_age is not None:
            parts.append(f"Max-Age={max_age}")
        if http_only:
            parts.append("HttpOnly")
        if secure:
            parts.append("Secure")
        self.headers.append(("Set-Cookie", "; ".join(parts)))


class HttpError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


class Throttle:
    """Allow at most `limit` failures per key within `window` seconds."""

    def __init__(self, limit: int = 10, window: float = 900):
        self.limit = limit
        self.window = window
        self._hits: dict[str, deque] = defaultdict(deque)
        self._lock = threading.Lock()

    def _trim(self, key: str, now: float) -> deque:
        hits = self._hits[key]
        while hits and hits[0] < now - self.window:
            hits.popleft()
        return hits

    def blocked(self, *keys: str) -> bool:
        now = time.monotonic()
        with self._lock:
            return any(len(self._trim(k, now)) >= self.limit for k in keys if k)

    def hit(self, *keys: str) -> None:
        now = time.monotonic()
        with self._lock:
            if len(self._hits) > 10_000:  # forget keys with no recent failures
                for k in [k for k, v in self._hits.items() if not v or v[-1] < now - self.window]:
                    del self._hits[k]
            for k in keys:
                if k:
                    self._trim(k, now).append(now)


class PicksStore:
    """Reads picks.json, reloading whenever the refresh job replaces it."""

    def __init__(self, path: str):
        self.path = path
        self._lock = threading.Lock()
        self._mtime: float | None = None
        self._data: dict | None = None
        self._by_ticker: dict[str, dict] = {}

    def get(self) -> dict | None:
        try:
            mtime = os.stat(self.path).st_mtime
        except FileNotFoundError:
            return self._data
        with self._lock:
            if mtime != self._mtime:
                try:
                    with open(self.path, encoding="utf-8") as fh:
                        data = json.load(fh)
                    self._data = data
                    self._by_ticker = {s["ticker"]: s for s in data.get("stocks", [])}
                    self._mtime = mtime
                except (OSError, ValueError):
                    pass  # keep serving the previous copy
            return self._data

    def stock(self, ticker: str) -> dict | None:
        self.get()
        return self._by_ticker.get(ticker)


def safe_next(url: str) -> str:
    """Only allow redirects to paths on this site."""
    if url.startswith("/") and not url.startswith("//") and "\\" not in url:
        return url
    return "/picks"


Handler = Callable[["Context"], Response]


class Context:
    def __init__(self, app: "App", req: Request):
        self.app = app
        self.req = req
        self.settings = app.settings
        self.user: User | None = app.db.user_for_session(req.cookies.get("session", ""))
        self.csrf = req.cookies.get("csrf") or ""
        self.new_csrf = not self.csrf
        if self.new_csrf:
            self.csrf = secrets.token_urlsafe(24)

    def html(self, body: str, status: int = 200) -> Response:
        return Response(body, status)


class App:
    def __init__(
        self,
        settings: Settings,
        db: Database | None = None,
        store: PicksStore | None = None,
        stripe: Stripe | None = None,
        mailer: Callable[[Settings, str, str, str], None] = send_email,
        log: Callable[[str], None] = print,
    ):
        self.settings = settings
        self.db = db or Database(settings.db_path)
        self.store = store or PicksStore(settings.picks_path)
        if stripe is None and settings.stripe_enabled:
            stripe = Stripe(settings.stripe_secret_key, settings.stripe_price_id)
        self.stripe = stripe
        self.mailer = mailer
        self.log = log
        # Per-email limits protect accounts. Per-IP limits are looser because
        # many visitors can share an address (offices, phone networks, proxies).
        self.throttle = Throttle(limit=10)
        self.ip_throttle = Throttle(limit=30)
        with open(os.path.join(PACKAGE_DIR, "static", "style.css"), "rb") as fh:
            self.css = fh.read()
        self.routes: dict[tuple[str, str], Handler] = {
            ("GET", "/"): self.home,
            ("GET", "/methodology"): self.methodology,
            ("GET", "/terms"): self.terms,
            ("GET", "/signup"): self.signup_form,
            ("POST", "/signup"): self.signup,
            ("GET", "/login"): self.login_form,
            ("POST", "/login"): self.login,
            ("POST", "/logout"): self.logout,
            ("GET", "/forgot"): self.forgot_form,
            ("POST", "/forgot"): self.forgot,
            ("GET", "/reset"): self.reset_form,
            ("POST", "/reset"): self.reset,
            ("GET", "/account"): self.account,
            ("POST", "/subscribe"): self.subscribe,
            ("GET", "/welcome"): self.welcome,
            ("POST", "/billing"): self.billing,
            ("POST", "/stripe/webhook"): self.webhook,
            ("GET", "/picks"): self.picks,
            ("GET", "/stocks"): self.all_stocks,
            ("GET", "/static/style.css"): self.stylesheet,
            ("GET", "/healthz"): self.health,
        }

    # WSGI plumbing

    def __call__(self, environ: dict, start_response: Callable) -> Iterable[bytes]:
        req = Request(environ)
        ctx: Context | None = None
        try:
            ctx = Context(self, req)
            resp = self.dispatch(ctx)
        except HttpError as err:
            resp = self.error_page(ctx, err.status, err.message)
        except Exception:
            self.log(traceback.format_exc())
            resp = self.error_page(ctx, 500, "Something went wrong on our end. Please try again.")
        if ctx is not None and ctx.new_csrf:
            resp.set_cookie("csrf", ctx.csrf, max_age=None, secure=self.settings.cookie_secure)
        self.add_security_headers(resp)
        status = f"{resp.status} {STATUS_TEXT.get(resp.status, 'OK')}"
        resp.headers.append(("Content-Length", str(len(resp.body))))
        start_response(status, resp.headers)
        return [b"" if req.method == "HEAD" else resp.body]

    def add_security_headers(self, resp: Response) -> None:
        resp.headers += [
            ("X-Content-Type-Options", "nosniff"),
            ("X-Frame-Options", "DENY"),
            ("Referrer-Policy", "same-origin"),
            (
                "Content-Security-Policy",
                "default-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; "
                "form-action 'self' https://checkout.stripe.com https://billing.stripe.com; "
                "frame-ancestors 'none'; base-uri 'none'",
            ),
        ]
        if not any(k == "Cache-Control" for k, _ in resp.headers):
            resp.headers.append(("Cache-Control", "no-store"))
        if self.settings.cookie_secure:
            resp.headers.append(("Strict-Transport-Security", "max-age=31536000"))

    def dispatch(self, ctx: Context) -> Response:
        req = ctx.req
        method = "GET" if req.method == "HEAD" else req.method
        if method == "POST" and req.path != "/stripe/webhook":
            self.check_csrf(ctx)
        handler = self.routes.get((method, req.path))
        if handler:
            return handler(ctx)
        if method == "GET" and req.path.startswith("/stock/"):
            return self.stock(ctx, req.path[len("/stock/") :])
        if any(path == req.path for _, path in self.routes):
            raise HttpError(405, "That action isn't allowed here.")
        raise HttpError(404, "We couldn't find that page.")

    def check_csrf(self, ctx: Context) -> None:
        sent = ctx.req.form.get("csrf", "")
        cookie = ctx.req.cookies.get("csrf", "")
        if not cookie or not sent or not hmac.compare_digest(sent, cookie):
            raise HttpError(403, "Your form expired. Please go back, reload the page and try again.")

    def error_page(self, ctx: Context | None, status: int, message: str) -> Response:
        title = "Page not found" if status == 404 else "Sorry"
        user = ctx.user if ctx else None
        csrf = ctx.csrf if ctx else ""
        return Response(pages.simple(self.settings, title, message, user, csrf), status)

    def login_session(self, user: User, resp: Response) -> Response:
        token = self.db.create_session(user.id)
        resp.set_cookie("session", token, max_age=30 * 86400, secure=self.settings.cookie_secure)
        return resp

    def require_login(self, ctx: Context) -> Response | None:
        if ctx.user is None:
            target = ctx.req.path
            return Response.redirect("/login?next=" + urllib.parse.quote(target))
        return None

    def require_member(self, ctx: Context) -> Response | None:
        if (redirect := self.require_login(ctx)) is not None:
            return redirect
        if not ctx.user.has_access:
            return Response.redirect("/account")
        return None

    # Public pages

    def home(self, ctx: Context) -> Response:
        return ctx.html(pages.home(self.settings, self.store.get(), ctx.user, ctx.csrf))

    def methodology(self, ctx: Context) -> Response:
        return ctx.html(pages.methodology(self.settings, ctx.user, ctx.csrf))

    def terms(self, ctx: Context) -> Response:
        return ctx.html(pages.terms(self.settings, ctx.user, ctx.csrf))

    def stylesheet(self, ctx: Context) -> Response:
        resp = Response(self.css, content_type="text/css; charset=utf-8")
        resp.headers.append(("Cache-Control", "public, max-age=3600"))
        return resp

    def health(self, ctx: Context) -> Response:
        data = self.store.get()
        body = json.dumps({"ok": True, "picks_as_of": data.get("as_of") if data else None})
        return Response(body, content_type="application/json")

    # Accounts

    def signup_form(self, ctx: Context) -> Response:
        if ctx.user:
            return Response.redirect("/account")
        return ctx.html(pages.signup(self.settings, ctx.csrf))

    def signup(self, ctx: Context) -> Response:
        form = ctx.req.form
        email = form.get("email", "").strip()
        password = form.get("password", "")
        error = ""
        if not EMAIL_RE.match(email) or len(email) > 254:
            error = "Please enter a valid email address."
        elif not 8 <= len(password) <= 200:
            error = "Your password needs at least 8 characters."
        elif form.get("agree") != "1":
            error = "Please confirm you've read the terms."
        elif self.ip_throttle.blocked("signup:" + ctx.req.client_ip):
            raise HttpError(429, "Too many sign-ups from your network. Please try again later.")
        if error:
            return ctx.html(pages.signup(self.settings, ctx.csrf, error, email), 400)
        self.ip_throttle.hit("signup:" + ctx.req.client_ip)
        user = self.db.create_user(email, password)
        if user is None:
            msg = "There's already an account with that email. Try logging in."
            return ctx.html(pages.signup(self.settings, ctx.csrf, msg, email), 400)
        return self.login_session(user, Response.redirect("/account?new=1"))

    def login_form(self, ctx: Context) -> Response:
        if ctx.user:
            return Response.redirect(safe_next(ctx.req.arg("next") or "/account"))
        message = "Your password was changed. Please log in." if ctx.req.arg("reset") else ""
        return ctx.html(pages.login(self.settings, ctx.csrf, next_url=ctx.req.arg("next"), message=message))

    def login(self, ctx: Context) -> Response:
        form = ctx.req.form
        email = form.get("email", "").strip()
        next_url = form.get("next", "")
        ip_key, email_key = "ip:" + ctx.req.client_ip, "email:" + email.lower()
        if self.throttle.blocked(email_key) or self.ip_throttle.blocked(ip_key):
            raise HttpError(429, "Too many failed attempts. Please wait 15 minutes and try again.")
        user = self.db.authenticate(email, form.get("password", ""))
        if user is None:
            self.throttle.hit(email_key)
            self.ip_throttle.hit(ip_key)
            error = "That email and password don't match."
            return ctx.html(pages.login(self.settings, ctx.csrf, error, email, next_url), 400)
        default = "/picks" if user.has_access else "/account"
        return self.login_session(user, Response.redirect(safe_next(next_url) if next_url else default))

    def logout(self, ctx: Context) -> Response:
        token = ctx.req.cookies.get("session", "")
        if token:
            self.db.delete_session(token)
        resp = Response.redirect("/")
        resp.set_cookie("session", "", max_age=0, secure=self.settings.cookie_secure)
        return resp

    def forgot_form(self, ctx: Context) -> Response:
        return ctx.html(pages.forgot(self.settings, ctx.csrf))

    def forgot(self, ctx: Context) -> Response:
        if not self.settings.email_enabled:
            return ctx.html(pages.forgot(self.settings, ctx.csrf))
        email = ctx.req.form.get("email", "").strip()
        key = "reset:" + ctx.req.client_ip
        if self.ip_throttle.blocked(key):
            raise HttpError(429, "Too many reset requests. Please try again later.")
        self.ip_throttle.hit(key)
        user = self.db.get_user_by_email(email) if EMAIL_RE.match(email) else None
        if user:
            token = self.db.create_reset_token(user.id)
            link = f"{self.settings.base_url}/reset?token={urllib.parse.quote(token)}"
            text = (
                f"Someone asked to reset the password for your {self.settings.site_name} account.\n\n"
                f"Choose a new password here (the link works for one hour):\n{link}\n\n"
                "If this wasn't you, ignore this email and your password stays the same."
            )
            try:
                self.mailer(self.settings, user.email, f"Reset your {self.settings.site_name} password", text)
            except Exception as err:  # noqa: BLE001 - never reveal mail errors to the visitor
                self.log(f"password reset email to user {user.id} failed: {err}")
        return ctx.html(pages.forgot(self.settings, ctx.csrf, sent=True))

    def reset_form(self, ctx: Context) -> Response:
        token = ctx.req.arg("token")
        valid = bool(token) and self.db.reset_token_user(token) is not None
        return ctx.html(pages.reset(self.settings, ctx.csrf, token, valid))

    def reset(self, ctx: Context) -> Response:
        token = ctx.req.form.get("token", "")
        password = ctx.req.form.get("password", "")
        valid = bool(token) and self.db.reset_token_user(token) is not None
        if not valid:
            return ctx.html(pages.reset(self.settings, ctx.csrf, token, False), 400)
        if not 8 <= len(password) <= 200:
            error = "Your password needs at least 8 characters."
            return ctx.html(pages.reset(self.settings, ctx.csrf, token, True, error), 400)
        self.db.use_reset_token(token, password)
        return Response.redirect("/login?reset=1")

    def account(self, ctx: Context) -> Response:
        if (redirect := self.require_login(ctx)) is not None:
            return redirect
        message = ""
        if ctx.req.arg("new") and not ctx.user.has_access:
            message = "Your account is ready. Subscribe below to unlock the full list."
        elif ctx.req.arg("pending"):
            message = "We're waiting for Stripe to confirm your payment. Refresh this page in a minute."
        return ctx.html(pages.account(self.settings, ctx.user, ctx.csrf, message, ctx.req.arg("error")))

    # Billing

    def subscribe(self, ctx: Context) -> Response:
        if (redirect := self.require_login(ctx)) is not None:
            return redirect
        if ctx.user.has_access:
            return Response.redirect("/picks")
        if self.stripe is None:
            return Response.redirect("/account")
        try:
            url = self.stripe.create_checkout_session(ctx.user, self.settings.base_url)
        except StripeError as err:
            self.log(f"checkout for user {ctx.user.id} failed: {err}")
            return Response.redirect("/account?error=" + urllib.parse.quote("We couldn't reach the payment page. Please try again."))
        return Response.redirect(url)

    def welcome(self, ctx: Context) -> Response:
        if (redirect := self.require_login(ctx)) is not None:
            return redirect
        session_id = ctx.req.arg("session_id")
        if self.stripe and session_id and not ctx.user.has_access:
            try:
                session = self.stripe.retrieve_checkout_session(session_id)
                sync_checkout_session(self.db, self.stripe, session, expect_user=ctx.user.id)
            except StripeError as err:
                self.log(f"welcome sync for user {ctx.user.id} failed: {err}")
        user = self.db.get_user(ctx.user.id)
        if user and user.has_access:
            return Response.redirect("/picks?welcome=1")
        return Response.redirect("/account?pending=1")

    def billing(self, ctx: Context) -> Response:
        if (redirect := self.require_login(ctx)) is not None:
            return redirect
        if self.stripe is None or not ctx.user.stripe_customer_id:
            return Response.redirect("/account")
        try:
            url = self.stripe.create_portal_session(ctx.user.stripe_customer_id, f"{self.settings.base_url}/account")
        except StripeError as err:
            self.log(f"billing portal for user {ctx.user.id} failed: {err}")
            return Response.redirect("/account?error=" + urllib.parse.quote("We couldn't open billing. Please try again."))
        return Response.redirect(url)

    def webhook(self, ctx: Context) -> Response:
        if self.stripe is None:
            raise HttpError(404, "Payments aren't set up.")
        try:
            event = verify_webhook(
                ctx.req.body(), ctx.req.environ.get("HTTP_STRIPE_SIGNATURE", ""), self.settings.stripe_webhook_secret
            )
        except WebhookError as err:
            self.log(f"rejected Stripe webhook: {err}")
            return Response(json.dumps({"error": str(err)}), 400, "application/json")
        try:
            result = handle_event(self.db, self.stripe, event)
        except StripeError as err:
            # A 5xx makes Stripe retry the event later.
            self.log(f"Stripe webhook {event.get('type')} failed: {err}")
            return Response(json.dumps({"error": "retry"}), 502, "application/json")
        self.log(f"Stripe webhook {event.get('type')}: {result}")
        return Response(json.dumps({"received": True}), content_type="application/json")

    # Members-only pages

    def picks(self, ctx: Context) -> Response:
        if (redirect := self.require_member(ctx)) is not None:
            return redirect
        data = self.store.get()
        if not data:
            return ctx.html(pages.layout(self.settings, "Picks", pages.no_data(self.settings), user=ctx.user, csrf=ctx.csrf))
        message = "Welcome aboard! Here's today's list." if ctx.req.arg("welcome") else ""
        return ctx.html(pages.picks(self.settings, data, ctx.user, ctx.csrf, message))

    def all_stocks(self, ctx: Context) -> Response:
        if (redirect := self.require_member(ctx)) is not None:
            return redirect
        data = self.store.get()
        if not data:
            return ctx.html(pages.layout(self.settings, "All stocks", pages.no_data(self.settings), user=ctx.user, csrf=ctx.csrf))
        return ctx.html(pages.all_stocks(self.settings, data, ctx.user, ctx.csrf))

    def stock(self, ctx: Context, ticker: str) -> Response:
        ticker = ticker.upper()
        if not TICKER_RE.match(ticker):
            raise HttpError(404, "We couldn't find that page.")
        data = self.store.get()
        is_sample = ticker in pages.sample_tickers(data)
        if not is_sample and (redirect := self.require_member(ctx)) is not None:
            return redirect
        s = self.store.stock(ticker)
        if not data or s is None:
            raise HttpError(404, f"We don't cover {ticker}.")
        member = ctx.user is not None and ctx.user.has_access
        return ctx.html(pages.stock(self.settings, data, s, ctx.user, ctx.csrf, is_sample=is_sample and not member))


def create_app(settings: Settings | None = None) -> App:
    """Entry point for WSGI servers, e.g. `waitress-serve --call stockpicks.web:create_app`."""
    from .config import load_dotenv

    if settings is None:
        load_dotenv()
        settings = Settings.from_env()
    return App(settings)
