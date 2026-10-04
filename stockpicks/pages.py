"""HTML for every page. All dynamic values pass through `e()` before output."""

from __future__ import annotations

import html
from datetime import datetime, timezone

from . import fmt
from .config import Settings
from .db import User
from .scoring import FACTORS, MAX_DEBT_YEARS, METRICS, MIN_YEARS_OF_HISTORY, SHRINKING_SALES

DISCLAIMER = (
    "For information and education only. This is not personalized investment advice and "
    "not a recommendation to buy or sell any security. Scores come from a mechanical model "
    "applied to public data that may be late or wrong. Investing involves risk, including loss "
    "of principal. Do your own research or talk to a licensed adviser before you invest."
)


def e(value: object) -> str:
    return html.escape("" if value is None else str(value), quote=True)


def _human(d: datetime) -> str:
    return f"{d:%b} {d.day}, {d.year}"


def _date(iso: str | None) -> str:
    if not iso:
        return "–"
    try:
        return _human(datetime.fromisoformat(iso[:10]))
    except ValueError:
        return iso


def _timestamp(ts: int | None) -> str:
    if not ts:
        return "–"
    return _human(datetime.fromtimestamp(ts, tz=timezone.utc))


def csrf_field(csrf: str) -> str:
    return f'<input type="hidden" name="csrf" value="{e(csrf)}">'


def layout(
    settings: Settings,
    title: str,
    body: str,
    *,
    user: User | None,
    csrf: str,
    active: str = "",
    description: str = "",
) -> str:
    def nav_link(href: str, label: str, key: str) -> str:
        cls = ' class="active"' if key == active else ""
        return f'<a href="{href}"{cls}>{label}</a>'

    links = [nav_link("/methodology", "How it works", "methodology")]
    if user and user.has_access:
        links = [nav_link("/picks", "Picks", "picks"), nav_link("/stocks", "All stocks", "stocks")] + links
    if user:
        links.append(nav_link("/account", "Account", "account"))
        links.append(
            f'<form method="post" action="/logout">{csrf_field(csrf)}'
            '<button class="linkish" type="submit">Log out</button></form>'
        )
    else:
        links.append(nav_link("/login", "Log in", "login"))
        links.append('<a class="btn small" href="/signup">Subscribe</a>')
    name = e(settings.site_name)
    page_title = f"{e(title)} · {name}" if title else name
    support = (
        f' · <a href="mailto:{e(settings.support_email)}">{e(settings.support_email)}</a>'
        if settings.support_email
        else ""
    )
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{page_title}</title>
<meta name="description" content="{e(description or 'Long-term stock picks scored from the financial reports companies file with the SEC.')}">
<link rel="stylesheet" href="/static/style.css">
</head>
<body>
<header class="site-header"><div class="wrap">
<a class="logo" href="/">{name}<span>.</span></a>
<nav>{''.join(links)}</nav>
</div></header>
<main><div class="wrap">
{body}
</div></main>
<footer class="site-footer"><div class="wrap">
<p>{e(DISCLAIMER)}</p>
<p>© {datetime.now().year} {name} · <a href="/terms">Terms &amp; disclaimer</a>{support}
· Financial data: SEC EDGAR</p>
</div></footer>
</body>
</html>"""


def notice(message: str | None, error: bool = False) -> str:
    if not message:
        return ""
    return f'<div class="notice{" error" if error else ""}" role="status">{e(message)}</div>'


def score_cell(score: float) -> str:
    width = max(0.0, min(100.0, score))
    return f'<span class="score">{score:.0f}<span class="bar"><i style="width:{width:.0f}%"></i></span></span>'


def factor_bars(factors: dict[str, float]) -> str:
    rows = []
    for key, (label, weight, _) in FACTORS.items():
        value = factors.get(key, 50.0)
        rows.append(
            f'<div class="factor"><span>{e(label)} <span class="muted small">({weight:.0%})</span></span>'
            f'<span class="bar"><i style="width:{value:.0f}%"></i></span><b>{value:.0f}</b></div>'
        )
    return f'<div class="factors">{"".join(rows)}</div>'


def no_data(settings: Settings) -> str:
    return (
        '<div class="card"><h2>The first analysis is still running</h2>'
        "<p>We're reading this year's SEC filings for every company on the list. "
        "Check back in a few minutes.</p></div>"
    )


def _picks(data: dict | None) -> list[dict]:
    if not data:
        return []
    return sorted((s for s in data["stocks"] if s.get("rank")), key=lambda s: s["rank"])


def sample_tickers(data: dict | None, count: int = 2) -> set[str]:
    """The lowest-ranked picks are shown free on the home page as a sample."""
    picks = _picks(data)
    return {s["ticker"] for s in picks[-count:]} if len(picks) > count else set()


def _cta(settings: Settings, user: User | None) -> tuple[str, str]:
    if user and user.has_access:
        return "/picks", "See today's picks"
    if user:
        return "/account", f"Subscribe for {settings.price_label}"
    return "/signup", f"Get the full list for {settings.price_label}"


def _stock_card(s: dict, link: bool = True) -> str:
    strengths = "".join(f"<li>{e(t)}</li>" for t in s["strengths"][:4])
    title = f'<a href="/stock/{e(s["ticker"])}">{e(s["ticker"])}</a>' if link else e(s["ticker"])
    return f"""<div class="card">
