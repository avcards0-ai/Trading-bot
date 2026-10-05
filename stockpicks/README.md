# stockpicks: a subscription website for long-term stock picks

A complete website you can charge for, with two plans: **Basic ($10/month, 25 picks)** and **Premium ($25/month, 50 picks)**. Every Monday it:

1. Reads the financial reports that ~220 large US companies file with the SEC (sales, profits, cash flow, debt, share buybacks) from [SEC EDGAR](https://www.sec.gov/search-filings/edgar-application-programming-interfaces), plus each company's recent filings (auditor changes, restatements, cyber incidents and so on).
2. Gets the latest share price to judge valuation.
3. Scores every company on **quality, growth, financial strength and value**, removes anything with a red flag, and publishes the top 50 as a new weekly list, each pick with plain-English reasons. Picks that weren't on last week's list are marked **NEW**.

Who sees what:

| | Picks | Scorecards |
|---|---|---|
| Visitors | 3 free picks (from the bottom of the Basic list); the rest are locked | The free picks only |
| Basic ($10/month) | The top 25; picks 26-50 are shown locked with an *Upgrade* link | Their 25 picks |
| Premium ($25/month) | All 50 | Every company analyzed, including why each did or didn't make the list |

Locked rows show only rank, sector and score; nothing that identifies the company reaches the browser. Basic members can upgrade with one click on their account page.

The list isn't forced to be 25 brand-new stocks every week. Only about 100 of the ~220 companies pass the red-flag checks, so forcing all-new picks would run out of good companies within a month, and long-term picks are meant to be held. Good companies stay on the list, and newcomers get the NEW badge.

Python 3.10+ and the standard library only. [waitress](https://pypi.org/project/waitress/) is used as the web server if it's installed (the Docker image installs it).

> **Not financial advice.** The site publishes the same mechanical, impersonal list to every subscriber, and its pages, footer and terms say so. Read [Before you charge money](#before-you-charge-money).

## Try it on your computer

```bash
cp .env.example .env
# Edit .env: set SEC_USER_AGENT to your name/site and email, e.g. "LongHold you@example.com"
python -m stockpicks check        # tests your settings and says what to fix
python -m stockpicks refresh      # takes 1-3 minutes the first time
python -m stockpicks serve        # then open http://localhost:8000
```

Without Stripe keys, people can sign up but can't pay. To look around as a member, sign up on the site and then give yourself free access:

```bash
python -m stockpicks grant you@example.com
```

## How the scoring works

Each measure is ranked against every covered company as a percentile (0-100). Measures roll up into four factors, and the factors are weighted into the overall score. The site's **How it works** page explains this to visitors, generated from the same code.

| Factor | Weight | Measures |
|---|---|---|
| Quality | 30% | Return on invested capital, operating margin, free-cash-flow margin, profitable years (of last 5) |
| Growth | 25% | Sales growth and EPS growth (3-year, per year) |
| Financial strength | 20% | Net debt ÷ operating cash flow, change in share count (buybacks vs dilution) |
| Value | 25% | Earnings yield (1 ÷ P/E), free-cash-flow yield |

**Red flags.** A company with any of these can't be a pick, however well it scores:

- a loss in the latest fiscal year
- negative free cash flow
- net debt above 4 years of operating cash flow
- sales shrinking more than 5% a year
- market value under $2B
- no annual report in 18 months
- no current price

**Not covered:** banks, insurers and REITs (SIC 6000-6799), foreign 20-F filers, and companies with fewer than 4 years of 10-K data.

Fundamentals come from audited annual 10-K numbers. Each company's data is cached and only downloaded again when it files a new 10-K or 10-Q, so the weekly refresh mostly just updates prices.

To change which companies are analyzed, edit `stockpicks/universe.txt` (one ticker per line), or point `UNIVERSE_FILE` at your own list. To change the weights or thresholds, edit `stockpicks/scoring.py`.

## Taking payments with Stripe

1. Create a [Stripe](https://dashboard.stripe.com) account and stay in **test mode** while you set up.
2. **Product catalog → Add product**: name it "Basic", choose *Recurring*, $10, monthly. Copy the price ID (`price_...`) into `STRIPE_PRICE_ID`. Add a second product, "Premium", at $25 monthly, and copy its price ID into `STRIPE_PREMIUM_PRICE_ID`. (To offer one plan only, set `PREMIUM_PICKS_COUNT=0`.)
3. **Developers → API keys**: copy the secret key (`sk_test_...`) into `STRIPE_SECRET_KEY`.
4. **Developers → Webhooks → Add endpoint**: URL `https://YOUR-DOMAIN/stripe/webhook`, with these events:
   - `checkout.session.completed`
   - `checkout.session.async_payment_succeeded`
   - `customer.subscription.created`, `customer.subscription.updated`, `customer.subscription.deleted`
   - `customer.subscription.paused`, `customer.subscription.resumed`

   Copy the signing secret (`whsec_...`) into `STRIPE_WEBHOOK_SECRET`.
5. **Settings → Billing → Customer portal**: turn it on and allow customers to cancel and update their card. To let Premium members switch down to Basic, also allow switching plans and add both products. The site's *Manage billing* button opens this portal. (Upgrades from Basic happen on the site itself and charge the price difference for the rest of the month.)
6. Subscribe on your site with the test card `4242 4242 4242 4242`. When it all works, repeat steps 2-4 in live mode and swap in the live keys.

Access is granted while a subscription is `active`, `trialing` or `past_due` (Stripe retries failed cards for a while). It ends automatically when Stripe cancels the subscription. Stripe handles card details, receipts, failed-payment emails, tax settings and promo codes (enabled at checkout).

## Putting it online

You need a server that stays on, a disk that survives restarts (for `DATA_DIR`), and HTTPS.

### Easiest: Render (about $7.25/month)

The repo includes `render.yaml`, so Render sets everything up for you:

1. Sign up at [render.com](https://render.com) with your GitHub account and add a payment card.
2. **New → Blueprint**, pick this repository and branch, and click **Connect**.
3. Fill in the values it asks for:
   - `SEC_USER_AGENT`: your site name and email, e.g. `LongHold you@example.com`
   - `SUPPORT_EMAIL`: where customers can reach you
   - Leave the four `STRIPE_` values blank for now.
4. Click **Apply**. After a few minutes the site is live at `https://longhold.onrender.com` (or a similar name; Render shows it).
5. Open the service's **Logs** tab. At startup it prints a setup check with `[ok]` or `[FIX]` next to each part, and the first stock analysis finishes within a few minutes.
6. Set up Stripe (above) using `https://YOUR-RENDER-ADDRESS/stripe/webhook`. Then go to **Environment**, fill in the four `STRIPE_` values and save. Render restarts the site, and the log should show `[ok] Payments` and `[ok] Premium plan`.
7. To give yourself free access, sign up on your site, then open the **Shell** tab and run `python -m stockpicks grant you@example.com`.

The address comes from Render automatically. Set `BASE_URL` only if you add your own domain (**Settings → Custom Domains**).

### Other hosts

**A small VPS** (Hetzner, DigitalOcean, Linode...) with Docker:

```bash
docker build -t stockpicks .
docker run -d --restart unless-stopped --name stockpicks \
  --env-file .env -v stockpicks-data:/data -p 127.0.0.1:8000:8000 stockpicks
```

Put [Caddy](https://caddyserver.com) in front for free automatic HTTPS. The whole Caddyfile is:

```
yourdomain.com {
    reverse_proxy 127.0.0.1:8000
}
```

**A platform host** (Render, Railway, Fly.io): deploy this repo's `Dockerfile`, add a persistent disk mounted at `/data`, and set the variables from `.env.example` in their dashboard.

Either way, set `BASE_URL=https://yourdomain.com`. The server publishes a new list every Monday at 06:00 UTC, before US markets open (`REFRESH=weekly`; `daily` and `off` also work), so you don't need cron. If a refresh fails (SEC or the price source is down), the site keeps showing the previous day's list and tries again 30 minutes later.

Back up `DATA_DIR/site.db`; it holds your subscribers' accounts.

## Running the site

```bash
python -m stockpicks check               # re-test settings, SEC, prices and Stripe
python -m stockpicks users --list        # accounts and subscription status
python -m stockpicks grant friend@x.com  # free access (friends, reviewers, refunds)
python -m stockpicks revoke friend@x.com
python -m stockpicks refresh             # re-run the analysis now
```

Every list is appended with its prices to `DATA_DIR/history.jsonl`. That's how NEW badges are worked out, and you can use it to show a track record later.

## Before you charge money

Not legal advice, but things to sort out first:

- **Investment-adviser rules.** In the US, a publication that gives the same impersonal analysis to all subscribers on a regular schedule generally falls under the "publisher's exclusion" rather than adviser registration. Keep it that way: no personalized advice, no "you should buy X" emails to individuals, and no promises of returns. Ask a securities lawyer to review the terms page (`/terms`) and your marketing.
- **Price data licensing.** SEC EDGAR data is public domain. Free price feeds (Stooq, Finnhub's free tier) generally don't allow commercial use. Once you have paying subscribers, move to a plan that allows it. The price source is one small file (`sources/prices.py`), so adding a provider is easy.
- **Taxes.** Stripe Tax can collect sales tax or VAT on subscriptions where it's required.
- **Your own positions.** The terms say you may own stocks you cover. Don't trade around list changes.

## Settings

All settings are environment variables (or lines in `.env`). See `.env.example` for the full list. The main ones:

| Variable | Default | |
|---|---|---|
| `SEC_USER_AGENT` | (required) | Name and contact email the SEC asks every client to send |
| `BASE_URL` | `http://localhost:8000` | Public address, used for Stripe redirects and email links. An `https://` URL turns on secure cookies |
| `SITE_NAME` | `LongHold` | Shown in the header, emails and page titles |
| `PRICE_LABEL` / `PREMIUM_PRICE_LABEL` | `$10/month` / `$25/month` | Text only. The real prices are the Stripe prices |
| `PICKS_COUNT` / `PREMIUM_PICKS_COUNT` | `25` / `50` | Picks per plan. `PREMIUM_PICKS_COUNT=0` offers one plan |
| `FREE_PICKS` | `3` | Picks anyone can see, taken from the bottom of the Basic list |
| `MIN_MARKET_CAP` | `2e9` | Smallest company allowed on the list |
| `PRICE_SOURCE` | `stooq` | `stooq` (no key) or `finnhub` (`FINNHUB_API_KEY`) |
| `STRIPE_*` | | See *Taking payments* |
| `SMTP_*` | | For password-reset emails. Without them, the reset page shows `SUPPORT_EMAIL` |
| `REFRESH` | `weekly` | `weekly` (Mondays), `daily`, or `off` |

## Security

- Passwords are hashed with scrypt.
- Sessions are random tokens, and only their hashes are stored.
- Cookies are HttpOnly and SameSite=Lax (Secure over HTTPS).
- Every form carries a CSRF token.
- Logins are rate-limited per IP and per email.
- Stripe webhooks are signature-checked and de-duplicated.
- Pages send a strict Content-Security-Policy and other security headers.

## Tests

```bash
python -m unittest discover -s tests -t .
```

The tests run offline against fixtures shaped like SEC EDGAR, Stooq and Stripe responses (`tests/stockpicks_helpers.py`). They cover parsing, scoring, the refresh job and caching, sign-up and login, CSRF, the paywall, password resets, Stripe checkout and webhooks, and HTML escaping.

## Layout

```
stockpicks/
  cli.py              refresh / serve / check / grant / revoke / users
  checks.py           setup checks (also printed to the log at startup)
  refresh.py          weekly job: SEC + prices -> scores -> data/picks.json
  plans.py            who sees what: visitors, Basic, Premium
  sources/sec.py      EDGAR tickers, filings and XBRL financials
  sources/prices.py   Stooq and Finnhub prices
  metrics.py          growth, margins, return on capital, debt, valuation
  scoring.py          percentiles, factor weights, red flags, plain-English reasons
  web.py              WSGI app: routing, sessions, CSRF, paywall
  pages.py            HTML for every page
  billing.py          Stripe Checkout, Billing Portal and webhooks
  db.py               SQLite users, sessions, password resets
  mailer.py           SMTP for password resets
  universe.txt        companies to analyze
  static/style.css    the site's styles (light and dark)
```
