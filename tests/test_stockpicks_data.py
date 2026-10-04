import json
import os
import unittest

from stockpicks.metrics import compute
from stockpicks.net import FetchError
from stockpicks.refresh import RefreshError, load_universe, refresh
from stockpicks.scoring import percentile, red_flags, score_all
from stockpicks.sources import sec
from stockpicks.sources.prices import fetch_finnhub, parse_stooq_csv

from .stockpicks_helpers import TODAY, FakeHttp, _point, _tag, make_facts, make_submissions, temp_settings


class SecParsingTests(unittest.TestCase):
    def test_ticker_map_normalizes_class_shares(self):
        companies = sec.parse_ticker_map({"0": {"cik_str": 1067983, "ticker": "BRK.B", "title": "Berkshire"}})
        self.assertEqual(companies["BRK-B"].cik, 1067983)

    def test_submissions_keep_reports_and_explain_8k_items(self):
        profile = sec.parse_submissions(make_submissions(320193, "Apple Inc."))
        self.assertEqual([f.form for f in profile.filings], ["10-Q", "8-K", "10-K"])
        self.assertEqual(profile.filings[1].description, "Reported results")
        self.assertEqual(
            profile.filings[0].url,
            "https://www.sec.gov/Archives/edgar/data/320193/000032019326000002/doc-0000320193-26-000002.htm",
        )
        self.assertEqual(profile.latest_periodic_accession, "0000320193-26-000002")
        self.assertEqual(sec.sector_for_sic(profile.sic), "Technology")

    def test_profile_round_trips_through_cache(self):
        profile = sec.parse_submissions(make_submissions(5, "Five"))
        self.assertEqual(sec.Profile.from_dict(profile.to_dict()), profile)

    def test_recent_warning_filings_are_called_out(self):
        raw = make_submissions(7, "Seven", filings=[
            ("8-K", "2026-05-01", "a-1", "4.02"),
            ("8-K", "2024-01-01", "a-2", "4.01"),  # too old to matter
        ])
        warnings = sec.parse_submissions(raw).warnings(TODAY)
        self.assertEqual(len(warnings), 1)
        self.assertIn("can't be relied on", warnings[0])

    def test_financials_are_annual_and_restatements_win(self):
        facts = make_facts(revenue0=100.0, growth=0.0)
        points = facts["facts"]["us-gaap"]["RevenueFromContractWithCustomerExcludingAssessedTax"]["units"]["USD"]
        # A quarter inside a 10-K, a 10-Q, and a later restatement of 2024.
        points.append({**_point(2025, 25.0, duration=True), "start": "2025-10-01"})
        points.append({**_point(2025, 30.0, duration=True, form="10-Q"), "start": "2025-07-01", "end": "2025-09-30"})
        points.append(_point(2024, 99.0, duration=True, filed="2026-02-15"))
        series = sec.extract_financials(facts)["series"]["revenue"]
        self.assertEqual(len(series), 6)
        self.assertEqual(series["2025-12-31"], 100.0)
        self.assertEqual(series["2024-12-31"], 99.0)

    def test_revenue_tags_are_merged_across_years(self):
        facts = make_facts()
        gaap = facts["facts"]["us-gaap"]
        gaap["SalesRevenueNet"] = _tag([_point(2016, 5e9, duration=True), _point(2025, 1.0, duration=True)])
        series = sec.extract_financials(facts)["series"]["revenue"]
        self.assertEqual(series["2016-12-31"], 5e9)
        self.assertNotEqual(series["2025-12-31"], 1.0)  # the higher-priority tag wins

    def test_latest_cover_page_share_count(self):
        so = sec.extract_financials(make_facts())["shares_outstanding"]
        self.assertEqual(so["date"], "2026-07-20")

    def test_financial_companies_are_detected(self):
        self.assertTrue(sec.is_financial(6021))
        self.assertFalse(sec.is_financial(7372))
        self.assertFalse(sec.is_financial(None))