<div class="stock-head" style="margin-bottom:8px"><div><h3>{title} · {e(s['name'])}</h3>
<span class="pill">Pick #{e(s['rank'])}</span> <span class="muted small">{e(s['sector'])}</span></div>
<div>{score_cell(s['score'])}</div></div>
<p class="muted">{e(s['summary'])}</p>
<ul class="ticks">{strengths}</ul>
</div>"""


def home(settings: Settings, data: dict | None, user: User | None, csrf: str) -> str:
    cta_href, cta_label = _cta(settings, user)
    name = e(settings.site_name)
    picks = _picks(data)
    if data:
        covered = data["covered"]
        passed = sum(1 for s in data["stocks"] if s["eligible"])
        stats = f"""<div class="grid four">
<div class="stat"><b>{covered}</b><span>companies analyzed</span></div>
<div class="stat"><b>{passed}</b><span>passed every red-flag check</span></div>
<div class="stat"><b>{len(picks)}</b><span>current picks</span></div>
<div class="stat"><b>{e(_date(data['as_of']))}</b><span>last updated</span></div>
</div>"""
        intro_count = f"{covered} large US companies"
    else:
        stats = ""
        intro_count = "hundreds of large US companies"

    preview = ""
    if picks:
        samples = sample_tickers(data)
        rows = []
        for s in [p for p in picks if p["ticker"] not in samples][:5]:
            rows.append(
                f'<tr><td class="num">#{s["rank"]}</td>'
                '<td><span class="locked">Members Only Inc</span> <span class="lock">🔒 members only</span></td>'
                f'<td class="hide-sm">{e(s["sector"])}</td><td>{score_cell(s["score"])}</td></tr>'
            )
        sample_cards = "".join(_stock_card(s) for s in picks if s["ticker"] in samples)
        preview = f"""<section>
<h2>Today's top picks</h2>
<p class="muted">Members see every pick, the full scorecard and the reasons behind it.</p>
<div class="table-wrap"><table>
<thead><tr><th class="num">Rank</th><th>Company</th><th class="hide-sm">Sector</th><th>Score</th></tr></thead>
<tbody>{''.join(rows)}</tbody></table></div>
<p style="margin-top:12px"><a class="btn" href="{cta_href}">{e(cta_label)}</a></p>
</section>"""
        if sample_cards:
            preview += f"""<section>
<h2>Free sample</h2>
<p class="muted">Two picks from the bottom of today's list, unlocked so you can see what members get.</p>
<div class="grid two">{sample_cards}</div>
</section>"""

    body = f"""<section class="hero">
