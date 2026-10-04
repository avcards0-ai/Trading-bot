"""SEC EDGAR: company list, recent filings and reported financials.

Everything here is public-domain data published by the SEC. Docs:
https://www.sec.gov/search-filings/edgar-application-programming-interfaces

EDGAR's fair-access policy allows up to 10 requests per second and requires a
User-Agent that names you and gives a contact email.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from typing import Any

TICKERS_URL = "https://www.sec.gov/files/company_tickers.json"
SUBMISSIONS_URL = "https://data.sec.gov/submissions/CIK{cik:010d}.json"
FACTS_URL = "https://data.sec.gov/api/xbrl/companyfacts/CIK{cik:010d}.json"
ARCHIVES_URL = "https://www.sec.gov/Archives/edgar/data/{cik}/{folder}/{doc}"

# Forms worth showing a reader, newest first.
SHOWN_FORMS = ("10-K", "10-K/A", "10-Q", "10-Q/A", "8-K", "8-K/A")
PERIODIC_FORMS = ("10-K", "10-K/A", "10-Q", "10-Q/A")

# Plain-English names for the 8-K items people care about.
EIGHT_K_ITEMS = {
    "1.01": "Signed a major agreement",
    "1.02": "Ended a major agreement",
    "1.03": "Bankruptcy or receivership",
    "1.05": "Cybersecurity incident",
    "2.01": "Completed an acquisition or sale",
    "2.02": "Reported results",
    "2.03": "Took on new debt",
    "2.05": "Restructuring or layoffs",
    "2.06": "Wrote down assets",
    "3.01": "Listing problem with its exchange",
    "4.01": "Changed auditor",
    "4.02": "Said past financials can't be relied on",
    "5.02": "Executive or board change",
    "5.03": "Changed bylaws or fiscal year",
    "5.07": "Shareholder vote results",
    "7.01": "Investor presentation",
    "8.01": "Other news",
}
# 8-K items that should make a long-term investor look closer.
WARNING_ITEMS = {
    "1.03": "filed an 8-K about bankruptcy or receivership",
    "1.05": "reported a cybersecurity incident",
    "3.01": "had a problem with its stock exchange listing",
    "4.01": "changed auditors",
    "4.02": "said some past financial statements can't be relied on",
}


@dataclass
class Company:
    ticker: str
    cik: int
    name: str


@dataclass
class Filing:
    form: str
    filed: str  # YYYY-MM-DD
    report_date: str
    accession: str
    url: str
    items: list[str] = field(default_factory=list)

    @property
    def description(self) -> str:
        if self.form.startswith("10-K"):
            return "Annual report"
        if self.form.startswith("10-Q"):
            return "Quarterly report"
        named = [EIGHT_K_ITEMS[i] for i in self.items if i in EIGHT_K_ITEMS]
        return "; ".join(named) or "Current report"

    def to_dict(self) -> dict:
        return {
            "form": self.form,
            "filed": self.filed,
            "report_date": self.report_date,
            "accession": self.accession,
            "url": self.url,
            "items": self.items,
            "description": self.description,
        }


@dataclass
class Profile:
    cik: int
    name: str
    sic: int | None
    sic_description: str
    filings: list[Filing]  # shown forms only, newest first

    def to_dict(self) -> dict:
        return {
            "cik": self.cik,
            "name": self.name,
            "sic": self.sic,
            "sic_description": self.sic_description,
            "filings": [f.to_dict() for f in self.filings],
        }

    @classmethod
    def from_dict(cls, d: dict) -> "Profile":
        filings = [
            Filing(
                form=f["form"],
                filed=f["filed"],
                report_date=f.get("report_date", ""),
                accession=f["accession"],
                url=f["url"],
                items=list(f.get("items") or []),
            )
            for f in d.get("filings") or []
        ]
        return cls(d["cik"], d.get("name", ""), d.get("sic"), d.get("sic_description", ""), filings)

    def warnings(self, today: date, days: int = 365) -> list[str]:
        """Sentences about worrying 8-K items filed in the last `days` days."""
        out = []
        for f in self.filings:
            filed = _date(f.filed)
            if filed is None or (today - filed).days > days:
                continue
            for item in f.items:
                if item in WARNING_ITEMS:
                    out.append(f"On {f.filed} it {WARNING_ITEMS[item]} (form {f.form}).")
        return out

    @property
    def latest_periodic_accession(self) -> str:
        """Changes whenever a new 10-K or 10-Q is filed, so it keys the facts cache."""
        for f in self.filings:
            if f.form in PERIODIC_FORMS:
                return f.accession
        return ""


def normalize_ticker(ticker: str) -> str:
    return ticker.strip().upper().replace(".", "-")


def parse_ticker_map(raw: Any) -> dict[str, Company]:
    """Parse company_tickers.json: {"0": {"cik_str": 320193, "ticker": "AAPL", "title": ...}}."""
    rows = raw.values() if isinstance(raw, dict) else raw or []
    companies: dict[str, Company] = {}
    for row in rows:
        try:
            ticker = normalize_ticker(row["ticker"])
            companies.setdefault(ticker, Company(ticker, int(row["cik_str"]), row.get("title") or ticker))
        except (KeyError, TypeError, ValueError):
            continue
    return companies


def _filing_url(cik: int, accession: str, doc: str) -> str:
    folder = accession.replace("-", "")
    return ARCHIVES_URL.format(cik=cik, folder=folder, doc=doc or f"{accession}-index.htm")


def parse_submissions(raw: dict, limit: int = 40) -> Profile:
    """Parse data.sec.gov/submissions/CIK##########.json."""
    cik = int(raw.get("cik") or 0)
    recent = (raw.get("filings") or {}).get("recent") or {}
    forms = recent.get("form") or []

    def col(name: str, i: int) -> str:
        values = recent.get(name) or []
        return str(values[i]) if i < len(values) and values[i] is not None else ""

    filings = []
    for i, form in enumerate(forms):
        if form not in SHOWN_FORMS:
            continue
        accession = col("accessionNumber", i)
        items = [x.strip() for x in col("items", i).split(",") if x.strip()]
        filings.append(
            Filing(
                form=form,
                filed=col("filingDate", i),
                report_date=col("reportDate", i),
                accession=accession,
                url=_filing_url(cik, accession, col("primaryDocument", i)),
                items=items,
            )
        )
    filings.sort(key=lambda f: f.filed, reverse=True)
    try:
        sic = int(raw.get("sic") or 0) or None
    except (TypeError, ValueError):
        sic = None
    return Profile(
        cik=cik,
        name=raw.get("name") or "",
        sic=sic,
        sic_description=raw.get("sicDescription") or "",
        filings=filings[:limit],
    )


