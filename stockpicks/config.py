"""Site settings, read from environment variables (or a .env file)."""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Mapping

PACKAGE_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_UNIVERSE = os.path.join(PACKAGE_DIR, "universe.txt")


def _bool(value: str | None, default: bool) -> bool:
    if value is None or value.strip() == "":
        return default
    return value.strip().lower() in ("1", "true", "yes", "on")


@dataclass
class Settings:
    site_name: str = "LongHold"
    base_url: str = "http://localhost:8000"
    data_dir: str = "data"
    # SEC requires a User-Agent that identifies you, e.g. "LongHold admin@example.com".
    sec_user_agent: str = ""
    price_source: str = "stooq"
    finnhub_api_key: str = ""
    universe_file: str = DEFAULT_UNIVERSE
    picks_count: int = 25
    min_market_cap: float = 2e9
    price_label: str = "$10/month"
    support_email: str = ""
    stripe_secret_key: str = ""
    stripe_price_id: str = ""
    stripe_webhook_secret: str = ""
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_user: str = ""
    smtp_password: str = ""
    smtp_from: str = ""
    cookie_secure: bool = False

    @classmethod
    def from_env(cls, env: Mapping[str, str] | None = None) -> "Settings":
        env = os.environ if env is None else env
        d = cls()
        # Render sets RENDER_EXTERNAL_URL, so BASE_URL is only needed for a custom domain.
        base_url = (env.get("BASE_URL") or env.get("RENDER_EXTERNAL_URL") or d.base_url).rstrip("/")
        return cls(
            site_name=env.get("SITE_NAME", d.site_name),
            base_url=base_url,
            data_dir=env.get("DATA_DIR", d.data_dir),
            sec_user_agent=env.get("SEC_USER_AGENT", ""),
            price_source=env.get("PRICE_SOURCE", d.price_source).lower(),
            finnhub_api_key=env.get("FINNHUB_API_KEY", ""),
            universe_file=env.get("UNIVERSE_FILE") or d.universe_file,
            picks_count=int(env.get("PICKS_COUNT") or d.picks_count),
            min_market_cap=float(env.get("MIN_MARKET_CAP") or d.min_market_cap),
            price_label=env.get("PRICE_LABEL", d.price_label),
            support_email=env.get("SUPPORT_EMAIL", ""),
            stripe_secret_key=env.get("STRIPE_SECRET_KEY", ""),
            stripe_price_id=env.get("STRIPE_PRICE_ID", ""),
            stripe_webhook_secret=env.get("STRIPE_WEBHOOK_SECRET", ""),
            smtp_host=env.get("SMTP_HOST", ""),
            smtp_port=int(env.get("SMTP_PORT") or d.smtp_port),
            smtp_user=env.get("SMTP_USER", ""),
            smtp_password=env.get("SMTP_PASSWORD", ""),
            smtp_from=env.get("SMTP_FROM", ""),
            cookie_secure=_bool(env.get("COOKIE_SECURE"), base_url.startswith("https://")),
        )

    @property
    def db_path(self) -> str:
        return os.path.join(self.data_dir, "site.db")

    @property
    def picks_path(self) -> str:
        return os.path.join(self.data_dir, "picks.json")

    @property
    def history_path(self) -> str:
        return os.path.join(self.data_dir, "history.jsonl")

    @property
    def cache_dir(self) -> str:
        return os.path.join(self.data_dir, "cache")

    @property
    def stripe_enabled(self) -> bool:
        # Prefix checks ignore placeholders like "later" typed into a host's dashboard.
        return self.stripe_secret_key.startswith(("sk_", "rk_")) and self.stripe_price_id.startswith("price_")

    @property
    def email_enabled(self) -> bool:
        return bool(self.smtp_host and (self.smtp_from or self.smtp_user))


def load_dotenv(path: str = ".env") -> None:
    """Load KEY=VALUE lines from a .env file without overriding real env vars."""
    try:
        with open(path, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except FileNotFoundError:
        return
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key.startswith("export "):
            key = key[len("export ") :]
        os.environ.setdefault(key.strip(), value.strip().strip("'\""))