<h1>Long-term stocks, picked from what companies actually report.</h1>
<p class="lead">Every day {name} reads the financial reports that {intro_count} file with the SEC
(sales, profits, cash flow, debt and buybacks) and checks them against today's prices.
Each company gets a score for quality, growth, financial strength and value, and the
{settings.picks_count} best long-term candidates make the list, each with plain-English reasons.</p>
<div class="actions"><a class="btn" href="{cta_href}">{e(cta_label)}</a>
<a class="btn secondary" href="/methodology">How the scoring works</a></div>
<p class="muted small">Cancel anytime in two clicks. No hype and no hot tips, just the numbers.</p>
</section>
<section>{stats}</section>
{preview}
<section class="steps">
<h2>How it works</h2>
<div class="grid three">
<div class="card"><h3>Read the filings</h3><p class="muted">We pull each company's audited annual
results straight from SEC EDGAR, the government's official database of company reports, and watch for
new filings such as auditor changes, restatements and cyber incidents.</p></div>
<div class="card"><h3>Score every company</h3><p class="muted">Ten measures (return on capital, margins,
cash flow, growth, debt, buybacks and valuation) are ranked against every other company on the list.</p></div>
<div class="card"><h3>Filter the red flags</h3><p class="muted">Companies that lost money, burned cash,
carry too much debt or have shrinking sales can't make the list, however cheap they look.</p></div>
</div>
</section>
<section>
<h2>Simple pricing</h2>
<div class="card price-card">
<div class="amount">{e(settings.price_label)}</div>
<ul class="ticks">
<li>The full list of {settings.picks_count} long-term picks, refreshed daily</li>
<li>A scorecard for every company we cover, with the reasons in plain English</li>
<li>Red flags and recent SEC filings for each company</li>
<li>Cancel anytime from your account page</li>
</ul>
<a class="btn block" href="{cta_href}">{e(cta_label)}</a>
</div>
</section>
<section class="prose">
<h2>Questions</h2>
<details><summary>Is this financial advice?</summary><p>No. {name} publishes the same list to every
subscriber, built by a transparent model from public data. It doesn't know your goals or situation.
Use it as a starting point for your own research.</p></details>
<details><summary>Where does the data come from?</summary><p>Company financials come from the reports
companies file with the US Securities and Exchange Commission (SEC EDGAR). Share prices come from a
market data provider and are used only to judge valuation.</p></details>
<details><summary>How often does the list change?</summary><p>Scores are recalculated every day with
fresh prices. The underlying business numbers change when companies file new annual reports, so
long-term picks don't churn much from day to day.</p></details>
<details><summary>Why aren't banks or insurers on the list?</summary><p>Their financial statements
work differently (debt is their raw material), so the same yardsticks would mislead. They're left out
rather than scored badly.</p></details>
<details><summary>How do I cancel?</summary><p>Go to Account, then Manage billing. Payments are handled
by Stripe; we never see your card number.</p></details>
</section>"""
    return layout(settings, "", body, user=user, csrf=csrf)


def methodology(settings: Settings, user: User | None, csrf: str) -> str:
    factor_rows = []
    for key, (label, weight, blurb) in FACTORS.items():
        measures = ", ".join(e(m.label) for m in METRICS if m.factor == key)
        factor_rows.append(
            f"<tr><td><b>{e(label)}</b><br><span class='muted small'>{e(blurb)}</span></td>"
            f"<td class='num'>{weight:.0%}</td><td>{measures}</td></tr>"
        )
    body = f"""<div class="prose">
