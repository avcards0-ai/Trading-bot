"""The daily job: read SEC filings and prices, score every company, write picks.json."""

from __future__ import annotations

import json
import os
import tempfile
from datetime import date, datetime, timezone
from typing import Callable

from . import metrics as metrics_mod
from .config import Settings
from .net import FetchError, Http
from .scoring import score_all
from .sources import prices as prices_mod
from .sources import sec

Log = Callable[[str], None]

# If fewer than this share of covered companies get a price, the price source
# is probably down, so keep yesterday's list rather than publish a broken one.
MIN_PRICE_COVERAGE = 0.5
FINANCIALS_NOT_COVERED = (
    "Banks, insurers and real-estate trusts need different yardsticks, so they aren't covered."
)


class RefreshError(Exception):
    pass


def load_universe(path: str) -> list[str]:
    tickers = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.split("#", 1)[0].strip()
            if line:
                tickers.append(sec.normalize_ticker(line))
    return list(dict.fromkeys(tickers))


def write_json_atomic(path: str, data: object) -> None:
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(data, fh, separators=(",", ":"))
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def _read_cache(path: str) -> dict:
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (FileNotFoundError, ValueError):
        return {}


def _company_data(company: sec.Company, http: Http, cache_dir: str, log: Log) -> tuple[sec.Profile, dict | None]:
    """Profile and extracted financials, re-downloading facts only after a new 10-K/10-Q."""
    path = os.path.join(cache_dir, f"CIK{company.cik:010d}.json")
    cached = _read_cache(path)
    try:
        profile = sec.parse_submissions(http.get_json(sec.SUBMISSIONS_URL.format(cik=company.cik)))
    except FetchError as e:
        if not cached.get("profile"):
            raise
        log(f"  {company.ticker}: SEC filings list unavailable ({e}); using cached copy")
        return sec.Profile.from_dict(cached["profile"]), cached.get("financials")

    key = profile.latest_periodic_accession
    financials = cached.get("financials")
    if financials is None or cached.get("key") != key:
        try:
            financials = sec.extract_financials(http.get_json(sec.FACTS_URL.format(cik=company.cik)))
        except FetchError as e:
            if e.status == 404:
                financials = {"series": {}, "shares_outstanding": None}  # no XBRL data at all
            elif financials is None:
                raise
            else:
                log(f"  {company.ticker}: SEC financials unavailable ({e}); using cached copy")
    os.makedirs(cache_dir, exist_ok=True)
    write_json_atomic(path, {"key": key, "profile": profile.to_dict(), "financials": financials})
    return profile, financials


def refresh(
    settings: Settings,
    sec_http: Http | None = None,
    price_http: Http | None = None,
    log: Log = print,
    today: date | None = None,
) -> dict:
    """Run the full analysis and write settings.picks_path. Returns the written data."""
    if not sec_http and "@" not in settings.sec_user_agent:
        raise RefreshError(
            "Set SEC_USER_AGENT to your site name and contact email, e.g. "
            "'LongHold admin@example.com'. The SEC blocks requests without one."
        )
    today = today or date.today()
    sec_http = sec_http or Http(settings.sec_user_agent, min_interval=0.12)
    price_http = price_http or Http(min_interval=0.2)
    cache_dir = os.path.join(settings.cache_dir, "sec")

    universe = load_universe(settings.universe_file)
    log(f"Analyzing {len(universe)} companies from SEC EDGAR...")
    ticker_map = sec.parse_ticker_map(sec_http.get_json(sec.TICKERS_URL))

    companies, not_covered = [], []
    for i, ticker in enumerate(universe, start=1):
        company = ticker_map.get(ticker)
        if company is None:
            not_covered.append({"ticker": ticker, "name": ticker, "reason": "Not in the SEC's list of company tickers."})
            continue
        try:
            profile, financials = _company_data(company, sec_http, cache_dir, log)
        except FetchError as e:
            log(f"  {ticker}: skipped, SEC unavailable ({e})")
            not_covered.append({"ticker": ticker, "name": company.name, "reason": "SEC data was unavailable today."})
            continue
        if sec.is_financial(profile.sic):
            not_covered.append({"ticker": ticker, "name": profile.name or company.name, "reason": FINANCIALS_NOT_COVERED})
            continue
        companies.append((company, profile, financials or {}))
        if i % 25 == 0:
            log(f"  {i}/{len(universe)} companies read")

    tickers = [c.ticker for c, _, _ in companies]
    log(f"Fetching prices for {len(tickers)} companies from {settings.price_source}...")
    prices = prices_mod.fetch_prices(tickers, settings.price_source, price_http, settings.finnhub_api_key, log)
    if tickers and len(prices) < MIN_PRICE_COVERAGE * len(tickers):
        raise RefreshError(
            f"Only got prices for {len(prices)} of {len(tickers)} companies from "
            f"{settings.price_source}; keeping the previous list."
        )

    rows = []
    for company, profile, financials in companies:
        rows.append({
            "ticker": company.ticker,
            "name": profile.name or company.name,
            "cik": company.cik,
            "sector": sec.sector_for_sic(profile.sic),
            "industry": profile.sic_description,
            "filings": [f.to_dict() for f in profile.filings[:8]],
            "metrics": metrics_mod.compute(financials, prices.get(company.ticker)),
            "warnings": profile.warnings(today),
        })
    scored, more_not_covered = score_all(rows, settings.min_market_cap, settings.picks_count, today)
    not_covered = sorted(not_covered + more_not_covered, key=lambda n: n["ticker"])
    if not scored:
        raise RefreshError("No company could be scored; keeping the previous list.")

    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    data = {
        "generated_at": generated_at,
        "as_of": today.isoformat(),
        "universe_size": len(universe),
        "covered": len(scored),
        "picks_count": sum(1 for s in scored if s["rank"]),
        "price_source": settings.price_source,
        "stocks": scored,
        "not_covered": not_covered,
    }
    write_json_atomic(settings.picks_path, data)

    # Keep a dated record of every list so a track record can be shown later.
    with open(settings.history_path, "a", encoding="utf-8") as fh:
        picks = [
            {"rank": s["rank"], "ticker": s["ticker"], "score": s["score"], "price": s["metrics"]["price"]}
            for s in scored
            if s["rank"]
        ]
        fh.write(json.dumps({"as_of": data["as_of"], "generated_at": generated_at, "picks": picks}) + "\n")

    log(f"Done: {data['covered']} companies scored, {data['picks_count']} picks, "
        f"{len(not_covered)} not covered. Wrote {settings.picks_path}")
    return data
