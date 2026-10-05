import hashlib
import hmac
import io
import json
import time
import unittest
import urllib.parse
from wsgiref.util import setup_testing_defaults

from stockpicks.billing import Stripe, StripeError, handle_event, verify_webhook, WebhookError
from stockpicks.checks import format_checks, run_checks
from stockpicks.config import Settings
from stockpicks.db import Database, hash_password, verify_password
from stockpicks.refresh import refresh
from stockpicks.web import App, PicksStore, safe_next

from .stockpicks_helpers import TODAY, FakeHttp, temp_settings

WEBHOOK_SECRET = "whsec_test"


def sign(payload: bytes, secret: str = WEBHOOK_SECRET, ts: int | None = None) -> str:
    ts = int(time.time()) if ts is None else ts
    sig = hmac.new(secret.encode(), f"{ts}.".encode() + payload, hashlib.sha256).hexdigest()
    return f"t={ts},v1={sig}"


class FakeStripe:
    """A Stripe transport that records requests and answers from canned objects."""

    def __init__(self):
        self.requests = []
        self.subscriptions = {}
        self.sessions = {}
        self.fail = False

    def __call__(self, method, url, headers, body):
        self.requests.append((method, url, body.decode() if body else ""))
        if self.fail:
            return 500, b'{"error": {"message": "boom"}}'
        path = urllib.parse.urlsplit(url).path[len("/v1"):]
        if method == "POST" and path == "/checkout/sessions":
            return 200, json.dumps({"id": "cs_1", "url": "https://checkout.stripe.com/c/pay/cs_1"}).encode()
        if method == "POST" and path == "/billing_portal/sessions":
            return 200, json.dumps({"url": "https://billing.stripe.com/p/session/1"}).encode()
        if path.startswith("/prices/"):
            if path.endswith("/price_missing"):
                return 404, b'{"error": {"message": "No such price"}}'
            return 200, json.dumps({"id": "price_123", "active": True, "currency": "usd", "unit_amount": 1000,
                                    "recurring": {"interval": "month"}}).encode()
        if path.startswith("/subscriptions/"):
            return 200, json.dumps(self.subscriptions[path.rsplit("/", 1)[1]]).encode()
        if path.startswith("/checkout/sessions/"):
            return 200, json.dumps(self.sessions[path.rsplit("/", 1)[1]]).encode()
        return 404, b'{"error": {"message": "no such route"}}'


class Result:
    def __init__(self, status, headers, body):
        self.status = status
        self.headers = headers
        self.text = body.decode("utf-8")

    def header(self, name):
        return next((v for k, v in self.headers if k.lower() == name.lower()), None)


class Client:
    def __init__(self, app):
        self.app = app
        self.cookies = {}

    def request(self, method, path, form=None, body=b"", headers=None, csrf=True):
        path, _, query = path.partition("?")
        if form is not None:
            form = dict(form)
            if csrf:
                form.setdefault("csrf", self.cookies.get("csrf", ""))
            body = urllib.parse.urlencode(form).encode()
        environ = {}
        setup_testing_defaults(environ)
        environ.update({
            "REQUEST_METHOD": method,
            "PATH_INFO": path,
            "QUERY_STRING": query,
            "CONTENT_LENGTH": str(len(body)),
            "wsgi.input": io.BytesIO(body),
            "HTTP_COOKIE": "; ".join(f"{k}={v}" for k, v in self.cookies.items()),
            "REMOTE_ADDR": "203.0.113.9",
        })
        environ.update(headers or {})
        captured = {}

        def start_response(status, response_headers):
            captured["status"] = int(status.split()[0])
            captured["headers"] = response_headers

        out = b"".join(self.app(environ, start_response))
        for key, value in captured["headers"]:
            if key == "Set-Cookie":
                name, _, rest = value.partition("=")
                val = rest.split(";", 1)[0]
                if "Max-Age=0" in value:
                    self.cookies.pop(name, None)
                else:
                    self.cookies[name] = val
        return Result(captured["status"], captured["headers"], out)

    def get(self, path, **kw):
        return self.request("GET", path, **kw)

    def post(self, path, form=None, **kw):
        if "csrf" not in self.cookies:
            self.get("/")
        return self.request("POST", path, form=form or {}, **kw)


