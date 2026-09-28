import type { Chain, RiskLimits, ScanResponse, StrategyParams } from '@memeguard/shared';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { KeyRound, Play, Radar, ShieldCheck, Square } from 'lucide-react';
import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { RiskBadge } from '../components/RiskBadge';
import { DecisionView, tokenHref } from '../components/tables';
import { Button, Card, ErrorBox, Spinner } from '../components/ui';
import { ApiError, adminKey, api } from '../lib/api';

const CHAINS: Chain[] = ['solana', 'ethereum', 'base', 'bsc', 'arbitrum'];

const LIMIT_FIELDS: {
  key: keyof RiskLimits;
  label: string;
  unit: string;
  stricter: 'lower' | 'higher' | 'bool';
}[] = [
  { key: 'maxPositionPercent', label: 'MAX_POSITION_PERCENT', unit: '% of equity', stricter: 'lower' },
  { key: 'maxDailyLossPercent', label: 'MAX_DAILY_LOSS', unit: '% of day-start equity', stricter: 'lower' },
  { key: 'maxDrawdownPercent', label: 'MAX_DRAWDOWN', unit: '% from peak', stricter: 'lower' },
  { key: 'maxOpenPositions', label: 'MAX_OPEN_POSITIONS', unit: 'positions', stricter: 'lower' },
  { key: 'minLiquidityUsd', label: 'MIN_LIQUIDITY', unit: 'USD', stricter: 'higher' },
  { key: 'maxRugScore', label: 'MAX_RUG_SCORE', unit: '0–100', stricter: 'lower' },
  { key: 'maxSlippagePercent', label: 'MAX_SLIPPAGE', unit: '% price impact', stricter: 'lower' },
  { key: 'minTokenAgeMinutes', label: 'MIN_TOKEN_AGE', unit: 'minutes', stricter: 'higher' },
  { key: 'maxLiquiditySharePercent', label: 'MAX_LIQUIDITY_SHARE', unit: '% of pool', stricter: 'lower' },
  { key: 'minPositionUsd', label: 'MIN_POSITION_USD', unit: 'USD', stricter: 'higher' },
  { key: 'maxDataAgeSeconds', label: 'MAX_DATA_AGE', unit: 'seconds', stricter: 'lower' },
];

const STRATEGY_FIELDS: { key: keyof StrategyParams; label: string; unit: string }[] = [
  { key: 'stopLossPercent', label: 'Stop loss', unit: '%' },
  { key: 'takeProfitPercent', label: 'Take profit', unit: '%' },
  { key: 'trailingStopPercent', label: 'Trailing stop (blank = off)', unit: '%' },
  { key: 'maxHoldMinutes', label: 'Max hold time', unit: 'min' },
  { key: 'riskPerTradePercent', label: 'Risk per trade', unit: '% of equity' },
  { key: 'minStrategyScore', label: 'Min strategy score', unit: '0–100' },
  { key: 'minBuySellRatio', label: 'Min buy/sell ratio (1h)', unit: '×' },
  { key: 'minVolume1hUsd', label: 'Min 1h volume', unit: 'USD' },
  { key: 'maxPriceChange5mPercent', label: 'Max 5m price change (no chasing)', unit: '%' },
  { key: 'minPriceChange1hPercent', label: 'Min 1h price change', unit: '%' },
  { key: 'maxTokenAgeMinutes', label: 'Max token age', unit: 'min' },
  { key: 'exitOnRugScoreAbove', label: 'Exit when rug score ≥', unit: '0–100' },
  { key: 'exitOnLiquidityDropPercent', label: 'Exit when liquidity drops ≥', unit: '%' },
];

