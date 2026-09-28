"""Tunable thresholds and environment loading."""

from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass
class ScanThresholds:
    """Limits used when scoring a token before you buy."""

    min_liquidity_usd: float = 10_000
    critical_liquidity_usd: float = 2_000
    top10_warn_pct: float = 30
    top10_danger_pct: float = 50
    single_holder_warn_pct: float = 10
    single_holder_danger_pct: float = 20
    lp_locked_warn_pct: float = 90
    lp_locked_danger_pct: float = 50
    transfer_fee_danger_pct: float = 10
    new_pair_minutes: float = 60
    # This many buys with zero sells in the last hour looks like a honeypot.
    honeypot_min_buys: int = 30
    price_crash_1h_pct: float = 50


@dataclass
class GuardSettings:
    """Limits used when watching tokens you already hold."""

    poll_interval: float = 30
    rugcheck_interval: float = 300
    rugcheck_spacing: float = 1.0
    window_minutes: float = 10
    liquidity_drop_pct: float = 40
    price_drop_pct: float = 50
    lp_unlock_drop_pts: float = 20
    whale_min_pct: float = 3
    whale_sell_fraction: float = 0.5
    alert_cooldown: float = 600
    missing_polls_before_alert: int = 2


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
