# rugguard: rug-pull protection for Solana memecoins

`rugguard` does two jobs:

1. **`scan`**: checks a token *before you buy* and gives it a risk score with plain-English reasons.
2. **`watch`**: guards tokens *you already hold* and alerts you (console, Telegram, Discord) the moment rug signals appear, such as liquidity being pulled, LP unlocked, whales dumping or the fee being raised.

It only reads public data from [RugCheck](https://rugcheck.xyz) (on-chain authorities, LP locks, holders) and [DexScreener](https://dexscreener.com) (price, liquidity, trades). It never touches your wallet or places trades.

> **Heuristics only, not financial advice.** A clean result does not mean a token is safe. Many rugs are
> slow dumps or social scams that no on-chain check can catch. Never put in more than you can lose.

## Setup

Python 3.9+ with no third-party dependencies.

```bash
git clone https://github.com/avcards0-ai/Trading-bot.git
cd Trading-bot
cp .env.example .env   # optional: add Telegram / Discord for watch alerts
```

## Scan before you buy

```bash
python -m rugguard scan <MINT_ADDRESS> [<MINT_ADDRESS> ...]
python -m rugguard scan -f watchlist.txt --json
```

Example output:

```
MCAT (Moon Cat)  7GCihgDB8fe6KNjn2MYtkzZcRjQy3t9GHdC8uHYmW2hr
  Verdict: AVOID   risk score 100/100
  Market:  $8.40K liquidity across 1 pair(s) | price $0.001 | mcap $1.00M | raydium
  Findings:
    [HIGH]   Mint authority is still enabled, so the dev can print more tokens and dump them on you.
    [HIGH]   Only 0% of liquidity is locked or burned, so the dev can pull the pool.
    [HIGH]   One wallet (9xQe…VFin) holds 35.0% of supply.
    [MEDIUM] Top 10 wallets hold 35.0% of supply.
    [MEDIUM] RugCheck linked 1 insider wallet(s) to this token, which is a common sign of bundled dev buys.
    [MEDIUM] Only $8,400 of liquidity.
    [MEDIUM] Pair is only 25 minutes old.
    [LOW]    Metadata is mutable, so the name and image can be changed later.
```

### What it checks

| Check | Severity | Why it matters |
|---|---|---|
| RugCheck marks token as rugged | CRITICAL | Already happened |
| Mint authority enabled | HIGH | Dev can mint unlimited supply and dump it |
| Freeze authority enabled | HIGH | Dev can freeze your tokens so you can't sell |
| LP < 50% locked/burned (< 90% = MEDIUM) | HIGH | Dev can withdraw the liquidity pool |
| Token-2022 transfer fee (≥ 10% = HIGH) | MEDIUM/HIGH | Hidden tax on every transfer and sell |
| Top 10 wallets ≥ 50% of supply (≥ 30% = MEDIUM) | HIGH | A few wallets can crash the price |
| Single wallet ≥ 20% (≥ 10% = MEDIUM) | HIGH | One wallet can crash the price |
| Insider or bundled wallets detected | MEDIUM | Dev sniped their own launch |
| Many buys, zero sells in the last hour | HIGH | Classic honeypot pattern |
| Price down ≥ 50% in the last hour | HIGH | Dump in progress |
| Liquidity < $2k (< $10k = MEDIUM) | HIGH | Easy to drain, hard to exit |
| Pair < 1 hour old (< 24h = LOW) | MEDIUM | Most rugs happen early |
| Mutable metadata | LOW | Name and image can be changed |
| Other RugCheck warnings (copycat, creator rug history, …) | per RugCheck | |

Liquidity-pool and locker accounts are excluded from holder concentration, so the pool itself doesn't count as a whale. If RugCheck or DexScreener can't be reached, that gets flagged as a risk rather than treated as clean.

**Score:** HIGH = 35, MEDIUM = 15, LOW = 5, capped at 100.
**Verdict:** `AVOID` (≥ 70 or any CRITICAL), `HIGH RISK` (≥ 35), `CAUTION` (≥ 15), `NO MAJOR RED FLAGS`.

## Guard what you hold

```bash
python -m rugguard watch <MINT_ADDRESS> [<MINT_ADDRESS> ...]
python -m rugguard watch -f holdings.txt --interval 20 --liquidity-drop 30
```

It first scans every token to set a baseline. It then polls DexScreener every `--interval` seconds (default 30) and re-checks RugCheck every `--rugcheck-interval` seconds (default 300). It alerts on:

| Alert | Severity | Trigger |
|---|---|---|
| `LIQUIDITY_PULLED` | CRITICAL | Total liquidity drops ≥ `--liquidity-drop`% (default 40) within `--window` minutes (default 10) |
| `PAIR_GONE` | CRITICAL | The token's DEX pairs disappear for 2 polls in a row |
| `LP_UNLOCKED` | CRITICAL | Locked LP falls by ≥ 20 percentage points |
| `RUGGED` | CRITICAL | RugCheck starts flagging the token as rugged |
| `PRICE_CRASH` | HIGH | Price drops ≥ `--price-drop`% (default 50) within the window |
| `WHALE_DUMP` | HIGH | A holder with ≥ 3% of supply sells half or more, or leaves the top holders |
| `FEE_RAISED` | HIGH | Transfer fee increases |
| `MINT_AUTHORITY` / `FREEZE_AUTHORITY` | HIGH | Authority is set to a new address |
| `NO_SELLS` | HIGH | Many buys, zero sells (selling may be blocked) |
| `SCAN_AVOID` | HIGH | Initial scan verdict is AVOID |

Each alert type fires at most once per token every 10 minutes. Every alert is printed to the console. Alerts at `--notify-level` (default `HIGH`) or above are also pushed to Telegram and Discord.

### Telegram / Discord alerts

Put these in `.env` (see `.env.example`):

- **Telegram:** create a bot with [@BotFather](https://t.me/BotFather) and set `TELEGRAM_BOT_TOKEN`. Message your bot once, then get your `TELEGRAM_CHAT_ID` from `https://api.telegram.org/bot<TOKEN>/getUpdates`.
- **Discord:** Channel settings → Integrations → Webhooks → New Webhook. Set `DISCORD_WEBHOOK_URL`.

To keep it running on a server: `nohup python -m rugguard watch -f holdings.txt > rugguard.log 2>&1 &`

## Limitations

- **Pump.fun tokens still on the bonding curve** have no LP yet, so there's no LP-lock result. Authority and holder checks still apply.
- **Rate limits:** both APIs are free and public. Keep `--interval` at 15s or more, and keep the watchlist to a few dozen tokens.
- **Latency:** alerts are only as fast as the polling interval plus the indexers' delay. A dev who pulls liquidity in one block can beat any polling bot. The guard helps you react, but it can't make you front-run a rug.
- **Heuristics:** legit tokens can trip these checks and scams can pass them. Use the output as one input, not the decision.

## Tests

```bash
python -m unittest discover -s tests -t .
```

The tests run offline against recorded-shape API fixtures in `tests/helpers.py`.

## Layout

```
rugguard/
  cli.py                 scan / watch commands
  scanner.py             risk scoring for one token
  guard.py               polling loop and change detection for held tokens
  alerts.py              console, Telegram and Discord delivery
  config.py              thresholds (ScanThresholds, GuardSettings) and .env loader
  net.py                 stdlib HTTP + JSON with retries
  sources/rugcheck.py    RugCheck report parser
  sources/dexscreener.py DexScreener pair parser
```
