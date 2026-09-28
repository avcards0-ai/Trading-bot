"""RugCheck on-chain token report for Solana (authorities, LP locks, holders).

Docs: https://api.rugcheck.xyz/swagger/index.html
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Callable

from ..net import get_json

BASE_URL = "https://api.rugcheck.xyz/v1"

# knownAccounts types that hold tokens on behalf of a pool or locker rather
# than a person, so they don't count towards holder concentration.
_NON_HOLDER_TYPES = {"AMM", "LOCKER"}


@dataclass
class Holder:
    address: str  # token account
    owner: str  # wallet that controls the token account
    pct: float  # percent of supply, 0-100
    insider: bool = False


@dataclass
class Risk:
    name: str
    description: str
    level: str  # "danger", "warn", or "info"


@dataclass
class RugCheckReport:
    mint: str
    name: str = ""
    symbol: str = ""
    creator: str | None = None
    mint_authority: str | None = None
    freeze_authority: str | None = None
    metadata_mutable: bool = False
    transfer_fee_pct: float = 0.0
    lp_locked_pct: float | None = None
    rugged: bool = False
    holders: list[Holder] = field(default_factory=list)
    total_holders: int | None = None
    insiders_detected: int = 0
    risks: list[Risk] = field(default_factory=list)
    score_normalised: float | None = None


def _num(value: Any) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _lp_locked_pct(raw: dict) -> float | None:
    """Percent of LP locked or burned, taken from the deepest market."""
    top_level = _num(raw.get("lpLockedPct"))
    if top_level is not None:
        return top_level

    best_pct, best_depth = None, -1.0
    for market in raw.get("markets") or []:
        lp = market.get("lp") or {}
        pct = _num(lp.get("lpLockedPct"))
        if pct is None:
            continue
        depth = (_num(lp.get("baseUSD")) or 0) + (_num(lp.get("quoteUSD")) or 0)
        if depth > best_depth:
            best_pct, best_depth = pct, depth
    return best_pct


def _non_holder_accounts(raw: dict) -> set[str]:
    accounts = set()
    for address, info in (raw.get("knownAccounts") or {}).items():
        if (info or {}).get("type") in _NON_HOLDER_TYPES:
            accounts.add(address)
    for market in raw.get("markets") or []:
        for key in ("pubkey", "liquidityAAccount", "liquidityBAccount"):
            if market.get(key):
                accounts.add(market[key])
    return accounts


def parse_report(raw: dict, mint: str) -> RugCheckReport:
    token = raw.get("token") or {}
    meta = raw.get("tokenMeta") or {}
    fee = raw.get("transferFee") or {}

    excluded = _non_holder_accounts(raw)
    holders = []
    for h in raw.get("topHolders") or []:
        address, owner = h.get("address") or "", h.get("owner") or ""
        if address in excluded or owner in excluded:
            continue
        holders.append(
            Holder(
                address=address,
                owner=owner,
                pct=_num(h.get("pct")) or 0.0,
                insider=bool(h.get("insider")),
            )
        )
    holders.sort(key=lambda h: h.pct, reverse=True)

    risks = [
        Risk(
            name=r.get("name") or "",
            description=r.get("description") or "",
            level=(r.get("level") or "").lower(),
        )
        for r in raw.get("risks") or []
    ]

    return RugCheckReport(
        mint=raw.get("mint") or mint,
        name=meta.get("name") or "",
        symbol=meta.get("symbol") or "",
        creator=raw.get("creator"),
        mint_authority=raw.get("mintAuthority", token.get("mintAuthority")),
        freeze_authority=raw.get("freezeAuthority", token.get("freezeAuthority")),
        metadata_mutable=bool(meta.get("mutable")),
        transfer_fee_pct=_num(fee.get("pct")) or 0.0,
        lp_locked_pct=_lp_locked_pct(raw),
        rugged=bool(raw.get("rugged")),
        holders=holders,
        total_holders=raw.get("totalHolders"),
        insiders_detected=int(_num(raw.get("graphInsidersDetected")) or 0),
        risks=risks,
        score_normalised=_num(raw.get("score_normalised")),
    )


def fetch_report(mint: str, fetch: Callable[[str], Any] = get_json) -> RugCheckReport:
    return parse_report(fetch(f"{BASE_URL}/tokens/{mint}/report") or {}, mint)
