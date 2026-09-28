"""Command-line entry point: `python -m rugguard scan|watch ...`."""

from __future__ import annotations

import argparse
import json
import re
import sys
import time

from .alerts import Notifier
from .config import GuardSettings, ScanThresholds, load_dotenv
from .guard import Guard
from .scanner import Severity, format_result, scan

# Solana addresses are base58-encoded 32-byte keys.
_MINT_RE = re.compile(r"^[1-9A-HJ-NP-Za-km-z]{32,44}$")

DISCLAIMER = (
    "Heuristics only, not financial advice. A clean result does not mean a token is safe."
)


def _read_mints(args: argparse.Namespace) -> list[str]:
    mints = list(args.mints)
    if args.file:
        with open(args.file, encoding="utf-8") as fh:
            for line in fh:
                line = line.split("#", 1)[0].strip()
                if line:
                    mints.append(line)
    valid = []
    for mint in dict.fromkeys(mints):
        if _MINT_RE.match(mint):
            valid.append(mint)
        else:
            print(f"Skipping '{mint}': not a valid Solana mint address.", file=sys.stderr)
    return valid


def _scan_thresholds(args: argparse.Namespace) -> ScanThresholds:
    return ScanThresholds(min_liquidity_usd=args.min_liquidity)


def cmd_scan(args: argparse.Namespace) -> int:
    mints = _read_mints(args)
    if not mints:
        print("No valid mints to scan.", file=sys.stderr)
        return 1
    thresholds = _scan_thresholds(args)
    results = []
    for i, mint in enumerate(mints):
        if i:
            time.sleep(1)  # stay well inside the public APIs' rate limits
        results.append(scan(mint, thresholds))

    if args.json:
        print(json.dumps([r.to_dict() for r in results], indent=2))
    else:
        print("\n\n".join(format_result(r) for r in results))
        print(f"\n{DISCLAIMER}")
    return 0


def cmd_watch(args: argparse.Namespace) -> int:
    mints = _read_mints(args)
    if not mints:
        print("No valid mints to watch.", file=sys.stderr)
        return 1
    notifier = Notifier.from_env(remote_min_severity=Severity[args.notify_level])
    settings = GuardSettings(
        poll_interval=args.interval,
        rugcheck_interval=args.rugcheck_interval,
        window_minutes=args.window,
        liquidity_drop_pct=args.liquidity_drop,
        price_drop_pct=args.price_drop,
    )
    guard = Guard(mints, notifier, settings=settings, thresholds=_scan_thresholds(args))

    channels = ", ".join(notifier.channels) or "console only (set TELEGRAM_* or DISCORD_WEBHOOK_URL in .env)"
    notifier.info(f"rugguard watching {len(mints)} token(s). Alerts: {channels}. Ctrl+C to stop.")
    try:
        guard.run()
    except KeyboardInterrupt:
        notifier.info("Stopped.")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="rugguard",
        description="Rug-pull scanner and position guard for Solana memecoins.",
        epilog=DISCLAIMER,
    )
    sub = parser.add_subparsers(dest="command", required=True)

    def add_common(p: argparse.ArgumentParser) -> None:
        p.add_argument("mints", nargs="*", help="token mint address(es)")
        p.add_argument("-f", "--file", help="file with one mint per line (# comments allowed)")
        p.add_argument(
            "--min-liquidity", type=float, default=ScanThresholds.min_liquidity_usd,
            help="flag tokens with less USD liquidity than this (default: %(default)g)",
        )

    scan_p = sub.add_parser("scan", help="score tokens for rug risk before you buy")
    add_common(scan_p)
    scan_p.add_argument("--json", action="store_true", help="print machine-readable JSON")
    scan_p.set_defaults(func=cmd_scan)

    d = GuardSettings()
    watch_p = sub.add_parser("watch", help="monitor tokens you hold and alert on rug signals")
    add_common(watch_p)
    watch_p.add_argument("--interval", type=float, default=d.poll_interval,
                         help="seconds between market polls (default: %(default)g)")
    watch_p.add_argument("--rugcheck-interval", type=float, default=d.rugcheck_interval,
                         help="seconds between on-chain re-checks (default: %(default)g)")
    watch_p.add_argument("--window", type=float, default=d.window_minutes,
                         help="minutes of history to compare against (default: %(default)g)")
    watch_p.add_argument("--liquidity-drop", type=float, default=d.liquidity_drop_pct,
                         help="alert when liquidity falls this %% within the window (default: %(default)g)")
    watch_p.add_argument("--price-drop", type=float, default=d.price_drop_pct,
                         help="alert when price falls this %% within the window (default: %(default)g)")
    watch_p.add_argument("--notify-level", choices=["LOW", "MEDIUM", "HIGH", "CRITICAL"], default="HIGH",
                         help="minimum severity pushed to Telegram/Discord (default: %(default)s)")
    watch_p.set_defaults(func=cmd_watch)
    return parser


def main(argv: list[str] | None = None) -> int:
    load_dotenv()
    args = build_parser().parse_args(argv)
    return args.func(args)
