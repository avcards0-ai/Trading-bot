"""Turn a company's annual 10-K numbers (plus today's price) into comparable metrics."""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import date, timedelta

TAX_RATE = 0.21  # US statutory rate; used so return on capital is comparable across companies
GROWTH_YEARS = 3
CONSISTENCY_YEARS = 5


@dataclass
class Metrics:
    fiscal_year_end: str | None = None
    years_of_history: int = 0
    revenue: float | None = None
    net_income: float | None = None
    eps: float | None = None
    operating_income: float | None = None
    operating_cash_flow: float | None = None
    free_cash_flow: float | None = None
    total_debt: float | None = None
    cash: float | None = None
    net_debt: float | None = None
    shares_outstanding: float | None = None
    price: float | None = None
    market_cap: float | None = None
    pe: float | None = None
    # Scored metrics (see scoring.METRICS).
    roic: float | None = None
    operating_margin: float | None = None
    fcf_margin: float | None = None
    profitable_years: int | None = None
    profit_years_checked: int | None = None
    revenue_growth: float | None = None
    eps_growth: float | None = None
    net_debt_to_cash_flow: float | None = None
    share_count_change: float | None = None
    earnings_yield: float | None = None
    fcf_yield: float | None = None
    notes: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return asdict(self)


def _at(series: dict[str, float], when: date, tolerance_days: int = 45) -> float | None:
    """The value whose period ends closest to `when`, within the tolerance."""
    best = None
    for key, value in series.items():
        gap = abs((date.fromisoformat(key) - when).days)
        if gap <= tolerance_days and (best is None or gap < best[0]):
            best = (gap, value)
    return None if best is None else best[1]


def _cagr(start: float | None, end: float | None, years: float) -> float | None:
    if start is None or end is None or start <= 0 or end <= 0 or years <= 0:
        return None
    return (end / start) ** (1 / years) - 1


def compute(financials: dict, price: float | None) -> Metrics:
    """Compute metrics from `sources.sec.extract_financials` output."""
    s = financials.get("series") or {}
    revenue = s.get("revenue") or {}
    m = Metrics(price=price)
    if not revenue:
        m.notes.append("No annual revenue reported in 10-K filings.")
        return m

    fy = date.fromisoformat(max(revenue))
    m.fiscal_year_end = fy.isoformat()
    m.years_of_history = sum(1 for k in revenue if date.fromisoformat(k) <= fy)

    def now(name: str) -> float | None:
        return _at(s.get(name) or {}, fy)

    def ago(name: str, years: int) -> tuple[float | None, float]:
        """Value about `years` fiscal years back, and the exact years elapsed."""
        target = fy - timedelta(days=round(365.25 * years))
        series = s.get(name) or {}
        value = _at(series, target)
        if value is None:
            return None, 0.0
        key = min(series, key=lambda k: abs((date.fromisoformat(k) - target).days))
        return value, (fy - date.fromisoformat(key)).days / 365.25

    m.revenue = now("revenue")
    m.net_income = now("net_income")
    m.eps = now("eps_diluted")
    m.operating_income = now("operating_income")
    m.operating_cash_flow = now("operating_cash_flow")
    capex = now("capex")

    if m.operating_cash_flow is not None and capex is not None:
        m.free_cash_flow = m.operating_cash_flow - abs(capex)
    elif m.operating_cash_flow is not None:
        m.notes.append("No capital spending reported, so free cash flow wasn't checked.")

    # Balance sheet at fiscal year end.
    debt_total = now("debt_total")
    if debt_total is None:
        parts = [now("debt_noncurrent"), now("debt_current")]
        debt_total = sum(p for p in parts if p is not None) if any(p is not None for p in parts) else None
    borrowings = now("short_term_borrowings")
    if debt_total is None and borrowings is None:
        m.total_debt = 0.0  # companies with no debt usually report no debt tags at all
    else:
        m.total_debt = (debt_total or 0.0) + (borrowings or 0.0)
    cash = now("cash")
    investments = now("short_term_investments")
    m.cash = (cash or 0.0) + (investments or 0.0)
    m.net_debt = m.total_debt - m.cash
    equity = now("equity")

    # Quality.
    if m.revenue and m.revenue > 0:
        if m.operating_income is not None:
            m.operating_margin = m.operating_income / m.revenue
        if m.free_cash_flow is not None:
            m.fcf_margin = m.free_cash_flow / m.revenue
    if m.operating_income is not None and equity is not None:
        invested = equity + m.total_debt - m.cash
        if invested > 0:
            m.roic = m.operating_income * (1 - TAX_RATE) / invested
        else:
            m.notes.append("Invested capital is negative (often from heavy buybacks), so return on capital wasn't scored.")
    income = s.get("net_income") or {}
    recent = sorted((k for k in income if date.fromisoformat(k) <= fy), reverse=True)[:CONSISTENCY_YEARS]
    if len(recent) >= 3:
        m.profitable_years = sum(1 for k in recent if income[k] > 0)
        m.profit_years_checked = len(recent)

    # Growth.
    old_revenue, years = ago("revenue", GROWTH_YEARS)
    m.revenue_growth = _cagr(old_revenue, m.revenue, years)
    old_eps, years = ago("eps_diluted", GROWTH_YEARS)
    m.eps_growth = _cagr(old_eps, m.eps, years)
    if old_eps is not None and old_eps <= 0 and m.eps and m.eps > 0:
        m.notes.append("Earnings per share were negative three years ago, so EPS growth can't be measured.")

    # Financial strength.
    if m.operating_cash_flow and m.operating_cash_flow > 0:
        m.net_debt_to_cash_flow = m.net_debt / m.operating_cash_flow
    old_shares, _ = ago("diluted_shares", GROWTH_YEARS)
    shares_now = now("diluted_shares")
    if old_shares and shares_now:
        m.share_count_change = shares_now / old_shares - 1

    # Valuation needs today's price.
    so = financials.get("shares_outstanding")
    m.shares_outstanding = (so or {}).get("value") or shares_now
    if price:
        if m.shares_outstanding:
            m.market_cap = price * m.shares_outstanding
        if m.eps is not None:
            m.earnings_yield = m.eps / price
        elif m.net_income is not None and m.market_cap:
            m.earnings_yield = m.net_income / m.market_cap
        if m.earnings_yield and m.earnings_yield > 0:
            m.pe = 1 / m.earnings_yield
        if m.free_cash_flow is not None and m.market_cap:
            m.fcf_yield = m.free_cash_flow / m.market_cap
    return m