class MetricsTests(unittest.TestCase):
    def metrics(self, price=100.0, **kw):
        return compute(sec.extract_financials(make_facts(**kw)), price)

    def test_growth_margins_and_valuation(self):
        m = self.metrics(revenue0=10e9, growth=0.10, op_margin=0.25, net_margin=0.20, capex_pct=0.05,
                         shares0=1e9, share_change=0.0, cash=3e9, debt=4e9, equity=12e9)
        self.assertEqual(m.fiscal_year_end, "2025-12-31")
        self.assertAlmostEqual(m.revenue_growth, 0.10, places=3)
        self.assertAlmostEqual(m.eps_growth, 0.10, places=3)
        self.assertAlmostEqual(m.operating_margin, 0.25)
        revenue = 10e9 * 1.1**5
        self.assertAlmostEqual(m.free_cash_flow, revenue * 0.20 * 1.2 - revenue * 0.05)
        self.assertAlmostEqual(m.net_debt, 1e9)
        self.assertAlmostEqual(m.roic, revenue * 0.25 * 0.79 / 13e9)
        self.assertEqual(m.profitable_years, 5)
        self.assertAlmostEqual(m.market_cap, 100.0 * 1e9)
        self.assertAlmostEqual(m.pe, 100.0 / (revenue * 0.20 / 1e9))
        self.assertAlmostEqual(m.share_count_change, 0.0)

    def test_no_price_means_no_valuation(self):
        m = self.metrics(price=None)
        self.assertIsNone(m.pe)
        self.assertIsNone(m.market_cap)
        self.assertIsNotNone(m.roic)

    def test_negative_invested_capital_is_noted(self):
        m = self.metrics(equity=-20e9)
        self.assertIsNone(m.roic)
        self.assertTrue(any("buybacks" in n for n in m.notes))

    def test_missing_capex_skips_free_cash_flow(self):
        fin = sec.extract_financials(make_facts())
        fin["series"]["capex"] = {}
        m = compute(fin, 100.0)
        self.assertIsNone(m.free_cash_flow)
        self.assertTrue(any("capital spending" in n for n in m.notes))

    def test_no_revenue(self):
        m = compute({"series": {}, "shares_outstanding": None}, 10.0)
        self.assertIsNone(m.fiscal_year_end)


class ScoringTests(unittest.TestCase):
    def test_percentile_counts_ties_as_half(self):
        self.assertEqual(percentile(5, [1, 5, 5, 9]), 50.0)
        self.assertEqual(percentile(9, [1, 5, 5, 9]), 87.5)
        self.assertEqual(percentile(3, []), 50.0)

    def test_red_flags(self):
        m = compute(sec.extract_financials(make_facts(net_margin=-0.1, op_margin=-0.1)), 0.5)
        flags = red_flags(m, 2e9, TODAY)
        self.assertTrue(any("Lost money" in f for f in flags))
        self.assertTrue(any("market value" in f for f in flags))
        self.assertTrue(any("Burned cash" in f for f in flags))

    def test_stale_reports_are_flagged(self):
        m = compute(sec.extract_financials(make_facts()), 100.0)
        flags = red_flags(m, 2e9, TODAY.replace(year=2028))
        self.assertTrue(any("18 months" in f for f in flags))

    def test_ranking_and_picks(self):
        def row(ticker, **kw):
            return {"ticker": ticker, "name": ticker, "metrics": compute(sec.extract_financials(make_facts(**kw)), 100.0)}

        rows = [
            row("BEST", growth=0.2, op_margin=0.4, net_margin=0.3),
            row("OKAY", growth=0.05, op_margin=0.15, net_margin=0.1),
            row("LOSS", growth=0.1, op_margin=-0.2, net_margin=-0.2),
            {"ticker": "NODATA", "name": "No Data", "metrics": compute({"series": {}}, 1.0)},
        ]
        scored, not_covered = score_all(rows, 2e9, picks_count=5, today=TODAY)
        self.assertEqual([n["ticker"] for n in not_covered], ["NODATA"])
        by = {s["ticker"]: s for s in scored}
        self.assertEqual(by["BEST"]["rank"], 1)
        self.assertEqual(by["OKAY"]["rank"], 2)
        self.assertIsNone(by["LOSS"]["rank"])
        self.assertFalse(by["LOSS"]["eligible"])
        self.assertGreater(by["BEST"]["score"], by["OKAY"]["score"])
        self.assertTrue(any("Sales grew 20%" in t for t in by["BEST"]["strengths"]))
        self.assertTrue(any("Loses money" in t for t in by["LOSS"]["concerns"]))

    def test_picks_count_is_respected(self):
        rows = [
            {"ticker": f"T{i}", "name": "x", "metrics": compute(sec.extract_financials(make_facts(growth=0.01 * i)), 100.0)}
            for i in range(6)
        ]
        scored, _ = score_all(rows, 2e9, picks_count=2, today=TODAY)
        self.assertEqual(sorted(s["rank"] for s in scored if s["rank"]), [1, 2])


