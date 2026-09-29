import type { SocialStatus } from '@memeguard/shared';
import { useQuery } from '@tanstack/react-query';
import { AtSign, ExternalLink } from 'lucide-react';
import { Link } from 'react-router-dom';
import { RiskBadge, RugScore } from '../components/RiskBadge';
import { Card, Empty, ErrorBox, Pill, Spinner, StatTile, Td, Th } from '../components/ui';
import { api } from '../lib/api';
import { num, shortAddr, timeAgo } from '../lib/format';

const tokenLink = (t: { chain: string; address: string }) => `/tokens/${t.address}?chain=${t.chain}`;

function Verdict({ label }: { label: string | null }) {
  if (!label) return <span className="text-xs text-muted">analysing…</span>;
  const tone = label.startsWith('BUY') ? 'blue' : label.includes('RUG') ? 'critical' : 'neutral';
  return <Pill tone={tone}>{label}</Pill>;
}

export function SocialPage() {
  const q = useQuery({ queryKey: ['social'], queryFn: api.social, refetchInterval: 20_000 });
  if (q.isLoading) return <Spinner />;
  if (q.error) return <ErrorBox error={q.error} />;
  const s = q.data as SocialStatus;
  const dayAgo = Date.now() - 86_400_000;
  const calls24h = s.mentions.filter((m) => Date.parse(m.tweetedAt) >= dayAgo).length;
  const watching = s.trackedAccounts.filter((a) => a.found).length;

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-center gap-3">
        <h1 className="flex items-center gap-2 text-lg font-semibold">
          <AtSign size={18} className="text-series-1" aria-hidden />X tracker
        </h1>
        <Pill tone={s.enabled ? 'good' : 'neutral'}>
          {s.enabled ? `Watching ${watching} account${watching === 1 ? '' : 's'}` : 'Off'}
        </Pill>
        <Pill tone="neutral">Read-only</Pill>
      </div>
      <p className="max-w-3xl text-sm text-ink-2">
        Watches the X accounts you list for posted contract addresses and sends every one through the full rug
        and risk analysis. A post never skips a check: most promoted tokens are skipped. For tokens it
        analyses, it also checks who is posting the contract, flagging bot-style or copy-pasted promotion and
        brand-new or missing project accounts.
      </p>

      {!s.enabled && (
        <Card title="The X tracker is off">
          <div className="space-y-2 text-sm text-ink-2">
            <p>
              Add an X API bearer token to <code className="rounded bg-surface-3 px-1 text-ink">.env</code> as{' '}
              <code className="rounded bg-surface-3 px-1 text-ink">X_BEARER_TOKEN</code>, and the accounts to
              watch as <code className="rounded bg-surface-3 px-1 text-ink">X_TRACKED_ACCOUNTS</code> (for
              example <code className="rounded bg-surface-3 px-1 text-ink">handle1,handle2</code>). Then
              restart and start the engine.
            </p>
            <p>Reading posts requires an X developer plan that includes it; X&apos;s free tier may not.</p>
          </div>
        </Card>
      )}

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <StatTile
          label="Accounts watched"
          value={num(watching)}
          hint={`${s.trackedAccounts.length} configured`}
        />
        <StatTile label="Calls in the last 24h" value={num(calls24h)} hint="posts with a contract address" />
        <StatTile label="Tokens called (24h)" value={num(s.mostMentioned.length)} />
        <StatTile
          label="Mention lookups this hour"
          value={
            s.mentionSearch.enabled
              ? `${s.mentionSearch.usedLastHour} / ${s.mentionSearch.maxPerHour}`
              : 'off'
          }
          hint="X searches for analysed tokens"
        />
      </div>

      <div className="grid gap-5 xl:grid-cols-3">
        <Card title="Tracked accounts" padded={false}>
          {s.trackedAccounts.length === 0 ? (
            <Empty>No accounts listed. Set X_TRACKED_ACCOUNTS in .env.</Empty>
          ) : (
            <ul className="divide-y divide-border/60">
              {s.trackedAccounts.map((a) => (
                <li key={a.handle} className="flex items-start justify-between gap-3 px-4 py-2.5">
                  <div className="min-w-0">
                    <a
                      href={`https://x.com/${a.handle}`}
                      target="_blank"
                      rel="noreferrer"
                      className="text-sm font-medium text-ink hover:text-series-1"
                    >
                      @{a.handle}
                    </a>
                    <div className="text-xs text-muted">
                      {a.followers !== null ? `${num(a.followers)} followers · ` : ''}
                      {a.lastPolledAt ? `checked ${timeAgo(a.lastPolledAt)}` : 'not checked yet'}
                    </div>
                    {a.lastError && <div className="text-xs text-critical">{a.lastError}</div>}
                  </div>
                  <Pill tone={a.found === false ? 'critical' : a.found ? 'good' : 'neutral'}>
                    {a.found === false ? 'Not found' : a.found ? 'Watching' : 'Pending'}
                  </Pill>
                </li>
              ))}
            </ul>
          )}
        </Card>

        <Card
          className="xl:col-span-2"
          title="Most-called tokens (24h)"
          subtitle="By how many tracked accounts posted them, with the bot's own verdict"
          padded={false}
        >
          {s.mostMentioned.length === 0 ? (
            <Empty>No calls in the last 24 hours.</Empty>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full min-w-[640px] border-collapse">
                <thead>
                  <tr>
                    <Th>Token</Th>
                    <Th>Posted by</Th>
                    <Th align="right">Rug score</Th>
                    <Th>Risk</Th>
                    <Th>Bot&apos;s decision</Th>
                  </tr>
                </thead>
                <tbody>
                  {s.mostMentioned.map((m) => (
                    <tr key={`${m.chain}:${m.address}`} className="hover:bg-surface-2/60">
                      <Td>
                        <Link to={tokenLink(m)} className="font-medium hover:text-series-1">
                          {m.symbol ?? shortAddr(m.address)}
                        </Link>
                        <div className="text-xs text-muted">{m.chain}</div>
                      </Td>
                      <Td>
                        <span className="text-xs text-ink-2">
                          {m.accounts.map((a) => `@${a}`).join(', ')}
                        </span>
                      </Td>
                      <Td align="right">
                        <RugScore score={m.rugScore} />
                      </Td>
                      <Td>
                        <RiskBadge level={m.overallRisk} compact />
                      </Td>
                      <Td>
                        <Verdict label={m.lastDecisionLabel} />
                      </Td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>
      </div>

      <Card title="Latest calls" subtitle="Newest first" padded={false}>
        {s.mentions.length === 0 ? (
          <Empty>{s.enabled ? 'No calls yet.' : 'Turn the tracker on to see calls here.'}</Empty>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[900px] border-collapse">
              <thead>
                <tr>
                  <Th>When</Th>
                  <Th>Account</Th>
                  <Th>Token</Th>
                  <Th>Post</Th>
                  <Th align="right">Rug score</Th>
                  <Th>Bot&apos;s decision</Th>
                </tr>
              </thead>
              <tbody>
                {s.mentions.map((m) => (
                  <tr key={m.id} className="hover:bg-surface-2/60">
                    <Td>
                      <span className="text-xs text-ink-2">{timeAgo(m.tweetedAt)}</span>
                    </Td>
                    <Td>
                      <span className="text-sm text-ink">@{m.authorHandle}</span>
                      {m.authorFollowers !== null && (
                        <div className="text-xs text-muted">{num(m.authorFollowers)} followers</div>
                      )}
                    </Td>
                    <Td>
                      <Link to={tokenLink(m)} className="font-medium hover:text-series-1">
                        {m.symbol ?? shortAddr(m.address)}
                      </Link>
                      <div className="text-xs text-muted">{m.chain}</div>
                    </Td>
                    <Td>
                      <div className="w-[22rem] whitespace-normal text-xs text-ink-2">
                        {m.text.length > 180 ? `${m.text.slice(0, 180)}…` : m.text}{' '}
                        <a
                          href={m.url}
                          target="_blank"
                          rel="noreferrer"
                          className="inline-flex items-center gap-0.5 text-series-1 hover:underline"
                        >
                          open <ExternalLink size={11} aria-hidden />
                        </a>
                      </div>
                    </Td>
                    <Td align="right">
                      <RugScore score={m.rugScore} />
                    </Td>
                    <Td>
                      <Verdict label={m.lastDecisionLabel} />
                    </Td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
      <p className="text-xs text-muted">
        Promoted tokens are often paid placements or pump-and-dumps. Treat a call as a lead to check, not a
        signal to buy.
      </p>
    </div>
  );
}
