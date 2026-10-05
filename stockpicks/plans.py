"""Who sees what: visitors, Basic subscribers and Premium subscribers."""

from __future__ import annotations

from .config import Settings
from .db import User

VISITOR, BASIC, PREMIUM = "visitor", "basic", "premium"


def tier_for(user: User | None, settings: Settings) -> str:
    if user is None or not user.has_access:
        return VISITOR
    if settings.premium_offered and (user.comped or user.plan == PREMIUM):
        return PREMIUM
    return BASIC


def pick_limit(tier: str, settings: Settings) -> int:
    """How many of the ranked picks this tier unlocks (free picks aside)."""
    return {VISITOR: 0, BASIC: settings.picks_count, PREMIUM: settings.total_picks}[tier]


def free_tickers(data: dict | None, settings: Settings) -> set[str]:
    """The lowest-ranked picks of the Basic list, which anyone can see.

    Nothing is free if that would give away the whole Basic list.
    """
    if not data or settings.free_picks <= 0:
        return set()
    basic = sorted(
        (s for s in data["stocks"] if s.get("rank") and s["rank"] <= settings.picks_count),
        key=lambda s: s["rank"],
    )
    if len(basic) <= settings.free_picks:
        return set()
    return {s["ticker"] for s in basic[-settings.free_picks:]}


def can_view(stock: dict, tier: str, settings: Settings, free: set[str]) -> bool:
    """Whether this tier may open a stock's scorecard."""
    if tier == PREMIUM or stock["ticker"] in free:
        return True
    rank = stock.get("rank")
    return tier == BASIC and rank is not None and rank <= settings.picks_count
