import type { BacktestResult } from '@memeguard/shared';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { AlertOctagon, AlertTriangle } from 'lucide-react';
import { useState } from 'react';
import { DrawdownChart, LineSeriesChart } from '../components/charts';
import { Button, Card, ChartCard, Empty, ErrorBox, Pill, Spinner, Td, Th } from '../components/ui';
import { api } from '../lib/api';
import { dateTime, num, pct, price, usd } from '../lib/format';

function Metric({ label, value, emphasis }: { label: string; value: string; emphasis?: boolean }) {
  return (
    <div className="rounded-lg border border-border px-3 py-2">
      <div className="text-xs text-muted">{label}</div>
      <div className={emphasis ? 'tabular mt-0.5 text-lg font-semibold text-ink' : 'tabular mt-0.5 text-sm font-medium text-ink'}>{value}</div>
    </div>
  );
}

function Result({ r }: { r: BacktestResult }) {
  const m = r.metrics;
  const n = (v: number | null, d = 2) => (v === null ? '—' : v.toFixed(d));
  return (
    <div className="space-y-5">
      <div className="space-y-2">
        {r.warnings.map((w) => (
          <div key={w} className="flex items-start gap-2 rounded-lg border border-warning/40 bg-warning/10 px-3 py-2 text-sm text-ink">
            <AlertTriangle size={15} className="mt-0.5 shrink-0 text-warning" aria-hidden /> {w}
          </div>
        ))}
      </div>

      <Card title="Results" subtitle={`${r.name} · ${r.source}${r.syntheticData ? ' (synthetic)' : ''} · ${dateTime(r.finishedAt)}`}>
        <div className="grid gap-2 sm:grid-cols-3 lg:grid-cols-6">
          <Metric label="Starting balance" value={usd(m.startingBalanceUsd)} />
          <Metric label="Ending balance" value={usd(m.endingBalanceUsd)} emphasis />
          <Metric label="Total return" value={pct(m.totalReturnPct, { sign: true, digits: 2 })} emphasis />
          <Metric label="Maximum drawdown" value={`${pct(m.maxDrawdownPct, { digits: 2 })} (${usd(m.maxDrawdownUsd)})`} emphasis />
          <Metric label="Number of trades" value={num(m.numberOfTrades)} />
          <Metric label="Win rate" value={m.winRate === null ? '—' : pct(m.winRate * 100)} />
          <Metric label="Winning trades" value={num(m.winningTrades)} />
          <Metric label="Losing trades" value={num(m.losingTrades)} />
          <Metric label="Average win" value={usd(m.averageWinUsd)} />
          <Metric label="Average loss" value={usd(m.averageLossUsd)} />
          <Metric label="Profit factor" value={n(m.profitFactor)} />
          <Metric label="Largest gain" value={usd(m.largestGainUsd)} />
          <Metric label="Largest loss" value={usd(m.largestLossUsd)} />
        </div>
        <h3 className="mb-2 mt-5 text-sm font-semibold">Risk-adjusted</h3>
        <div className="grid gap-2 sm:grid-cols-3 lg:grid-cols-6">
          <Metric label="Expectancy / trade" value={usd(m.expectancyUsd)} />
          <Metric label="Sharpe (per trade)" value={n(m.sharpeRatio, 3)} />
          <Metric label="Sortino (per trade)" value={n(m.sortinoRatio, 3)} />
          <Metric label="Calmar" value={n(m.calmarRatio, 3)} />
          <Metric label="CVaR 95% (worst 5%)" value={pct(m.cvar95Pct, { digits: 2 })} />
          <Metric label="Exposure" value={pct(m.exposurePct)} />
          <Metric label="Fees paid" value={usd(m.totalFeesUsd)} />
        </div>
        <h3 className="mb-2 mt-5 text-sm font-semibold">Rug protection</h3>
        <div className="grid gap-2 sm:grid-cols-3 lg:grid-cols-6">
          <Metric label="Tokens evaluated" value={num(m.tokensEvaluated)} />
          <Metric label="Skipped for rug risk" value={num(m.tokensSkippedForRugRisk)} />
          <Metric label="Scams avoided" value={num(m.rugsAvoided)} />
          <Metric label="Scams traded into" value={num(m.rugsHit)} emphasis />
          <Metric label="Catastrophic losses" value={num(m.catastrophicLosses)} emphasis />
        </div>
      </Card>

      <Card title={`Catastrophic events (${r.catastrophicEvents.length})`} subtitle="Rugs while holding, gaps through the stop, trades losing more than the catastrophic threshold, drawdown-limit breaches" padded={false}>
        {r.catastrophicEvents.length === 0 ? (
          <Empty>None in this run. That does not mean none can happen: stealth rugs look clean at launch.</Empty>
        ) : (
          <div className="max-h-80 overflow-auto">
            <table className="w-full min-w-[700px]">
              <thead>
                <tr><Th>Time</Th><Th>Kind</Th><Th>Token</Th><Th align="right">Loss</Th><Th>Description</Th></tr>
              </thead>
              <tbody>
                {r.catastrophicEvents.map((e, i) => (
                  <tr key={`${e.ts}-${i}`}>
                    <Td>{dateTime(e.ts)}</Td>
                    <Td>
                      <span className="inline-flex items-center gap-1 text-xs">
                        <AlertOctagon size={13} className="text-critical" aria-hidden /> {e.kind.replace(/_/g, ' ')}
                      </span>
                    </Td>
                    <Td>{e.symbol ?? '—'}</Td>
                    <Td align="right">{usd(-e.lossUsd)} ({pct(-e.lossPct)})</Td>
                    <Td className="whitespace-normal text-xs text-ink-2">{e.description}</Td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      <div className="grid gap-5 xl:grid-cols-2">
        <ChartCard
          title="Equity"
          chart={<LineSeriesChart data={r.equityCurve as unknown as Record<string, unknown>[]} dataKey="equityUsd" name="Equity" format={(v) => usd(v, { compact: true })} />}
          table={
            <table className="w-full">
              <thead><tr><Th>Time</Th><Th align="right">Equity</Th></tr></thead>
              <tbody>{r.equityCurve.slice(-500).map((p) => <tr key={p.ts}><Td>{dateTime(p.ts)}</Td><Td align="right">{usd(p.equityUsd)}</Td></tr>)}</tbody>
            </table>
          }
        />
        <ChartCard
          title="Drawdown"
          chart={<DrawdownChart data={r.equityCurve} height={240} />}
          table={
            <table className="w-full">
              <thead><tr><Th>Time</Th><Th align="right">Drawdown</Th></tr></thead>
              <tbody>{r.equityCurve.slice(-500).map((p) => <tr key={p.ts}><Td>{dateTime(p.ts)}</Td><Td align="right">{pct(p.drawdownPct, { digits: 2 })}</Td></tr>)}</tbody>
            </table>
          }
        />
      </div>

      <Card title={`Trades (${r.trades.length})`} padded={false}>
        {r.trades.length === 0 ? (
          <Empty>No trades: every candidate failed the rug filter, strategy or risk checks.</Empty>
        ) : (
          <div className="max-h-96 overflow-auto">
            <table className="w-full min-w-[800px]">
              <thead>
                <tr><Th>Token</Th><Th>Entry</Th><Th>Exit</Th><Th align="right">Size</Th><Th align="right">Entry price</Th><Th align="right">Exit price</Th><Th align="right">P/L</Th><Th>Exit reason</Th></tr>
              </thead>
              <tbody>
                {r.trades.map((t, i) => (
                  <tr key={`${t.address}-${i}`} className={t.catastrophic ? 'bg-critical/10' : undefined}>
                    <Td>{t.symbol ?? t.address.slice(0, 8)} {t.catastrophic && <Pill tone="critical">catastrophic</Pill>}</Td>
                    <Td>{dateTime(t.entryTs)}</Td>
                    <Td>{dateTime(t.exitTs)}</Td>
                    <Td align="right">{usd(t.sizeUsd)}</Td>
                    <Td align="right">{price(t.entryPriceUsd)}</Td>
                    <Td align="right">{price(t.exitPriceUsd)}</Td>
                    <Td align="right">{usd(t.pnlUsd, { sign: true })} ({pct(t.pnlPct, { sign: true })})</Td>
                    <Td className="text-xs text-ink-2">{t.exitReason.replace(/_/g, ' ')}</Td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </div>
  );
}

export function BacktestPage() {
  const qc = useQueryClient();
  const [source, setSource] = useState<'synthetic' | 'database'>('synthetic');
  const [tokens, setTokens] = useState(200);
  const [seed, setSeed] = useState('42');
  const [assumeClean, setAssumeClean] = useState(false);
  const [selected, setSelected] = useState<number | null>(null);
  const runs = useQuery({ queryKey: ['backtests'], queryFn: api.backtests });
  const loaded = useQuery({ queryKey: ['backtest', selected], queryFn: () => api.backtest(selected as number), enabled: selected !== null });
  const run = useMutation({
    mutationFn: () => api.runBacktest({ source, tokens, seed, assumeCleanSecurity: assumeClean }),
    onSuccess: (r) => {
      setSelected(null);
      void qc.invalidateQueries({ queryKey: ['backtests'] });
      return r;
    },
  });
  const result = run.data && selected === null ? run.data : loaded.data;

  return (
    <div className="space-y-5">
      <div>
        <h1 className="text-lg font-semibold">Backtesting</h1>
        <p className="mt-1 max-w-3xl text-sm text-muted">
          Replays token histories through the same rug detector, strategy, sizing and risk limits used live. Fills are pessimistic (stops fill first when a bar touches both, stops gap, rugs exit into the drained pool). Judge a strategy by drawdown and catastrophic events — not total return alone.
        </p>
      </div>
      <Card title="Run a backtest" subtitle="Requires the admin API key (Configuration page)">
        <form
          className="flex flex-wrap items-end gap-4"
          onSubmit={(e) => {
            e.preventDefault();
            run.mutate();
          }}
        >
          <label className="text-xs text-muted">
            Data source
            <select value={source} onChange={(e) => setSource(e.target.value as 'synthetic' | 'database')} className="mt-1 block rounded-md border border-border bg-surface-2 px-2 py-1.5 text-sm text-ink">
              <option value="synthetic">Synthetic scenarios (engine test)</option>
              <option value="database">Recorded history (database replay)</option>
            </select>
          </label>
          <label className="text-xs text-muted">
            Tokens
            <input type="number" min={1} max={1000} value={tokens} onChange={(e) => setTokens(Number(e.target.value))} className="mt-1 block w-24 rounded-md border border-border bg-surface-2 px-2 py-1.5 text-sm text-ink" />
          </label>
          <label className="text-xs text-muted">
            Seed
            <input value={seed} onChange={(e) => setSeed(e.target.value)} className="mt-1 block w-28 rounded-md border border-border bg-surface-2 px-2 py-1.5 text-sm text-ink" />
          </label>
          <label className="flex items-center gap-2 text-xs text-muted" title="Only affects tokens that have no security data">
            <input type="checkbox" checked={assumeClean} onChange={(e) => setAssumeClean(e.target.checked)} />
            Assume clean security when data is missing (optimistic)
          </label>
          <Button type="submit" variant="primary" disabled={run.isPending}>
            {run.isPending ? 'Running…' : 'Run backtest'}
          </Button>
        </form>
        {run.error && <div className="mt-3"><ErrorBox error={run.error} /></div>}
      </Card>

      <Card title="Previous runs" padded={false}>
        {runs.isLoading ? (
          <Spinner />
        ) : (runs.data?.items.length ?? 0) === 0 ? (
          <Empty>No saved runs yet.</Empty>
        ) : (
          <div className="max-h-64 overflow-auto">
            <table className="w-full">
              <thead><tr><Th>Run</Th><Th>Source</Th><Th align="right">Return</Th><Th align="right">Max DD</Th><Th align="right">Trades</Th><Th align="right">Catastrophic</Th><Th align="right">Created</Th></tr></thead>
              <tbody>
                {runs.data?.items.map((b) => (
                  <tr key={b.id} className="cursor-pointer hover:bg-surface-2/60" onClick={() => setSelected(b.id)}>
                    <Td><span className="text-series-1">{b.name}</span></Td>
                    <Td>{b.source}{b.synthetic && ' (synthetic)'}</Td>
                    <Td align="right">{pct(b.metrics.totalReturnPct, { sign: true, digits: 2 })}</Td>
                    <Td align="right">{pct(b.metrics.maxDrawdownPct, { digits: 2 })}</Td>
                    <Td align="right">{b.metrics.numberOfTrades}</Td>
                    <Td align="right">{b.metrics.catastrophicLosses}</Td>
                    <Td align="right">{dateTime(b.createdAt)}</Td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      {loaded.isLoading && selected !== null && <Spinner />}
      {result && <Result r={result} />}
    </div>
  );
}
