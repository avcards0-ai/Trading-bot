import type { TokenListItem } from '@memeguard/shared';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { LEVEL_HEX, RiskBadge, levelForScore } from '../components/RiskBadge';
import { TokenName, tokenHref } from '../components/tables';
import { Card, Empty, ErrorBox, Spinner, Td, Th } from '../components/ui';
import { api } from '../lib/api';
import { pct, timeAgo, usd } from '../lib/format';

function Board({ items }: { items: TokenListItem[] }) {
  if (items.length === 0) return <Empty>No analysed tokens yet.</Empty>;
  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[640px] border-collapse">
        <thead>
          <tr>
            <Th className="w-8">#</Th>
            <Th>Token</Th>
            <Th>Rug score</Th>
            <Th>Overall</Th>
            <Th>Honeypot</Th>
            <Th>Liquidity</Th>
            <Th align="right">Top-10 hold</Th>
            <Th align="right">Liquidity</Th>
            <Th align="right">Analysed</Th>
          </tr>
        </thead>
        <tbody>
          {items.map((t, i) => {
            const s = t.rugScore ?? 0;
            return (
              <tr key={t.id} className="hover:bg-surface-2/60">
                <Td className="text-muted">{i + 1}</Td>
                <Td className="max-w-[12rem]">
                  <TokenName t={t} />
                </Td>
                <Td>
                  <Link to={tokenHref(t)} className="flex items-center gap-2" title={`Rug score ${s}/100`}>
                    <span className="tabular w-8 text-sm font-semibold text-ink">{Math.round(s)}</span>
                    <span className="h-1.5 w-24 rounded-full bg-surface-3" aria-hidden>
                      <span className="block h-1.5 rounded-full" style={{ width: `${Math.max(2, s)}%`, background: LEVEL_HEX[levelForScore(s)] }} />
                    </span>
                  </Link>
                </Td>
                <Td>
                  <RiskBadge level={t.overallRisk} compact />
                </Td>
                <Td>
                  <RiskBadge level={t.honeypotRisk} compact />
                </Td>
                <Td>
                  <RiskBadge level={t.liquidityRisk} compact />
                </Td>
                <Td align="right">{pct(t.top10HolderPercent)}</Td>
                <Td align="right">{usd(t.liquidityUsd, { compact: true })}</Td>
                <Td align="right">
                  <span className="text-xs text-ink-2">{timeAgo(t.lastAnalyzedAt)}</span>
                </Td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

export function LeaderboardPage() {
  const dangerous = useQuery({ queryKey: ['tokens', 'lb-danger'], queryFn: () => api.tokens({ limit: 25, sort: 'rugScore', order: 'desc', analyzedOnly: true }), refetchInterval: 30_000 });
  const safest = useQuery({ queryKey: ['tokens', 'lb-safe'], queryFn: () => api.tokens({ limit: 25, sort: 'rugScore', order: 'asc', analyzedOnly: true }), refetchInterval: 30_000 });
  return (
    <div className="space-y-5">
      <div>
        <h1 className="text-lg font-semibold">Risk leaderboard</h1>
        <p className="mt-1 text-sm text-muted">
          Ranked by RUG_SCORE (0 = no risk signals found, 100 = near-certain scam). A low score is not a recommendation: missing data always counts as risk.
        </p>
      </div>
      <div className="grid gap-5 2xl:grid-cols-2">
        <Card title="Most dangerous" subtitle="Highest rug scores — never traded" padded={false}>
          {dangerous.isLoading ? <Spinner /> : dangerous.error ? <div className="p-4"><ErrorBox error={dangerous.error} /></div> : <Board items={dangerous.data?.items ?? []} />}
        </Card>
        <Card title="Lowest risk" subtitle="Lowest rug scores among analysed tokens" padded={false}>
          {safest.isLoading ? <Spinner /> : safest.error ? <div className="p-4"><ErrorBox error={safest.error} /></div> : <Board items={safest.data?.items ?? []} />}
        </Card>
      </div>
    </div>
  );
}
