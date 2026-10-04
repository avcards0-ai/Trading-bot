"""Rank companies on quality, growth, financial strength and value.

Every metric is turned into a percentile (0-100) against all covered companies,
so a score of 90 means "better than 90% of the list". Factor scores average
their metrics, and the overall score weights the four factors. A company with
any red flag stays visible but can't make the picks list.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from typing import Callable

from .fmt import money, pct
from .metrics import Metrics

FACTORS: dict[str, tuple[str, float, str]] = {
    "quality": ("Quality", 0.30, "How profitable the business is and how much cash it throws off."),
    "growth": ("Growth", 0.25, "How fast sales and earnings per share have grown over three years."),
    "strength": ("Financial strength", 0.20, "How easily it can carry its debt, and whether it shrinks or dilutes its share count."),
    "value": ("Value", 0.25, "How much you pay today for each dollar of earnings and free cash flow."),
}


@dataclass(frozen=True)
class MetricSpec:
    key: str
    factor: str
    label: str
    higher_is_better: bool
    strength: Callable[[float, Metrics], str | None]
    concern: Callable[[float, Metrics], str | None]


def _roic_good(v, m):
    return f"Earns {pct(v)} a year after tax on the money invested in the business." if v >= 0.12 else None


def _roic_bad(v, m):
    if v < 0:
        return "Loses money on the capital invested in the business."
    return f"Earns only {pct(v)} a year on the money invested in the business." if v < 0.08 else None


def _margin_good(v, m):
    return f"Keeps {pct(v)} of every sales dollar as operating profit." if v >= 0.12 else None


def _margin_bad(v, m):
    if v < 0:
        return f"Operating loss of {pct(-v)} of sales."
    return f"Thin operating margin: {pct(v)} of sales." if v < 0.08 else None


def _fcf_margin_good(v, m):
    return f"Turns {pct(v)} of its sales into free cash." if v >= 0.08 else None


def _fcf_margin_bad(v, m):
    if v < 0:
        return "Spends more cash than the business brings in."
    return f"Only {pct(v)} of sales ends up as free cash." if v < 0.04 else None


def _profit_good(v, m):
    n = m.profit_years_checked
    return f"Made a profit in each of the last {n} years." if n and v == n else None


def _profit_bad(v, m):
    n = m.profit_years_checked
    if not n or v >= n:
        return None
    losses = n - int(v)
    return f"Lost money in {losses} of the last {n} years."


def _growth_good(what):
    def f(v, m):
        return f"{what} grew {pct(v)} a year over the last 3 years." if v >= 0.05 else None
    return f


def _growth_bad(what):
    def f(v, m):
        if v < 0:
            return f"{what} shrank {pct(-v)} a year over the last 3 years."
        return f"{what} grew only {pct(v)} a year over the last 3 years." if v < 0.03 else None
    return f


def _debt_good(v, m):
    if v <= 0:
        return f"Has more cash than debt ({money(-(m.net_debt or 0))} net cash)."
    return f"Could pay off all its debt with {v:.1f} years of cash flow." if v <= 1.5 else None


def _debt_bad(v, m):
    return f"Debt equals {v:.1f} years of operating cash flow." if v > 2.5 else None


def _shares_good(v, m):
    return f"Bought back {pct(-v, 1)} of its shares over 3 years, so each share owns more." if v < -0.01 else None


def _shares_bad(v, m):
    return f"Share count grew {pct(v, 1)} over 3 years, diluting owners." if v > 0.02 else None


def _ey_good(v, m):
    return f"Reasonably priced at {m.pe:.0f}× earnings." if m.pe and m.pe <= 25 else None


def _ey_bad(v, m):
    return f"Expensive at {m.pe:.0f}× earnings." if m.pe and m.pe >= 35 else None


def _fcfy_good(v, m):
    return f"Free cash flow is {pct(v, 1)} of its market value each year." if v >= 0.04 else None


def _fcfy_bad(v, m):
    if v < 0:
        return None  # already covered by the free-cash-flow margin
    return f"Free cash flow is only {pct(v, 1)} of its market value." if v < 0.025 else None


METRICS = [
    MetricSpec("roic", "quality", "Return on invested capital", True, _roic_good, _roic_bad),
    MetricSpec("operating_margin", "quality", "Operating margin", True, _margin_good, _margin_bad),
    MetricSpec("fcf_margin", "quality", "Free cash flow margin", True, _fcf_margin_good, _fcf_margin_bad),
    MetricSpec("profitable_years", "quality", "Profitable years (of last 5)", True, _profit_good, _profit_bad),
    MetricSpec("revenue_growth", "growth", "Sales growth (3-yr, per year)", True, _growth_good("Sales"), _growth_bad("Sales")),
    MetricSpec("eps_growth", "growth", "EPS growth (3-yr, per year)", True,
               _growth_good("Earnings per share"), _growth_bad("Earnings per share")),
    MetricSpec("net_debt_to_cash_flow", "strength", "Net debt ÷ operating cash flow", False, _debt_good, _debt_bad),
    MetricSpec("share_count_change", "strength", "Share count change (3 yrs)", False, _shares_good, _shares_bad),
    MetricSpec("earnings_yield", "value", "Earnings yield (1 ÷ P/E)", True, _ey_good, _ey_bad),
    MetricSpec("fcf_yield", "value", "Free cash flow yield", True, _fcfy_good, _fcfy_bad),
]

STALE_DAYS = 550
MAX_DEBT_YEARS = 4.0
SHRINKING_SALES = -0.05
MIN_YEARS_OF_HISTORY = 4


def percentile(value: float, population: list[float]) -> float:
    """Share of the population below `value` (ties count half), as 0-100."""
    if not population:
        return 50.0
    below = sum(1 for p in population if p < value)
    equal = sum(1 for p in population if p == value)
    return 100.0 * (below + 0.5 * equal) / len(population)


def coverage_problem(m: Metrics) -> str | None:
    """Why a company can't be scored at all, or None if it can."""
    if m.fiscal_year_end is None:
        return "No annual (10-K) financial data. Foreign companies that file 20-F reports aren't covered."
    if m.years_of_history < MIN_YEARS_OF_HISTORY:
        return f"Only {m.years_of_history} years of reported results; at least {MIN_YEARS_OF_HISTORY} are needed."
    if m.revenue is None or m.net_income is None:
        return "Latest annual report is missing revenue or net income."
    return None


