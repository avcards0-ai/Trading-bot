"""Fixtures shaped like SEC EDGAR, Stooq and Stripe responses, for offline tests."""

from __future__ import annotations

import copy
import io
import os
import tempfile
import urllib.parse
from datetime import date

from stockpicks.config import Settings
from stockpicks.net import FetchError

TODAY = date(2026, 10, 4)
YEARS = range(2020, 2026)  # fiscal years ending Dec 31, 2020-2025


def _point(year: int, val: float, *, duration: bool, form: str = "10-K", filed: str | None = None) -> dict:
    p = {
        "end": f"{year}-12-31",
        "val": val,
        "accn": f"0000000000-{year % 100:02d}-000001",
        "fy": year,
        "fp": "FY",
        "form": form,
        "filed": filed or f"{year + 1}-02-15",
    }
    if duration:
        p["start"] = f"{year}-01-01"
    return p


def _tag(points: list[dict], unit: str = "USD") -> dict:
    return {"label": "x", "description": "x", "units": {unit: points}}


def make_facts(
    *,
    revenue0: float = 10e9,
    growth: float = 0.10,
    op_margin: float = 0.25,
    net_margin: float = 0.18,
    capex_pct: float = 0.05,
    shares0: float = 1e9,
    share_change: float = -0.02,
    cash: float = 3e9,
    debt: float = 4e9,
    equity: float = 12e9,
    loss_years: tuple[int, ...] = (),
    revenue_tag: str = "RevenueFromContractWithCustomerExcludingAssessedTax",
) -> dict:
    """A data.sec.gov companyfacts body with six fiscal years of 10-K data."""
    rev, ni, eps, oi, ocf, capex, shares = ([] for _ in range(7))
    for i, y in enumerate(YEARS):
        r = revenue0 * (1 + growth) ** i
        n = -abs(r * net_margin) if y in loss_years else r * net_margin
        s = shares0 * (1 + share_change) ** i
        rev.append(_point(y, r, duration=True))
        ni.append(_point(y, n, duration=True))
        eps.append(_point(y, n / s, duration=True))
        oi.append(_point(y, r * op_margin, duration=True))
        ocf.append(_point(y, n * 1.2 if n > 0 else n, duration=True))
        capex.append(_point(y, r * capex_pct, duration=True))
        shares.append(_point(y, s, duration=True))
    last = YEARS[-1]
    gaap = {
        revenue_tag: _tag(rev),
        "NetIncomeLoss": _tag(ni),
        "EarningsPerShareDiluted": _tag(eps, "USD/shares"),
        "OperatingIncomeLoss": _tag(oi),
        "NetCashProvidedByUsedInOperatingActivities": _tag(ocf),
        "PaymentsToAcquirePropertyPlantAndEquipment": _tag(capex),
        "WeightedAverageNumberOfDilutedSharesOutstanding": _tag(shares, "shares"),
        "StockholdersEquity": _tag([_point(y, equity, duration=False) for y in YEARS]),
        "CashAndCashEquivalentsAtCarryingValue": _tag([_point(y, cash, duration=False) for y in YEARS]),
        "LongTermDebt": _tag([_point(y, debt, duration=False) for y in YEARS]),
        "Assets": _tag([_point(y, equity + debt + cash, duration=False) for y in YEARS]),
    }
    shares_now = shares0 * (1 + share_change) ** (len(YEARS) - 1)
    dei = {
        "EntityCommonStockSharesOutstanding": _tag(
            [{"end": f"{last + 1}-07-20", "val": shares_now, "form": "10-Q", "filed": f"{last + 1}-07-30",
              "accn": "0000000000-26-000002", "fy": last + 1, "fp": "Q2"}],
            "shares",
        )
    }
    return {"cik": 1, "entityName": "Test", "facts": {"dei": dei, "us-gaap": gaap}}


def make_submissions(cik: int, name: str, sic: int = 7372, filings: list[tuple] | None = None) -> dict:
    """A data.sec.gov submissions body. filings: (form, filed, accession, items)."""
    if filings is None:
        filings = [
            ("8-K", "2026-07-25", f"0000{cik:06d}-26-000003", "2.02,9.01"),
            ("10-Q", "2026-07-30", f"0000{cik:06d}-26-000002", ""),
            ("4", "2026-06-01", f"0000{cik:06d}-26-000009", ""),
            ("10-K", "2026-02-15", f"0000{cik:06d}-26-000001", ""),
        ]
    cols = {k: [] for k in ("accessionNumber", "filingDate", "reportDate", "form", "primaryDocument", "items")}
    for form, filed, acc, items in filings:
        cols["accessionNumber"].append(acc)
        cols["filingDate"].append(filed)
        cols["reportDate"].append(filed)
        cols["form"].append(form)
        cols["primaryDocument"].append(f"doc-{acc}.htm")
        cols["items"].append(items)
    return {
        "cik": str(cik),
        "name": name,
        "sic": str(sic),
        "sicDescription": "Services-Prepackaged Software",
        "tickers": [],
        "filings": {"recent": cols, "files": []},
    }


