"""Alert delivery: console, plus Telegram and Discord when configured."""

from __future__ import annotations

import os
import sys
import time
from dataclasses import dataclass
from typing import Callable, TextIO

from .net import FetchError, post_json
from .scanner import Severity


@dataclass
class Alert:
    mint: str
    symbol: str
    severity: Severity
    code: str
    message: str
    url: str = ""


def format_alert(alert: Alert) -> str:
    lines = [f"[{alert.severity.name}] {alert.symbol}: {alert.message}", alert.mint]
    if alert.url:
        lines.append(alert.url)
    return "\n".join(lines)


class Notifier:
    """Prints everything to the console and forwards serious alerts to chat."""

    def __init__(
        self,
        telegram_token: str | None = None,
        telegram_chat_id: str | None = None,
        discord_webhook: str | None = None,
        remote_min_severity: Severity = Severity.HIGH,
        out: TextIO | None = None,
        err: TextIO | None = None,
        post: Callable[[str, dict], None] = post_json,
    ):
        self.telegram_token = telegram_token
        self.telegram_chat_id = telegram_chat_id
        self.discord_webhook = discord_webhook
        self.remote_min_severity = remote_min_severity
        self.out = out or sys.stdout
        self.err = err or sys.stderr
        self.post = post

    @classmethod
    def from_env(cls, **kwargs) -> "Notifier":
        return cls(
            telegram_token=os.environ.get("TELEGRAM_BOT_TOKEN") or None,
            telegram_chat_id=os.environ.get("TELEGRAM_CHAT_ID") or None,
            discord_webhook=os.environ.get("DISCORD_WEBHOOK_URL") or None,
            **kwargs,
        )

    @property
    def channels(self) -> list[str]:
        names = []
        if self.telegram_token and self.telegram_chat_id:
            names.append("telegram")
        if self.discord_webhook:
            names.append("discord")
        return names

    def info(self, message: str) -> None:
        print(f"{time.strftime('%H:%M:%S')} {message}", file=self.out, flush=True)

    def warn(self, message: str) -> None:
        print(f"{time.strftime('%H:%M:%S')} WARNING: {message}", file=self.err, flush=True)

    def send(self, alert: Alert) -> None:
        text = format_alert(alert)
        self.info(text)
        if alert.severity < self.remote_min_severity:
            return
        if self.telegram_token and self.telegram_chat_id:
            self._deliver(
                "Telegram",
                f"https://api.telegram.org/bot{self.telegram_token}/sendMessage",
                {"chat_id": self.telegram_chat_id, "text": text, "disable_web_page_preview": True},
            )
        if self.discord_webhook:
            self._deliver("Discord", self.discord_webhook, {"content": text[:2000]})

    def _deliver(self, channel: str, url: str, payload: dict) -> None:
        try:
            self.post(url, payload)
        except FetchError as e:
            self.warn(f"{channel} alert failed: {e}")