def is_financial(sic: int | None) -> bool:
    """Banks, insurers, brokers and REITs (SIC 6000-6799) need different yardsticks."""
    return sic is not None and 6000 <= sic <= 6799


def sector_for_sic(sic: int | None) -> str:
    if sic is None:
        return "Other"
    ranges = [
        (100, 999, "Consumer Staples"),
        (1000, 1299, "Materials"),
        (1300, 1399, "Energy"),
        (1400, 1499, "Materials"),
        (1500, 1599, "Homebuilding"),
        (1600, 1799, "Industrials"),
        (2000, 2199, "Consumer Staples"),
        (2200, 2399, "Consumer Discretionary"),
        (2400, 2799, "Materials"),
        (2800, 2829, "Materials"),
        (2830, 2836, "Health Care"),
        (2840, 2844, "Consumer Staples"),
        (2845, 2899, "Materials"),
        (2900, 2999, "Energy"),
        (3000, 3299, "Materials"),
        (3300, 3399, "Materials"),
        (3400, 3569, "Industrials"),
        (3570, 3579, "Technology"),
        (3580, 3599, "Industrials"),
        (3600, 3629, "Industrials"),
        (3630, 3659, "Consumer Discretionary"),
        (3660, 3699, "Technology"),
        (3700, 3719, "Consumer Discretionary"),
        (3720, 3799, "Industrials"),
        (3800, 3825, "Industrials"),
        (3826, 3826, "Health Care"),
        (3827, 3840, "Industrials"),
        (3841, 3851, "Health Care"),
        (3852, 3999, "Consumer Discretionary"),
        (4000, 4799, "Industrials"),
        (4800, 4899, "Communication"),
        (4900, 4999, "Utilities"),
        (5000, 5121, "Industrials"),
        (5122, 5122, "Health Care"),
        (5123, 5199, "Industrials"),
        (5200, 5399, "Consumer Discretionary"),
        (5400, 5499, "Consumer Staples"),
        (5500, 5899, "Consumer Discretionary"),
        (5900, 5911, "Consumer Discretionary"),
        (5912, 5912, "Consumer Staples"),
        (5913, 5999, "Consumer Discretionary"),
        (6000, 6799, "Financials"),
        (7000, 7369, "Consumer Discretionary"),
        (7370, 7379, "Technology"),
        (7380, 7399, "Business Services"),
        (7800, 7999, "Communication"),
        (8000, 8099, "Health Care"),
        (8700, 8799, "Business Services"),
    ]
    for low, high, name in ranges:
        if low <= sic <= high:
            return name
    return "Other"


# --- Reported financials ---------------------------------------------------