class Site(unittest.TestCase):
    """A site with real picks data, a fake Stripe and a captured mailbox."""

    @classmethod
    def setUpClass(cls):
        cls.base_settings = temp_settings(picks_count=5)
        http = FakeHttp()
        cls.data = refresh(cls.base_settings, sec_http=http, price_http=http, log=lambda m: None, today=TODAY)

    def setUp(self):
        import shutil
        import tempfile

        data_dir = tempfile.mkdtemp(prefix="stockpicks-web-")
        shutil.copy(self.base_settings.picks_path, data_dir)
        self.settings = temp_settings(
            data_dir=data_dir,
            picks_count=5,
            stripe_secret_key="sk_test_x",
            stripe_price_id="price_123",
            stripe_webhook_secret=WEBHOOK_SECRET,
            smtp_host="smtp.example.com",
            smtp_from="hello@example.com",
            cookie_secure=True,
        )
        self.stripe_api = FakeStripe()
        self.mail = []
        self.logs = []
        self.app = App(
            self.settings,
            stripe=Stripe("sk_test_x", "price_123", transport=self.stripe_api),
            mailer=lambda settings, to, subject, text: self.mail.append((to, subject, text)),
            log=self.logs.append,
        )
        self.db = self.app.db
        self.client = Client(self.app)

    def picks(self):
        return sorted((s for s in self.data["stocks"] if s["rank"]), key=lambda s: s["rank"])

    def signup(self, email="sam@example.com", password="correct horse"):
        return self.client.post("/signup", {"email": email, "password": password, "agree": "1"})

    def member(self, email="member@example.com"):
        self.signup(email)
        self.db.set_comped(email, True)


class PublicPageTests(Site):
    def test_home_hides_top_picks_but_shows_samples(self):
        r = self.client.get("/")
        self.assertEqual(r.status, 200)
        picks = self.picks()
        self.assertNotIn(picks[0]["name"], r.text)
        self.assertIn("members only", r.text)
        for s in picks[-2:]:
            self.assertIn(f'/stock/{s["ticker"]}', r.text)
        self.assertIn("$10/month", r.text)
        self.assertIn("not personalized investment advice", r.text)

    def test_home_before_first_refresh(self):
        app = App(temp_settings(), log=lambda m: None)
        r = Client(app).get("/")
        self.assertEqual(r.status, 200)
        self.assertIn("Long-term stocks", r.text)

    def test_methodology_terms_and_static(self):
        self.assertIn("Return on invested capital", self.client.get("/methodology").text)
        self.assertIn("not a registered", self.client.get("/terms").text)
        css = self.client.get("/static/style.css")
        self.assertEqual(css.header("Content-Type"), "text/css; charset=utf-8")
        health = json.loads(self.client.get("/healthz").text)
        self.assertEqual(health["picks_as_of"], "2026-10-04")

    def test_security_headers(self):
        r = self.client.get("/")
        self.assertEqual(r.header("X-Frame-Options"), "DENY")
        self.assertIn("frame-ancestors 'none'", r.header("Content-Security-Policy"))
        self.assertIn("HttpOnly", r.header("Set-Cookie"))
        self.assertIn("Secure", r.header("Set-Cookie"))
        self.assertIn("Strict-Transport-Security", [k for k, _ in r.headers])

    def test_errors(self):
        self.assertEqual(self.client.get("/nope").status, 404)
        self.assertEqual(self.client.get("/stock/%3Cx%3E").status, 404)
        self.assertEqual(self.client.request("GET", "/logout").status, 405)
        head = self.client.request("HEAD", "/")
        self.assertEqual((head.status, head.text), (200, ""))

    def test_sample_stock_is_public_but_others_are_not(self):
        sample = self.picks()[-1]["ticker"]
        r = self.client.get(f"/stock/{sample}")
        self.assertEqual(r.status, 200)
        self.assertIn("free sample", r.text)
        r = self.client.get(f"/stock/{self.picks()[0]['ticker']}")
        self.assertEqual(r.status, 303)
        self.assertTrue(r.header("Location").startswith("/login?next=/stock/"))


