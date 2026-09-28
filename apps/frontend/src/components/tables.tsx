import type { Decision, Position, TokenListItem, Trade } from '@memeguard/shared';
import { clsx } from 'clsx';
import { CheckCircle2, CircleDashed, XCircle, AlertTriangle, MinusCircle } from 'lucide-react';
import { Link } from 'react-router-dom';
import { age, dateTime, num, pct, price, ratio, shortAddr, timeAgo, usd } from '../lib/format';
import { DecisionBadge, RiskBadge, RugScore } from './RiskBadge';
import { Empty, Pill, Signed, Td, Th } from './ui';

export const tokenHref = (t: { chain: string; address: string }) => `/tokens/${encodeURIComponent(t.address)}?chain=${t.chain}`;

export function TokenName({ t }: { t: Pick<TokenListItem, 'chain' | 'address' | 'symbol' | 'name'> }) {
  return (
    <Link to={tokenHref(t)} className="group flex min-w-0 flex-col">
      <span className="truncate font-medium text-ink group-hover:text-series-1">{t.symbol ?? shortAddr(t.address)}</span>
      <span className="truncate text-xs text-muted">
        {t.chain} · {t.name ? t.name.slice(0, 22) : shortAddr(t.address)}
      </span>
    </Link>
  );
}

export function TokenTable({ items, compact = false }: { items: TokenListItem[]; compact?: boolean }) {
  if (items.length === 0) return <Empty>No tokens yet. Discovery runs every minute; or scan a token from Settings.</Empty>;
  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[900px] border-collapse">
        <thead>
          <tr>
            <Th>Token</Th>
            <Th align="right">Price</Th>
            <Th align="right">Mkt cap</Th>
            <Th align="right">Liquidity</Th>
            {!compact && <Th align="right">24h vol</Th>}
            {!compact && <Th align="right">Holders</Th>}
            <Th align="right">Top holder</Th>
            <Th align="right">Buy/sell 1h</Th>
            <Th align="right">Rug score</Th>
            <Th>Honeypot</Th>
            <Th>Contract</Th>
            {!compact && <Th>Position</Th>}
            <Th>Decision</Th>
            {!compact && <Th align="right">Age</Th>}
          </tr>
        </thead>
        <tbody>
          {items.map((t) => (
            <tr key={t.id} className="hover:bg-surface-2/60">
              <Td className="max-w-[12rem]">
                <TokenName t={t} />
              </Td>
              <Td align="right">{price(t.priceUsd)}</Td>
              <Td align="right">{usd(t.marketCapUsd, { compact: true })}</Td>
              <Td align="right">{usd(t.liquidityUsd, { compact: true })}</Td>
              {!compact && <Td align="right">{usd(t.volume24hUsd, { compact: true })}</Td>}
              {!compact && <Td align="right">{num(t.holderCount)}</Td>}
              <Td align="right">{pct(t.topHolderPercent)}</Td>
              <Td align="right">{ratio(t.buySellRatio1h)}</Td>
              <Td align="right">
                <RugScore score={t.rugScore} />
              </Td>
              <Td>
                <RiskBadge level={t.honeypotRisk} compact />
              </Td>
              <Td>
                <RiskBadge level={t.contractRisk} compact />
              </Td>
              {!compact && (
                <Td>
                  {t.openPosition ? (
                    <span className="text-xs">
                      <Pill tone="blue">open</Pill>{' '}
                      <Signed value={t.openPosition.unrealizedPnlUsd}>{usd(t.openPosition.unrealizedPnlUsd, { sign: true })}</Signed>
                    </span>
                  ) : (
                    <span className="text-xs text-muted">—</span>
                  )}
                </Td>
              )}
              <Td>
                <DecisionBadge action={t.lastDecision} label={t.lastDecisionLabel} />
              </Td>
              {!compact && <Td align="right">{age(t.pairCreatedAt ?? t.firstSeenAt)}</Td>}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function PositionsTable({ items, onClose, busyId }: { items: Position[]; onClose?: (p: Position) => void; busyId?: number | null }) {
  if (items.length === 0) return <Empty>No positions.</Empty>;
  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[860px] border-collapse">
        <thead>
          <tr>
            <Th>Token</Th>
            <Th>Status</Th>
            <Th align="right">Size</Th>
            <Th align="right">Entry</Th>
            <Th align="right">Current / exit</Th>
            <Th align="right">Stop / target</Th>
            <Th align="right">P/L</Th>
            <Th>Reason</Th>
            <Th align="right">Opened</Th>
            {onClose && <Th />}
          </tr>
        </thead>
        <tbody>
          {items.map((p) => {
            const pnl = p.status === 'open' ? p.unrealizedPnlUsd : p.realizedPnlUsd;
            const pnlPct = p.status === 'open' ? p.unrealizedPnlPct : p.realizedPnlUsd !== null ? (p.realizedPnlUsd / p.costBasisUsd) * 100 : null;
            return (
              <tr key={p.id} className="hover:bg-surface-2/60">
                <Td>
                  <Link to={tokenHref(p)} className="font-medium hover:text-series-1">
                    {p.symbol ?? shortAddr(p.address)}
                  </Link>
                  <div className="text-xs text-muted">
                    {p.chain} · {p.mode}
                  </div>
                </Td>
                <Td>
                  <Pill tone={p.status === 'open' ? 'blue' : 'neutral'}>{p.status}</Pill>
                </Td>
                <Td align="right">{usd(p.costBasisUsd)}</Td>
                <Td align="right">{price(p.entryPriceUsd)}</Td>
                <Td align="right">{price(p.status === 'open' ? p.currentPriceUsd : p.exitPriceUsd)}</Td>
                <Td align="right">
                  <span className="text-xs text-ink-2">
                    {price(p.stopLossPriceUsd)} / {price(p.takeProfitPriceUsd)}
                  </span>
                </Td>
                <Td align="right">
                  <Signed value={pnl}>
                    {usd(pnl, { sign: true })} ({pct(pnlPct, { sign: true })})
                  </Signed>
                </Td>
                <Td>
                  <span className="text-xs text-ink-2">{p.closeReason?.replace(/_/g, ' ') ?? '—'}</span>
                </Td>
                <Td align="right">
                  <span className="text-xs text-ink-2">{dateTime(p.openedAt)}</span>
                </Td>
                {onClose && (
                  <Td align="right">
                    {p.status === 'open' && (
                      <button
                        type="button"
                        disabled={busyId === p.id}
                        onClick={() => onClose(p)}
                        className="rounded-md border border-border px-2 py-1 text-xs text-ink hover:bg-surface-3 disabled:opacity-50"
                      >
                        {busyId === p.id ? 'Closing…' : 'Close'}
                      </button>
                    )}
                  </Td>
                )}
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

export function TradesTable({ items }: { items: Trade[] }) {
  if (items.length === 0) return <Empty>No trades yet.</Empty>;
  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[900px] border-collapse">
        <thead>
          <tr>
            <Th>Time</Th>
            <Th>Token</Th>
            <Th>Side</Th>
            <Th>Status</Th>
            <Th align="right">Requested</Th>
            <Th align="right">Filled</Th>
            <Th align="right">Price</Th>
            <Th align="right">Slippage</Th>
            <Th align="right">Fees</Th>
            <Th>Tx / error</Th>
          </tr>
        </thead>
        <tbody>
          {items.map((t) => (
            <tr key={t.id} className="hover:bg-surface-2/60">
              <Td>
                <span className="text-xs text-ink-2">{dateTime(t.createdAt)}</span>
              </Td>
              <Td>
                <Link to={tokenHref(t)} className="font-medium hover:text-series-1">
                  {t.symbol ?? shortAddr(t.address)}
                </Link>
              </Td>
              <Td>
                <Pill tone={t.side === 'buy' ? 'blue' : 'neutral'}>{t.side}</Pill>
              </Td>
              <Td>
                <Pill tone={t.status === 'filled' ? 'good' : 'critical'}>{t.status}</Pill>
              </Td>
              <Td align="right">{usd(t.requestedUsd)}</Td>
              <Td align="right">{usd(t.filledUsd)}</Td>
              <Td align="right">{price(t.priceUsd)}</Td>
              <Td align="right">{pct(t.slippagePct, { digits: 2 })}</Td>
              <Td align="right">{usd(t.feeUsd)}</Td>
              <Td className="max-w-[18rem]">
                <span className={clsx('block truncate text-xs', t.error ? 'text-ink' : 'text-muted')} title={t.error ?? t.txHash ?? ''}>
                  {t.error ?? shortAddr(t.txHash, 6)}
                </span>
              </Td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

const STAGE_ICON = {
  pass: { Icon: CheckCircle2, cls: 'text-good', label: 'pass' },
  warn: { Icon: AlertTriangle, cls: 'text-warning', label: 'warn' },
  fail: { Icon: XCircle, cls: 'text-critical', label: 'fail' },
  error: { Icon: XCircle, cls: 'text-critical', label: 'error' },
  skipped: { Icon: MinusCircle, cls: 'text-muted', label: 'skipped' },
} as const;

export function DecisionView({ d }: { d: Decision }) {
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <DecisionBadge action={d.action} label={d.label} />
        <span className="text-xs text-muted">
          confidence {Math.round(d.confidence * 100)}% · {d.mode} · {dateTime(d.createdAt)}
          {d.executed && ' · executed'}
        </span>
      </div>
      <ul className="list-disc space-y-1 pl-5 text-sm text-ink-2">
        {d.reasons.map((r, i) => (
          <li key={i}>{r}</li>
        ))}
      </ul>
      <ol className="space-y-1.5">
        {d.stages.map((s, i) => {
          const st = STAGE_ICON[s.status] ?? { Icon: CircleDashed, cls: 'text-muted', label: s.status };
          return (
            <li key={`${s.stage}-${i}`} className="rounded-lg border border-border px-3 py-2">
              <div className="flex items-center gap-2 text-sm">
                <st.Icon size={14} className={st.cls} aria-hidden />
                <span className="font-mono text-xs text-ink">{s.stage}</span>
                <span className="text-xs text-muted">{st.label}</span>
                <span className="ml-auto text-xs text-muted">{s.durationMs}ms</span>
              </div>
              <p className="mt-1 text-sm text-ink-2">{s.summary}</p>
              {Object.keys(s.metrics).length > 0 && (
                <div className="mt-1 flex flex-wrap gap-x-3 gap-y-0.5 text-xs text-muted">
                  {Object.entries(s.metrics).map(([k, v]) => (
                    <span key={k}>
                      {k}: <span className="tabular text-ink-2">{v === null ? 'n/a' : String(v)}</span>
                    </span>
                  ))}
                </div>
              )}
            </li>
          );
        })}
      </ol>
      {d.riskChecks.length > 0 && (
        <div>
          <h4 className="mb-1.5 text-sm font-semibold text-ink">Risk checks</h4>
          <ul className="grid gap-1 sm:grid-cols-2">
            {d.riskChecks.map((c) => (
              <li key={c.check} className="flex items-start gap-2 rounded-md bg-surface-2/60 px-2 py-1.5 text-xs">
                {c.passed ? <CheckCircle2 size={13} className="mt-0.5 shrink-0 text-good" aria-label="passed" /> : <XCircle size={13} className="mt-0.5 shrink-0 text-critical" aria-label="failed" />}
                <span>
                  <span className="font-mono text-ink">{c.check}</span> <span className="text-ink-2">{c.message}</span>
                </span>
              </li>
            ))}
          </ul>
        </div>
      )}
      {Object.keys(d.factors).length > 0 && (
        <details className="text-xs">
          <summary className="cursor-pointer text-muted hover:text-ink">Numerical factors ({Object.keys(d.factors).length})</summary>
          <div className="mt-2 grid gap-x-4 gap-y-0.5 sm:grid-cols-2 lg:grid-cols-3">
            {Object.entries(d.factors).map(([k, v]) => (
              <div key={k} className="flex justify-between gap-2 border-b border-border/50 py-0.5">
                <span className="text-muted">{k}</span>
                <span className="tabular text-ink-2">{v === null ? 'n/a' : v}</span>
              </div>
            ))}
          </div>
        </details>
      )}
    </div>
  );
}

export function DecisionFeed({ items }: { items: Decision[] }) {
  if (items.length === 0) return <Empty>Waiting for decisions…</Empty>;
  return (
    <ul className="divide-y divide-border/60">
      {items.map((d, i) => (
        <li key={`${d.id ?? i}-${d.createdAt}`} className="flex items-center gap-3 px-4 py-2 text-sm">
          <Link to={tokenHref(d)} className="w-24 shrink-0 truncate font-medium hover:text-series-1">
            {d.symbol ?? shortAddr(d.address)}
          </Link>
          <DecisionBadge action={d.action} label={d.label} />
          <span className="ml-auto flex shrink-0 items-center gap-3 text-xs text-muted">
            <span>
              rug <RugScore score={d.rugScore} />
            </span>
            {timeAgo(d.createdAt)}
          </span>
        </li>
      ))}
    </ul>
  );
}
