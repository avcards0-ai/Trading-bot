"""Latest share prices, used only to judge valuation (P/E, free-cash-flow yield).

Two providers:
- stooq: free, no key, end-of-day quotes, many tickers per request.
- finnhub: free key from https://finnhub.io, 60 requests per minute.

Check each provider's terms before charging for a site that shows its data.
"""

from __future__ import annotations

import csv
import io
import time
import urllib.parse
from typing import Callable, Iterable

from ..net import FetchError, Http

STOOQ_URL = "https://stooq.com/q/l/?s={symbols}&f=sd2t2ohlcv&h&e=csv"
STOOQ_BATCH = 20
FINNHUB_URL = "https://finnhub.io/api/v1/quote?symbol={symbol}&token={token}"

Log = Callable[[str], None]


def _float(value: str | None) -> float | None:
    try:
        number = float(value)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return None
    return number if number > 0 else None


def stooq_symbol(ticker: str) -> str:
    return ticker.lower() + ".us"


def parse_stooq_csv(text: str) -> dict[str, float]:
    """Parse Symbol,Date,Time,Open,High,Low,Close,Volume rows. Unknown symbols show N/D."""
    prices = {}
    for row in csv.DictReader(io.StringIO(text)):
        symbol = (row.get("Symbol") or "").strip().upper()
        close = _float(row.get("Close"))
        if symbol.endswith(".US") and close:
            prices[symbol[: -len(".US")]] = close
    return prices


def fetch_stooq(tickers: Iterable[str], http: Http, log: Log = print) -> dict[str, float]:
    tickers = list(tickers)
    prices: dict[str, float] = {}
    for i in range(0, len(tickers), STOOQ_BATCH):
        chunk = tickers[i : i + STOOQ_BATCH]
        symbols = "+".join(urllib.parse.quote(stooq_symbol(t)) for t in chunk)
        try:
            prices.update(parse_stooq_csv(http.get_text(STOOQ_URL.format(symbols=symbols))))
        except FetchError as e:
            log(f"  prices: stooq batch starting {chunk[0]} failed: {e}")
    return prices


def fetch_finnhub(
    tickers: Iterable[str], http: Http, api_key: str, log: Log = print, spacing: float = 1.05
) -> dict[str, float]:
    prices: dict[str, float] = {}
    for i, ticker in enumerate(tickers):
        if i and spacing:
            time.sleep(spacing)  # free tier: 60 calls per minute
        symbol = urllib.parse.quote(ticker.replace("-", "."))
        try:
            data = http.get_json(FINNHUB_URL.format(symbol=symbol, token=urllib.parse.quote(api_key)))
        except FetchError as e:
            # The URL carries the API key, so only log the status.
            log(f"  prices: finnhub {ticker} failed (HTTP {e.status or 'error'})")
            continue
        price = _float(str(data.get("c"))) if isinstance(data, dict) else None
        if price:
            prices[ticker] = price
    return prices


def fetch_prices(
    tickers: Iterable[str], source: str, http: Http, api_key: str = "", log: Log = print
) -> dict[str, float]:
    if source == "finnhub":
        if not api_key:
            raise ValueError("PRICE_SOURCE=finnhub needs FINNHUB_API_KEY")
        return fetch_finnhub(tickers, http, api_key, log)
    if source == "stooq":
        return fetch_stooq(tickers, http, log)
    raise ValueError(f"unknown PRICE_SOURCE {source!r} (use stooq or finnhub)")