class AccountTests(Site):
    def test_members_only_pages_redirect(self):
        r = self.client.get("/picks")
        self.assertEqual((r.status, r.header("Location")), (303, "/login?next=/picks"))
        self.signup()
        r = self.client.get("/picks")
        self.assertEqual((r.status, r.header("Location")), (303, "/account"))

    def test_signup_logs_in_and_offers_subscription(self):
        r = self.signup()
        self.assertEqual((r.status, r.header("Location")), (303, "/account?new=1"))
        page = self.client.get("/account?new=1").text
        self.assertIn("sam@example.com", page)
        self.assertIn("Subscribe for $10/month", page)

    def test_signup_validation(self):
        self.assertEqual(self.client.post("/signup", {"email": "bad", "password": "longenough", "agree": "1"}).status, 400)
        self.assertEqual(self.client.post("/signup", {"email": "a@b.co", "password": "short", "agree": "1"}).status, 400)
        self.assertEqual(self.client.post("/signup", {"email": "a@b.co", "password": "longenough"}).status, 400)
        self.signup("dup@example.com")
        self.client.post("/logout")
        r = self.signup("DUP@example.com")
        self.assertEqual(r.status, 400)
        self.assertIn("already an account", r.text)

    def test_csrf_is_required(self):
        self.client.get("/")
        r = self.client.request("POST", "/signup", form={"email": "x@y.co", "password": "longenough", "agree": "1"}, csrf=False)
        self.assertEqual(r.status, 403)
        r = self.client.request("POST", "/signup", form={"email": "x@y.co", "password": "longenough", "agree": "1", "csrf": "forged"})
        self.assertEqual(r.status, 403)

    def test_login_logout_and_throttle(self):
        self.signup()
        self.client.post("/logout")
        self.assertNotIn("session", self.client.cookies)
        self.assertEqual(self.client.get("/account").status, 303)

        r = self.client.post("/login", {"email": "sam@example.com", "password": "correct horse", "next": "//evil.com"})
        self.assertEqual((r.status, r.header("Location")), (303, "/picks"))
        self.assertEqual(self.client.get("/account").status, 200)
        self.client.post("/logout")

        for _ in range(10):
            self.assertEqual(self.client.post("/login", {"email": "sam@example.com", "password": "nope"}).status, 400)
        r = self.client.post("/login", {"email": "sam@example.com", "password": "correct horse"})
        self.assertEqual(r.status, 429)

    def test_safe_next(self):
        self.assertEqual(safe_next("/stock/AAPL"), "/stock/AAPL")
        for bad in ("//evil.com", "https://evil.com", "/\\evil.com", ""):
            self.assertEqual(safe_next(bad), "/picks")

    def test_password_reset(self):
        self.signup()
        self.client.post("/logout")
        self.client.post("/forgot", {"email": "nobody@example.com"})
        self.assertEqual(self.mail, [])
        r = self.client.post("/forgot", {"email": "sam@example.com"})
        self.assertIn("If an account exists", r.text)
        link = next(line for line in self.mail[0][2].splitlines() if "/reset?token=" in line)
        token = urllib.parse.unquote(link.split("token=")[1])
        self.assertTrue(link.startswith("https://picks.example.com/reset?token="))
        self.assertEqual(self.client.get(f"/reset?token={urllib.parse.quote(token)}").status, 200)
        r = self.client.post("/reset", {"token": token, "password": "a brand new one"})
        self.assertEqual((r.status, r.header("Location")), (303, "/login?reset=1"))
        self.assertEqual(self.client.post("/reset", {"token": token, "password": "again again"}).status, 400)
        r = self.client.post("/login", {"email": "sam@example.com", "password": "a brand new one"})
        self.assertEqual(r.status, 303)


