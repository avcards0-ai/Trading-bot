import type { RiskCheckName, SniperAttempt, SniperStatus } from '@memeguard/shared';
import { useQuery } from '@tanstack/react-query';
import { clsx } from 'clsx';
import { CheckCircle2, ChevronDown, ChevronRight, Crosshair, XCircle } from 'lucide-react';
import { Fragment, useState } from 'react';
import { Link } from 'react-router-dom';
import { PositionsTable } from '../components/tables';
import { Card, Empty, ErrorBox, Pill, Signed, Spinner, StatTile, Td, Th } from '../components/ui';
import { api } from '../lib/api';
import { num, pct, shortAddr, timeAgo, usd } from '../lib/format';

/** Plain-language names for the checks, as a trader would describe the problem. */
const CHECK_LABEL: Partial<Record<RiskCheckName, string>> = {
  TRADING_ENABLED: 'Auto-trading off',
  SNIPER_BUDGET: 'Sniper stopped',
  NOT_HALTED: 'Trading halted',
  SNIPER_MAX_OPEN: 'Sniper position limit',
  MAX_OPEN_POSITIONS: 'Total position limit',
  SNIPER_DAILY_TRADES: 'Daily trade limit',
  SNIPER_DAILY_LOSS: 'Daily loss limit',
  SUFFICIENT_CASH: 'Not enough cash',
  LAUNCH_PARSED: "Couldn't read the launch",
  NO_DUPLICATE_POSITION: 'Already holding it',
  LAUNCH_FRESH: 'Too late',
  LIQUIDITY_SECURED: 'Liquidity not locked',
  MIN_LIQUIDITY: 'Too little liquidity',
  MINT_AUTHORITY_REVOKED: 'Creator can mint more',
  FREEZE_AUTHORITY_REVOKED: 'Creator can freeze tokens',
  NO_DANGEROUS_EXTENSIONS: 'Dangerous token features',
  CREATOR_HOLDINGS: 'Creator holds too much',
  TOP_HOLDER: 'A whale holds too much',
  CREATOR_NO_RUG_HISTORY: 'Creator rugged before',
  CREATOR_WALLET_AGE: 'Creator wallet too new',
  PRICE_IMPACT: 'Price impact too high',
  SELL_ROUTE: "Can't sell it back",
};
const checkLabel = (c: RiskCheckName | null) =>
  c ? (CHECK_LABEL[c] ?? c.replace(/_/g, ' ').toLowerCase()) : '—';

/** Neutral names for the full checklist, where most checks pass. */
const CHECK_NAME: Partial<Record<RiskCheckName, string>> = {
  TRADING_ENABLED: 'Auto-trading on',
  SNIPER_BUDGET: 'Sniper running',
  NOT_HALTED: 'Trading not halted',
  SNIPER_MAX_OPEN: 'Sniper positions',
  MAX_OPEN_POSITIONS: 'All positions',
  SNIPER_DAILY_TRADES: 'Trades today',
  SNIPER_DAILY_LOSS: 'Loss today',
  SUFFICIENT_CASH: 'Cash',
  LAUNCH_PARSED: 'Launch read',
  NO_DUPLICATE_POSITION: 'Not already held',
  LAUNCH_FRESH: 'Launch age',
  LIQUIDITY_SECURED: 'Liquidity locked',
  MIN_LIQUIDITY: 'Liquidity size',
  MINT_AUTHORITY_REVOKED: 'Minting disabled',
  FREEZE_AUTHORITY_REVOKED: 'Freezing disabled',
  NO_DANGEROUS_EXTENSIONS: 'Token features',
  CREATOR_HOLDINGS: 'Creator holdings',
  TOP_HOLDER: 'Largest wallet',
  CREATOR_NO_RUG_HISTORY: 'Creator history',
  CREATOR_WALLET_AGE: 'Creator wallet age',
  PRICE_IMPACT: 'Price impact',
  SELL_ROUTE: 'Can sell back',
};
const checkName = (c: RiskCheckName) => CHECK_NAME[c] ?? c.replace(/_/g, ' ').toLowerCase();