<h1>How the scoring works</h1>
<p class="lead muted">No black box. Here's exactly how every company is scored.</p>
<h2>1. Gather the facts</h2>
<p>For each company we download the financial data it reported in its annual 10-K filings from
<a href="https://www.sec.gov/search-filings/edgar-application-programming-interfaces" rel="noopener">SEC EDGAR</a>,
the official public database of company reports. We use audited annual numbers rather than
quarterly estimates because long-term investing is about what a business does year after year.
We also read each company's recent filings so you can see what it has told investors lately, and we
call out filings that deserve a closer look: auditor changes, statements that past results can't be
relied on, cybersecurity incidents and exchange listing problems.</p>
<h2>2. Score ten measures</h2>
<p>Every measure is ranked against all the companies we cover, giving a percentile from 0 to 100.
A 90 means the company beats 90% of the list on that measure. Measures roll up into four factors:</p>
<div class="table-wrap"><table>
<thead><tr><th>Factor</th><th class="num">Weight</th><th>Measures</th></tr></thead>
<tbody>{''.join(factor_rows)}</tbody></table></div>
<p style="margin-top:16px">Return on invested capital uses operating profit after a flat 21% tax rate,
divided by equity plus debt minus cash. Growth rates compare the latest fiscal year with three years
earlier. Valuation uses the latest share price against the latest annual earnings and free cash flow.
If a measure isn't available for a company, it counts as average (50) rather than helping or hurting.</p>
<h2>3. Remove red flags</h2>
<p>A company can't make the picks list, however well it scores, if any of these is true:</p>
<ul class="ticks flags">
<li>It lost money in its latest fiscal year</li>
<li>It had negative free cash flow in its latest fiscal year</li>
<li>Its net debt is more than {MAX_DEBT_YEARS:.0f} years of operating cash flow</li>
<li>Its sales have shrunk more than {fmt.pct(-SHRINKING_SALES)} a year over three years</li>
<li>Its market value is under {fmt.money(settings.min_market_cap)}</li>
<li>It hasn't filed an annual report in 18 months, or we couldn't get a current price</li>
</ul>
<h2>4. Publish the list</h2>
<p>The {settings.picks_count} highest-scoring companies with no red flags become the picks.
Everything updates daily. Members can also see every other company's scorecard and why it
didn't make the cut.</p>
<h2>What's not covered</h2>
<p>Banks, insurers and real-estate trusts are left out because their financial statements need
different yardsticks. Foreign companies that file 20-F reports instead of 10-Ks aren't covered, and
companies need at least {MIN_YEARS_OF_HISTORY} years of reported results.</p>
<h2>Limits</h2>
<p>A model built on past results can't see the future. It doesn't read news, judge management or
predict competition, and reported numbers can be restated. Treat the list as a well-researched shortlist, not a
buy signal, and spread your money across many holdings.</p>
</div>"""
    return layout(settings, "How it works", body, user=user, csrf=csrf, active="methodology")


def picks(settings: Settings, data: dict, user: User | None, csrf: str, message: str = "") -> str:
    rows = []
    for s in _picks(data):
        m = s["metrics"]
        f = s["factors"]
        why = s["strengths"][0] if s["strengths"] else s["summary"]
        rows.append(f"""<tr>
<td class="num">#{s['rank']}</td>
<td><a class="ticker" href="/stock/{e(s['ticker'])}">{e(s['ticker'])}</a><span class="name">{e(s['name'])}</span></td>
<td class="hide-sm">{e(s['sector'])}</td>
<td>{score_cell(s['score'])}</td>
<td class="num hide-sm">{f['quality']:.0f} / {f['growth']:.0f} / {f['strength']:.0f} / {f['value']:.0f}</td>
<td class="num">{fmt.times(m['pe'], 0) if m['pe'] else '–'}</td>
<td class="num hide-sm">{fmt.pct(m['revenue_growth'])}</td>
<td class="why hide-sm">{e(why)}</td>
</tr>""")
    body = f"""{notice(message)}
