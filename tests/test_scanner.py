import unittest

from rugguard.net import FetchError
from rugguard.scanner import Severity, format_result, scan
from rugguard.sources.dexscreener import group_pairs
from rugguard.sources.rugcheck import parse_report

from .helpers import MINT, NOW, OTHER_MINT, FakeFetch, make_pair, make_report, not_found


def codes(result):
    return {f.code for f in result.findings}


class ParseTests(unittest.TestCase):
    def test_pool_accounts_are_not_counted_as_holders(self):
        report = parse_report(make_report(), MINT)
        self.assertEqual([h.pct for h in report.holders], [4.0, 3.0, 2.0])
        self.assertEqual(report.lp_locked_pct, 100)

    def test_authorities_fall_back_to_token_block(self):
        raw = make_report(token={"mintAuthority": "Auth1111111111111111111111111111111111111"})
        del raw["mintAuthority"]
        self.assertEqual(parse_report(raw, MINT).mint_authority, "Auth1111111111111111111111111111111111111")

    def test_best_pair_is_deepest_and_liquidity_is_summed(self):
        pairs = [
            make_pair(liquidity=10_000, pair_address="PairSmall"),
            make_pair(liquidity=90_000, pair_address="PairBig"),
            make_pair(liquidity=90_000, pair_address="PairBig"),  # duplicate
            make_pair(mint=OTHER_MINT, liquidity=1_000_000, pair_address="PairOther"),
        ]
        market = group_pairs(pairs, [MINT])[MINT]
        self.assertEqual(market.best.pair_address, "PairBig")
        self.assertEqual(market.total_liquidity_usd, 100_000)
        self.assertEqual(market.pair_count, 2)

    def test_wrapped_pairs_response_is_accepted(self):
        fetch = FakeFetch(rugcheck=[make_report()], dex=[{"schemaVersion": "1.0.0", "pairs": [make_pair()]}])
        self.assertIsNotNone(scan(MINT, fetch=fetch, now=NOW).market)


class ScanTests(unittest.TestCase):
    def test_clean_token(self):
        result = scan(MINT, fetch=FakeFetch(rugcheck=[make_report()], dex=[[make_pair()]]), now=NOW)
        self.assertEqual(result.verdict, "NO MAJOR RED FLAGS")
        self.assertEqual(result.score, 0)
        self.assertEqual(result.symbol, "TEST")

    def test_classic_rug_setup_is_avoid(self):
        raw = make_report(
            mintAuthority="Dev11111111111111111111111111111111111111",
            freezeAuthority="Dev11111111111111111111111111111111111111",
            markets=[{"pubkey": "M", "lp": {"lpLockedPct": 0, "baseUSD": 900, "quoteUSD": 900}}],
            topHolders=[{"address": "DevAcct", "owner": "DevWallet", "pct": 35.0, "insider": True}],
        )
        fetch = FakeFetch(rugcheck=[raw], dex=[[make_pair(liquidity=1_800, created_at=NOW - 600)]])
        result = scan(MINT, fetch=fetch, now=NOW)
        self.assertEqual(result.verdict, "AVOID")
        self.assertEqual(result.score, 100)
        self.assertTrue({
            "MINT_AUTHORITY", "FREEZE_AUTHORITY", "LP_UNLOCKED", "WHALE",
            "TOP10_CONCENTRATION", "INSIDERS", "LOW_LIQUIDITY", "NEW_PAIR",
        } <= codes(result))
        self.assertEqual(result.findings[0].severity, Severity.HIGH)

    def test_rugged_flag_is_critical(self):
        result = scan(MINT, fetch=FakeFetch(rugcheck=[make_report(rugged=True)], dex=[[make_pair()]]), now=NOW)
        self.assertEqual(result.verdict, "AVOID")
        self.assertIn("RUGGED", codes(result))

    def test_honeypot_heuristic(self):
        fetch = FakeFetch(rugcheck=[make_report()], dex=[[make_pair(buys_h1=120, sells_h1=0)]])
        result = scan(MINT, fetch=fetch, now=NOW)
        self.assertIn("NO_SELLS", codes(result))
        self.assertEqual(result.verdict, "HIGH RISK")

    def test_rugcheck_risks_are_included_without_double_counting(self):
        raw = make_report(
            mintAuthority="Dev11111111111111111111111111111111111111",
            risks=[
                {"name": "Mint Authority still enabled", "description": "", "level": "danger"},
                {"name": "Creator history of rugged tokens", "description": "Creator has rugged before", "level": "danger"},
                {"name": "Copycat token", "description": "", "level": "warn"},
            ],
        )
        result = scan(MINT, fetch=FakeFetch(rugcheck=[raw], dex=[[make_pair()]]), now=NOW)
        messages = [f.message for f in result.findings]
        self.assertEqual(sum("Mint" in m for m in messages), 1)
        self.assertIn("RugCheck: Creator history of rugged tokens: Creator has rugged before", messages)
        self.assertIn("RugCheck: Copycat token", messages)

    def test_missing_rugcheck_report_is_not_treated_as_clean(self):
        result = scan(MINT, fetch=FakeFetch(rugcheck=[not_found()], dex=[[make_pair()]]), now=NOW)
        self.assertIn("NO_ONCHAIN_DATA", codes(result))
        self.assertEqual(result.verdict, "CAUTION")

    def test_no_pair_and_api_outage(self):
        result = scan(MINT, fetch=FakeFetch(rugcheck=[make_report()], dex=[[]]), now=NOW)
        self.assertIn("NO_PAIR", codes(result))

        outage = FetchError("https://api.dexscreener.com", "HTTP 503 Service Unavailable", status=503)
        result = scan(MINT, fetch=FakeFetch(rugcheck=[make_report()], dex=[outage]), now=NOW)
        self.assertIn("NO_MARKET_DATA", codes(result))
        self.assertTrue(result.errors)

    def test_format_and_json(self):
        result = scan(MINT, fetch=FakeFetch(rugcheck=[make_report(mintAuthority="X" * 43)], dex=[[make_pair()]]), now=NOW)
        text = format_result(result)
        self.assertIn("Verdict: HIGH RISK", text)
        self.assertIn("[HIGH]", text)
        self.assertEqual(result.to_dict()["findings"][0]["severity"], "HIGH")


if __name__ == "__main__":
    unittest.main()
