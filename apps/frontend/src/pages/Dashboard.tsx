import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { LineSeriesChart } from '../components/charts';
import { AlertList } from './Alerts';
import { DecisionFeed, PositionsTable, TokenTable } from '../components/tables';
import { Card, ChartCard, ErrorBox, Spinner, StatTile, Td, Th } from '../components/ui';
import { useLive } from '../hooks/useLive';
import { api } from '../lib/api';
import { dateTime, pct, usd } from '../lib/format';

export function PerformanceTiles() {
  const perf = useQuery({ queryKey: ['performance'], queryFn: api.performance, refetchInterval: 30_000 });
  if (perf.isLoading) return <Spinner />;
  if (perf.error) return <ErrorBox error={perf.error} />;
  const p = perf.data;
  if (!p) return null;
  const ret = ((p.equityUsd - p.startingBalanceUsd) / p.startingBalanceUsd) * 100;
  return (
    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4 2xl:grid-cols-7">
      <div className="rounded-xl border border-border bg-surface px-4 py-3 sm:col-span-2 lg:col-span-1 2xl:col-span-1">
        <div className="text-xs text-muted">Equity ({p.mode})</div>
        <div className="tabular mt-1 text-3xl font-semibold text-ink">{usd(p.equityUsd)}</div>
        <div className={ret >= 0 ? 'tabular text-xs text-good' : 'tabular text-xs text-critical'}>
          {ret >= 0 ? '▲' : '▼'} {pct(ret, { sign: true, digits: 2 })} since start
        </div>
        <div className="mt-0.5 text-xs text-muted">Liquidation value {usd(p.conservativeEquityUsd)}</div>
      </div>
      <StatTile
        label="Daily P/L"
        value={usd(p.dailyPnlUsd, { sign: true })}
        delta={`${p.dailyPnlPct >= 0 ? '▲' : '▼'} ${pct(p.dailyPnlPct, { sign: true, digits: 2 })} today`}
        deltaGood={p.dailyPnlUsd >= 0}
      />
      <StatTile
        label="Realized P/L"
        value={usd(p.realizedPnlUsd, { sign: true })}
        hint={`${p.closedPositions} closed positions`}
      />
      <StatTile
        label="Unrealized P/L"
        value={usd(p.unrealizedPnlUsd, { sign: true })}
        hint={`${p.openPositions} open`}
      />
      <StatTile
        label="Win rate"
        value={p.winRate === null ? '—' : pct(p.winRate * 100)}
        hint={`${p.winningTrades} W / ${p.losingTrades} L`}
      />
      <StatTile
        label="Drawdown"
        value={pct(p.drawdownPct, { digits: 2 })}
        hint={`max ${pct(p.maxDrawdownPct, { digits: 2 })}`}
      />
      <StatTile
        label="Profit factor"
        value={p.profitFactor === null ? '—' : p.profitFactor.toFixed(2)}
        hint={`${p.totalTrades} fills`}
      />
    </div>
  );
}

