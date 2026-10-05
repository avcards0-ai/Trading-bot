"""Command-line entry point: `python -m stockpicks refresh|serve|grant|revoke|users`."""

from __future__ import annotations

import argparse
import os
import sys
import threading
from collections import Counter
from datetime import datetime, timedelta, timezone

from .checks import LOCAL_HOSTS, format_checks, run_checks
from .config import Settings, load_dotenv
from .db import Database
from .net import FetchError
from .refresh import RefreshError, refresh

RETRY_AFTER_FAILURE = 1800  # seconds


def _log(message: str) -> None:
    # One write per message so lines from the web and refresh threads don't interleave.
    sys.stdout.write(message + "\n")
    sys.stdout.flush()


def cmd_refresh(args: argparse.Namespace) -> int:
    settings = Settings.from_env()
    try:
        refresh(settings, log=_log)
    except (RefreshError, FetchError, ValueError) as e:
        print(f"Refresh failed: {e}", file=sys.stderr)
        return 1
    return 0


def cmd_check(args: argparse.Namespace) -> int:
    checks = run_checks(Settings.from_env())
    print(format_checks(checks))
    return 1 if any(c.ok is False for c in checks) else 0


def _log_checks(settings: Settings) -> None:
    try:
        _log("Setup check:\n" + format_checks(run_checks(settings)))
    except Exception as e:  # noqa: BLE001 - a failed check must never stop the site
        _log(f"Setup check failed to run: {e}")


# New lists come out at 06:00 UTC: before US markets open, after the weekend.
PUBLISH_HOUR_UTC = 6


def last_publish_time(now: datetime, schedule: str) -> datetime:
    """The most recent scheduled publish time at or before `now` (Mondays for weekly)."""
    slot = now.replace(hour=PUBLISH_HOUR_UTC, minute=0, second=0, microsecond=0)
    if schedule == "weekly":
        slot -= timedelta(days=now.weekday())
    if slot > now:
        slot -= timedelta(days=7 if schedule == "weekly" else 1)
    return slot


def run_scheduler(settings: Settings, schedule: str, stop: threading.Event, log=_log) -> None:
    """Publish a new list on schedule (and right away if there's none yet), until `stop` is set."""
    period = timedelta(days=7 if schedule == "weekly" else 1)
    while not stop.is_set():
        now = datetime.now(timezone.utc)
        slot = last_publish_time(now, schedule)
        try:
            published = datetime.fromtimestamp(os.path.getmtime(settings.picks_path), timezone.utc)
        except OSError:
            published = None
        if published is not None and published >= slot:
            wait = (slot + period - now).total_seconds()
        else:
            try:
                refresh(settings, log=log)
                wait = (slot + period - datetime.now(timezone.utc)).total_seconds()
            except Exception as e:  # noqa: BLE001 - keep the site up whatever happens
                log(f"Scheduled refresh failed: {e}. Retrying in {RETRY_AFTER_FAILURE // 60} minutes.")
                wait = RETRY_AFTER_FAILURE
        stop.wait(max(1.0, min(wait, 3600)))


def cmd_serve(args: argparse.Namespace) -> int:
    from .web import App

    settings = Settings.from_env()
    app = App(settings, log=_log)
    if args.refresh != "off":
        if "@" in settings.sec_user_agent:
            threading.Thread(
                target=run_scheduler,
                args=(settings, args.refresh, threading.Event()),
                daemon=True,
                name="refresh",
            ).start()
        else:
            _log("SEC_USER_AGENT isn't set, so new lists won't be published. See .env.example.")
    threading.Thread(target=_log_checks, args=(settings,), daemon=True, name="check").start()
    if settings.base_url.startswith(LOCAL_HOSTS):
        _log(f"{settings.site_name} is running. Open http://localhost:{args.port} in your browser. "
             "That address only works on this computer; to share the site, put it online (see README).")
    else:
        _log(f"{settings.site_name} is live. Share this address: {settings.base_url}")
    try:
        import waitress  # production-grade server, used when installed
    except ImportError:
        from socketserver import ThreadingMixIn
        from wsgiref.simple_server import WSGIServer, make_server

        class ThreadingWSGIServer(ThreadingMixIn, WSGIServer):
            daemon_threads = True

        with make_server(args.host, args.port, app, server_class=ThreadingWSGIServer) as server:
            try:
                server.serve_forever()
            except KeyboardInterrupt:
                pass
        return 0
    waitress.serve(app, host=args.host, port=args.port, threads=8)
    return 0


def cmd_grant(args: argparse.Namespace) -> int:
    db = Database(Settings.from_env().db_path)
    if not db.set_comped(args.email, args.command == "grant"):
        print(f"No account for {args.email}. They need to sign up first.", file=sys.stderr)
        return 1
    print(f"{'Gave' if args.command == 'grant' else 'Removed'} free access for {args.email}.")
    return 0


def cmd_users(args: argparse.Namespace) -> int:
    users = Database(Settings.from_env().db_path).list_users()
    paying = sum(1 for u in users if u.has_access and not u.comped)
    print(f"{len(users)} accounts, {paying} with a paid subscription.")
    for status, count in sorted(Counter(u.subscription_status for u in users).items()):
        print(f"  {status}: {count}")
    if args.list:
        for u in users:
            flag = " (free access)" if u.comped else ""
            print(f"  {u.email}  {u.subscription_status}{flag}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="stockpicks",
        description="Paid website that ranks long-term stocks from SEC filings.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("refresh", help="analyze every company now and rewrite the picks")
    p.set_defaults(func=cmd_refresh)

    p = sub.add_parser("check", help="test your settings: SEC, prices, Stripe, storage")
    p.set_defaults(func=cmd_check)

    p = sub.add_parser("serve", help="run the website")
    p.add_argument("--host", default=os.environ.get("HOST", "127.0.0.1"),
                   help="address to listen on (default: %(default)s; use 0.0.0.0 on a server)")
    p.add_argument("--port", type=int, default=int(os.environ.get("PORT") or 8000),
                   help="port to listen on (default: %(default)s)")
    p.add_argument("--refresh", choices=["weekly", "daily", "off"],
                   default=(os.environ.get("REFRESH") or "weekly").lower(),
                   help="publish a new list every Monday (weekly), every day, or never (default: %(default)s)")
    p.set_defaults(func=cmd_serve)

    for name, text in (("grant", "give an account free access"), ("revoke", "remove free access")):
        p = sub.add_parser(name, help=text)
        p.add_argument("email")
        p.set_defaults(func=cmd_grant)

    p = sub.add_parser("users", help="count accounts and subscriptions")
    p.add_argument("--list", action="store_true", help="also list every account")
    p.set_defaults(func=cmd_users)
    return parser


def main(argv: list[str] | None = None) -> int:
    load_dotenv()
    args = build_parser().parse_args(argv)
    return args.func(args)