function AdminKeyCard() {
  const qc = useQueryClient();
  const [value, setValue] = useState('');
  const [remember, setRemember] = useState(false);
  const [hasKey, setHasKey] = useState(() => adminKey.get() !== null);
  return (
    <Card
      title="Admin access"
      subtitle="Administrative actions require the API_KEY configured on the backend"
    >
      <div className="flex flex-wrap items-end gap-3">
        <label className="text-xs text-muted">
          API key
          <input
            type="password"
            autoComplete="off"
            value={value}
            onChange={(e) => setValue(e.target.value)}
            placeholder={hasKey ? '•••••••• (stored)' : 'paste API_KEY'}
            className="mt-1 block w-80 max-w-full rounded-md border border-border bg-surface-2 px-2 py-1.5 text-sm text-ink"
          />
        </label>
        <label className="flex items-center gap-2 text-xs text-muted">
          <input type="checkbox" checked={remember} onChange={(e) => setRemember(e.target.checked)} />{' '}
          Remember on this device
        </label>
        <Button
          variant="primary"
          disabled={value.trim().length === 0}
          onClick={() => {
            adminKey.set(value.trim(), remember);
            setValue('');
            setHasKey(true);
            void qc.invalidateQueries();
          }}
        >
          <KeyRound size={14} aria-hidden /> Save key
        </Button>
        {hasKey && (
          <Button
            onClick={() => {
              adminKey.clear();
              setHasKey(false);
            }}
          >
            Forget key
          </Button>
        )}
      </div>
      <p className="mt-2 text-xs text-muted">
        The key is kept in this browser's session storage (or local storage if remembered) and sent only in
        the Authorization header — never in URLs.
      </p>
    </Card>
  );
}

function EngineCard() {
  const qc = useQueryClient();
  const status = useQuery({ queryKey: ['status'], queryFn: api.status, refetchInterval: 10_000 });
  const done = () => qc.invalidateQueries({ queryKey: ['status'] });
  const start = useMutation({ mutationFn: api.engineStart, onSuccess: done });
  const stop = useMutation({ mutationFn: api.engineStop, onSuccess: done });
  const resume = useMutation({ mutationFn: api.resume, onSuccess: done });
  const discover = useMutation({ mutationFn: api.discover });
  const err = start.error ?? stop.error ?? resume.error ?? discover.error;
  const s = status.data;
  return (
    <Card
      title="Engine control"
      subtitle={s ? `Engine ${s.engineRunning ? 'running' : 'stopped'} · ${s.mode} mode` : undefined}
    >
      <div className="flex flex-wrap gap-2">
        <Button
          variant="primary"
          onClick={() => start.mutate()}
          disabled={start.isPending || s?.engineRunning}
        >
          <Play size={14} aria-hidden /> Start engine
        </Button>
        <Button onClick={() => stop.mutate()} disabled={stop.isPending || s?.engineRunning === false}>
          <Square size={14} aria-hidden /> Stop engine
        </Button>
        <Button onClick={() => discover.mutate()} disabled={discover.isPending}>
          <Radar size={14} aria-hidden /> Run discovery now
        </Button>
        {s?.halted && (
          <Button
            variant="danger"
            onClick={() => {
              if (window.confirm('Resume trading after a risk halt? Make sure you understand why it halted.'))
                resume.mutate();
            }}
          >
            <ShieldCheck size={14} aria-hidden /> Resume after halt
          </Button>
        )}
      </div>
      <p className="mt-2 text-xs text-muted">
        Stopping the engine halts discovery and new entries only; open positions keep their stop-loss,
        take-profit and rug-exit protection.
      </p>
      {stop.data?.note && <p className="mt-1 text-xs text-ink-2">{stop.data.note}</p>}
      {err && (
        <div className="mt-3">
          <ErrorBox error={err} />
        </div>
      )}
    </Card>
  );
}

