import contextlib
import io
import json
import unittest
from unittest import mock

from rugguard import cli
from rugguard.scanner import scan

from .helpers import MINT, NOW, FakeFetch, make_pair, make_report


def offline_scan(mint, thresholds):
    return scan(mint, thresholds, fetch=FakeFetch(rugcheck=[make_report()], dex=[[make_pair()]]), now=NOW)


class CliTests(unittest.TestCase):
    def run_cli(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = cli.main(list(argv))
        return code, out.getvalue(), err.getvalue()

    def test_invalid_mint_is_rejected(self):
        code, _, err = self.run_cli("scan", "not-a-mint")
        self.assertEqual(code, 1)
        self.assertIn("not a valid Solana mint", err)

    @mock.patch("rugguard.cli.scan", side_effect=offline_scan)
    def test_scan_text(self, _):
        code, out, _ = self.run_cli("scan", MINT)
        self.assertEqual(code, 0)
        self.assertIn("NO MAJOR RED FLAGS", out)
        self.assertIn("not financial advice", out)

    @mock.patch("rugguard.cli.scan", side_effect=offline_scan)
    def test_scan_json(self, _):
        code, out, _ = self.run_cli("scan", MINT, "--json")
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out)[0]["verdict"], "NO MAJOR RED FLAGS")


if __name__ == "__main__":
    unittest.main()
