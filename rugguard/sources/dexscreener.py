"""DexScreener market data (price, liquidity, trade counts) for Solana tokens.

Docs: https://docs.dexscreener.com/api/reference
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable, Iterable

from ..net import get_json

BASE_URL = "https://api.dexscreener.com"
CHAIN_ID = "solana"
MAX_BATCH = 30  # the /tokens endpoint accepts up to 30 addresses per call


@dataclass
class PairSnapshot:
    pair_address: str
    dex_id: str
    url: str
    symbol: str
    name: str
    price_usd: float | None
    liquidity_usd: float
    market_cap: float | None
    created_at: float | None  # unix seconds
    buys_m5: int
    sells_m5: int
    buys_h1: int
    sells_h1: int
    price_change_m5: float | None
    price_change_h1: float | None
    price_change_h24: float | None


@dataclass
class TokenMarket:
    """All pairs for one token, summarised by its deepest pair."""

    mint: str
    best: PairSnapshot
    total_liquidity_usd: float
    pair_count: int


def _num(value: Any) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _int(value: Any) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def parse_pair(raw: dict) -> PairSnapshot:
    base = raw.get("baseToken") or {}
    txns = raw.get("txns") or {}
    change = raw.get("priceChange") or {}
    created_ms = _num(raw.get("pairCreatedAt"))
    return PairSnapshot(
        pair_address=raw.get("pairAddress") or "",
        dex_id=raw.get("dexId") or "",
        url=raw.get("url") or "",
        symbol=base.get("symbol") or "",
        name=base.get("name") or "",
        price_usd=_num(raw.get("priceUsd")),
        liquidity_usd=_num((raw.get("liquidity") or {}).get("usd")) or 0.0,
        market_cap=_num(raw.get("marketCap")) or _num(raw.get("fdv")),
        created_at=created_ms / 1000 if created_ms else None,
        buys_m5=_int((txns.get("m5") or {}).get("buys")),
        sells_m5=_int((txns.get("m5") or {}).get("sells")),
        buys_h1=_int((txns.get("h1") or {}).get("buys")),
        sells_h1=_int((txns.get("h1") or {}).get("sells")),
        price_change_m5=_num(change.get("m5")),
        price_change_h1=_num(change.get("h1")),
        price_change_h24=_num(change.get("h24")),
    )


def group_pairs(raw_pairs: Iterable[dict], mints: Iterable[str]) -> dict[str, TokenMarket]:
    """Group raw pairs by the token they trade, keeping only the given mints.

    Only pairs where the token is the base token are used, so a mint's price
    is always quoted in USD per that token.
    """
    wanted = set(mints)
    grouped: dict[str, list[PairSnapshot]] = {}
    for raw in raw_pairs:
        if not isinstance(raw, dict) or raw.get("chainId", CHAIN_ID) != CHAIN_ID:
            continue
        mint = (raw.get("baseToken") or {}).get("address")
        if mint in wanted:
            grouped.setdefault(mint, []).append(parse_pair(raw))

    markets = {}
    for mint, pairs in grouped.items():
        # De-duplicate: the same pair can appear in more than one batch.
        unique = {p.pair_address: p for p in pairs}.values()
        best = max(unique, key=lambda p: p.liquidity_usd)
        markets[mint] = TokenMarket(
            mint=mint,
            best=best,
            total_liquidity_usd=sum(p.liquidity_usd for p in unique),
            pair_count=len(unique),
        )
    return markets


def fetch_markets(
    mints: Iterable[str], fetch: Callable[[str], Any] = get_json
) -> dict[str, TokenMarket]:
    """Fetch market data for any number of mints, 30 per request.

    Mints with no DEX pair are simply absent from the result.
    """
    mints = list(dict.fromkeys(mints))
    raw_pairs: list[dict] = []
    for i in range(0, len(mints), MAX_BATCH):
        chunk = mints[i : i + MAX_BATCH]
        data = fetch(f"{BASE_URL}/tokens/v1/{CHAIN_ID}/{','.join(chunk)}")
        # /tokens/v1 returns a list; the older /latest/dex endpoints wrap it.
        if isinstance(data, dict):
            data = data.get("pairs")
        raw_pairs.extend(data or [])
    return group_pairs(raw_pairs, mints)
