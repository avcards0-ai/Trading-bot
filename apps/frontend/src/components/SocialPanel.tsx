import type { SocialData } from '@memeguard/shared';
import { ExternalLink } from 'lucide-react';
import type { ReactNode } from 'react';
import { num, timeAgo } from '../lib/format';
import { Empty, Pill } from './ui';

const pctText = (v: number | null) => (v === null ? '—' : `${Math.round(v * 100)}%`);

function Row({ label, children, hint }: { label: string; children: ReactNode; hint?: string }) {
  return (
    <div className="flex items-baseline justify-between gap-3 border-b border-border/60 py-1.5 last:border-0">
      <dt className="text-sm text-ink-2">
        {label}
        {hint && <span className="block text-xs text-muted">{hint}</span>}
      </dt>
      <dd className="tabular text-right text-sm text-ink">{children}</dd>
    </div>
  );
}

/** Share with a warning pill once it crosses the level the rug model treats as suspicious. */
function Share({ v, warnAt }: { v: number | null; warnAt: number }) {
  if (v === null) return <>—</>;
  return v >= warnAt ? <Pill tone="warning">{pctText(v)}</Pill> : <>{pctText(v)}</>;
}

/** What X (Twitter) shows about a token: its own account and who is posting the contract. */
export function SocialPanel({ social }: { social: SocialData | null | undefined }) {
  if (!social) {
    return (
      <Empty>
        No X data for this token yet. With X_BEARER_TOKEN set, the bot looks up who is posting the contract
        address (see the X tracker page).
      </Empty>
    );
  }
  const off = social.officialAccount;
  return (
    <div className="grid gap-6 lg:grid-cols-2">
      <div>
        <h3 className="mb-1 text-sm font-semibold text-ink">The token&apos;s own account</h3>
        <dl>
          {!off ? (
            <Row label="Listed account">none listed</Row>
          ) : off.status === 'not_found' ? (
            <Row label={`@${off.username}`}>
              <Pill tone="critical">Doesn&apos;t exist or suspended</Pill>
            </Row>
          ) : (
            <>
              <Row label="Account">
                <a
                  href={`https://x.com/${off.username}`}
                  target="_blank"
                  rel="noreferrer"
                  className="inline-flex items-center gap-1 hover:text-series-1"
                >
                  @{off.username} <ExternalLink size={12} aria-hidden />
                </a>
              </Row>
              <Row label="Account age">
                {off.accountAgeDays === null ? (
                  '—'
                ) : off.accountAgeDays < 7 ? (
                  <Pill tone="warning">{off.accountAgeDays.toFixed(1)} days</Pill>
                ) : (
                  `${Math.round(off.accountAgeDays)} days`
                )}
              </Row>
              <Row label="Followers">{num(off.followers)}</Row>
              <Row label="Verified">{off.verified ? 'yes' : 'no'}</Row>
            </>
          )}
        </dl>

        <h3 className="mb-1 mt-5 text-sm font-semibold text-ink">Posts mentioning the contract</h3>
        <dl>
          <Row label="Last hour / last 24 hours">
            {social.mentions.lastHour} / {social.mentions.last24h}
          </Row>
          <Row
            label="Posts sampled"
            hint={social.mentions.sampleTruncated ? 'more exist than one page' : undefined}
          >
            {social.mentions.sampleSize}
          </Row>
          <Row label="Different accounts">{social.uniqueAuthors}</Row>
          <Row label="Accounts under 30 days old" hint="bot and burner accounts">
            <Share v={social.freshAuthorShare} warnAt={0.6} />
          </Row>
          <Row label="Accounts with under 50 followers">
            <Share v={social.lowFollowerAuthorShare} warnAt={0.6} />
          </Row>
          <Row label="Copy-pasted posts" hint="same text, links and numbers ignored">
            <Share v={social.duplicateTextShare} warnAt={0.5} />
          </Row>
        </dl>
        <p className="mt-2 text-xs text-muted">Checked {timeAgo(social.fetchedAt)} on X.</p>
      </div>
      <div>
        <h3 className="mb-1 text-sm font-semibold text-ink">Biggest accounts posting it</h3>
        {social.topAuthors.length === 0 ? (
          <Empty>No posts found.</Empty>
        ) : (
          <ul className="divide-y divide-border/60">
            {social.topAuthors.map((a) => (
              <li key={a.username} className="flex items-baseline justify-between gap-3 py-1.5 text-sm">
                <a
                  href={`https://x.com/${a.username}`}
                  target="_blank"
                  rel="noreferrer"
                  className="truncate text-ink hover:text-series-1"
                >
                  @{a.username}
                  {a.verified && <span className="ml-1 text-xs text-muted">verified</span>}
                </a>
                <span className="tabular shrink-0 text-xs text-ink-2">
                  {num(a.followers)} followers
                  {a.accountAgeDays !== null && ` · ${a.accountAgeDays}d old`}
                </span>
              </li>
            ))}
          </ul>
        )}
        <p className="mt-3 text-xs text-muted">
          Hype is easy to fake. The rug model only uses this to raise risk (missing or brand-new accounts,
          coordinated promotion), never as a reason to buy.
        </p>
      </div>
    </div>
  );
}