class MemberTests(Site):
    def test_member_sees_picks_and_scorecards(self):
        self.member()
        r = self.client.get("/picks")
        self.assertEqual(r.status, 200)
        for s in self.picks():
            self.assertIn(f'/stock/{s["ticker"]}', r.text)
        top = self.picks()[0]
        page = self.client.get(f"/stock/{top['ticker']}").text
        self.assertIn("Overall score", page)
        self.assertIn("What it told the SEC recently", page)
        self.assertNotIn("free sample", page)
        stocks = self.client.get("/stocks").text
        self.assertIn("Not covered", stocks)
        self.assertIn("different yardsticks", stocks)
        self.assertIn("Red flag", stocks)

    def test_company_names_are_escaped(self):
        self.member()
        for path in ("/picks", "/stocks", "/stock/EVIL"):
            text = self.client.get(path).text
            self.assertNotIn("<script>Evil", text, path)
            self.assertIn("&lt;script&gt;Evil", text, path)

    def test_store_reloads_when_file_changes(self):
        store = PicksStore(self.settings.picks_path)
        self.assertEqual(store.get()["as_of"], "2026-10-04")
        with open(self.settings.picks_path) as fh:
            data = json.load(fh)
        data["as_of"] = "2026-10-05"
        with open(self.settings.picks_path, "w") as fh:
            json.dump(data, fh)
        import os
        os.utime(self.settings.picks_path, (time.time() + 5, time.time() + 5))
        self.assertEqual(store.get()["as_of"], "2026-10-05")


class BillingTests(Site):
    def active_subscription(self, sub_id="sub_1", customer="cus_1", user_id=None, status="active"):
        sub = {
            "id": sub_id,
            "object": "subscription",
            "customer": customer,
            "status": status,
            "cancel_at_period_end": False,
            "items": {"data": [{"current_period_end": 1_800_000_000}]},
            "metadata": {"user_id": str(user_id or "")},
        }
        self.stripe_api.subscriptions[sub_id] = sub
        return sub

    def post_event(self, event, signature=None):
        payload = json.dumps(event).encode()
        return self.client.request(
            "POST", "/stripe/webhook", body=payload,
            headers={"HTTP_STRIPE_SIGNATURE": signature or sign(payload), "CONTENT_TYPE": "application/json"},
        )

    def test_subscribe_redirects_to_checkout_then_welcome_grants_access(self):
        self.signup()
        user = self.db.get_user_by_email("sam@example.com")
        r = self.client.post("/subscribe")
        self.assertEqual((r.status, r.header("Location")), (303, "https://checkout.stripe.com/c/pay/cs_1"))
        method, url, body = self.stripe_api.requests[0]
        params = urllib.parse.parse_qs(body)
        self.assertEqual(params["line_items[0][price]"], ["price_123"])
        self.assertEqual(params["customer_email"], ["sam@example.com"])
        self.assertEqual(params["client_reference_id"], [str(user.id)])
        self.assertEqual(params["success_url"], ["https://picks.example.com/welcome?session_id={CHECKOUT_SESSION_ID}"])

        self.active_subscription(user_id=user.id)
        self.stripe_api.sessions["cs_1"] = {
            "id": "cs_1", "mode": "subscription", "status": "complete",
            "client_reference_id": str(user.id), "customer": "cus_1", "subscription": "sub_1",
        }
        r = self.client.get("/welcome?session_id=cs_1")
        self.assertEqual(r.header("Location"), "/picks?welcome=1")
        self.assertIn("Welcome aboard", self.client.get("/picks?welcome=1").text)
        self.assertIn("Renews on", self.client.get("/account").text)

        r = self.client.post("/billing")
        self.assertEqual(r.header("Location"), "https://billing.stripe.com/p/session/1")

    def test_welcome_ignores_someone_elses_checkout(self):
        self.signup("a@example.com")
        self.stripe_api.sessions["cs_x"] = {
            "id": "cs_x", "mode": "subscription", "status": "complete",
            "client_reference_id": "999", "customer": "cus_x", "subscription": "sub_x",
        }
        r = self.client.get("/welcome?session_id=cs_x")
        self.assertEqual(r.header("Location"), "/account?pending=1")

    def test_webhook_lifecycle(self):
        self.signup()
        user = self.db.get_user_by_email("sam@example.com")
        self.active_subscription(user_id=user.id)
        completed = {
            "id": "evt_1", "type": "checkout.session.completed",
            "data": {"object": {"mode": "subscription", "status": "complete", "client_reference_id": str(user.id),
                                "customer": "cus_1", "subscription": "sub_1"}},
        }
        self.assertEqual(self.post_event(completed).status, 200)
        user = self.db.get_user(user.id)
        self.assertTrue(user.has_access)
        self.assertEqual(user.current_period_end, 1_800_000_000)

        self.stripe_api.subscriptions["sub_1"]["status"] = "past_due"
        self.post_event({"id": "evt_2", "type": "customer.subscription.updated",
                         "data": {"object": {"id": "sub_1", "customer": "cus_1", "status": "active"}}})
        user = self.db.get_user(user.id)
        self.assertEqual(user.subscription_status, "past_due")  # read live, not from the event
        self.assertTrue(user.has_access)

        deleted = {"id": "evt_3", "type": "customer.subscription.deleted",
                   "data": {"object": {"id": "sub_1", "customer": "cus_1", "status": "canceled"}}}
        self.post_event(deleted)
        self.assertFalse(self.db.get_user(user.id).has_access)
        self.assertEqual(self.client.get("/picks").header("Location"), "/account")

    def test_old_subscription_ending_does_not_cut_off_new_one(self):
        self.signup()
        user = self.db.get_user_by_email("sam@example.com")
        self.db.update_subscription(user.id, customer_id="cus_1", subscription_id="sub_new", status="active",
                                    current_period_end=None, cancel_at_period_end=False)
        self.post_event({"id": "evt_9", "type": "customer.subscription.deleted",
                         "data": {"object": {"id": "sub_old", "customer": "cus_1", "status": "canceled"}}})
        self.assertTrue(self.db.get_user(user.id).has_access)

    def test_webhook_rejects_bad_signatures_and_dedupes(self):
        event = {"id": "evt_5", "type": "invoice.paid", "data": {"object": {}}}
        self.assertEqual(self.post_event(event, signature="t=1,v1=deadbeef").status, 400)
        self.assertEqual(self.post_event(event).status, 200)
        self.assertEqual(handle_event(self.db, self.app.stripe, event), "duplicate")

    def test_stripe_outage_asks_for_retry(self):
        self.signup()
        user = self.db.get_user_by_email("sam@example.com")
        self.stripe_api.fail = True
        event = {"id": "evt_6", "type": "checkout.session.completed",
                 "data": {"object": {"mode": "subscription", "client_reference_id": str(user.id),
                                     "customer": "cus_1", "subscription": "sub_1"}}}
        self.assertEqual(self.post_event(event).status, 502)
        self.assertFalse(self.db.event_seen("evt_6"))
        r = self.client.post("/subscribe")
        self.assertTrue(r.header("Location").startswith("/account?error="))

    def test_without_stripe_signup_still_works(self):
        app = App(temp_settings(), log=lambda m: None)
        client = Client(app)
        client.post("/signup", {"email": "a@b.co", "password": "longenough", "agree": "1"})
        self.assertIn("Payments aren", client.get("/account").text)
        self.assertEqual(client.post("/subscribe").header("Location"), "/account")


