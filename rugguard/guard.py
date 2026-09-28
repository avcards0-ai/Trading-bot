"""Position guard: watch tokens you hold and alert the moment rug signals appear."""

from __future__ import annotations

import time
from collections import deque
from dataclasses import dataclass, field
from typing import Any, Callable

from .alerts import Alert, Notifier
from .config import GuardSettings, ScanThresholds
from .net import FetchError, get_json
from .scanner import Severity, scan, short
from .sources.dexscreener import TokenMarket, fetch_markets
from .sources.rugcheck import RugCheckReport, fetch_report


@dataclass
class TokenState:
    mint: str
    symbol: str = ""
    url: str = ""
    # (timestamp, total liquidity USD, price USD) samples inside the window
    history: deque = field(default_factory=deque)
    last_market: TokenMarket | None = None
    last_report: RugCheckReport | None = None
    missing_polls: int = 0
    last_alert_at: dict[str, float] = field(default_factory=dict)


class Guard:
    def __init__(
        self,
        mints: list[str],
        notifier: Notifier,
        settings: GuardSettings | None = None,
        thresholds: ScanThresholds | None = None,
        fetch: Callable[[str], Any] = get_json,
        clock: Callable[[], float] = time.time,
        sleep: Callable[[float], None] = time.sleep,
    ):
        self.mints = list(dict.fromkeys(mints))
        self.notifier = notifier
        self.s = settings or GuardSettings()
        self.t = thresholds or ScanThresholds()
        self.fetch = fetch
        self.clock = clock
        self.sleep = sleep
        self.states = {m: TokenState(mint=m, symbol=short(m)) for m in self.mints}
        self._next_rugcheck = 0.0

    # -- lifecycle ---------------------------------------------------------

    def start(self) -> None:
        """Run a full scan of every token to set baselines."""
        now = self.clock()
        for i, mint in enumerate(self.mints):
            if i:
                self.sleep(self.s.rugcheck_spacing)
            result = scan(mint, self.t, fetch=self.fetch, now=now)
            st = self.states[mint]
            st.symbol = result.symbol or st.symbol
            st.last_report = result.report
            if result.market is not None:
                self._record_market(st, result.market, now)
            self.notifier.info(f"Watching {st.symbol}: {result.verdict} (risk {result.score}/100)")
            if result.verdict == "AVOID":
                reasons = "; ".join(f.message for f in result.findings[:3])
                self._send([self._alert(st, Severity.HIGH, "SCAN_AVOID", f"Initial scan says AVOID. {reasons}")], now)
        self._next_rugcheck = now + self.s.rugcheck_interval

    def run(self, max_ticks: int | None = None) -> None:
        self.start()
        ticks = 0
        while max_ticks is None or ticks < max_ticks:
            self.sleep(self.s.poll_interval)
            self.tick()
            ticks += 1

    def tick(self) -> list[Alert]:
        """Poll once. Returns the alerts that were actually sent."""
        now = self.clock()
        candidates: list[Alert] = []

        try:
            markets = fetch_markets(self.mints, fetch=self.fetch)
        except FetchError as e:
            self.notifier.warn(f"DexScreener poll failed: {e}")
        else:
            for mint in self.mints:
                candidates += self.check_market(self.states[mint], markets.get(mint), now)

        if now >= self._next_rugcheck:
            for i, mint in enumerate(self.mints):
                if i:
                    self.sleep(self.s.rugcheck_spacing)
                try:
                    report = fetch_report(mint, fetch=self.fetch)
                except FetchError as e:
                    self.notifier.warn(f"RugCheck poll failed for {self.states[mint].symbol}: {e}")
                    continue
                candidates += self.check_report(self.states[mint], report)
            self._next_rugcheck = now + self.s.rugcheck_interval

        return self._send(candidates, now)

    # -- checks ------------------------------------------------------------

    def check_market(self, st: TokenState, market: TokenMarket | None, now: float) -> list[Alert]:
        s = self.s
        if market is None:
            if st.last_market is None:
                return []  # never had a pair, so there's nothing to compare against
            st.missing_polls += 1
            if st.missing_polls >= s.missing_polls_before_alert:
                return [self._alert(
                    st, Severity.CRITICAL, "PAIR_GONE",
                    "DexScreener no longer lists any pair for this token. Liquidity may have been pulled.",
                )]
            return []

        st.missing_polls = 0
        self._record_market(st, market, now)
        alerts = []
        liq = market.total_liquidity_usd
        window = f"{s.window_minutes:g} min"

        peak_liq = max(sample[1] for sample in st.history)
        if peak_liq > 0:
            drop = (peak_liq - liq) / peak_liq * 100
            if drop >= s.liquidity_drop_pct:
                alerts.append(self._alert(
                    st, Severity.CRITICAL, "LIQUIDITY_PULLED",
                    f"Liquidity down {drop:.0f}% in {window} (${peak_liq:,.0f} -> ${liq:,.0f}).",
                ))

        price = market.best.price_usd
        prices = [sample[2] for sample in st.history if sample[2]]
        if price and prices:
            peak_price = max(prices)
            drop = (peak_price - price) / peak_price * 100
            if drop >= s.price_drop_pct:
                alerts.append(self._alert(
                    st, Severity.HIGH, "PRICE_CRASH",
                    f"Price down {drop:.0f}% in {window} ({peak_price:.8g} -> {price:.8g} USD).",
                ))

        b = market.best
        if b.buys_h1 >= self.t.honeypot_min_buys and b.sells_h1 == 0:
            alerts.append(self._alert(
                st, Severity.HIGH, "NO_SELLS",
                f"{b.buys_h1} buys and 0 sells in the last hour. Selling may be blocked.",
            ))
        return alerts

    def check_report(self, st: TokenState, report: RugCheckReport) -> list[Alert]:
        prev, st.last_report = st.last_report, report
        st.symbol = report.symbol or st.symbol
        alerts = []

        if report.rugged and not (prev and prev.rugged):
            alerts.append(self._alert(st, Severity.CRITICAL, "RUGGED", "RugCheck now flags this token as rugged."))
        if prev is None:
            return alerts

        if report.mint_authority and report.mint_authority != prev.mint_authority:
            alerts.append(self._alert(
                st, Severity.HIGH, "MINT_AUTHORITY",
                f"Mint authority changed to {short(report.mint_authority)}, so new supply can be minted.",
            ))
        if report.freeze_authority and report.freeze_authority != prev.freeze_authority:
            alerts.append(self._alert(
                st, Severity.HIGH, "FREEZE_AUTHORITY",
                f"Freeze authority changed to {short(report.freeze_authority)}, so accounts can be frozen.",
            ))
        if (
            prev.lp_locked_pct is not None
            and report.lp_locked_pct is not None
            and prev.lp_locked_pct - report.lp_locked_pct >= self.s.lp_unlock_drop_pts
        ):
            alerts.append(self._alert(
                st, Severity.CRITICAL, "LP_UNLOCKED",
                f"Locked LP fell from {prev.lp_locked_pct:.0f}% to {report.lp_locked_pct:.0f}%.",
            ))
        if report.transfer_fee_pct > prev.transfer_fee_pct:
            alerts.append(self._alert(
                st, Severity.HIGH, "FEE_RAISED",
                f"Transfer fee raised from {prev.transfer_fee_pct:.1f}% to {report.transfer_fee_pct:.1f}%.",
            ))

        # An empty holder list is more likely an API hiccup than every whale
        # selling at once, so only compare when we have data.
        if report.holders:
            current = {h.address: h.pct for h in report.holders}
            for h in prev.holders:
                if h.pct < self.s.whale_min_pct:
                    continue
                now_pct = current.get(h.address)
                who = short(h.owner or h.address)
                if now_pct is None:
                    msg = f"Whale {who} ({h.pct:.1f}% of supply) dropped out of the top holders."
                elif now_pct <= h.pct * (1 - self.s.whale_sell_fraction):
                    msg = f"Whale {who} sold down from {h.pct:.1f}% to {now_pct:.1f}% of supply."
                else:
                    continue
                alerts.append(self._alert(st, Severity.HIGH, f"WHALE_DUMP:{h.address}", msg))
        return alerts

    # -- helpers -----------------------------------------------------------

    def _record_market(self, st: TokenState, market: TokenMarket, now: float) -> None:
        st.last_market = market
        st.symbol = market.best.symbol or st.symbol
        st.url = market.best.url or st.url
        st.history.append((now, market.total_liquidity_usd, market.best.price_usd))
        cutoff = now - self.s.window_minutes * 60
        while st.history and st.history[0][0] < cutoff:
            st.history.popleft()

    def _alert(self, st: TokenState, severity: Severity, code: str, message: str) -> Alert:
        return Alert(mint=st.mint, symbol=st.symbol, severity=severity, code=code, message=message, url=st.url)

    def _send(self, alerts: list[Alert], now: float) -> list[Alert]:
        """Deliver alerts, skipping repeats of the same code within the cooldown."""
        sent = []
        for alert in alerts:
            st = self.states[alert.mint]
            last = st.last_alert_at.get(alert.code)
            if last is not None and now - last < self.s.alert_cooldown:
                continue
            st.last_alert_at[alert.code] = now
            self.notifier.send(alert)
            sent.append(alert)
        return sent