# name, ticker, cik, sic, price, facts kwargs
UNIVERSE = [
    ("Great Compounder Inc", "GRT", 101, 7372, 300.0, dict(growth=0.15, op_margin=0.35, net_margin=0.28, cash=8e9, debt=1e9)),
    ("Steady Brands Co", "STDY", 102, 2080, 60.0, dict(growth=0.05, op_margin=0.22, net_margin=0.15)),
    ("Cheap Industrial Corp", "CHIP", 103, 3560, 40.0, dict(growth=0.04, op_margin=0.12, net_margin=0.08)),
    ("Fast Grower Holdings", "FAST", 104, 7370, 500.0, dict(growth=0.30, op_margin=0.20, net_margin=0.15, share_change=0.03)),
    ("Loss Maker Ltd", "LOSS", 105, 2834, 20.0, dict(growth=0.10, op_margin=-0.10, net_margin=-0.15, loss_years=(2025,))),
    ("Debt Heavy Inc", "DEBT", 106, 4512, 30.0, dict(growth=0.03, op_margin=0.10, net_margin=0.05, debt=60e9, cash=1e9)),
    ("Shrinking Retail Co", "SHRK", 107, 5311, 15.0, dict(growth=-0.10, op_margin=0.06, net_margin=0.03)),
    ("Big Bank Corp", "BANK", 108, 6021, 50.0, dict()),
    ("Middling Machines", "MIDL", 109, 3530, 80.0, dict(growth=0.06, op_margin=0.15, net_margin=0.10)),
    ("<script>Evil</script> Corp", "EVIL", 110, 7372, 100.0, dict(growth=0.08, op_margin=0.20, net_margin=0.15)),
]


def ticker_map() -> dict:
    rows = {str(i): {"cik_str": cik, "ticker": t, "title": n} for i, (n, t, cik, _, _, _) in enumerate(UNIVERSE)}
    rows["99"] = {"cik_str": 999, "ticker": "BRK.B", "title": "Berkshire"}
    return rows


class FakeHttp:
    """Stands in for net.Http, routing by URL. Counts every call."""

    def __init__(self, prices: dict[str, float] | None = None, fail: set[str] | None = None):
        self.calls: list[str] = []
        self.prices = {t: p for _, t, _, _, p, _ in UNIVERSE} if prices is None else prices
        self.fail = fail or set()
        self.submissions = {cik: make_submissions(cik, n, sic) for n, _, cik, sic, _, _ in UNIVERSE}
        self.facts = {cik: make_facts(**kw) for _, _, cik, _, _, kw in UNIVERSE}

    def _check(self, url: str) -> None:
        self.calls.append(url)
        for marker in self.fail:
            if marker in url:
                raise FetchError(url, "HTTP 503 Service Unavailable", status=503)

    def get_json(self, url: str):
        self._check(url)
        if url.endswith("company_tickers.json"):
            return ticker_map()
        cik = int(url.rsplit("CIK", 1)[1].split(".")[0])
        source = self.submissions if "/submissions/" in url else self.facts if "/companyfacts/" in url else None
        if source is None:
            raise AssertionError(f"unexpected URL {url}")
        if cik not in source:
            raise FetchError(url, "HTTP 404 Not Found", status=404)
        return copy.deepcopy(source[cik])

    def get_text(self, url: str) -> str:
        self._check(url)
        assert "stooq.com" in url, url
        # Symbols are joined with a literal "+", which query parsing reads as a space.
        symbols = urllib.parse.parse_qs(urllib.parse.urlsplit(url).query)["s"][0].split(" ")
        out = io.StringIO()
        out.write("Symbol,Date,Time,Open,High,Low,Close,Volume\r\n")
        for sym in symbols:
            ticker = sym.upper()[: -len(".US")]
            price = self.prices.get(ticker)
            if price is None:
                out.write(f"{sym.upper()},N/D,N/D,N/D,N/D,N/D,N/D,N/D\r\n")
            else:
                out.write(f"{sym.upper()},2026-10-02,22:00:00,{price},{price},{price},{price},1000\r\n")
        return out.getvalue()


def temp_settings(**overrides) -> Settings:
    data_dir = tempfile.mkdtemp(prefix="stockpicks-test-")
    universe = os.path.join(data_dir, "universe.txt")
    with open(universe, "w", encoding="utf-8") as fh:
        fh.write("# test universe\n")
        fh.write("\n".join(t for _, t, _, _, _, _ in UNIVERSE))
        fh.write("\nNOPE\nbrk.b\n")
    values = dict(
        data_dir=data_dir,
        universe_file=universe,
        sec_user_agent="Test admin@example.com",
        picks_count=3,
        min_market_cap=2e9,
        base_url="https://picks.example.com",
        support_email="help@example.com",
    )
    values.update(overrides)
    return Settings(**values)