class UnitTests(unittest.TestCase):
    def test_password_hashing(self):
        stored = hash_password("hunter22")
        self.assertTrue(verify_password("hunter22", stored))
        self.assertFalse(verify_password("hunter23", stored))
        self.assertFalse(verify_password("x", "garbage"))

    def test_sessions_and_comped_access(self):
        db = Database(temp_settings().db_path)
        user = db.create_user("Pat@Example.com", "longenough")
        self.assertIsNone(db.create_user("pat@example.com", "other-pass"))
        token = db.create_session(user.id)
        self.assertEqual(db.user_for_session(token).id, user.id)
        self.assertIsNone(db.user_for_session("wrong"))
        self.assertFalse(user.has_access)
        self.assertTrue(db.set_comped("pat@example.com", True))
        self.assertTrue(db.get_user(user.id).has_access)
        db.set_password(user.id, "new password")
        self.assertIsNone(db.user_for_session(token))
        self.assertIsNotNone(db.authenticate("PAT@example.com", "new password"))

    def test_webhook_signature(self):
        payload = b'{"id": "evt"}'
        self.assertEqual(verify_webhook(payload, sign(payload), WEBHOOK_SECRET)["id"], "evt")
        with self.assertRaises(WebhookError):
            verify_webhook(payload, sign(payload, secret="other"), WEBHOOK_SECRET)
        with self.assertRaises(WebhookError):
            verify_webhook(payload, sign(payload, ts=int(time.time()) - 3600), WEBHOOK_SECRET)
        with self.assertRaises(WebhookError):
            verify_webhook(payload, "", WEBHOOK_SECRET)

    def test_stripe_errors_surface_message(self):
        stripe = Stripe("sk", "price", transport=lambda *a: (402, b'{"error": {"message": "Card declined"}}'))
        with self.assertRaisesRegex(StripeError, "Card declined"):
            stripe.retrieve_subscription("sub_1")