const OUTCOME: Record<SniperAttempt['outcome'], { tone: 'blue' | 'neutral' | 'warning'; label: string }> = {
  bought: { tone: 'blue', label: 'Bought' },
  rejected: { tone: 'neutral', label: 'Skipped' },
  failed: { tone: 'warning', label: 'Error' },
  dropped: { tone: 'neutral', label: 'Dropped' },
};

function StateBadge({ s }: { s: SniperStatus }) {
  const [tone, text] = !s.enabled
    ? (['neutral', 'Off'] as const)
    : !s.running
      ? (['warning', 'Stopped (engine not running)'] as const)
      : s.listener.connected
        ? (['good', 'Listening for launches'] as const)
        : (['critical', 'Reconnecting to Solana'] as const);
  return (
    <Pill tone={tone}>
      <span
        className={clsx(
          'inline-block h-1.5 w-1.5 rounded-full',
          tone === 'good'
            ? 'bg-good'
            : tone === 'critical'
              ? 'bg-critical'
              : tone === 'warning'
                ? 'bg-warning'
                : 'bg-muted',
        )}
        aria-hidden
      />
      {text}
    </Pill>
  );
}

/** Horizontal bars: how many launches each check turned away (one series, so one hue, no legend). */
function RejectionBars({ counts }: { counts: SniperStatus['stats']['rejectionsByCheck'] }) {
  const rows = (Object.entries(counts) as [RiskCheckName, number][]).sort((a, b) => b[1] - a[1]);
  if (rows.length === 0) return <Empty>No launches turned away yet.</Empty>;
  const total = rows.reduce((a, [, n]) => a + n, 0);
  const max = rows[0]?.[1] ?? 1;
  return (
    <ul className="space-y-2.5 p-4" aria-label="Launches rejected, by reason">
      {rows.map(([check, n]) => (
        <li
          key={check}
          className="grid grid-cols-[minmax(0,11rem)_1fr_auto] items-center gap-3"
          title={`${checkLabel(check)}: ${n} of ${total} rejections (${((n / total) * 100).toFixed(0)}%)`}
        >
          <span className="truncate text-xs text-ink-2">{checkLabel(check)}</span>
          <span className="h-2.5">
            <span
              className="block h-full rounded-r bg-series-1"
              style={{ width: `${Math.max(2, (n / max) * 100)}%` }}
            />
          </span>
          <span className="tabular text-xs text-ink">{n}</span>
        </li>
      ))}
    </ul>
  );
}

function Setting({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex items-baseline justify-between gap-3 border-b border-border/60 py-1.5 last:border-0">
      <dt className="text-xs text-muted">{label}</dt>
      <dd className="tabular text-right text-sm text-ink">{children}</dd>
    </div>
  );
}