# Each series merges several XBRL tags because companies switch tags over the
# years (e.g. SalesRevenueNet before 2018, RevenueFromContract... after).
# For each fiscal year the first tag in the list that has a value wins.
DURATION_SERIES: dict[str, tuple[str, list[str]]] = {
    "revenue": ("USD", [
        "Revenues",
        "RevenueFromContractWithCustomerExcludingAssessedTax",
        "RevenueFromContractWithCustomerIncludingAssessedTax",
        "SalesRevenueNet",
        "SalesRevenueGoodsNet",
        "SalesRevenueServicesNet",
    ]),
    "net_income": ("USD", [
        "NetIncomeLoss",
        "NetIncomeLossAvailableToCommonStockholdersBasic",
        "ProfitLoss",
    ]),
    "eps_diluted": ("USD/shares", [
        "EarningsPerShareDiluted",
        "EarningsPerShareBasicAndDiluted",
        "EarningsPerShareBasic",
    ]),
    "operating_income": ("USD", ["OperatingIncomeLoss"]),
    "operating_cash_flow": ("USD", [
        "NetCashProvidedByUsedInOperatingActivities",
        "NetCashProvidedByUsedInOperatingActivitiesContinuingOperations",
    ]),
    "capex": ("USD", [
        "PaymentsToAcquirePropertyPlantAndEquipment",
        "PaymentsToAcquireProductiveAssets",
        "PaymentsToAcquireOtherPropertyPlantAndEquipment",
    ]),
    "diluted_shares": ("shares", [
        "WeightedAverageNumberOfDilutedSharesOutstanding",
        "WeightedAverageNumberOfSharesOutstandingBasic",
    ]),
}

INSTANT_SERIES: dict[str, tuple[str, list[str]]] = {
    "assets": ("USD", ["Assets"]),
    "equity": ("USD", [
        "StockholdersEquity",
        "StockholdersEquityIncludingPortionAttributableToNoncontrollingInterest",
    ]),
    "cash": ("USD", [
        "CashAndCashEquivalentsAtCarryingValue",
        "CashCashEquivalentsRestrictedCashAndRestrictedCashEquivalents",
        "Cash",
    ]),
    "short_term_investments": ("USD", [
        "ShortTermInvestments",
        "MarketableSecuritiesCurrent",
        "AvailableForSaleSecuritiesDebtSecuritiesCurrent",
    ]),
    "debt_total": ("USD", ["LongTermDebt"]),
    "debt_noncurrent": ("USD", [
        "LongTermDebtNoncurrent",
        "LongTermDebtAndCapitalLeaseObligations",
    ]),
    "debt_current": ("USD", [
        "LongTermDebtCurrent",
        "LongTermDebtAndCapitalLeaseObligationsCurrent",
    ]),
    "short_term_borrowings": ("USD", ["ShortTermBorrowings", "CommercialPaper"]),
}


def _date(value: Any) -> date | None:
    try:
        return date.fromisoformat(str(value)[:10])
    except ValueError:
        return None


def _annual_points(points: list[dict], duration: bool) -> dict[str, float]:
    """Keep 10-K values covering one fiscal year, keyed by period end.

    A 10-K repeats prior years as comparatives, and amendments restate them,
    so for each period end the most recently filed value wins.
    """
    best: dict[str, tuple[str, float]] = {}
    for p in points:
        if not str(p.get("form", "")).startswith("10-K"):
            continue
        end = _date(p.get("end"))
        if end is None or not isinstance(p.get("val"), (int, float)):
            continue
        if duration:
            start = _date(p.get("start"))
            if start is None or not 350 <= (end - start).days <= 380:
                continue
        elif p.get("start"):
            continue
        filed = str(p.get("filed", ""))
        key = end.isoformat()
        if key not in best or filed >= best[key][0]:
            best[key] = (filed, float(p["val"]))
    return {k: v for k, (_, v) in best.items()}


def _merge_tags(gaap: dict, unit: str, tags: list[str], duration: bool) -> dict[str, float]:
    merged: dict[str, float] = {}
    for tag in tags:
        points = ((gaap.get(tag) or {}).get("units") or {}).get(unit) or []
        for end, val in _annual_points(points, duration).items():
            merged.setdefault(end, val)
    return dict(sorted(merged.items()))


def _latest_shares_outstanding(facts: dict) -> dict | None:
    """Cover-page share count from the newest filing of any kind."""
    points = (
        ((facts.get("dei") or {}).get("EntityCommonStockSharesOutstanding") or {})
        .get("units", {})
        .get("shares")
        or []
    )
    best = None
    for p in points:
        if not isinstance(p.get("val"), (int, float)) or p["val"] <= 0 or _date(p.get("end")) is None:
            continue
        key = (str(p["end"]), str(p.get("filed", "")))
        if best is None or key > best[0]:
            best = (key, p)
    if best is None:
        return None
    return {"date": best[1]["end"], "value": float(best[1]["val"])}


def extract_financials(raw_facts: dict) -> dict:
    """Reduce data.sec.gov/api/xbrl/companyfacts (several MB) to the annual series we use.

    Returns {"series": {name: {"YYYY-MM-DD": value}}, "shares_outstanding": {...} | None}.
    """
    facts = raw_facts.get("facts") or {}
    gaap = facts.get("us-gaap") or {}
    series = {}
    for name, (unit, tags) in DURATION_SERIES.items():
        series[name] = _merge_tags(gaap, unit, tags, duration=True)
    for name, (unit, tags) in INSTANT_SERIES.items():
        series[name] = _merge_tags(gaap, unit, tags, duration=False)
    return {"series": series, "shares_outstanding": _latest_shares_outstanding(facts)}