export function DashboardPage() {
  const live = useLive();
  const perf = useQuery({ queryKey: ['performance'], queryFn: api.performance, refetchInterval: 30_000 });
  const positions = useQuery({
    queryKey: ['positions', 'open'],
    queryFn: () => api.positions('open'),
    refetchInterval: 20_000,
  });
  const tokens = useQuery({
    queryKey: ['tokens', 'feed'],
    queryFn: () => api.tokens({ limit: 15, sort: 'lastAnalyzedAt', order: 'desc', analyzedOnly: true }),
  });
  const decisions = useQuery({ queryKey: ['decisions', 'recent'], queryFn: () => api.decisions(20) });
  const alerts = useQuery({ queryKey: ['alerts', 'recent'], queryFn: () => api.alerts({ limit: 8 }) });
  const status = useQuery({ queryKey: ['status'], queryFn: api.status, refetchInterval: 15_000 });

  const feed = [
    ...live.analyzed,
    ...(tokens.data?.items ?? []).filter((t) => !live.analyzed.some((a) => a.id === t.id)),
  ].slice(0, 15);
  const decisionFeed =
    live.decisions.length > 0 ? live.decisions.slice(0, 20) : (decisions.data?.items ?? []);
  const curve = perf.data?.equityCurve ?? [];

  return (
    <div className="space-y-5">
      <PerformanceTiles />

      <div className="grid gap-5 xl:grid-cols-3">
        <div className="xl:col-span-2">
          <ChartCard
            title="Equity"
            subtitle="Mark-to-market equity, sampled by the metrics loop"
            chart={
              curve.length < 2 ? (
                <div className="flex h-60 items-center justify-center text-sm text-muted">
                  The equity curve fills in as the metrics loop records snapshots.
                </div>
              ) : (
                <LineSeriesChart
                  data={curve as unknown as Record<string, unknown>[]}
                  dataKey="equityUsd"
                  name="Equity"
                  format={(v) => usd(v, { compact: true })}
                />
              )
            }
            table={
              <table className="w-full">
                <thead>
                  <tr>
                    <Th>Time</Th>
                    <Th align="right">Equity</Th>
                    <Th align="right">Drawdown</Th>
                  </tr>
                </thead>
                <tbody>
                  {[...curve].reverse().map((c) => (
                    <tr key={c.ts}>
                      <Td>{dateTime(c.ts)}</Td>
                      <Td align="right">{usd(c.equityUsd)}</Td>
                      <Td align="right">{pct(c.drawdownPct, { digits: 2 })}</Td>
                    </tr>
                  ))}
                </tbody>
              </table>
            }
          />
        </div>
        <Card
          title="System"
          subtitle={status.data ? `Up ${Math.round(status.data.uptimeSeconds / 60)} min` : undefined}
          actions={
            <Link to="/system" className="text-xs text-series-1 hover:underline">
              Details
            </Link>
          }
        >
          {status.data ? (
            <ul className="space-y-1.5 text-sm">
              <li className="flex justify-between">
                <span className="text-muted">Database</span>
                <span>{status.data.database.ok ? `ok (${status.data.database.driver})` : 'error'}</span>
              </li>
              {status.data.loops.map((l) => (
                <li key={l.name} className="flex justify-between gap-2">
                  <span className="text-muted">{l.name}</span>
                  <span className="truncate text-right">
                    {l.running ? 'running' : 'stopped'}
                    {l.lastError ? ' · error' : ''}
                  </span>
                </li>
              ))}
              <li className="flex justify-between">
                <span className="text-muted">Providers healthy</span>
                <span>
                  {status.data.providers.filter((p) => p.configured && p.lastError === null).length}/
                  {status.data.providers.filter((p) => p.configured).length}
                </span>
              </li>
              <li className="flex justify-between">
                <span className="text-muted">LLM reviewer</span>
                <span>{status.data.llmReviewer.enabled ? status.data.llmReviewer.model : 'off'}</span>
              </li>
            </ul>
          ) : (
            <Spinner />
          )}
        </Card>
      </div>

      <Card
        title="Open positions"
        padded={false}
        actions={
          <Link to="/positions" className="text-xs text-series-1 hover:underline">
            All positions
          </Link>
        }
      >
        {positions.isLoading ? <Spinner /> : <PositionsTable items={positions.data?.items ?? []} />}
      </Card>

      <div className="grid gap-5 xl:grid-cols-3">
        <Card
          title="Live token feed"
          subtitle="Most recently analysed tokens"
          padded={false}
          className="xl:col-span-2"
          actions={
            <Link to="/tokens" className="text-xs text-series-1 hover:underline">
              Full feed
            </Link>
          }
        >
          {tokens.isLoading ? <Spinner /> : <TokenTable items={feed} compact />}
        </Card>
        <Card title="Decisions" subtitle="Live pipeline output" padded={false}>
          <div className="max-h-[32rem] overflow-y-auto">
            <DecisionFeed items={decisionFeed} />
          </div>
        </Card>
      </div>

      <Card
        title="Recent alerts"
        padded={false}
        actions={
          <Link to="/alerts" className="text-xs text-series-1 hover:underline">
            Alert center
          </Link>
        }
      >
        <AlertList items={alerts.data?.items ?? []} />
      </Card>
    </div>
  );
}