<h1>Today's long-term picks</h1>
<p class="muted">{len(rows)} companies with the best scores and no red flags, out of {data['covered']} analyzed.
Updated {e(_date(data['as_of']))}. Click a company for its full scorecard.</p>
<div class="table-wrap"><table>
<thead><tr><th class="num">Rank</th><th>Company</th><th class="hide-sm">Sector</th><th>Score</th>
<th class="num hide-sm">Q / G / S / V</th><th class="num">P/E</th><th class="num hide-sm">Sales growth</th>
<th class="hide-sm">Why it's here</th></tr></thead>
<tbody>{''.join(rows)}</tbody></table></div>
<p class="muted small" style="margin-top:12px">Q / G / S / V = quality, growth, financial strength and value
scores (0-100). Sales growth is per year over three years.
<a href="/methodology">How the scoring works</a>.</p>"""
    return layout(settings, "Picks", body, user=user, csrf=csrf, active="picks")


def all_stocks(settings: Settings, data: dict, user: User | None, csrf: str) -> str:
    rows = []
    for s in data["stocks"]:
        if s["rank"]:
            status = f'<span class="pill">Pick #{s["rank"]}</span>'
        elif s["red_flags"]:
            status = f'<span class="pill bad">Red flag</span> <span class="muted small">{e(s["red_flags"][0])}</span>'
        else:
            status = '<span class="pill muted">Just missed</span>'
        rows.append(f"""<tr>
<td class="num">{s['overall_rank']}</td>
<td><a class="ticker" href="/stock/{e(s['ticker'])}">{e(s['ticker'])}</a><span class="name">{e(s['name'])}</span></td>
<td class="hide-sm">{e(s['sector'])}</td>
<td>{score_cell(s['score'])}</td>
<td>{status}</td>
</tr>""")
    skipped = "".join(
        f"<tr><td><b>{e(n['ticker'])}</b><span class='name'>{e(n['name'])}</span></td><td class='muted'>{e(n['reason'])}</td></tr>"
        for n in data.get("not_covered") or []
    )
    skipped_html = (
        f"""<h2 style="margin-top:40px">Not covered</h2>
<div class="table-wrap"><table><thead><tr><th>Company</th><th>Why</th></tr></thead>
<tbody>{skipped}</tbody></table></div>"""
        if skipped
        else ""
    )
    body = f"""<h1>Every company we analyze</h1>
