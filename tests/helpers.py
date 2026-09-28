"""Fixtures shaped like real RugCheck and DexScreener API responses."""

from __future__ import annotations

import copy

from rugguard.net import FetchError

MINT = "7GCihgDB8fe6KNjn2MYtkzZcRjQy3t9GHdC8uHYmW2hr"
OTHER_MINT = "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"
NOW = 1_790_000_000.0


def make_report(mint: str = MINT, **overrides) -> dict:
    """A RugCheck /tokens/{mint}/report body for a token with no red flags."""
    report = {
        "mint": mint,
        "creator": "Creator1111111111111111111111111111111111",
        "token": {"mintAuthority": None, "freezeAuthority": None, "supply": 1_000_000_000},
        "mintAuthority": None,
        "freezeAuthority": None,
        "tokenMeta": {"name": "Test Coin", "symbol": "TEST", "mutable": False},
        "transferFee": {"pct": 0, "maxAmount": 0, "authority": "11111111111111111111111111111111"},
        "topHolders": [
            # The pool vault is the biggest "holder" but must be ignored.
            {"address": "PoolVault11111111111111111111111111111111", "owner": "RaydiumAuth1111111111111111111111111111111",
             "pct": 40.0, "insider": False},
            {"address": "HolderA111111111111111111111111111111111", "owner": "WalletA111111111111111111111111111111111",
             "pct": 4.0, "insider": False},
            {"address": "HolderB111111111111111111111111111111111", "owner": "WalletB111111111111111111111111111111111",
             "pct": 3.0, "insider": False},
            {"address": "HolderC111111111111111111111111111111111", "owner": "WalletC111111111111111111111111111111111",
             "pct": 2.0, "insider": False},
        ],
        "knownAccounts": {
            "RaydiumAuth1111111111111111111111111111111": {"name": "Raydium Authority V4", "type": "AMM"},
        },
        "markets": [
            {
                "pubkey": "Market111111111111111111111111111111111111",
                "marketType": "raydium",
                "liquidityAAccount": "PoolVault11111111111111111111111111111111",
                "liquidityBAccount": "PoolVaultB1111111111111111111111111111111",
                "lp": {"lpLockedPct": 100, "baseUSD": 60_000, "quoteUSD": 60_000},
            }
        ],
        "risks": [],
        "rugged": False,
        "totalHolders": 4200,
        "graphInsidersDetected": 0,
        "score_normalised": 1,
    }
    report.update(overrides)
    return report


def make_pair(
    mint: str = MINT,
    liquidity: float = 120_000,
    price: float = 0.001,
    pair_address: str = "Pair1111111111111111111111111111111111111",
    created_at: float = NOW - 30 * 86400,
    buys_h1: int = 50,
    sells_h1: int = 40,
    change_h1: float = 2.0,
) -> dict:
    """One pair object as returned by DexScreener /tokens/v1/solana/{mints}."""
    return {
        "chainId": "solana",
        "dexId": "raydium",
        "url": f"https://dexscreener.com/solana/{pair_address.lower()}",
        "pairAddress": pair_address,
        "baseToken": {"address": mint, "name": "Test Coin", "symbol": "TEST"},
        "quoteToken": {"address": "So11111111111111111111111111111111111111112", "name": "Wrapped SOL", "symbol": "SOL"},
        "priceNative": "0.00001",
        "priceUsd": str(price),
        "txns": {"m5": {"buys": 5, "sells": 4}, "h1": {"buys": buys_h1, "sells": sells_h1}},
        "volume": {"h24": 500_000},
        "priceChange": {"m5": 0.1, "h1": change_h1, "h24": 10},
        "liquidity": {"usd": liquidity, "base": 1, "quote": 1},
        "fdv": 1_000_000,
        "marketCap": 1_000_000,
        "pairCreatedAt": int(created_at * 1000),
    }


class FakeFetch:
    """Stands in for net.get_json, routing by URL.

    `rugcheck` and `dex` are queues of responses, one consumed per call; the
    last one keeps repeating. A queued exception is raised instead.
    """

    def __init__(self, rugcheck=(), dex=()):
        self.queues = {"rugcheck": list(rugcheck), "dex": list(dex)}
        self.urls: list[str] = []

    def _next(self, key: str):
        queue = self.queues[key]
        if not queue:
            raise AssertionError(f"no {key} response queued")
        item = queue.pop(0) if len(queue) > 1 else queue[0]
        if isinstance(item, Exception):
            raise item
        return copy.deepcopy(item)

    def __call__(self, url: str):
        self.urls.append(url)
        if "rugcheck" in url:
            return self._next("rugcheck")
        if "dexscreener" in url:
            return self._next("dex")
        raise AssertionError(f"unexpected URL {url}")


def not_found(url: str = "https://api.rugcheck.xyz") -> FetchError:
    return FetchError(url, "HTTP 404 Not Found", status=404)