class PriceTests(unittest.TestCase):
    def test_stooq_csv(self):
        text = "Symbol,Date,Time,Open,High,Low,Close,Volume\nAAPL.US,2026-10-02,22:00:00,1,1,1,227.5,1\nZZZZ.US,N/D,N/D,N/D,N/D,N/D,N/D,N/D\n"
        self.assertEqual(parse_stooq_csv(text), {"AAPL": 227.5})

    def test_finnhub_hides_the_api_key_in_logs(self):
        class Http:
            def get_json(self, url):
                if "BAD" in url:
                    raise FetchError(url, "HTTP 401", status=401)
                return {"c": 12.5}

        logs = []
        prices = fetch_finnhub(["GOOD", "BAD", "BRK-B"], Http(), "secret-key", logs.append, spacing=0)
        self.assertEqual(prices, {"GOOD": 12.5, "BRK-B": 12.5})
        self.assertNotIn("secret-key", " ".join(logs))


class RefreshTests(unittest.TestCase):
    def test_full_refresh_writes_picks_and_history(self):
        settings = temp_settings()
        http = FakeHttp()
        data = refresh(settings, sec_http=http, price_http=http, log=lambda m: None, today=TODAY)

        with open(settings.picks_path) as fh:
            self.assertEqual(json.load(fh)["as_of"], "2026-10-04")
        reasons = {n["ticker"]: n["reason"] for n in data["not_covered"]}
        self.assertIn("different yardsticks", reasons["BANK"])
        self.assertIn("Not in the SEC", reasons["NOPE"])
        self.assertIn("BRK-B", reasons)
        picks = [s["ticker"] for s in sorted(data["stocks"], key=lambda s: s["rank"] or 99) if s["rank"]]
        self.assertEqual(len(picks), 3)
        self.assertEqual(picks[0], "GRT")
        for bad in ("LOSS", "DEBT", "SHRK"):
            self.assertNotIn(bad, picks)
        stock = next(s for s in data["stocks"] if s["ticker"] == "GRT")
        self.assertEqual(stock["filings"][0]["form"], "10-Q")
        with open(settings.history_path) as fh:
            self.assertEqual(len(json.loads(fh.readline())["picks"]), 3)

    def test_facts_are_cached_until_a_new_report(self):
        settings = temp_settings()
        http = FakeHttp()
        refresh(settings, sec_http=http, price_http=http, log=lambda m: None, today=TODAY)
        first = sum("companyfacts" in u for u in http.calls)

        http.calls.clear()
        refresh(settings, sec_http=http, price_http=http, log=lambda m: None, today=TODAY)
        self.assertEqual(sum("companyfacts" in u for u in http.calls), 0)

        http.submissions[101]["filings"]["recent"]["accessionNumber"][1] = "new-10q"
        http.calls.clear()
        refresh(settings, sec_http=http, price_http=http, log=lambda m: None, today=TODAY)
        self.assertEqual([u for u in http.calls if "companyfacts" in u], [sec.FACTS_URL.format(cik=101)])
        self.assertGreater(first, 1)

    def test_sec_outage_falls_back_to_cache(self):
        settings = temp_settings()
        refresh(settings, sec_http=FakeHttp(), price_http=FakeHttp(), log=lambda m: None, today=TODAY)
        down = FakeHttp(fail={"/submissions/", "/companyfacts/"})
        data = refresh(settings, sec_http=down, price_http=down, log=lambda m: None, today=TODAY)
        self.assertEqual(data["covered"], 9)

    def test_price_outage_keeps_previous_list(self):
        settings = temp_settings()
        refresh(settings, sec_http=FakeHttp(), price_http=FakeHttp(), log=lambda m: None, today=TODAY)
        before = os.path.getmtime(settings.picks_path)
        no_prices = FakeHttp(prices={})
        with self.assertRaises(RefreshError):
            refresh(settings, sec_http=no_prices, price_http=no_prices, log=lambda m: None, today=TODAY)
        self.assertEqual(os.path.getmtime(settings.picks_path), before)

    def test_requires_sec_contact(self):
        with self.assertRaises(RefreshError):
            refresh(temp_settings(sec_user_agent=""), log=lambda m: None)

    def test_default_universe_parses(self):
        tickers = load_universe(temp_settings().universe_file)
        self.assertIn("BRK-B", tickers)
        from stockpicks.config import DEFAULT_UNIVERSE
        default = load_universe(DEFAULT_UNIVERSE)
        self.assertGreater(len(default), 150)
        self.assertEqual(len(default), len(set(default)))


if __name__ == "__main__":
    unittest.main()
