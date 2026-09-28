"""Minimal JSON-over-HTTP helpers built on the standard library."""

from __future__ import annotations

import json
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

USER_AGENT = "rugguard/0.1 (+https://github.com/avcards0-ai/Trading-bot)"


class FetchError(Exception):
    """Raised when a remote API can't be reached or returns an error."""

    def __init__(self, url: str, message: str, status: int | None = None):
        super().__init__(f"{message} ({url})")
        self.url = url
        self.status = status


def get_json(url: str, timeout: float = 15, retries: int = 2, backoff: float = 1.5) -> Any:
    """GET a URL and decode JSON, retrying on 429/5xx and network errors."""
    last_error: FetchError | None = None
    for attempt in range(retries + 1):
        req = urllib.request.Request(
            url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"}
        )
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            last_error = FetchError(url, f"HTTP {e.code} {e.reason}", status=e.code)
            # Client errors other than rate limiting won't succeed on retry.
            if 400 <= e.code < 500 and e.code != 429:
                raise last_error from e
        except (urllib.error.URLError, TimeoutError, OSError, ValueError) as e:
            last_error = FetchError(url, str(e))
        if attempt < retries:
            time.sleep(backoff * (2**attempt))
    assert last_error is not None
    raise last_error


def post_json(url: str, payload: dict, timeout: float = 15) -> None:
    """POST a JSON body. Raises FetchError on failure.

    Webhook URLs embed secrets (bot tokens, webhook ids), so errors only
    report the host.
    """
    host = urllib.parse.urlsplit(url).netloc
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "User-Agent": USER_AGENT},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            resp.read()
    except urllib.error.HTTPError as e:
        raise FetchError(host, f"HTTP {e.code} {e.reason}", status=e.code) from e
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        raise FetchError(host, str(e)) from e
