"""HTTP helpers built on the standard library: gzip, retries and polite pacing."""

from __future__ import annotations

import gzip
import json
import threading
import time
import urllib.error
import urllib.request
from typing import Any

DEFAULT_USER_AGENT = "stockpicks/0.1 (+https://github.com/avcards0-ai/Trading-bot)"


class FetchError(Exception):
    """Raised when a remote API can't be reached or returns an error."""

    def __init__(self, url: str, message: str, status: int | None = None):
        super().__init__(f"{message} ({url})")
        self.url = url
        self.status = status


class Http:
    """A small HTTP client that spaces requests out by `min_interval` seconds.

    SEC EDGAR allows at most 10 requests per second per client and blocks
    clients that don't send a descriptive User-Agent.
    """

    def __init__(
        self,
        user_agent: str = DEFAULT_USER_AGENT,
        min_interval: float = 0.0,
        timeout: float = 30,
        retries: int = 2,
        backoff: float = 2.0,
    ):
        self.user_agent = user_agent
        self.min_interval = min_interval
        self.timeout = timeout
        self.retries = retries
        self.backoff = backoff
        self._lock = threading.Lock()
        self._last = 0.0

    def _pace(self) -> None:
        with self._lock:
            wait = self._last + self.min_interval - time.monotonic()
            if wait > 0:
                time.sleep(wait)
            self._last = time.monotonic()

    def get_bytes(self, url: str, accept: str = "*/*") -> bytes:
        last_error: FetchError | None = None
        for attempt in range(self.retries + 1):
            self._pace()
            req = urllib.request.Request(
                url,
                headers={
                    "User-Agent": self.user_agent,
                    "Accept": accept,
                    "Accept-Encoding": "gzip",
                },
            )
            try:
                with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                    body = resp.read()
                    if resp.headers.get("Content-Encoding") == "gzip":
                        body = gzip.decompress(body)
                    return body
            except urllib.error.HTTPError as e:
                last_error = FetchError(url, f"HTTP {e.code} {e.reason}", status=e.code)
                # Client errors other than rate limiting won't succeed on retry.
                if 400 <= e.code < 500 and e.code != 429:
                    raise last_error from e
            except (urllib.error.URLError, TimeoutError, OSError, EOFError) as e:
                last_error = FetchError(url, str(e))
            if attempt < self.retries:
                time.sleep(self.backoff * (2**attempt))
        assert last_error is not None
        raise last_error

    def get_json(self, url: str) -> Any:
        body = self.get_bytes(url, accept="application/json")
        try:
            return json.loads(body.decode("utf-8"))
        except ValueError as e:
            raise FetchError(url, f"invalid JSON: {e}") from e

    def get_text(self, url: str) -> str:
        return self.get_bytes(url).decode("utf-8", errors="replace")