def red_flags(m: Metrics, min_market_cap: float, today: date) -> list[str]:
    flags = []
    if m.price is None:
        flags.append("Couldn't get a current share price, so its valuation wasn't checked.")
    if m.fiscal_year_end and (today - date.fromisoformat(m.fiscal_year_end)).days > STALE_DAYS:
        flags.append("No new annual report in the last 18 months.")
    if m.net_income is not None and m.net_income < 0:
        flags.append("Lost money in its latest fiscal year.")
    if m.free_cash_flow is not None and m.free_cash_flow < 0:
        flags.append("Burned cash in its latest fiscal year (negative free cash flow).")
    if m.net_debt is not None and m.net_debt > 0:
        ocf = m.operating_cash_flow
        if ocf is None or ocf <= 0 or m.net_debt / ocf > MAX_DEBT_YEARS:
            flags.append(f"Debt is more than {MAX_DEBT_YEARS:.0f} years of operating cash flow.")
    if m.revenue_growth is not None and m.revenue_growth < SHRINKING_SALES:
        flags.append(f"Sales have been shrinking more than {pct(-SHRINKING_SALES)} a year.")
    if m.market_cap is not None and m.market_cap < min_market_cap:
        flags.append(f"Smaller than our {money(min_market_cap)} minimum market value.")
    return flags


def _summary(factors: dict[str, float]) -> str:
    ordered = sorted(factors, key=lambda f: factors[f], reverse=True)
    strong = [FACTORS[f][0].lower() for f in ordered if factors[f] >= 65][:2]
    weakest = ordered[-1]
    parts = []
    if strong:
        parts.append("Stands out on " + " and ".join(strong) + ".")
    else:
        parts.append("A balanced profile without a standout strength.")
    if factors[weakest] < 40:
        parts.append(f"Weakest on {FACTORS[weakest][0].lower()}.")
    return " ".join(parts)


def score_all(
    companies: list[dict],
    min_market_cap: float,
    picks_count: int,
    today: date,
) -> tuple[list[dict], list[dict]]:
    """Score companies and pick the best.

    Each input dict has "ticker", "name", "metrics" (a Metrics) and optionally
    "warnings" (sentences about recent filings) plus any extra keys to pass
    through. Returns (scored, not_covered); scored is sorted best first and
    picks carry a "rank".
    """
    covered, not_covered = [], []
    for c in companies:
        problem = coverage_problem(c["metrics"])
        if problem:
            not_covered.append({"ticker": c["ticker"], "name": c["name"], "reason": problem})
        else:
            covered.append(c)

    populations = {
        spec.key: [getattr(c["metrics"], spec.key) for c in covered if getattr(c["metrics"], spec.key) is not None]
        for spec in METRICS
    }

    scored = []
    for c in covered:
        m: Metrics = c["metrics"]
        percentiles: dict[str, float] = {}
        strengths: list[tuple[float, str]] = []
        concerns: list[tuple[float, str]] = []
        for spec in METRICS:
            value = getattr(m, spec.key)
            if value is None:
                continue
            p = percentile(value, populations[spec.key])
            if not spec.higher_is_better:
                p = 100.0 - p
            percentiles[spec.key] = round(p, 1)
            # Strengths must stand out against the list. Concerns need an
            # absolute problem (a 50x P/E is worth knowing about even if
            # peers are pricier) but never contradict an above-average rank.
            if p >= 70 and (text := spec.strength(value, m)):
                strengths.append((p, text))
            elif p <= 50 and (text := spec.concern(value, m)):
                concerns.append((p, text))

        factors = {}
        for factor in FACTORS:
            values = [percentiles[s.key] for s in METRICS if s.factor == factor and s.key in percentiles]
            # A factor with no data counts as average rather than helping or hurting.
            factors[factor] = round(sum(values) / len(values), 1) if values else 50.0
        total = sum(factors[f] * FACTORS[f][1] for f in FACTORS)

        flags = red_flags(m, min_market_cap, today)
        out = {k: v for k, v in c.items() if k not in ("metrics", "warnings")}
        out.update(
            score=round(total, 1),
            factors=factors,
            percentiles=percentiles,
            metrics=m.to_dict(),
            strengths=[t for _, t in sorted(strengths, reverse=True)],
            concerns=[t for _, t in sorted(concerns)] + list(c.get("warnings") or []),
            red_flags=flags,
            eligible=not flags,
            summary=_summary(factors),
            rank=None,
        )
        scored.append(out)

    scored.sort(key=lambda s: (-s["score"], s["ticker"]))
    rank = 0
    for i, s in enumerate(scored, start=1):
        s["overall_rank"] = i
        if s["eligible"] and rank < picks_count:
            rank += 1
            s["rank"] = rank
    not_covered.sort(key=lambda n: n["ticker"])
    return scored, not_covered
