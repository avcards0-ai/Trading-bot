"""Pre-buy rug-pull scan: combine on-chain and market signals into a risk score."""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from enum import IntEnum
from typing import Any, Callable

from .config import ScanThresholds
from .net import FetchError, get_json
from .sources.dexscreener import TokenMarket, fetch_markets
from .sources.rugcheck import RugCheckReport, fetch_report


class Severity(IntEnum):
    """Each value is the number of points a finding adds to the risk score."""

    INFO = 0
    LOW = 5
    MEDIUM = 15
    HIGH = 35
    CRITICAL = 100


@dataclass
class Finding:
    severity: Severity
    code: str
    message: str


@dataclass
class ScanResult:
    mint: str
    name: str
    symbol: str
    score: int
    verdict: str
    findings: list[Finding]
    report: RugCheckReport | None = None
    market: TokenMarket | None = None
    errors: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        m = self.market
        return {
            "mint": self.mint,
            "name": self.name,
            "symbol": self.symbol,
            "score": self.score,
            "verdict": self.verdict,
            "findings": [
                {"severity": f.severity.name, "code": f.code, "message": f.message}
                for f in self.findings
            ],
            "market": None
            if m is None
            else {
                "liquidity_usd": m.total_liquidity_usd,
                "pair_count": m.pair_count,
                "price_usd": m.best.price_usd,
                "market_cap": m.best.market_cap,
                "dex": m.best.dex_id,
                "url": m.best.url,
            },
            "errors": self.errors,
        }


# RugCheck risk names containing these are already covered by our own checks,
# so they're skipped to avoid counting the same problem twice.
_COVERED_RISKS = (
    "mint authority",
    "freeze authority",
    "lp unlocked",
    "liquidity",
    "holder",
    "ownership",
    "mutable metadata",
    "transfer fee",
)

_RISK_LEVELS = {"danger": Severity.HIGH, "warn": Severity.MEDIUM}


def short(address: str) -> str:
    return f"{address[:4]}…{address[-4:]}" if len(address) > 12 else address


def _report_findings(r: RugCheckReport, t: ScanThresholds) -> list[Finding]:
    out = []
    if r.rugged:
        out.append(Finding(Severity.CRITICAL, "RUGGED", "RugCheck flags this token as already rugged."))
    if r.mint_authority:
        out.append(Finding(
            Severity.HIGH, "MINT_AUTHORITY",
            "Mint authority is still enabled, so the dev can print more tokens and dump them on you.",
        ))
    if r.freeze_authority:
        out.append(Finding(
            Severity.HIGH, "FREEZE_AUTHORITY",
            "Freeze authority is still enabled, so your tokens can be frozen and you won't be able to sell.",
        ))

    if r.lp_locked_pct is not None:
        pct = r.lp_locked_pct
        if pct < t.lp_locked_danger_pct:
            out.append(Finding(
                Severity.HIGH, "LP_UNLOCKED",
                f"Only {pct:.0f}% of liquidity is locked or burned, so the dev can pull the pool.",
            ))
        elif pct < t.lp_locked_warn_pct:
            out.append(Finding(
                Severity.MEDIUM, "LP_PARTLY_UNLOCKED",
                f"{pct:.0f}% of liquidity is locked or burned; the rest can be withdrawn.",
            ))

    if r.transfer_fee_pct > 0:
        sev = Severity.HIGH if r.transfer_fee_pct >= t.transfer_fee_danger_pct else Severity.MEDIUM
        out.append(Finding(
            sev, "TRANSFER_FEE",
            f"Token-2022 transfer fee of {r.transfer_fee_pct:.1f}% is taken on every transfer.",
        ))

    if r.holders:
        top10 = sum(h.pct for h in r.holders[:10])
        if top10 >= t.top10_danger_pct:
            out.append(Finding(Severity.HIGH, "TOP10_CONCENTRATION", f"Top 10 wallets hold {top10:.1f}% of supply."))
        elif top10 >= t.top10_warn_pct:
            out.append(Finding(Severity.MEDIUM, "TOP10_CONCENTRATION", f"Top 10 wallets hold {top10:.1f}% of supply."))

        whale = r.holders[0]
        who = short(whale.owner or whale.address)
        if whale.pct >= t.single_holder_danger_pct:
            out.append(Finding(Severity.HIGH, "WHALE", f"One wallet ({who}) holds {whale.pct:.1f}% of supply."))
        elif whale.pct >= t.single_holder_warn_pct:
            out.append(Finding(Severity.MEDIUM, "WHALE", f"One wallet ({who}) holds {whale.pct:.1f}% of supply."))

    insiders = max(r.insiders_detected, sum(1 for h in r.holders if h.insider))
    if insiders:
        out.append(Finding(
            Severity.MEDIUM, "INSIDERS",
            f"RugCheck linked {insiders} insider wallet(s) to this token, which is a common sign of bundled dev buys.",
        ))

    if r.metadata_mutable:
        out.append(Finding(Severity.LOW, "MUTABLE_METADATA", "Metadata is mutable, so the name and image can be changed later."))

    for risk in r.risks:
        name = risk.name.lower()
        if any(k in name for k in _COVERED_RISKS):
            continue
        sev = _RISK_LEVELS.get(risk.level, Severity.LOW)
        detail = f": {risk.description}" if risk.description else ""
        out.append(Finding(sev, "RUGCHECK", f"RugCheck: {risk.name}{detail}"))
    return out