<p class="muted">All {data['covered']} scored companies, best first. A company needs a top score
<em>and</em> no red flags to become a pick. Updated {e(_date(data['as_of']))}.</p>
<div class="table-wrap"><table>
<thead><tr><th class="num">#</th><th>Company</th><th class="hide-sm">Sector</th><th>Score</th><th>Status</th></tr></thead>
<tbody>{''.join(rows)}</tbody></table></div>
{skipped_html}"""
    return layout(settings, "All stocks", body, user=user, csrf=csrf, active="stocks")


def _metric_value(key: str, m: dict) -> str:
    v = m.get(key)
    if v is None:
        return "–"
    if key == "profitable_years":
        return f"{v} of {m.get('profit_years_checked') or '?'}"
    if key == "net_debt_to_cash_flow":
        return "net cash" if v <= 0 else fmt.times(v)
    return fmt.pct(v, 1)


def stock(
    settings: Settings, data: dict, s: dict, user: User | None, csrf: str, is_sample: bool = False
) -> str:
    m = s["metrics"]
    if s["rank"]:
        status = f'<span class="pill">Pick #{s["rank"]} of {data["picks_count"]}</span>'
    elif s["red_flags"]:
        status = '<span class="pill bad">Not a pick: red flag</span>'
    else:
        status = '<span class="pill muted">Not a pick: score too low</span>'

    def items(lines: list[str]) -> str:
        return "".join(f"<li>{e(t)}</li>" for t in lines)

    lists = []
    if s["red_flags"]:
        lists.append(f'<div class="card"><h3>Red flags</h3><ul class="ticks flags">{items(s["red_flags"])}</ul></div>')
    lists.append(
        '<div class="card"><h3>Why it scores well</h3>'
        + (f'<ul class="ticks">{items(s["strengths"])}</ul>' if s["strengths"] else '<p class="muted">No standout strengths.</p>')
        + "</div>"
    )
    lists.append(
        '<div class="card"><h3>Things to watch</h3>'
        + (f'<ul class="ticks crosses">{items(s["concerns"])}</ul>' if s["concerns"] else '<p class="muted">Nothing notable.</p>')
        + "</div>"
    )

    metric_rows = []
    for spec in METRICS:
        pctile = s["percentiles"].get(spec.key)
        cls = "" if pctile is None else (" good" if pctile >= 70 else (" bad" if pctile <= 30 else ""))
        metric_rows.append(
            f"<tr><td>{e(spec.label)}</td><td class='num'>{e(_metric_value(spec.key, m))}</td>"
            f"<td class='num{cls}'>{'–' if pctile is None else f'{pctile:.0f}'}</td></tr>"
        )
    net_debt = m.get("net_debt")
    facts = [
        ("Share price", fmt.price(m.get("price"))),
        ("Market value", fmt.money(m.get("market_cap"))),
        ("P/E ratio", fmt.times(m.get("pe"), 1)),
        ("Revenue (last fiscal year)", fmt.money(m.get("revenue"))),
        ("Net income", fmt.money(m.get("net_income"))),
        ("Free cash flow", fmt.money(m.get("free_cash_flow"))),
        ("Net cash" if (net_debt or 0) <= 0 else "Net debt", fmt.money(abs(net_debt) if net_debt is not None else None)),
        ("Fiscal year ended", _date(m.get("fiscal_year_end"))),
    ]
    fact_rows = "".join(f"<tr><td>{e(k)}</td><td class='num'>{e(v)}</td></tr>" for k, v in facts)
    filings = "".join(
        f'<li><span class="date">{e(_date(f["filed"]))}</span><span><a href="{e(f["url"])}" rel="noopener">'
        f'{e(f["form"])}</a> · {e(f["description"])}</span></li>'
        for f in s.get("filings") or []
    )
    notes = "".join(f"<li>{e(n)}</li>" for n in m.get("notes") or [])
    sample_note = notice(
        f"This is a free sample. Subscribe for {settings.price_label} to see every pick." if is_sample else None
    )
    edgar = f"https://www.sec.gov/cgi-bin/browse-edgar?action=getcompany&CIK={int(s['cik'])}&type=&dateb=&owner=include&count=40"
    body = f"""{sample_note}
<div class="stock-head">
<div><h1>{e(s['ticker'])} · {e(s['name'])}</h1>
<p>{status} <span class="muted">{e(s['sector'])}{' · ' + e(s['industry']) if s.get('industry') else ''}</span></p>
<p class="muted" style="max-width:640px">{e(s['summary'])}</p></div>
<div class="card score-card"><div class="muted small">Overall score</div>
<div class="big-score">{s['score']:.0f}<span class="muted" style="font-size:1rem">/100</span></div>
{factor_bars(s['factors'])}</div>
</div>
<div class="grid three" style="margin-bottom:32px">{''.join(lists)}</div>
<div class="grid two" style="margin-bottom:32px">
<div><h2>Scorecard</h2><div class="table-wrap"><table>
<thead><tr><th>Measure</th><th class="num">Value</th><th class="num">Percentile</th></tr></thead>
<tbody>{''.join(metric_rows)}</tbody></table></div>
<p class="muted small" style="margin-top:8px">Percentile = share of covered companies this one beats on the measure.</p></div>
<div><h2>Key numbers</h2><div class="table-wrap"><table><tbody>{fact_rows}</tbody></table></div></div>
</div>
<div class="grid two">
<div class="card"><h3>What it told the SEC recently</h3>
{f'<ul class="filings">{filings}</ul>' if filings else '<p class="muted">No recent filings found.</p>'}
<p class="small" style="margin-top:12px"><a href="{e(edgar)}" rel="noopener">All filings on SEC EDGAR</a></p></div>
<div class="card"><h3>Data notes</h3>
{f'<ul class="small muted">{notes}</ul>' if notes else '<p class="muted small">All measures were available.</p>'}
<p class="muted small">Numbers come from the company's annual 10-K filings. The price is the latest close from
{e(data.get('price_source', 'our price provider'))}, as of {e(_date(data['as_of']))}.</p></div>
</div>"""
    return layout(settings, f"{s['ticker']} scorecard", body, user=user, csrf=csrf, active="stocks")


def _auth_page(settings: Settings, title: str, inner: str, user: User | None, csrf: str, active: str) -> str:
    body = f'<div class="narrow" style="margin:0 auto"><h1>{e(title)}</h1><div class="card">{inner}</div></div>'
    return layout(settings, title, body, user=user, csrf=csrf, active=active)


def signup(settings: Settings, csrf: str, error: str = "", email: str = "") -> str:
    inner = f"""{notice(error, error=True)}