class SetupCheckTests(unittest.TestCase):
    def test_everything_configured(self):
        settings = temp_settings(stripe_secret_key="sk_test_x", stripe_price_id="price_123",
                                 stripe_webhook_secret="whsec_x", support_email="help@example.com")
        http = FakeHttp()
        refresh(settings, sec_http=http, price_http=http, log=lambda m: None, today=TODAY)
        http.prices.update(AAPL=227.5, MSFT=480.1)  # the check samples these two
        stripe = Stripe("sk_test_x", "price_123", transport=FakeStripe())
        checks = {c.name: c for c in run_checks(settings, sec_http=http, price_http=http, stripe=stripe)}
        self.assertTrue(all(c.ok is not False for c in checks.values()), format_checks(list(checks.values())))
        self.assertIn("10.00 USD per month", checks["Payments"].detail)
        self.assertIn("TEST mode", checks["Payments"].detail)
        self.assertIn("/stripe/webhook", checks["Payment updates"].detail)
        self.assertIn("3 picks", checks["Stock analysis"].detail)
        self.assertTrue(format_checks(list(checks.values())).endswith("All set."))

    def test_problems_are_explained(self):
        settings = temp_settings(sec_user_agent="", base_url="http://example.com",
                                 stripe_secret_key="sk_live_x", stripe_price_id="price_missing")
        down = FakeHttp(prices={})
        stripe = Stripe("sk_live_x", "price_missing", transport=FakeStripe())
        checks = {c.name: c for c in run_checks(settings, sec_http=down, price_http=down, stripe=stripe)}
        for name in ("SEC data", "Share prices", "Web address", "Payments", "Payment updates"):
            self.assertIs(checks[name].ok, False, name)
        self.assertIn("finnhub", checks["Share prices"].detail)
        self.assertIn("No such price", checks["Payments"].detail)
        self.assertIsNone(checks["Stock analysis"].ok)

    def test_render_address_and_placeholder_keys(self):
        settings = Settings.from_env({"RENDER_EXTERNAL_URL": "https://longhold.onrender.com",
                                      "STRIPE_SECRET_KEY": "later", "STRIPE_PRICE_ID": "later"})
        self.assertEqual(settings.base_url, "https://longhold.onrender.com")
        self.assertTrue(settings.cookie_secure)
        self.assertFalse(settings.stripe_enabled)
        custom = Settings.from_env({"RENDER_EXTERNAL_URL": "https://x.onrender.com", "BASE_URL": "https://picks.com/"})
        self.assertEqual(custom.base_url, "https://picks.com")


class ClientIpTests(unittest.TestCase):
    def ip(self, **environ):
        from stockpicks.web import Request
        return Request({"REQUEST_METHOD": "GET", **environ}).client_ip

    def test_client_ip(self):
        self.assertEqual(self.ip(REMOTE_ADDR="10.0.0.1"), "10.0.0.1")
        self.assertEqual(self.ip(REMOTE_ADDR="10.0.0.1", HTTP_X_FORWARDED_FOR="1.1.1.1, 2.2.2.2"), "2.2.2.2")
        self.assertEqual(self.ip(HTTP_X_FORWARDED_FOR="1.1.1.1, 2.2.2.2", HTTP_TRUE_CLIENT_IP="3.3.3.3"), "3.3.3.3")
        self.assertEqual(self.ip(HTTP_CF_CONNECTING_IP="4.4.4.4"), "4.4.4.4")


if __name__ == "__main__":
    unittest.main()
