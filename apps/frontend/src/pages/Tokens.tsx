import type { Chain } from '@memeguard/shared';
import { keepPreviousData, useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { TokenTable } from '../components/tables';
import { Button, Card, ErrorBox, Spinner } from '../components/ui';
import { api, type TokenQuery } from '../lib/api';

const CHAINS: Chain[] = ['solana', 'ethereum', 'base', 'bsc', 'arbitrum'];

export function TokensPage() {
  const [q, setQ] = useState<TokenQuery>({ limit: 50, offset: 0, sort: 'lastAnalyzedAt', order: 'desc' });
  const [search, setSearch] = useState('');
  const tokens = useQuery({ queryKey: ['tokens', q], queryFn: () => api.tokens(q), placeholderData: keepPreviousData, refetchInterval: 20_000 });
  const set = (patch: Partial<TokenQuery>) => setQ((prev) => ({ ...prev, offset: 0, ...patch }));

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end gap-3">
        <h1 className="mr-auto text-lg font-semibold">Live token feed</h1>
        <form
          onSubmit={(e) => {
            e.preventDefault();
            set({ search: search.trim() || undefined });
          }}
          className="flex gap-2"
        >
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Symbol, name or address"
            aria-label="Search tokens"
            className="w-56 rounded-md border border-border bg-surface-2 px-2 py-1.5 text-sm text-ink placeholder:text-muted"
          />
          <Button type="submit">Search</Button>
        </form>
        <select aria-label="Chain" value={q.chain ?? ''} onChange={(e) => set({ chain: (e.target.value || undefined) as Chain | undefined })} className="rounded-md border border-border bg-surface-2 px-2 py-1.5 text-sm text-ink">
          <option value="">All chains</option>
          {CHAINS.map((c) => (
            <option key={c} value={c}>
              {c}
            </option>
          ))}
        </select>
        <select aria-label="Overall risk" value={q.risk ?? ''} onChange={(e) => set({ risk: (e.target.value || undefined) as TokenQuery['risk'] })} className="rounded-md border border-border bg-surface-2 px-2 py-1.5 text-sm text-ink">
          <option value="">Any risk</option>
          <option value="LOW">Low</option>
          <option value="MEDIUM">Medium</option>
          <option value="HIGH">High</option>
          <option value="CRITICAL">Critical</option>
        </select>
        <select
          aria-label="Sort"
          value={`${q.sort}:${q.order}`}
          onChange={(e) => {
            const [sort, order] = e.target.value.split(':') as [TokenQuery['sort'], 'asc' | 'desc'];
            set({ sort, order });
          }}
          className="rounded-md border border-border bg-surface-2 px-2 py-1.5 text-sm text-ink"
        >
          <option value="lastAnalyzedAt:desc">Recently analysed</option>
          <option value="firstSeenAt:desc">Newest discovered</option>
          <option value="pairCreatedAt:desc">Youngest pairs</option>
          <option value="rugScore:desc">Highest rug score</option>
          <option value="rugScore:asc">Lowest rug score</option>
          <option value="liquidityUsd:desc">Most liquidity</option>
          <option value="volume24hUsd:desc">Most volume</option>
          <option value="marketCapUsd:desc">Largest market cap</option>
        </select>
      </div>
      <Card padded={false} title={tokens.data ? `${tokens.data.total} tokens` : 'Tokens'} subtitle="Updates in real time as the engine analyses tokens">
        {tokens.isLoading ? <Spinner /> : tokens.error ? <div className="p-4"><ErrorBox error={tokens.error} /></div> : <TokenTable items={tokens.data?.items ?? []} />}
      </Card>
      <div className="flex items-center justify-end gap-2 text-xs text-muted">
        {tokens.data && (
          <span>
            {Math.min(tokens.data.total, (q.offset ?? 0) + 1)}–{Math.min(tokens.data.total, (q.offset ?? 0) + (q.limit ?? 50))} of {tokens.data.total}
          </span>
        )}
        <Button disabled={(q.offset ?? 0) === 0} onClick={() => setQ((p) => ({ ...p, offset: Math.max(0, (p.offset ?? 0) - (p.limit ?? 50)) }))}>
          Previous
        </Button>
        <Button disabled={!tokens.data || (q.offset ?? 0) + (q.limit ?? 50) >= tokens.data.total} onClick={() => setQ((p) => ({ ...p, offset: (p.offset ?? 0) + (p.limit ?? 50) }))}>
          Next
        </Button>
      </div>
    </div>
  );
}