<form class="stack" method="post" action="/signup">{csrf_field(csrf)}
<label>Email<input type="email" name="email" value="{e(email)}" required autocomplete="email" maxlength="254"></label>
<label>Password<input type="password" name="password" required minlength="8" maxlength="200" autocomplete="new-password">
<span class="muted small" style="font-weight:400">At least 8 characters.</span></label>
<label class="check"><input type="checkbox" name="agree" value="1" required>
<span>I understand this is general research, not personalized investment advice, and I agree to the
<a href="/terms">terms</a>.</span></label>
<button class="btn block" type="submit">Create account</button>
</form>
<p class="muted small" style="margin-top:16px">Next you'll pay {e(settings.price_label)} securely with Stripe.
Already have an account? <a href="/login">Log in</a>.</p>"""
    return _auth_page(settings, "Create your account", inner, None, csrf, "signup")


def login(settings: Settings, csrf: str, error: str = "", email: str = "", next_url: str = "", message: str = "") -> str:
    inner = f"""{notice(error, error=True)}{notice(message)}
<form class="stack" method="post" action="/login">{csrf_field(csrf)}
<input type="hidden" name="next" value="{e(next_url)}">
<label>Email<input type="email" name="email" value="{e(email)}" required autocomplete="email"></label>
<label>Password<input type="password" name="password" required autocomplete="current-password"></label>
<button class="btn block" type="submit">Log in</button>
</form>
<p class="muted small" style="margin-top:16px"><a href="/forgot">Forgot your password?</a> ·
New here? <a href="/signup">Create an account</a>.</p>"""
    return _auth_page(settings, "Log in", inner, None, csrf, "login")


def forgot(settings: Settings, csrf: str, sent: bool = False) -> str:
    if not settings.email_enabled:
        contact = (
            f'email <a href="mailto:{e(settings.support_email)}">{e(settings.support_email)}</a>'
            if settings.support_email
            else "contact the site owner"
        )
        inner = f"<p>To reset your password, {contact} from the address you signed up with.</p>"
    elif sent:
        inner = "<p>If an account exists for that email, we've sent a link to reset the password. It expires in an hour.</p>"
    else:
        inner = f"""<form class="stack" method="post" action="/forgot">{csrf_field(csrf)}
<label>Email<input type="email" name="email" required autocomplete="email"></label>
<button class="btn block" type="submit">Email me a reset link</button></form>"""
    return _auth_page(settings, "Reset your password", inner, None, csrf, "login")


def reset(settings: Settings, csrf: str, token: str, valid: bool, error: str = "") -> str:
    if not valid:
        inner = '<p>This reset link is invalid or has expired. <a href="/forgot">Request a new one</a>.</p>'
    else:
        inner = f"""{notice(error, error=True)}
