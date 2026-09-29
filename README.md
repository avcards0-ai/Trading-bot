# MemeGuard

Rug-detection-first analysis and risk-gated trading for newly launched meme coins
(Solana, Ethereum, Base, BSC, Arbitrum).

MemeGuard discovers new pools, pulls on-chain, contract, holder, liquidity and market data from
several independent sources, and scores every token for rug-pull and honeypot risk. It then decides
**BUY / SELL / HOLD / SKIP** with structured reasoning. It trades **only in paper mode by default**.
No order is placed unless every configured risk check passes. When data is missing or a check
errors, the system treats that as risk and does not trade (it fails closed).

> **This is a detection and defensive-trading tool.** It flags rug pulls, honeypots, hidden
> minting, liquidity removal, wash trading, coordinated wallets and malicious contract features.
> It does **not** create tokens, manipulate markets, or contain any wallet-draining, backdoor or
> stealth-ownership functionality.
>
> Meme-coin trading is extremely risky. The strategy is a transparent heuristic, **not a proven
> edge**. Most new tokens go to zero, and a low rug score is not a guarantee. Use paper mode. If you
> ever go live, use a dedicated wallet holding only money you can afford to lose.

---

## Contents

1. [Quick start (local, no database server)](#quick-start-local-no-database-server)
2. [Quick start (Docker + PostgreSQL)](#quick-start-docker--postgresql)
3. [Configuration](#configuration)
4. [Paper trading](#paper-trading)
5. [Launch sniper (paper only)](#launch-sniper-paper-only)
6. [X (Twitter) tracker](#x-twitter-tracker)
7. [Rug scanner](#rug-scanner)
8. [Backtesting](#backtesting)
9. [Tests and quality checks](#tests-and-quality-checks)
10. [Enabling live trading](#enabling-live-trading)
11. [Architecture](#architecture)
12. [Rug-risk model](#rug-risk-model)
13. [Risk management](#risk-management)
14. [API reference](#api-reference)
15. [Security](#security)
16. [Known limitations](#known-limitations)

---

## Quick start (local, no database server)

Requirements: **Node.js ≥ 22** and npm. By default the backend uses embedded PostgreSQL
(PGlite), so no database server is needed.

```bash
git clone <this repo> memeguard && cd memeguard
npm ci
cp .env.example .env
# Set an admin key (required for POST endpoints and dashboard actions):
sed -i "s/^API_KEY=.*/API_KEY=$(openssl rand -hex 32)/" .env      # macOS: sed -i ''

npm run dev            # backend  → http://127.0.0.1:8080   (migrates the DB automatically)
npm run dev:frontend   # dashboard → http://localhost:5173  (second terminal)
```

Open the dashboard and go to **Settings**. Paste the `API_KEY` to enable admin actions (scan,
paper trade, close position, engine control, strategy edits). The key is kept in browser storage
and sent only in the `Authorization` header, never in URLs.

Production build:

```bash
npm run build          # backend → apps/backend/dist, frontend → apps/frontend/dist
npm start              # runs the built backend (reads .env)
npm run preview -w @memeguard/frontend   # serves the built dashboard on :4173 with the /api proxy
```

## Quick start (Docker + PostgreSQL)

```bash
cp .env.example .env
# Required by compose:
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 24)/" .env
sed -i "s/^API_KEY=.*/API_KEY=$(openssl rand -hex 32)/" .env

docker compose up --build -d
# dashboard → http://localhost:8081      API → http://127.0.0.1:8080
docker compose logs -f backend
docker compose down            # add -v to also delete the database volume
```

The stack runs `postgres:16-alpine`, the backend (non-root, health-checked, migrations applied at
boot) and the dashboard (nginx, which proxies `/api` including the SSE stream). Ports bind to
`127.0.0.1` only.

If your network intercepts TLS (a corporate proxy) and `npm ci` fails with
`SELF_SIGNED_CERT_IN_CHAIN`, build the images with the proxy CA as a BuildKit secret. The CA is
used only during the build and is not stored in the image. Then start compose without `--build`:

```bash
docker build --secret id=npm_ca,src=/path/to/ca-bundle.crt \
  -f apps/backend/Dockerfile -t memeguard-backend:local .
docker build --secret id=npm_ca,src=/path/to/ca-bundle.crt \
  -f apps/frontend/Dockerfile -t memeguard-frontend:local .
docker compose up -d
```

---

## Configuration

All configuration comes from environment variables (`.env` is loaded automatically). See
[`.env.example`](.env.example) for the full, commented list. The process validates everything at
startup and refuses to start on invalid values.

| Variable                                                                              | Default                    | Purpose                                                                                                     |
| ------------------------------------------------------------------------------------- | -------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `RPC_URL`                                                                             | –                          | Solana RPC (mint/freeze authority, Token-2022 extensions, holders, wallet ages). Required for live trading. |
| `WALLET_PRIVATE_KEY` / `WALLET_KEYPAIR_PATH`                                          | –                          | **Live mode only.** Prefer a 0600 keypair file. Never needed for paper trading.                             |
| `API_KEY`                                                                             | –                          | Admin API key (≥ 24 chars). Admin endpoints are **disabled** while empty.                                   |
| `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`                                              | –                          | Telegram alerts.                                                                                            |
| `DISCORD_WEBHOOK_URL`                                                                 | –                          | Discord alerts.                                                                                             |
| `DATABASE_URL`                                                                        | `pglite://./data/pglite`   | `postgres://…`, `pglite://<dir>` or `pglite://memory`.                                                      |
| `TRADING_MODE`                                                                        | `paper`                    | `paper` or `live` (see [live trading](#enabling-live-trading)).                                             |
| `AUTO_TRADE` / `ENGINE_AUTOSTART`                                                     | `true`                     | Let the engine enter positions automatically / start discovery at boot.                                     |
| `CHAINS`                                                                              | `solana,base,ethereum,bsc` | Chains to scan.                                                                                             |
| `ETHEREUM_RPC_URL`, `BASE_RPC_URL`, `BSC_RPC_URL`, `ARBITRUM_RPC_URL`                 | –                          | EVM bytecode, proxy and owner analysis.                                                                     |
| `ETHERSCAN_API_KEY`                                                                   | –                          | Contract verification, deployer history and wallet ages on EVM chains.                                      |
| `GOPLUS_APP_KEY/SECRET`, `HONEYPOT_IS_API_KEY`, `RUGCHECK_API_KEY`, `JUPITER_API_KEY` | –                          | Optional keys that raise provider rate limits.                                                              |
| `ANTHROPIC_API_KEY`, `LLM_REVIEW_ENABLED`                                             | –, `false`                 | Optional LLM second opinion that can only **raise** risk.                                                   |

**Hard risk limits** (runtime strategy edits may only make these stricter):

| Variable                      | Default | Meaning                                                                            |
| ----------------------------- | ------- | ---------------------------------------------------------------------------------- |
| `MAX_POSITION_PERCENT`        | 2       | Max position size, % of equity                                                     |
| `MAX_DAILY_LOSS`              | 5       | Max loss per UTC day, % of day-start equity. Halts new entries until the next day. |
| `MAX_DRAWDOWN`                | 20      | Max drawdown from peak, %. Halts trading until manually resumed.                   |
| `MAX_OPEN_POSITIONS`          | 5       | Simultaneous positions                                                             |
| `MIN_LIQUIDITY`               | 25000   | Minimum pool liquidity, USD                                                        |
| `MAX_RUG_SCORE`               | 35      | Maximum acceptable RUG_SCORE (0–100)                                               |
| `MAX_SLIPPAGE`                | 3       | Maximum expected entry price impact, %                                             |
| `MIN_TOKEN_AGE`               | 30      | Minimum pair age, minutes                                                          |
| `MAX_LIQUIDITY_SHARE_PERCENT` | 1       | A position may not exceed this % of pool liquidity                                 |
| `REQUIRE_HONEYPOT_CHECK`      | true    | Refuse entries unless sellability was verified                                     |
| `MAX_DATA_AGE_SECONDS`        | 120     | Stale market data means no trade                                                   |

The `STRATEGY_*` variables are defaults for the editable strategy (stop loss, take profit,
trailing stop, max hold time, risk per trade, entry thresholds, exit triggers).

---

## Paper trading

Paper trading is the default. Nothing extra is needed:

```bash
npm run dev            # engine autostarts: discovery → analysis → risk checks → paper orders
```

The paper executor simulates real execution costs:

- **price impact** from the pool's constant-product curve, based on current liquidity;
- **DEX fees, network fees** (per chain) and the token's **buy/sell taxes**;
- **latency drift** between decision and fill, and **slippage-limit reverts**;
- **random transaction failures** (`PAPER_FAILURE_RATE`; the network fee is still charged);
- **liquidity limits**: an order larger than the allowed share of the pool is refused.

Positions are monitored every `MONITOR_INTERVAL_SECONDS`. Exit rules run in priority order:
rug-risk escalation → liquidity pull → stop loss → trailing stop → take profit → max hold time.
Every exit is recorded as a SELL decision linked to its trade.

Manual paper trades (admin key required):

```bash
KEY=<your API_KEY>
# Buy: runs the full pipeline, including every risk check. Refused if any check fails.
curl -s -X POST http://127.0.0.1:8080/paper-trade -H "Authorization: Bearer $KEY" \
  -H 'content-type: application/json' \
  -d '{"chain":"solana","address":"<mint>","side":"buy","amountUsd":100}'
# Sell / close:
curl -s -X POST http://127.0.0.1:8080/paper-trade -H "Authorization: Bearer $KEY" \
  -H 'content-type: application/json' -d '{"chain":"solana","address":"<mint>","side":"sell"}'
curl -s -X POST http://127.0.0.1:8080/positions/<id>/close -H "Authorization: Bearer $KEY"
```

Engine control: `POST /engine/start`, `POST /engine/stop` (stops new entries; open positions
remain protected by the monitor), and `POST /risk/resume` (clears a drawdown halt).

### Soak test (timed paper run on live data)

The most realistic check short of real money: run the whole engine against the live market for a
fixed time, then read one report.

```bash
npm run soak -- --minutes 30                  # writes soak-report.json and prints a summary
npm run soak -- --minutes 120 --out run2.json # longer run
```

It always runs in paper mode, whatever `TRADING_MODE` says, and never loads a wallet. It uses a
fresh in-memory database, so your normal paper account is untouched (`--db` overrides this). The
report covers:

- tokens found and analysed, risk verdicts, likely scams and the most common red flags;
- decisions and their reasons;
- paper trades and P/L;
- the health of every data source. It says in plain words when a source is failing, rate-limited,
  or answering in a format the adapter no longer understands.

Run it before anything else on a new machine or after a long break: it is the quickest way to
find a provider that changed its API. Thirty minutes shows whether the pipeline works on real data;
it is far too short to judge profitability.

## Launch sniper (paper only)

The sniper is an optional part of the engine that tries to buy brand-new Solana tokens within
seconds of their pool being created. It is **off by default**, runs in **paper mode only**, and
refuses to start when `TRADING_MODE=live`.

Turn it on in `.env` (it needs a Solana `RPC_URL`), then start the engine:

```bash
SNIPER_ENABLED=true
RPC_URL=https://<your Solana RPC provider>
```

How it works:

1. **Listens in real time.** It subscribes to the logs of the launch programs (`SNIPER_SOURCES`:
   Raydium AMM v4, Raydium CPMM and PumpSwap by default) over your RPC provider's WebSocket.
   It reacts only to **confirmed** pool creations. It never front-runs or sandwiches other traders'
   pending transactions.
2. **Checks the launch, failing closed.** It uses only what can be known at launch, and the first
   failed check ends the attempt:
   - its own budget: open sniper positions, trades per day, daily loss, cash, and the global limits;
   - the launch is still fresh (`SNIPER_MAX_LAUNCH_AGE_SECONDS`);
   - the liquidity is secured: LP tokens are burned, sent to the incinerator, or held by a program
     account such as a locker or launchpad. LP held by an ordinary wallet, or no LP token at all,
     fails;
   - enough starting liquidity;
   - mint and freeze authority revoked, and no dangerous Token-2022 features (permanent delegate,
     transfer hook, pausable, high transfer fee, …);
   - the creator holds at most `SNIPER_MAX_CREATOR_PERCENT` and no other wallet more than
     `SNIPER_MAX_TOP_HOLDER_PERCENT`;
   - the creator's wallet is old enough, and no earlier token by the same creator was flagged by
     this bot;
   - price impact is acceptable;
   - a Jupiter buy-and-sell-back quote works, which rules out honeypots. New pools can take a few
     seconds to become routable; it waits up to `SNIPER_SELL_ROUTE_WAIT_SECONDS`.
3. **Buys small, sells fast.** It buys a fixed `SNIPER_POSITION_USD` at the pool's current on-chain
   price, using the same paper execution model as the main strategy. Its positions are priced from
   the pool's vaults every `SNIPER_MONITOR_SECONDS`. They exit on stop loss, take profit, the
   short `SNIPER_MAX_HOLD_MINUTES` limit, or a liquidity pull. If the pool is emptied, the
   position is written off as a total loss, because there is nothing left to sell into.

Every launch that gets past the budget checks is recorded as a decision (BUY or
`SKIP — SNIPER: <reason>`) with each check's result. The **Launch sniper** dashboard page shows:

- whether the WebSocket stream is connected;
- how many launches were seen, checked and bought;
- **why launches were skipped**;
- **how many seconds after launch it bought, and how much more it paid than the opening price.**

The last two numbers tell you quickly whether the sniper can compete. Professional snipers use
private transaction bundles and servers next to the validators, and usually buy in the same block
as the launch. This bot typically arrives seconds later.

`GET /sniper` returns the same status as JSON.

## X (Twitter) tracker

Read-only tracking of X, using the official X API v2 (no scraping). It never posts, likes,
follows or sends messages. Off unless `X_BEARER_TOKEN` is set.

```bash
X_BEARER_TOKEN=<app-only bearer token from the X developer portal>
X_TRACKED_ACCOUNTS=handle1,handle2      # accounts whose posts you want watched
```

It does two things:

1. **Watches accounts for token calls.** Every `X_POLL_SECONDS` it reads the listed accounts' new
   posts and pulls out contract addresses, both typed ones and ones inside DexScreener,
   pump.fun or similar links. Addresses seen only in links are confirmed as tokens first (a
   link can point at a pool). EVM addresses are matched to their chain. Each new call is recorded
   and raises a `SOCIAL_MENTION` alert. The token is then queued for the **full analysis**; it is
   bought only if every rug and risk check passes, exactly like any other token.
2. **Checks who is posting a token.** For tokens being analysed, it searches recent posts that
   mention the contract address (up to `X_MAX_SEARCHES_PER_HOUR`), and looks up the X account
   the token lists on DexScreener. The rug model uses this only to **raise** risk, in the
   market-integrity category:
   - the listed account doesn't exist or was suspended;
   - the listed account is under a week old;
   - coordinated promotion: most posting accounts are under 30 days old, or most posts are
     copy-pasted.

   Missing X data is never counted against a token, because X is optional.

The **X tracker** page shows each watched account's status and the latest calls, with the
bot's own rug score and decision next to every one. It also lists the most-called tokens of the
last 24 hours. Each token page has a **Social (X)** tab. `GET /social` returns the same data.

Promoted tokens are often paid placements or pump-and-dumps: treat a call as a lead to check,
never as a reason to buy.

## Rug scanner

Analyse any token without trading:

```bash
npm run scan -- --chain solana --address <mint>
npm run scan -- --chain base --address 0x… --json      # raw decision + report JSON
npm run scan -- --chain solana --address <mint> --trade # may place a PAPER order if all checks pass
```

The output includes RUG_SCORE, HONEYPOT_RISK, LIQUIDITY_RISK, CONTRACT_RISK,
WALLET_CONCENTRATION_RISK, DEVELOPER_RISK, MARKET_INTEGRITY_RISK and OVERALL_RISK. It also lists
the explanation for each, every contributing factor, the pipeline stages, the risk checks, and
which data sources failed (failed sources are treated as risk).

Via the API: `POST /scan {"chain","address"}`, then `GET /risk/:address` or
`GET /tokens/:address`. `POST /scan {"discover":true}` triggers one discovery pass.

## Backtesting

```bash
npm run backtest                                   # synthetic dataset (clearly labelled SYNTHETIC)
npm run backtest -- --tokens 500 --seed 7 --save   # save → visible on the dashboard's Backtest page
npm run backtest -- --source db                    # replay tokens recorded by the running engine
npm run backtest -- --source file --file data.json --out result.json
```

Backtests replay history through the **same** rug detector, strategy, position sizing and risk
manager used in live operation. Fills are pessimistic:

- if a bar touches both the stop and the target, the stop is assumed to fill first;
- a gap through the stop fills at the bar's open;
- a rug exits at the bar's low;
- a honeypot is unsellable.

Reported metrics: total return, max drawdown, trades, win rate, average win/loss, profit factor,
largest gain/loss, expectancy, Sharpe/Sortino (per trade), Calmar, CVaR 95%, exposure and fees. It
also reports scams avoided vs. hit, and lists every **catastrophic loss explicitly** (loss beyond
`CATASTROPHIC_LOSS_PERCENT`, rug while holding, stop gap-through, drawdown breach).

The synthetic generator mixes organic tokens with pump-and-dumps, rug pulls, stealth rugs,
honeypots and slow bleeds. Treat its results as a test of the **safety machinery**, not as evidence
of profitability. File datasets follow the schema in
[`apps/backend/src/backtest/types.ts`](apps/backend/src/backtest/types.ts): tokens with OHLCV
`bars`, optional `security` snapshot, `riskTimeline`, `events` and `outcome`. Datasets without
security data are treated as risky unless you pass `--assume-clean-security`; the report flags that
as optimistic.

---

## Tests and quality checks

```bash
npm test                   # backend (unit + integration) and frontend tests
npm run test:unit          # backend unit tests
npm run test:integration   # API + engine end-to-end against embedded PostgreSQL
npm run typecheck
npm run lint
npx prettier --check .

# Optional: run the PostgreSQL integration test against a real server
TEST_DATABASE_URL=postgres://user:pass@127.0.0.1:5432/memeguard_test npm run test:integration
```

Integration tests use a fake network (`test/helpers/fakeWorld.ts`) that serves each provider's
documented response format. That covers clean tokens, honeypots, mint/freeze authority, unlocked
LP, high tax, provider outages and rate limiting. Tests never touch real APIs or wallets.

---

## Enabling live trading

Live trading is **off** unless you configure all of the following. If any is missing, the process
refuses to start. It never silently falls back to paper.

1. `TRADING_MODE=live`
2. `LIVE_TRADING_CONFIRMATION=I_UNDERSTAND_LIVE_TRADING_CAN_LOSE_REAL_MONEY`
3. Exactly one of `WALLET_KEYPAIR_PATH` (recommended; the file must be `chmod 600`) or
   `WALLET_PRIVATE_KEY`, for a **dedicated** hot wallet
4. `RPC_URL` (a dedicated Solana RPC provider)
5. `API_KEY` set
6. `REQUIRE_HONEYPOT_CHECK=true`
7. `LIVE_MAX_POSITION_USD` > 0: an absolute USD cap per position, on top of the % limits
8. `CHAINS` must include `solana`. Live execution is implemented for Solana only (Jupiter
   routing). Entries on other chains are rejected by the `LIVE_EXECUTION_SUPPORTED` risk check.

Recommended first steps: start with tiny limits (`LIVE_MAX_POSITION_USD=5`, `MAX_OPEN_POSITIONS=1`),
set `AUTO_TRADE=false`, and use `npm run scan -- --trade` on tokens you have reviewed yourself. The
trading mode cannot be changed at runtime, and `POST /paper-trade` is disabled in live mode.

Before every live buy, the executor gets a Jupiter quote for the full round trip. The sell leg must
be routable, and slippage must be within limits. The executor signs locally and checks that the fee
payer is your wallet. It then confirms the transaction on-chain and records the actual balance
changes.

---

## Architecture

```
┌────────────────────────── apps/backend (Fastify, TypeScript) ──────────────────────────┐
│                                                                                        │
│  Engine loops ─ discovery (GeckoTerminal new pools, DexScreener profiles)              │
│               ─ watchlist (re-analyse young tokens)                                    │
│               ─ position monitor (always on: SL/TP/trailing/rug/liquidity exits)       │
│               ─ metrics (equity, daily loss & drawdown halts)                          │
│        │ priority work queue (dedupe, bounded, concurrency-capped)                     │
│        ▼                                                                               │
│  Decision pipeline                                                                     │
│   DISCOVERY → ON_CHAIN → CONTRACT → WALLET → LIQUIDITY → MARKET → RUG_RISK             │
│             → STRATEGY → RISK_CHECK → EXECUTION (paper | live)                         │
│        │                                                                               │
│  Adapters (rate-limited, retried, circuit-broken, schema-validated HTTP)               │
│   DexScreener · GeckoTerminal · GoPlus · Honeypot.is · RugCheck · Etherscan V2         │
│   Solana RPC (mint, Token-2022, holders, wallet funding) · EVM RPC (bytecode) · Jupiter│
│        │                                                                               │
│  PostgreSQL / PGlite (Drizzle, SQL migrations) · Alerts (Telegram, Discord) · SSE      │
└──────────────────────────────────────┬─────────────────────────────────────────────────┘
                                       │ REST + Server-Sent Events
┌──────────────────────────────────────▼─────────────────────────────────────────────────┐
│  apps/frontend (React, Vite, TanStack Query, lightweight-charts)                       │
│  Dashboard · Tokens · Risk leaderboard · Token detail · Positions · Performance        │
│  Backtests · Alert center · System status · Settings/strategy                          │
└────────────────────────────────────────────────────────────────────────────────────────┘
packages/shared: domain and API types shared by both apps
```

Code map (`apps/backend/src`):

| Path         | Responsibility                                                                              |
| ------------ | ------------------------------------------------------------------------------------------- |
| `config/`    | env validation, live-trading gate, runtime strategy store (tighten-only)                    |
| `lib/`       | HTTP client (rate limit, retry, circuit breaker), logger with secret redaction, math        |
| `adapters/`  | one adapter per external source, plus Solana/EVM inspectors and Jupiter                     |
| `analysis/`  | snapshot collection and conservative merge, trade-flow analysis, rug detector, LLM reviewer |
| `strategy/`  | market signals, entry/exit rules, position sizing                                           |
| `risk/`      | `RiskManager`: every pre-trade check, fail closed                                           |
| `execution/` | AMM impact model, paper executor, live Solana executor                                      |
| `trading/`   | portfolio accounting and halts, trade service, exit decisions                               |
| `engine/`    | decision pipeline, loops, work queue                                                        |
| `alerts/`    | alert rules, dedupe/rate limit, Telegram and Discord notifiers                              |
| `backtest/`  | replay engine, metrics, synthetic scenarios, data sources                                   |
| `api/`       | REST routes, auth, SSE                                                                      |
| `db/`        | schema, client (Postgres or PGlite), repositories; migrations in `apps/backend/drizzle`     |
| `cli/`       | `migrate`, `scan`, `backtest`                                                               |

Database tables: `tokens`, `wallets`, `token_wallets`, `transactions`, `trades`, `positions`,
`risk_scores`, `price_history`, `liquidity_history`, `ai_decisions`, `alerts`,
`performance_metrics`, `accounts`, `strategy_configs`, `backtest_runs`, `event_log`. Change the schema in
`src/db/schema.ts`, run `npm run db:generate` to create a new SQL migration, then
`npm run db:migrate` (or rely on `DB_AUTO_MIGRATE=true`).

## Rug-risk model

The detector is deterministic and explainable. Each signal becomes a **factor** with points and a
plain-language explanation. Factors are grouped into categories: honeypot, liquidity, contract,
concentration, developer, market integrity and data quality.

- Within a category, factors combine by noisy-OR, so independent red flags compound without
  exceeding 100.
- Categories combine with a weighted p-norm (p = 3), so the worst category dominates. Many small
  issues do not add up to a high score.
- A **critical** factor forces RUG_SCORE ≥ 90 and marks the token "likely scam". Examples:
  confirmed honeypot, ≥ 50% sell tax, owner can change balances, permanent delegate, already
  rugged, active developer dumping.
- Levels: `< 25` LOW, `< 50` MEDIUM, `< 75` HIGH, `≥ 75` CRITICAL. OVERALL_RISK is the worse of
  the score's level and the worst core category.
- **Missing data is risk.** An unverified sell simulation, unknown contract or unknown LP lock
  adds points, so a token can never look safe because a provider was down.
- History-aware: liquidity pulls, tax increases, contract-code changes and ownership changes
  between analyses raise the score and trigger alerts.

Signals covered: mint and freeze authority, ownership/renounce status, proxy/upgradeable
contracts, hidden owner, balance-modifying and blacklist functions, trading cooldowns and pause
switches, Token-2022 extensions (transfer hooks, permanent delegate, transfer fees), buy/sell/
transfer taxes, honeypot simulation, sellability, LP lock/burn and creator LP, liquidity depth and
drops, top-holder and top-10 concentration, holder count, fresh-wallet share, funding clusters,
deployer age/history/holdings, developer transfers and sells, volume/liquidity ratio, wash-trading
patterns (round trips, uniform sizes, few unique traders), buy/sell imbalance, extreme price moves,
source verification, and known-scam flags.

A token judged a likely scam always gets **`SKIP — HIGH RUG RISK`**, whatever the strategy score.

## Risk management

`RiskManager` runs before every order. Any failure (or any error while checking) blocks the trade:

`TRADING_ENABLED`, `LIVE_EXECUTION_SUPPORTED`, `NOT_HALTED`, `MAX_DAILY_LOSS` (including the
worst-case loss of the new position), `MAX_DRAWDOWN`, `MAX_OPEN_POSITIONS`,
`NO_DUPLICATE_POSITION`, `MIN_LIQUIDITY`, `MAX_RUG_SCORE`, `NO_CRITICAL_FLAGS`,
`HONEYPOT_VERIFIED`, `MIN_TOKEN_AGE`, `DATA_FRESHNESS`, `MIN_POSITION_SIZE`,
`MAX_POSITION_PERCENT`, `LIQUIDITY_SHARE`, `MAX_SLIPPAGE`, `SUFFICIENT_CASH`, `LLM_REVIEW`
(when required).

Position size is the minimum of: the max-position %, risk-per-trade ÷ (stop distance + costs), the
allowed pool share, available cash and the live USD cap. That is then scaled by decision
confidence. Equity for risk purposes is **conservative**: open positions are valued at estimated
liquidation proceeds. Exits are never blocked by entry checks.

---

## API reference

Reads are public unless `REQUIRE_AUTH_FOR_READS=true`. Admin routes need
`Authorization: Bearer <API_KEY>` (or `X-API-Key`). If `API_KEY` is unset, admin routes return 503.

| Method & path                                  | Description                                                                                                                                 |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `GET /health`                                  | liveness                                                                                                                                    |
| `GET /status`                                  | engine, loops, providers, notifiers, queue, DB                                                                                              |
| `GET /config`                                  | effective limits/strategy and a redacted system config                                                                                      |
| `GET /tokens`                                  | `?limit&offset&sort&order&chain&risk&search&analyzedOnly`                                                                                   |
| `GET /tokens/:address`                         | detail: snapshot, risk report, price/liquidity/risk history, decisions, positions, alerts                                                   |
| `GET /tokens/:address/wallets`                 | holders, clusters, deployer, developer activity, transfers                                                                                  |
| `GET /risk/:address`                           | latest rug-risk report                                                                                                                      |
| `GET /positions`                               | `?status=open\|closed\|all`                                                                                                                 |
| `GET /trades`                                  | paginated trade log                                                                                                                         |
| `GET /performance`                             | equity, P/L, drawdown, win rate, equity curve, daily P/L                                                                                    |
| `GET /decisions`                               | `?action=BUY\|SELL\|HOLD\|SKIP`                                                                                                             |
| `GET /alerts`                                  | `?severity&type&unacknowledged`                                                                                                             |
| `GET /logs`                                    | engine event log (skipped opportunities, errors, config changes)                                                                            |
| `GET /backtests`, `GET /backtests/:id`         | saved backtests                                                                                                                             |
| `GET /sniper`                                  | launch sniper status, limits, recent launches with every check, sniper positions                                                            |
| `GET /social`                                  | X tracker: watched accounts, latest calls with the bot's verdict, most-called tokens, search budget                                         |
| `GET /events`                                  | Server-Sent Events: `token.analyzed`, `decision`, `trade`, `position`, `alert`, `performance`, `status`, `sniper.attempt`, `social.mention` |
| `POST /scan`                                   | `{chain,address,allowTrade?}` analyse now, or `{discover:true}`                                                                             |
| `POST /paper-trade`                            | `{chain,address,side,amountUsd?,positionId?}` (paper mode only)                                                                             |
| `POST /positions/:id/close`                    | manual close                                                                                                                                |
| `POST /strategy`                               | `{limits?,strategy?}`; values looser than the hard env limits are rejected                                                                  |
| `POST /engine/start`, `POST /engine/stop`      | engine control                                                                                                                              |
| `POST /risk/resume`                            | clear a drawdown halt                                                                                                                       |
| `POST /alerts/:id/ack`, `POST /alerts/ack-all` | acknowledge alerts                                                                                                                          |
| `POST /backtest`                               | run a synthetic or DB backtest and save it                                                                                                  |

---

## Security

- **No keys in code.** Secrets come only from the environment or a keypair file. The keypair file
  must be `0600`.
- **Secrets never reach logs.** Two layers of protection:
  1. sensitive keys (`privateKey`, `authorization`, `apiKey`, tokens, …) are removed by path;
  2. every configured secret value is scrubbed from each log line before it is written. That
     includes URL-embedded API keys, the DB password and alternate encodings of the wallet key.

  Provider URLs are sanitised before they appear in errors.

- **Fail closed.** Missing data raises risk. A failing check blocks the trade. An invalid config
  stops the process. A missing admin key disables admin routes.
- The runtime strategy can only be **tightened** relative to the env hard limits. The trading mode
  cannot be changed at runtime. A drawdown halt requires a manual resume.
- The API binds to `127.0.0.1` by default. It uses Helmet headers, CORS allow-listing, rate
  limiting and constant-time key comparison.
- Alerts escape HTML (Telegram) and disable mentions (Discord). The optional LLM reviewer treats
  token metadata as untrusted input and can only raise risk.

## Known limitations

- **The X tracker is untested against the real X API**; it was built to the documented v2
  formats and tested against a simulated API. Reading posts requires an X API plan that includes
  it, and plans and rate limits change. The mention search samples one page of posts (up to 100)
  per lookup.

- **The launch sniper is untested against mainnet.** Its program ids, log markers and
  transaction parsing follow the programs' public behaviour and were tested against a simulated
  chain only. Launch programs change often; `SNIPER_SOURCES` accepts `name=programId` for new
  ones. The parser is deliberately strict: a transaction it cannot attribute is skipped, not
  guessed. It is paper-only, and its latency (WebSocket plus several RPC and Jupiter calls) is
  seconds, not milliseconds.

- **Provider integrations were built against the providers' documented response formats and
  tested with recorded-format fixtures.** They were not exercised against the live services from
  the development sandbox, where outbound access was blocked. Expect to adjust a field mapping or
  two on first real use. Schema-validation errors are logged and the affected source is treated as
  missing (so the token becomes riskier, never safer).
- **Live execution is Solana-only** (via Jupiter). EVM chains are analysed and paper-traded, but
  live EVM orders are refused by a risk check.
- **The strategy is a heuristic with no demonstrated edge.** Synthetic backtests validate the
  safety logic, not profitability. Validate on real recorded data (`--source db` after running the
  engine for a while) before trusting any number.
- **Rug detection is probabilistic.** New scam techniques, off-chain coordination, and rugs executed
  within a single block can evade any detector. Honeypot simulation covers the chains Honeypot.is
  supports (Ethereum, BSC, Base). On Solana, sellability relies on Jupiter round-trip quotes plus
  GoPlus/RugCheck.
- Free provider tiers are rate-limited (GeckoTerminal ~30 req/min). Discovery throughput is
  bounded by these limits. Add keys or tune `*_RPM` values.
- Wallet-cluster analysis examines the top `WALLET_ANALYSIS_TOP_N` holders and their first funders
  only. Deep graph analysis would need an indexer.
- Paper fills use a constant-product AMM model. Concentrated-liquidity pools (CLMM, Uniswap v3) and
  MEV/sandwich effects are approximated, not simulated.
- Sharpe and Sortino are per-trade, not annualised, because meme-coin holding periods are
  irregular.
- Single-process engine. Run one backend instance per database.