function ScanCard() {
  const [chain, setChain] = useState<Chain>('solana');
  const [address, setAddress] = useState('');
  const [allowTrade, setAllowTrade] = useState(false);
  const scan = useMutation({ mutationFn: () => api.scan({ chain, address: address.trim(), allowTrade }) });
  const result: ScanResponse | undefined = scan.data;
  return (
    <Card title="Rug scanner" subtitle="Run the full decision pipeline on any token">
      <form
        className="flex flex-wrap items-end gap-3"
        onSubmit={(e) => {
          e.preventDefault();
          if (address.trim()) scan.mutate();
        }}
      >
        <label className="text-xs text-muted">
          Chain
          <select
            value={chain}
            onChange={(e) => setChain(e.target.value as Chain)}
            className="mt-1 block rounded-md border border-border bg-surface-2 px-2 py-1.5 text-sm text-ink"
          >
            {CHAINS.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        </label>
        <label className="min-w-0 flex-1 text-xs text-muted">
          Token address
          <input
            value={address}
            onChange={(e) => setAddress(e.target.value)}
            placeholder="mint / contract address"
            className="mt-1 block w-full rounded-md border border-border bg-surface-2 px-2 py-1.5 font-mono text-sm text-ink"
          />
        </label>
        <label
          className="flex items-center gap-2 text-xs text-muted"
          title="Only executes if every risk check passes"
        >
          <input type="checkbox" checked={allowTrade} onChange={(e) => setAllowTrade(e.target.checked)} />{' '}
          Allow trade if all checks pass
        </label>
        <Button type="submit" variant="primary" disabled={scan.isPending || !address.trim()}>
          {scan.isPending ? 'Scanning…' : 'Scan'}
        </Button>
      </form>
      {scan.error && (
        <div className="mt-3">
          <ErrorBox error={scan.error} />
        </div>
      )}
      {result && (
        <div className="mt-4 space-y-3">
          <div className="flex flex-wrap items-center gap-3 text-sm">
            <span>
              RUG_SCORE <strong className="tabular">{result.risk.rugScore}</strong>
            </span>
            <span>
              Honeypot <RiskBadge level={result.risk.honeypotRisk} compact />
            </span>
            <span>
              Liquidity <RiskBadge level={result.risk.liquidityRisk} compact />
            </span>
            <span>
              Contract <RiskBadge level={result.risk.contractRisk} compact />
            </span>
            <span>
              Concentration <RiskBadge level={result.risk.walletConcentrationRisk} compact />
            </span>
            <span>
              Overall <RiskBadge level={result.risk.overallRisk} />
            </span>
            <Link to={tokenHref(result.decision)} className="text-series-1 hover:underline">
              Open token page
            </Link>
          </div>
          <DecisionView d={result.decision} />
        </div>
      )}
    </Card>
  );
}

function StrategyCard() {
  const qc = useQueryClient();
  const cfg = useQuery({ queryKey: ['config'], queryFn: api.config });
  const [limits, setLimits] = useState<Record<string, string>>({});
  const [strategy, setStrategy] = useState<Record<string, string>>({});
  const [autoTrade, setAutoTrade] = useState(true);
  const [chains, setChains] = useState<Chain[]>([]);
  useEffect(() => {
    const e = cfg.data?.effective;
    if (!e) return;
    setLimits(Object.fromEntries(LIMIT_FIELDS.map((f) => [f.key, String(e.limits[f.key])])));
    setStrategy(
      Object.fromEntries(
        STRATEGY_FIELDS.map((f) => [f.key, e.strategy[f.key] === null ? '' : String(e.strategy[f.key])]),
      ),
    );
    setAutoTrade(e.strategy.autoTrade);
    setChains(e.strategy.chains);
  }, [cfg.data]);
  const save = useMutation({
    mutationFn: () => {
      const e = cfg.data?.effective;
      const limitsPatch: Partial<RiskLimits> = {};
      for (const f of LIMIT_FIELDS) {
        const v = Number(limits[f.key]);
        if (Number.isFinite(v) && e && v !== e.limits[f.key])
          (limitsPatch as Record<string, number>)[f.key] = v;
      }
      const strategyPatch: Partial<StrategyParams> = { autoTrade, chains };
      for (const f of STRATEGY_FIELDS) {
        const raw = strategy[f.key] ?? '';
        if (f.key === 'trailingStopPercent')
          (strategyPatch as Record<string, unknown>)[f.key] = raw === '' ? null : Number(raw);
        else if (raw !== '') (strategyPatch as Record<string, unknown>)[f.key] = Number(raw);
      }
      return api.updateStrategy({ limits: limitsPatch, strategy: strategyPatch });
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['config'] }),
  });
  if (cfg.isLoading) return <Spinner />;
  if (cfg.error) return <ErrorBox error={cfg.error} />;
  const e = cfg.data?.effective;
  if (!e) return null;
  const issues = save.error instanceof ApiError ? save.error.issues : undefined;

  return (
    <Card
      title="Strategy & risk limits"
      subtitle={`Version ${e.version} · mode ${e.mode.toUpperCase()} (mode can only be changed in the environment + restart)`}
    >
      <form
        onSubmit={(ev) => {
          ev.preventDefault();
          save.mutate();
        }}
        className="space-y-5"
      >
        <div>
          <h3 className="text-sm font-semibold">Risk limits</h3>
          <p className="mb-2 text-xs text-muted">
            Environment variables are hard caps. Runtime values may only be stricter; looser values are
            rejected.
          </p>
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {LIMIT_FIELDS.map((f) => (
              <label key={f.key} className="text-xs text-muted">
                <span className="font-mono">{f.label}</span> ({f.unit})
                <input
                  inputMode="decimal"
                  value={limits[f.key] ?? ''}
                  onChange={(ev) => setLimits((l) => ({ ...l, [f.key]: ev.target.value }))}
                  className="mt-1 block w-full rounded-md border border-border bg-surface-2 px-2 py-1.5 text-sm text-ink"
                />
                <span className="text-[11px]">
                  hard limit {String(e.hardLimits[f.key])} (
                  {f.stricter === 'lower' ? 'must be ≤' : 'must be ≥'})
                </span>
              </label>
            ))}
            <div className="text-xs text-muted">
              <span className="font-mono">REQUIRE_HONEYPOT_CHECK</span>
              <div className="mt-2 text-sm text-ink">
                {e.limits.requireHoneypotCheck ? 'on' : 'off'}{' '}
                {e.hardLimits.requireHoneypotCheck && '(enforced by environment)'}
              </div>
            </div>
          </div>
        </div>
        <div>
          <h3 className="mb-2 text-sm font-semibold">Strategy</h3>
          <div className="mb-3 flex flex-wrap items-center gap-4 text-sm">
            <label className="flex items-center gap-2">
              <input type="checkbox" checked={autoTrade} onChange={(ev) => setAutoTrade(ev.target.checked)} />{' '}
              Auto-trade
            </label>
            {CHAINS.map((c) => (
              <label key={c} className="flex items-center gap-1.5 text-xs text-ink-2">
                <input
                  type="checkbox"
                  checked={chains.includes(c)}
                  onChange={(ev) =>
                    setChains((cs) => (ev.target.checked ? [...cs, c] : cs.filter((x) => x !== c)))
                  }
                />
                {c}
              </label>
            ))}
          </div>
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {STRATEGY_FIELDS.map((f) => (
              <label key={f.key} className="text-xs text-muted">
                {f.label} ({f.unit})
                <input
                  inputMode="decimal"
                  value={strategy[f.key] ?? ''}
                  onChange={(ev) => setStrategy((s) => ({ ...s, [f.key]: ev.target.value }))}
                  className="mt-1 block w-full rounded-md border border-border bg-surface-2 px-2 py-1.5 text-sm text-ink"
                />
              </label>
            ))}
          </div>
        </div>
        {save.error && (
          <div>
            <ErrorBox error={issues?.length ? 'Update rejected:' : save.error} />
            {issues && (
              <ul className="mt-2 list-disc pl-6 text-sm text-ink-2">
                {issues.map((i) => (
                  <li key={i}>{i}</li>
                ))}
              </ul>
            )}
          </div>
        )}
        {save.isSuccess && <p className="text-sm text-ink-2">Saved as version {save.data.version}.</p>}
        <Button type="submit" variant="primary" disabled={save.isPending}>
          {save.isPending ? 'Saving…' : 'Save configuration'}
        </Button>
      </form>
    </Card>
  );
}

export function SettingsPage() {
  return (
    <div className="space-y-5">
      <h1 className="text-lg font-semibold">Configuration</h1>
      <AdminKeyCard />
      <div className="grid gap-5 xl:grid-cols-2">
        <EngineCard />
        <Card title="Live trading" subtitle="Cannot be enabled from the dashboard">
          <p className="text-sm text-ink-2">
            Live trading requires an explicit environment change and a restart:{' '}
            <code className="text-ink">TRADING_MODE=live</code>, the exact confirmation phrase in{' '}
            <code className="text-ink">LIVE_TRADING_CONFIRMATION</code>, a wallet key file,{' '}
            <code className="text-ink">RPC_URL</code> and <code className="text-ink">API_KEY</code>. If any is
            missing the backend refuses to start. See the README.
          </p>
        </Card>
      </div>
      <ScanCard />
      <StrategyCard />
    </div>
  );
}