def _market_findings(m: TokenMarket, t: ScanThresholds, now: float) -> list[Finding]:
    out = []
    liq = m.total_liquidity_usd
    if liq < t.critical_liquidity_usd:
        out.append(Finding(Severity.HIGH, "LOW_LIQUIDITY", f"Only ${liq:,.0f} of liquidity, which is easy to drain and hard to exit."))
    elif liq < t.min_liquidity_usd:
        out.append(Finding(Severity.MEDIUM, "LOW_LIQUIDITY", f"Only ${liq:,.0f} of liquidity."))

    b = m.best
    if b.created_at:
        age_min = (now - b.created_at) / 60
        if age_min < t.new_pair_minutes:
            out.append(Finding(Severity.MEDIUM, "NEW_PAIR", f"Pair is only {max(age_min, 0):.0f} minutes old."))
        elif age_min < 24 * 60:
            out.append(Finding(Severity.LOW, "NEW_PAIR", f"Pair is only {age_min / 60:.1f} hours old."))

    if b.buys_h1 >= t.honeypot_min_buys and b.sells_h1 == 0:
        out.append(Finding(
            Severity.HIGH, "NO_SELLS",
            f"{b.buys_h1} buys and 0 sells in the last hour, which may mean it's a honeypot.",
        ))

    if b.price_change_h1 is not None and b.price_change_h1 <= -t.price_crash_1h_pct:
        out.append(Finding(Severity.HIGH, "PRICE_CRASH", f"Price is down {abs(b.price_change_h1):.0f}% in the last hour."))
    return out


def verdict_for(score: int, findings: list[Finding]) -> str:
    if score >= 70 or any(f.severity == Severity.CRITICAL for f in findings):
        return "AVOID"
    if score >= 35:
        return "HIGH RISK"
    if score >= 15:
        return "CAUTION"
    return "NO MAJOR RED FLAGS"


def evaluate(
    mint: str,
    report: RugCheckReport | None,
    market: TokenMarket | None,
    thresholds: ScanThresholds | None = None,
    now: float | None = None,
    report_error: str | None = None,
    market_error: str | None = None,
) -> ScanResult:
    """Score a token from already-fetched data. Pure, so it's easy to test."""
    t = thresholds or ScanThresholds()
    now = time.time() if now is None else now
    findings: list[Finding] = []

    if report is not None:
        findings += _report_findings(report, t)
    else:
        # Unknown authorities are a risk in themselves; never treat them as clean.
        findings.append(Finding(
            Severity.MEDIUM, "NO_ONCHAIN_DATA",
            f"Couldn't verify mint/freeze authority or LP lock ({report_error or 'no RugCheck report'}).",
        ))

    if market is not None:
        findings += _market_findings(market, t, now)
    elif market_error:
        findings.append(Finding(Severity.MEDIUM, "NO_MARKET_DATA", f"Couldn't load market data ({market_error})."))
    else:
        findings.append(Finding(
            Severity.MEDIUM, "NO_PAIR",
            "No DEX pair found. Either there's no tradable liquidity yet or it has been removed.",
        ))

    findings.sort(key=lambda f: f.severity, reverse=True)
    score = min(100, sum(int(f.severity) for f in findings))
    name = (report.name if report else "") or (market.best.name if market else "")
    symbol = (report.symbol if report else "") or (market.best.symbol if market else "")
    errors = [e for e in (report_error, market_error) if e]
    return ScanResult(
        mint=mint, name=name, symbol=symbol, score=score,
        verdict=verdict_for(score, findings), findings=findings,
        report=report, market=market, errors=errors,
    )


def scan(
    mint: str,
    thresholds: ScanThresholds | None = None,
    fetch: Callable[[str], Any] = get_json,
    now: float | None = None,
) -> ScanResult:
    """Fetch RugCheck and DexScreener data for one mint and score it."""
    report = market = None
    report_error = market_error = None
    try:
        report = fetch_report(mint, fetch=fetch)
    except FetchError as e:
        report_error = "RugCheck has no report for this mint" if e.status == 404 else f"RugCheck: {e}"
    try:
        market = fetch_markets([mint], fetch=fetch).get(mint)
    except FetchError as e:
        market_error = f"DexScreener: {e}"
    return evaluate(mint, report, market, thresholds, now, report_error, market_error)


def _usd(value: float | None) -> str:
    if value is None:
        return "?"
    for unit, size in (("B", 1e9), ("M", 1e6), ("K", 1e3)):
        if abs(value) >= size:
            return f"${value / size:,.2f}{unit}"
    if abs(value) >= 1:
        return f"${value:,.2f}"
    return f"${value:.8g}"


def format_result(result: ScanResult) -> str:
    label = result.symbol or "?"
    if result.name and result.name != result.symbol:
        label += f" ({result.name})"
    lines = [
        f"{label}  {result.mint}",
        f"  Verdict: {result.verdict}   risk score {result.score}/100",
    ]
    m = result.market
    if m is not None:
        lines.append(
            f"  Market:  {_usd(m.total_liquidity_usd)} liquidity across {m.pair_count} pair(s)"
            f" | price {_usd(m.best.price_usd)} | mcap {_usd(m.best.market_cap)} | {m.best.dex_id}"
        )
        if m.best.url:
            lines.append(f"           {m.best.url}")
    if result.findings:
        lines.append("  Findings:")
        width = max(len(f.severity.name) for f in result.findings) + 2
        for f in result.findings:
            lines.append(f"    {('[' + f.severity.name + ']').ljust(width)} {f.message}")
    else:
        lines.append("  Findings: none")
    return "\n".join(lines)