<form class="stack" method="post" action="/reset">{csrf_field(csrf)}
<input type="hidden" name="token" value="{e(token)}">
<label>New password<input type="password" name="password" required minlength="8" maxlength="200" autocomplete="new-password"></label>
<button class="btn block" type="submit">Set new password</button></form>"""
    return _auth_page(settings, "Choose a new password", inner, None, csrf, "login")


def account(settings: Settings, user: User, csrf: str, message: str = "", error: str = "") -> str:
    if user.comped:
        status = "Complimentary access."
    elif user.subscription_status in ("active", "trialing"):
        when = _timestamp(user.current_period_end)
        status = f"Active. Cancels on {when}." if user.cancel_at_period_end else f"Active. Renews on {when}."
    elif user.subscription_status == "past_due":
        status = "Your last payment failed. Update your card under Manage billing to keep access."
    elif user.subscription_status in ("canceled", "unpaid", "incomplete_expired"):
        status = "Your subscription has ended."
    elif user.subscription_status == "incomplete":
        status = "Your first payment didn't go through. Please try subscribing again."
    else:
        status = "No subscription yet."

    actions = []
    if user.has_access:
        actions.append('<a class="btn" href="/picks">See today\'s picks</a>')
    elif settings.stripe_enabled:
        actions.append(
            f'<form method="post" action="/subscribe">{csrf_field(csrf)}'
            f'<button class="btn" type="submit">Subscribe for {e(settings.price_label)}</button></form>'
        )
    else:
        actions.append('<p class="muted">Payments aren\'t set up on this site yet.</p>')
    if user.stripe_customer_id and settings.stripe_enabled:
        actions.append(
            f'<form method="post" action="/billing">{csrf_field(csrf)}'
            '<button class="btn secondary" type="submit">Manage billing or cancel</button></form>'
        )
    body = f"""<div class="narrow" style="margin:0 auto">
{notice(message)}{notice(error, error=True)}
<h1>Your account</h1>
<div class="card">
<p><span class="muted">Email</span><br><b>{e(user.email)}</b></p>
<p><span class="muted">Subscription</span><br>{e(status)}</p>
<div style="display:flex;gap:12px;flex-wrap:wrap;align-items:center">{''.join(actions)}</div>
</div></div>"""
    return layout(settings, "Account", body, user=user, csrf=csrf, active="account")


def terms(settings: Settings, user: User | None, csrf: str) -> str:
    name = e(settings.site_name)
    contact = (
        f'<a href="mailto:{e(settings.support_email)}">{e(settings.support_email)}</a>'
        if settings.support_email
        else "the site owner"
    )
    body = f"""<div class="prose">
<h1>Terms &amp; disclaimer</h1>
<h2>Not investment advice</h2>
<p>{name} is a publication. It provides general, impersonal research produced by a mechanical model that
is applied the same way to every company and shown the same way to every subscriber. It does not
consider your financial situation, goals or risk tolerance, and nothing on this site is a
recommendation that any particular person buy, sell or hold any security. {name} is not a registered
investment adviser or broker-dealer.</p>
<h2>No guarantees</h2>
<p>Scores are based on past reported results and public data that can be late, incomplete,
restated or wrong. Past performance does not predict future results. Stocks can lose value, including
all of your investment. You are solely responsible for your investment decisions.</p>
<h2>Data sources</h2>
<p>Company financial data comes from filings published by the US Securities and Exchange Commission on
EDGAR. Prices come from a third-party market data provider. We may hold positions in companies we cover.</p>
<h2>Subscriptions</h2>
<p>Subscriptions cost {e(settings.price_label)}, billed through Stripe until you cancel. You can cancel at
any time from your account page; you keep access until the end of the period you've paid for.
Payments already made are not refunded except where the law requires.</p>
<h2>Your data</h2>
<p>We store your email address, a scrambled (hashed) version of your password and your subscription
status. Card details are handled by Stripe and never reach our servers. We don't sell your data.</p>
<h2>Personal use</h2>
<p>Your subscription is for your own use. Please don't republish or resell the list.</p>
<h2>Contact</h2>
<p>Questions? Reach {contact}.</p>
</div>"""
    return layout(settings, "Terms & disclaimer", body, user=user, csrf=csrf)


def simple(settings: Settings, title: str, message: str, user: User | None, csrf: str) -> str:
    body = f'<div class="narrow" style="margin:0 auto"><h1>{e(title)}</h1><div class="card"><p>{e(message)}</p>' \
           f'<p><a href="/">Go to the home page</a></p></div></div>'
    return layout(settings, title, body, user=user, csrf=csrf)
