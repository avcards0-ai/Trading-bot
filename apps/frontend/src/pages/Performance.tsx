import { useQuery } from '@tanstack/react-query';
import { DailyPnlChart, DrawdownChart, LineSeriesChart, PnlLegend } from '../components/charts';
import { ChartCard, ErrorBox, Spinner, Td, Th } from '../components/ui';
import { api } from '../lib/api';
import { dateTime, pct, usd } from '../lib/format';
import { PerformanceTiles } from './Dashboard';

export function PerformancePage() {
  const perf = useQuery({ queryKey: ['performance'], queryFn: api.performance, refetchInterval: 30_000 });
  if (perf.isLoading) return <Spinner />;
  if (perf.error) return <ErrorBox error={perf.error} />;
  const p = perf.data;
  if (!p) return null;
  const curve = p.equityCurve;

  return (
    <div className="space-y-5">
      <div>
        <h1 className="text-lg font-semibold">Performance</h1>
        <p className="mt-1 text-sm text-muted">
          {p.mode === 'paper' ? 'Paper-trading' : 'Live'} account. Drawdown and daily P/L use liquidation value (positions valued at what a market sell would return), which is more conservative than mid-price equity.
        </p>
      </div>
      <PerformanceTiles />

      <ChartCard
        title="Equity curve"
        chart={
          curve.length < 2 ? (
            <div className="flex h-60 items-center justify-center text-sm text-muted">Not enough snapshots yet.</div>
          ) : (
            <LineSeriesChart data={curve as unknown as Record<string, unknown>[]} dataKey="equityUsd" name="Equity" format={(v) => usd(v, { compact: true })} height={280} />
          )
        }
        table={
          <table className="w-full">
            <thead>
              <tr><Th>Time</Th><Th align="right">Equity</Th><Th align="right">Cash</Th><Th align="right">Unrealized</Th><Th align="right">Realized</Th></tr>
            </thead>
            <tbody>
              {[...curve].reverse().map((c) => (
                <tr key={c.ts}>
                  <Td>{dateTime(c.ts)}</Td>
                  <Td align="right">{usd(c.equityUsd)}</Td>
                  <Td align="right">{usd(c.cashUsd)}</Td>
                  <Td align="right">{usd(c.unrealizedPnlUsd, { sign: true })}</Td>
                  <Td align="right">{usd(c.realizedPnlUsd, { sign: true })}</Td>
                </tr>
              ))}
            </tbody>
          </table>
        }
      />

      <div className="grid gap-5 xl:grid-cols-2">
        <ChartCard
          title="Drawdown"
          subtitle={`Current ${pct(p.drawdownPct, { digits: 2 })} · max ${pct(p.maxDrawdownPct, { digits: 2 })}`}
          chart={curve.length < 2 ? <div className="flex h-40 items-center justify-center text-sm text-muted">Not enough snapshots yet.</div> : <DrawdownChart data={curve} />}
          table={
            <table className="w-full">
              <thead><tr><Th>Time</Th><Th align="right">Drawdown</Th></tr></thead>
              <tbody>
                {[...curve].reverse().map((c) => (
                  <tr key={c.ts}><Td>{dateTime(c.ts)}</Td><Td align="right">{pct(c.drawdownPct, { digits: 2 })}</Td></tr>
                ))}
              </tbody>
            </table>
          }
        />
        <ChartCard
          title="Daily realized P/L"
          subtitle="Last 30 UTC days (by position close date)"
          actions={<PnlLegend />}
          chart={p.dailyPnl.length === 0 ? <div className="flex h-40 items-center justify-center text-sm text-muted">No closed positions yet.</div> : <DailyPnlChart data={p.dailyPnl} />}
          table={
            <table className="w-full">
              <thead><tr><Th>Day</Th><Th align="right">P/L</Th><Th align="right">Positions closed</Th></tr></thead>
              <tbody>
                {[...p.dailyPnl].reverse().map((d) => (
                  <tr key={d.day}><Td>{d.day}</Td><Td align="right">{usd(d.pnlUsd, { sign: true })}</Td><Td align="right">{d.trades}</Td></tr>
                ))}
              </tbody>
            </table>
          }
        />
      </div>

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        {[
          ['Starting balance', usd(p.startingBalanceUsd)],
          ['Average win', usd(p.averageWinUsd)],
          ['Average loss', usd(p.averageLossUsd)],
          ['Peak equity (liquidation value)', usd(p.peakEquityUsd)],
        ].map(([k, v]) => (
          <div key={k} className="rounded-xl border border-border bg-surface px-4 py-3">
            <div className="text-xs text-muted">{k}</div>
            <div className="tabular mt-1 text-lg font-semibold">{v}</div>
          </div>
        ))}
      </div>
    </div>
  );
}