function AttemptRow({ a }: { a: SniperAttempt }) {
  const [open, setOpen] = useState(false);
  const o = OUTCOME[a.outcome];
  return (
    <Fragment>
      <tr className="hover:bg-surface-2/60">
        <Td>
          <button
            type="button"
            onClick={() => setOpen((v) => !v)}
            className="inline-flex items-center gap-1 text-xs text-ink-2 hover:text-ink"
            aria-expanded={open}
            aria-label={open ? 'Hide checks' : 'Show checks'}
          >
            {open ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
            {timeAgo(a.detectedAt)}
          </button>
        </Td>
        <Td>
          {a.mint ? (
            <Link to={`/tokens/${a.mint}?chain=solana`} className="font-medium hover:text-series-1">
              {a.symbol ?? shortAddr(a.mint)}
            </Link>
          ) : (
            <span className="text-muted">unknown</span>
          )}
          <div className="text-xs text-muted">{a.source}</div>
        </Td>
        <Td>
          <Pill tone={o.tone}>{o.label}</Pill>
        </Td>
        <Td>
          <div className="w-[24rem] whitespace-normal">
            <div className="text-xs text-ink">
              {a.outcome === 'bought' ? 'All checks passed' : checkLabel(a.failedCheck)}
            </div>
            <div className="text-xs text-muted">{a.reason}</div>
          </div>
        </Td>
        <Td align="right">{a.secondsAfterLaunch !== null ? `${a.secondsAfterLaunch.toFixed(1)}s` : '—'}</Td>
        <Td align="right">{a.entryPremiumPct !== null ? pct(a.entryPremiumPct, { sign: true }) : '—'}</Td>
        <Td align="right">{usd(a.liquidityUsd, { compact: true })}</Td>
      </tr>
      {open && (
        <tr>
          <td colSpan={7} className="border-b border-border/60 bg-surface-2/40 px-4 py-3">
            {a.checks.length === 0 ? (
              <span className="text-xs text-muted">No checks ran.</span>
            ) : (
              <ul className="grid gap-1.5 sm:grid-cols-2">
                {a.checks.map((c, i) => (
                  <li key={`${c.check}-${i}`} className="flex items-start gap-2 text-xs">
                    {c.passed ? (
                      <CheckCircle2 size={14} className="mt-0.5 shrink-0 text-good" aria-label="passed" />
                    ) : (
                      <XCircle size={14} className="mt-0.5 shrink-0 text-critical" aria-label="failed" />
                    )}
                    <span>
                      <span className="text-ink">{checkName(c.check)}</span>
                      <span className="text-muted"> · {c.message}</span>
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </td>
        </tr>
      )}
    </Fragment>
  );
}

export function SniperPage() {
  const q = useQuery({ queryKey: ['sniper'], queryFn: api.sniper, refetchInterval: 5_000 });
  if (q.isLoading) return <Spinner />;
  if (q.error) return <ErrorBox error={q.error} />;
  const s = q.data as SniperStatus;
  const cfg = s.settings;

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-center gap-3">
        <h1 className="flex items-center gap-2 text-lg font-semibold">
          <Crosshair size={18} className="text-series-1" aria-hidden />
          Launch sniper
        </h1>
        <Pill tone="blue">Paper trading only</Pill>
        <StateBadge s={s} />
      </div>
      <p className="max-w-3xl text-sm text-ink-2">
        Watches Solana for brand-new pools and buys a small, fixed amount within seconds, but only when every
        launch check passes. It sells quickly: stop loss, take profit, a short time limit, or at once if the
        liquidity is pulled. It reacts to confirmed launches only and never jumps ahead of other traders&apos;
        pending transactions.
      </p>

      {!s.enabled && (
        <Card title="The sniper is off">
          <div className="space-y-2 text-sm text-ink-2">
            <p>{s.disabledReason}</p>
            <p>
              In <code className="rounded bg-surface-3 px-1 text-ink">.env</code> set{' '}
              <code className="rounded bg-surface-3 px-1 text-ink">SNIPER_ENABLED=true</code> and a Solana{' '}
              <code className="rounded bg-surface-3 px-1 text-ink">RPC_URL</code>, then restart and start the
              engine. It refuses to run in live mode.
            </p>
          </div>
        </Card>
      )}

      <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
        <StatTile
          label="Launches seen"
          value={num(s.stats.launchesSeen)}
          hint={`since ${timeAgo(s.stats.since)}`}
        />
        <StatTile
          label="Checked"
          value={num(s.stats.analysed)}
          hint={s.stats.dropped > 0 ? `${num(s.stats.dropped)} dropped (too late or queue full)` : undefined}
        />
        <StatTile
          label="Bought"
          value={num(s.stats.bought)}
          hint={`${num(s.stats.rejected)} skipped · ${num(s.stats.failed)} errors`}
        />
        <StatTile
          label="Typical time to buy"
          value={
            s.stats.medianSecondsAfterLaunch !== null
              ? `${s.stats.medianSecondsAfterLaunch.toFixed(1)}s`
              : '—'
          }
          hint="median, launch block to fill"
        />
        <StatTile
          label="Paid above opening price"
          value={
            s.stats.medianEntryPremiumPct !== null ? pct(s.stats.medianEntryPremiumPct, { sign: true }) : '—'
          }
          hint="median; lower is better"
        />
        <StatTile
          label="Sniper P/L (realized)"
          value={
            <Signed value={s.performance.realizedPnlUsd}>
              {usd(s.performance.realizedPnlUsd, { sign: true })}
            </Signed>
          }
          hint={`${s.performance.wins} W / ${s.performance.losses} L · today ${usd(s.performance.todayRealizedPnlUsd, { sign: true })}`}
        />
      </div>

      <div className="grid gap-5 xl:grid-cols-3">
        <Card
          className="xl:col-span-2"
          title="Why launches were skipped"
          subtitle="The first check each launch failed. Checks stop at the first failure."
          padded={false}
        >
          <RejectionBars counts={s.stats.rejectionsByCheck} />
        </Card>
        <Card
          title="Connection and limits"
          subtitle={cfg ? cfg.sources.map((x) => x.name).join(' · ') : 'Not configured'}
          padded={false}
        >
          <dl className="px-4 py-2">
            <Setting label="Solana stream">
              {s.listener.connected ? 'Connected' : s.enabled && s.running ? 'Reconnecting' : 'Not connected'}
            </Setting>
            <Setting label="Last message">{timeAgo(s.listener.lastMessageAt)}</Setting>
            {s.listener.reconnects > 0 && <Setting label="Reconnects">{s.listener.reconnects}</Setting>}
            {s.listener.lastError && <Setting label="Last problem">{s.listener.lastError}</Setting>}
            {cfg && (
              <>
                <Setting label="Size per trade">{usd(cfg.positionUsd)}</Setting>
                <Setting label="Open at once / trades per day">
                  {cfg.maxOpenPositions} / {cfg.maxTradesPerDay}
                </Setting>
                <Setting label="Daily loss limit">{usd(cfg.maxDailyLossUsd)}</Setting>
                <Setting label="Stop / target / time limit">
                  −{cfg.stopLossPercent}% / +{cfg.takeProfitPercent}% / {cfg.maxHoldMinutes} min
                </Setting>
                <Setting label="Buy only if launch is under">{cfg.maxLaunchAgeSeconds}s old</Setting>
                <Setting label="Minimum liquidity">{usd(cfg.minLiquidityUsd, { compact: true })}</Setting>
                <Setting label="Creator / top wallet holds at most">
                  {cfg.maxCreatorPercent}% / {cfg.maxTopHolderPercent}%
                </Setting>
                <Setting label="Creator wallet at least">{cfg.minCreatorWalletAgeHours}h old</Setting>
                <Setting label="Max price impact">{cfg.maxPriceImpactPercent}%</Setting>
              </>
            )}
          </dl>
        </Card>
      </div>

      <Card
        title="Recent launches"
        subtitle="Newest first. Open a row to see every check. Resets when the backend restarts."
        padded={false}
      >
        {s.recent.length === 0 ? (
          <Empty>{s.running ? 'Waiting for the next launch…' : 'No launches seen yet.'}</Empty>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[940px] border-collapse">
              <thead>
                <tr>
                  <Th>Seen</Th>
                  <Th>Token</Th>
                  <Th>Result</Th>
                  <Th>Why</Th>
                  <Th align="right">After launch</Th>
                  <Th align="right">Vs opening price</Th>
                  <Th align="right">Liquidity</Th>
                </tr>
              </thead>
              <tbody>
                {s.recent.map((a) => (
                  <AttemptRow key={a.signature} a={a} />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      <Card
        title="Sniper positions"
        subtitle={`${s.performance.openPositions} open · ${s.performance.closedPositions} closed. Priced from the pool on-chain every few seconds.`}
        padded={false}
      >
        <PositionsTable items={s.positions} />
      </Card>
      <p className="text-xs text-muted">
        Sniping is high risk: most new tokens fail, and professional snipers usually buy earlier and cheaper.
      </p>
    </div>
  );
}
