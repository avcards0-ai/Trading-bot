import io
import unittest

from rugguard.alerts import Alert, Notifier
from rugguard.config import GuardSettings
from rugguard.guard import Guard
from rugguard.scanner import Severity

from .helpers import MINT, NOW, FakeFetch, make_pair, make_report


class Clock:
    def __init__(self, start: float = NOW):
        self.now = start

    def __call__(self) -> float:
        return self.now

    def sleep(self, seconds: float) -> None:
        self.now += seconds


def make_guard(fetch, **settings):
    posts = []
    notifier = Notifier(
        telegram_token="123:abc", telegram_chat_id="42",
        out=io.StringIO(), err=io.StringIO(),
        post=lambda url, payload: posts.append((url, payload)),
    )
    clock = Clock()
    defaults = dict(poll_interval=30, rugcheck_interval=3600, rugcheck_spacing=0)
    defaults.update(settings)
    guard = Guard([MINT], notifier, settings=GuardSettings(**defaults), fetch=fetch, clock=clock, sleep=clock.sleep)
    return guard, clock, posts


BASE = make_report()
POOL, HOLDER_A, HOLDER_B, HOLDER_C = BASE["topHolders"]


def dumped_report() -> dict:
    """The same token after the dev pulled LP, raised the fee and whales sold.

    Holder A (4%) is gone from the list, B went 3% -> 1%, C is unchanged.
    """
    return make_report(
        markets=[dict(BASE["markets"][0], lp={"lpLockedPct": 0, "baseUSD": 500, "quoteUSD": 500})],
        transferFee={"pct": 5},
        topHolders=[POOL, dict(HOLDER_B, pct=1.0), HOLDER_C],
    )


class GuardTests(unittest.TestCase):
    def tick_at(self, guard, clock, seconds_after_start):
        clock.now = NOW + seconds_after_start
        return guard.tick()

    def test_liquidity_pull_alerts_once_per_cooldown(self):
        fetch = FakeFetch(
            rugcheck=[make_report()],
            dex=[[make_pair(liquidity=100_000)], [make_pair(liquidity=100_000)], [make_pair(liquidity=5_000)]],
        )
        guard, clock, posts = make_guard(fetch)
        guard.start()
        self.assertEqual(self.tick_at(guard, clock, 30), [])

        alerts = self.tick_at(guard, clock, 60)
        self.assertEqual([a.code for a in alerts], ["LIQUIDITY_PULLED"])
        self.assertEqual(alerts[0].severity, Severity.CRITICAL)
        self.assertIn("95%", alerts[0].message)
        self.assertEqual(len(posts), 1)
        self.assertIn("api.telegram.org/bot123:abc", posts[0][0])

        self.assertEqual(self.tick_at(guard, clock, 90), [])  # cooldown
        self.assertEqual(len(posts), 1)

    def test_price_crash(self):
        fetch = FakeFetch(rugcheck=[make_report()], dex=[[make_pair(price=0.01)], [make_pair(price=0.004)]])
        guard, clock, _ = make_guard(fetch)
        guard.start()
        alerts = self.tick_at(guard, clock, 30)
        self.assertEqual([a.code for a in alerts], ["PRICE_CRASH"])

    def test_old_samples_leave_the_window(self):
        fetch = FakeFetch(rugcheck=[make_report()], dex=[[make_pair(liquidity=100_000)], [make_pair(liquidity=40_000)]])
        guard, clock, _ = make_guard(fetch, window_minutes=10)
        guard.start()
        # 20 minutes later the 100k sample is outside the 10 minute window.
        self.assertEqual(self.tick_at(guard, clock, 1200), [])

    def test_pair_disappearing_needs_two_misses(self):
        fetch = FakeFetch(rugcheck=[make_report()], dex=[[make_pair()], [], []])
        guard, clock, _ = make_guard(fetch)
        guard.start()
        self.assertEqual(self.tick_at(guard, clock, 30), [])
        alerts = self.tick_at(guard, clock, 60)
        self.assertEqual([a.code for a in alerts], ["PAIR_GONE"])

    def test_onchain_changes_are_detected(self):
        fetch = FakeFetch(rugcheck=[make_report(), dumped_report()], dex=[[make_pair()]])
        guard, clock, _ = make_guard(fetch, rugcheck_interval=60)
        guard.start()
        self.assertEqual(self.tick_at(guard, clock, 30), [])  # rugcheck not due yet

        alerts = self.tick_at(guard, clock, 60)
        found = {a.code: a for a in alerts}
        self.assertEqual(found["LP_UNLOCKED"].severity, Severity.CRITICAL)
        self.assertIn("FEE_RAISED", found)
        self.assertIn("dropped out", found["WHALE_DUMP:" + HOLDER_A["address"]].message)
        self.assertIn("3.0% to 1.0%", found["WHALE_DUMP:" + HOLDER_B["address"]].message)
        # Holder C is below the whale threshold.
        self.assertEqual(len([c for c in found if c.startswith("WHALE_DUMP")]), 2)

    def test_empty_holder_list_does_not_fake_whale_dumps(self):
        fetch = FakeFetch(rugcheck=[make_report(), make_report(topHolders=[])], dex=[[make_pair()]])
        guard, clock, _ = make_guard(fetch, rugcheck_interval=60)
        guard.start()
        self.assertEqual(self.tick_at(guard, clock, 60), [])

    def test_rugged_token_alerts_on_start(self):
        fetch = FakeFetch(rugcheck=[make_report(rugged=True)], dex=[[make_pair()]])
        guard, _, posts = make_guard(fetch)
        guard.start()
        self.assertEqual(len(posts), 1)
        self.assertIn("AVOID", posts[0][1]["text"])

    def test_run_polls_on_interval(self):
        fetch = FakeFetch(rugcheck=[make_report()], dex=[[make_pair()]])
        guard, clock, _ = make_guard(fetch, poll_interval=15)
        guard.run(max_ticks=3)
        self.assertEqual(clock.now, NOW + 45)
        dex_calls = [u for u in fetch.urls if "dexscreener" in u]
        self.assertEqual(len(dex_calls), 4)  # start + 3 ticks


class NotifierTests(unittest.TestCase):
    def test_low_severity_stays_on_console(self):
        posts, out = [], io.StringIO()
        notifier = Notifier(discord_webhook="https://discord.example/hook", out=out,
                            post=lambda url, payload: posts.append(payload))
        notifier.send(Alert(MINT, "TEST", Severity.MEDIUM, "X", "meh"))
        notifier.send(Alert(MINT, "TEST", Severity.CRITICAL, "Y", "run"))
        self.assertIn("[MEDIUM] TEST: meh", out.getvalue())
        self.assertEqual([p["content"].splitlines()[0] for p in posts], ["[CRITICAL] TEST: run"])

    def test_delivery_failure_is_logged_not_raised(self):
        from rugguard.net import FetchError

        def boom(url, payload):
            raise FetchError("discord.example", "HTTP 500")

        err = io.StringIO()
        notifier = Notifier(discord_webhook="https://discord.example/hook", out=io.StringIO(), err=err, post=boom)
        notifier.send(Alert(MINT, "TEST", Severity.CRITICAL, "Y", "run"))
        self.assertIn("Discord alert failed", err.getvalue())


if __name__ == "__main__":
    unittest.main()
