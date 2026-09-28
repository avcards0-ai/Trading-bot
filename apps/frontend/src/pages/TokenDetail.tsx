import type { Chain, TokenSnapshot } from '@memeguard/shared';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Copy, ExternalLink, RefreshCw } from 'lucide-react';
import { useState } from 'react';
import { useParams, useSearchParams } from 'react-router-dom';
import { LineSeriesChart, TimeSeriesChart } from '../components/charts';
import { DecisionBadge, RiskBadge } from '../components/RiskBadge';
import { CategoryBars, RiskExplanation, RugScoreMeter } from '../components/RugRiskPanel';
import { DecisionView, PositionsTable } from '../components/tables';
import { Button, Card, ChartCard, Empty, ErrorBox, Pill, Spinner, StatTile, Td, Th } from '../components/ui';
import { AlertList } from './Alerts';
import { api, ApiError } from '../lib/api';
import { age, dateTime, explorerUrl, num, pct, price, ratio, shortAddr, timeAgo, usd } from '../lib/format';

function Flag({ label, value, bad }: { label: string; value: boolean | null | undefined | string | number; bad?: boolean }) {
  const shown = value === null || value === undefined ? 'unknown' : typeof value === 'boolean' ? (value ? 'yes' : 'no') : String(value);
  return (
    <div className="flex items-center justify-between gap-2 border-b border-border/50 py-1 text-sm">
      <span className="text-muted">{label}</span>
      <span className={bad ? 'font-medium text-ink' : 'text-ink-2'}>
        {bad && <span className="mr-1 text-critical" aria-label="risk">●</span>}
        {shown}
      </span>
    </div>
  );
}

function ContractDetails({ s }: { s: TokenSnapshot }) {
  const c = s.contract;
  const h = s.honeypot;
  if (!c) return <Empty>No contract data was available — treated as risk.</Empty>;
  return (
    <div className="grid gap-x-6 sm:grid-cols-2">
      <div>
        <Flag label="Token program" value={c.tokenProgram} bad={c.tokenProgram === 'unknown'} />
        <Flag label="Source verified" value={c.isVerified} bad={c.isVerified === false} />
        <Flag label="Upgradeable proxy" value={c.isProxy} bad={c.isProxy === true} />
        <Flag label="Owner" value={c.ownerAddress ? shortAddr(c.ownerAddress) : c.ownershipRenounced ? 'renounced' : null} bad={c.ownershipRenounced === false} />
        <Flag label="Hidden owner" value={c.hiddenOwner} bad={c.hiddenOwner === true} />
        <Flag label="Mint authority" value={c.mintAuthority ? shortAddr(c.mintAuthority) : c.mintable} bad={c.mintable === true} />
        <Flag label="Freeze authority" value={c.freezeAuthority ? shortAddr(c.freezeAuthority) : c.freezable} bad={c.freezable === true} />
        <Flag label="Owner can change balances" value={c.ownerCanChangeBalance} bad={c.ownerCanChangeBalance === true} />
        <Flag label="Metadata mutable" value={c.metadataMutable} bad={c.metadataMutable === true} />
      </div>
      <div>
        <Flag label="Honeypot (simulation)" value={h ? (h.isHoneypot === null ? `unverified${h.reason ? ` (${h.reason})` : ''}` : h.isHoneypot) : null} bad={h?.isHoneypot !== false} />
        <Flag label="Sell route found" value={h?.sellRouteFound} bad={h?.sellRouteFound === false} />
        <Flag label="Buy tax" value={pct(Math.max(c.buyTaxPct ?? -1, h?.buyTaxPct ?? -1) >= 0 ? Math.max(c.buyTaxPct ?? 0, h?.buyTaxPct ?? 0) : null)} bad={(c.buyTaxPct ?? 0) >= 10} />
        <Flag label="Sell tax" value={pct(Math.max(c.sellTaxPct ?? -1, h?.sellTaxPct ?? -1) >= 0 ? Math.max(c.sellTaxPct ?? 0, h?.sellTaxPct ?? 0) : null)} bad={(c.sellTaxPct ?? 0) >= 10 || (h?.sellTaxPct ?? 0) >= 10} />
        <Flag label="Taxes modifiable" value={c.taxModifiable} bad={c.taxModifiable === true} />
        <Flag label="Blacklist" value={c.hasBlacklist} bad={c.hasBlacklist === true} />
        <Flag label="Transfers pausable" value={c.transferPausable} bad={c.transferPausable === true} />
        <Flag label="Transfer hook" value={c.transferHook} bad={c.transferHook === true} />
        <Flag label="Non-transferable" value={c.nonTransferable} bad={c.nonTransferable === true} />
      </div>
      {c.suspiciousFunctions.length > 0 && (
        <div className="mt-3 sm:col-span-2">
          <div className="text-xs text-muted">Suspicious functions / extensions</div>
          <div className="mt-1 flex flex-wrap gap-1">
            {c.suspiciousFunctions.map((f) => (
              <code key={f} className="rounded bg-surface-3 px-1.5 py-0.5 text-xs text-ink">
                {f}
              </code>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

function WalletAnalysis({ address, chain }: { address: string; chain?: Chain }) {
  const q = useQuery({ queryKey: ['token', 'wallets', address, chain], queryFn: () => api.wallets(address, chain) });
  if (q.isLoading) return <Spinner />;
  if (q.error) return <ErrorBox error={q.error} />;
  const d = q.data;
  if (!d) return null;
  const clusterOf = new Map<string, string>();
  for (const c of d.walletAnalysis?.clusters ?? []) for (const w of c.wallets) clusterOf.set(w, c.funder);
  const walletInfo = new Map(d.wallets.map((w) => [w.address, w]));
  return (
    <div className="space-y-5">
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <StatTile label="Holders" value={num(d.holders?.holderCount)} />
        <StatTile label="Largest funding cluster" value={pct(d.walletAnalysis?.largestClusterPercent)} hint={`${d.walletAnalysis?.clusters.length ?? 0} clusters found`} />
        <StatTile label="Fresh wallets in top holders" value={d.walletAnalysis?.newWalletShare !== null && d.walletAnalysis?.newWalletShare !== undefined ? pct(d.walletAnalysis.newWalletShare * 100) : '—'} hint={`${d.walletAnalysis?.newWallets ?? 0} of ${d.walletAnalysis?.analyzedWallets ?? 0} analysed`} />
        <StatTile label="Deployer holds" value={pct(d.deployer?.holdsPercent)} hint={d.deployer?.address ? shortAddr(d.deployer.address) : 'deployer unknown'} />
      </div>

      <div>
        <h3 className="mb-2 text-sm font-semibold">Top holders</h3>
        {!d.holders || d.holders.topHolders.length === 0 ? (
          <Empty>Holder data unavailable.</Empty>
        ) : (
          <div className="max-h-96 overflow-auto">
            <table className="w-full min-w-[640px] border-collapse">
              <thead>
                <tr>
                  <Th>#</Th>
                  <Th>Wallet</Th>
                  <Th align="right">Share</Th>
                  <Th>Tags</Th>
                  <Th>Funding cluster</Th>
                  <Th align="right">Wallet age</Th>
                </tr>
              </thead>
              <tbody>
                {d.holders.topHolders.slice(0, 20).map((h, i) => {
                  const w = walletInfo.get(h.address);
                  return (
                    <tr key={`${h.address}-${i}`}>
                      <Td className="text-muted">{i + 1}</Td>
                      <Td>
                        <code className="text-xs text-ink">{shortAddr(h.address, 6)}</code>
                      </Td>
                      <Td align="right">{pct(h.percent, { digits: 2 })}</Td>
                      <Td>
                        <span className="flex flex-wrap gap-1">
                          {h.isLiquidityPool && <Pill tone="blue">pool</Pill>}
                          {h.isBurn && <Pill>burn</Pill>}
                          {h.isLocked && <Pill>locked</Pill>}
                          {h.isInsider && <Pill tone="critical">insider</Pill>}
                          {h.address === d.deployer?.address && <Pill tone="warning">deployer</Pill>}
                          {h.tag && !h.isLiquidityPool && <Pill>{h.tag.slice(0, 24)}</Pill>}
                        </span>
                      </Td>
                      <Td>{clusterOf.has(h.address) ? <code className="text-xs text-ink-2">{shortAddr(clusterOf.get(h.address), 5)}</code> : <span className="text-xs text-muted">—</span>}</Td>
                      <Td align="right">
                        <span className="text-xs text-ink-2">{w?.walletCreatedAt ? `${w.ageIsLowerBound ? '> ' : ''}${age(w.walletCreatedAt)}` : '—'}</span>
                      </Td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <div className="grid gap-5 lg:grid-cols-2">
        <div>
          <h3 className="mb-2 text-sm font-semibold">Developer activity</h3>
          {d.developer ? (
            <>
              <p className="text-sm text-ink-2">
                Last {Math.round(d.developer.lookbackMinutes)} min: {d.developer.sells} sells, {d.developer.transfersOut} outgoing transfers,{' '}
                {pct(d.developer.percentOfSupplyMoved)} of supply moved, {d.developer.transfersToFreshWallets} transfers to fresh wallets.
              </p>
              {d.developer.events.length > 0 && (
                <ul className="mt-2 space-y-1 text-xs">
                  {d.developer.events.slice(0, 10).map((e, i) => (
                    <li key={`${e.signature}-${i}`} className="flex gap-2">
                      <Pill tone={e.kind === 'sell' ? 'critical' : 'neutral'}>{e.kind.replace('_', ' ')}</Pill>
                      <span className="text-ink-2">{pct(e.percentOfSupply, { digits: 2 })} of supply</span>
                      <span className="text-muted">{timeAgo(e.timestamp)}</span>
                    </li>
                  ))}
                </ul>
              )}
            </>
          ) : (
            <Empty>No developer activity data.</Empty>
          )}
          {d.deployer && (
            <div className="mt-3 text-sm">
              <Flag label="Deployer wallet age" value={d.deployer.walletAgeDays !== null ? `${d.deployer.walletAgeDays.toFixed(1)} days` : null} bad={(d.deployer.walletAgeDays ?? 99) < 1} />
              <Flag label="Tokens/contracts created" value={d.deployer.tokensCreated} bad={(d.deployer.tokensCreated ?? 0) >= 5} />
              <Flag label="Known rugs" value={d.deployer.knownRugs} bad={(d.deployer.knownRugs ?? 0) > 0} />
              <Flag label="Honeypots by same creator" value={d.deployer.honeypotWithSameCreator} bad={d.deployer.honeypotWithSameCreator === true} />
            </div>
          )}
        </div>
        <div>
          <h3 className="mb-2 text-sm font-semibold">Trade flow (recent trades)</h3>
          {d.trades ? (
            <div className="text-sm">
              <Flag label="Trades sampled" value={d.trades.tradeCount} />
              <Flag label="Unique traders" value={d.trades.uniqueTraders} bad={d.trades.tradeCount >= 50 && d.trades.uniqueTraders / d.trades.tradeCount < 0.15} />
              <Flag label="Buyers / sellers" value={`${d.trades.buyers} / ${d.trades.sellers}`} />
              <Flag label="Buy / sell volume" value={`${usd(d.trades.buyVolumeUsd, { compact: true })} / ${usd(d.trades.sellVolumeUsd, { compact: true })}`} />
              <Flag label="Round-trip volume share" value={pct(d.trades.roundTripVolumeShare * 100)} bad={d.trades.roundTripVolumeShare >= 0.3} />
              <Flag label="Top trader volume share" value={pct(d.trades.topTraderVolumeShare * 100)} bad={d.trades.topTraderVolumeShare >= 0.25} />
              <Flag label="Trade-size variation (CV)" value={d.trades.tradeSizeCv?.toFixed(2) ?? null} bad={(d.trades.tradeSizeCv ?? 1) < 0.15} />
              <Flag label="Repeated trade sizes" value={pct(d.trades.repeatedSizeShare * 100)} bad={d.trades.repeatedSizeShare >= 0.4} />
            </div>
          ) : (
            <Empty>No trade-level data.</Empty>
          )}
        </div>
      </div>
    </div>
  );
}

export function TokenDetailPage() {
  const { address = '' } = useParams();
  const [params] = useSearchParams();
  const chain = (params.get('chain') ?? undefined) as Chain | undefined;
  const qc = useQueryClient();
  const [tab, setTab] = useState<'risk' | 'wallets' | 'contract' | 'decisions' | 'activity'>('risk');
  const detail = useQuery({ queryKey: ['token', address, chain], queryFn: () => api.token(address, chain), refetchInterval: 30_000 });
  const cfg = useQuery({ queryKey: ['config'], queryFn: api.config });
  const rescan = useMutation({
    mutationFn: () => api.scan({ chain: (detail.data?.token.chain ?? chain ?? 'solana') as Chain, address }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['token'] }),
  });
  const buy = useMutation({
    mutationFn: (amountUsd: number) => api.paperTrade({ chain: (detail.data?.token.chain ?? 'solana') as Chain, address, side: 'buy', amountUsd }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['token'] }),
  });

  if (detail.isLoading) return <Spinner />;
  if (detail.error) {
    return <ErrorBox error={detail.error instanceof ApiError && detail.error.status === 404 ? 'Token not analysed yet. Scan it from the Configuration page.' : detail.error} />;
  }
  const d = detail.data;
  if (!d) return null;
  const t = d.token;
  const s = d.snapshot;
  const risk = d.risk;
  const openPos = d.positions.find((p) => p.status === 'open');

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-start gap-4">
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <h1 className="text-xl font-semibold">{t.symbol ?? shortAddr(t.address)}</h1>
            <span className="text-sm text-muted">{t.name}</span>
            <Pill>{t.chain}</Pill>
            <RiskBadge level={t.overallRisk} />
            <DecisionBadge action={t.lastDecision} label={t.lastDecisionLabel} />
          </div>
          <div className="mt-1 flex flex-wrap items-center gap-2 text-xs text-muted">
            <code className="text-ink-2">{t.address}</code>
            <button type="button" onClick={() => void navigator.clipboard?.writeText(t.address)} className="hover:text-ink" aria-label="Copy address">
              <Copy size={12} />
            </button>
            <a href={explorerUrl(t.chain, t.address)} target="_blank" rel="noreferrer noopener" className="inline-flex items-center gap-1 hover:text-ink">
              explorer <ExternalLink size={12} />
            </a>
            <span>· pair age {age(t.pairCreatedAt)} · analysed {timeAgo(t.lastAnalyzedAt)}</span>
          </div>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button onClick={() => rescan.mutate()} disabled={rescan.isPending} title="Re-run the full pipeline (analysis only)">
            <RefreshCw size={14} className={rescan.isPending ? 'animate-spin' : ''} aria-hidden /> Re-scan
          </Button>
          {cfg.data?.effective.mode === 'paper' && !openPos && (
            <Button variant="primary" onClick={() => buy.mutate(100)} disabled={buy.isPending} title="Paper buy up to $100; every risk check still applies">
              Paper buy (≤ $100)
            </Button>
          )}
        </div>
      </div>
      {(rescan.error || buy.error) && <ErrorBox error={rescan.error ?? buy.error} />}
      {buy.data && (
        <div className="rounded-lg border border-border bg-surface p-3 text-sm">
          {buy.data.accepted ? 'Paper position opened.' : `Not executed: ${buy.data.decision.label}.`}{' '}
          <span className="text-ink-2">{buy.data.decision.reasons.slice(-2).join(' ')}</span>
        </div>
      )}

      <div className="grid gap-3 sm:grid-cols-3 lg:grid-cols-6">
        <StatTile label="Price" value={price(t.priceUsd)} delta={t.priceChange1hPct !== null ? `${t.priceChange1hPct >= 0 ? '▲' : '▼'} ${pct(t.priceChange1hPct, { sign: true })} 1h` : undefined} deltaGood={t.priceChange1hPct === null ? undefined : t.priceChange1hPct >= 0} />
        <StatTile label="Market cap" value={usd(t.marketCapUsd, { compact: true })} />
        <StatTile label="Liquidity" value={usd(t.liquidityUsd, { compact: true })} />
        <StatTile label="24h volume" value={usd(t.volume24hUsd, { compact: true })} />
        <StatTile label="Holders" value={num(t.holderCount)} hint={`top holder ${pct(t.topHolderPercent)}`} />
        <StatTile label="Buy/sell ratio (1h)" value={ratio(t.buySellRatio1h)} />
      </div>

      <div className="grid gap-5 xl:grid-cols-3">
        <div className="space-y-5 xl:col-span-2">
          <ChartCard
            title="Price"
            subtitle="USD price from recorded market snapshots"
            chart={<TimeSeriesChart points={d.priceHistory.map((p) => ({ ts: p.ts, value: p.priceUsd }))} formatter={price} label="Price" />}
            table={
              <table className="w-full">
                <thead>
                  <tr><Th>Time</Th><Th align="right">Price</Th><Th align="right">Mkt cap</Th><Th align="right">Vol 1h</Th><Th align="right">Buys/Sells 5m</Th></tr>
                </thead>
                <tbody>
                  {[...d.priceHistory].reverse().slice(0, 300).map((p) => (
                    <tr key={p.ts}>
                      <Td>{dateTime(p.ts)}</Td>
                      <Td align="right">{price(p.priceUsd)}</Td>
                      <Td align="right">{usd(p.marketCapUsd, { compact: true })}</Td>
                      <Td align="right">{usd(p.volume1hUsd, { compact: true })}</Td>
                      <Td align="right">{p.buys5m ?? '—'}/{p.sells5m ?? '—'}</Td>
                    </tr>
                  ))}
                </tbody>
              </table>
            }
          />
          <ChartCard
            title="Liquidity"
            subtitle="Pool liquidity in USD (a separate chart — never a second axis)"
            chart={<TimeSeriesChart points={d.liquidityHistory.map((p) => ({ ts: p.ts, value: p.liquidityUsd }))} formatter={(v) => usd(v, { compact: true })} label="Liquidity" height={180} />}
            table={
              <table className="w-full">
                <thead><tr><Th>Time</Th><Th align="right">Liquidity</Th><Th align="right">LP locked</Th></tr></thead>
                <tbody>
                  {[...d.liquidityHistory].reverse().slice(0, 300).map((p) => (
                    <tr key={p.ts}><Td>{dateTime(p.ts)}</Td><Td align="right">{usd(p.liquidityUsd)}</Td><Td align="right">{pct(p.lpLockedPercent)}</Td></tr>
                  ))}
                </tbody>
              </table>
            }
          />
        </div>
        <Card title="Rug-risk assessment" subtitle={risk ? `Generated ${timeAgo(risk.generatedAt)}` : undefined}>
          {risk ? (
            <div className="space-y-5">
              <RugScoreMeter score={risk.rugScore} limit={cfg.data?.effective.limits.maxRugScore} />
              <CategoryBars report={risk} />
            </div>
          ) : (
            <Empty>Not analysed yet.</Empty>
          )}
        </Card>
      </div>

      <div className="flex gap-1 border-b border-border" role="tablist">
        {(
          [
            ['risk', 'Risk explanation'],
            ['wallets', 'Wallet analysis'],
            ['contract', 'Contract'],
            ['decisions', `Decisions (${d.decisions.length})`],
            ['activity', 'Positions & alerts'],
          ] as const
        ).map(([k, label]) => (
          <button
            key={k}
            type="button"
            role="tab"
            aria-selected={tab === k}
            onClick={() => setTab(k)}
            className={tab === k ? 'border-b-2 border-series-1 px-3 py-2 text-sm text-ink' : 'px-3 py-2 text-sm text-muted hover:text-ink'}
          >
            {label}
          </button>
        ))}
      </div>

      {tab === 'risk' && (
        <div className="grid gap-5 xl:grid-cols-3">
          <Card title="Why these scores" className="xl:col-span-2">{risk ? <RiskExplanation report={risk} /> : <Empty>No report.</Empty>}</Card>
          <ChartCard
            title="Rug score history"
            chart={
              d.riskHistory.length < 2 ? (
                <Empty>One analysis so far.</Empty>
              ) : (
                <LineSeriesChart data={d.riskHistory as unknown as Record<string, unknown>[]} dataKey="rugScore" name="Rug score" format={(v) => v.toFixed(0)} height={200} />
              )
            }
            table={
              <table className="w-full">
                <thead><tr><Th>Time</Th><Th align="right">Rug score</Th><Th>Overall</Th></tr></thead>
                <tbody>
                  {[...d.riskHistory].reverse().map((r) => (
                    <tr key={r.ts}><Td>{dateTime(r.ts)}</Td><Td align="right">{r.rugScore}</Td><Td><RiskBadge level={r.overallRisk} compact /></Td></tr>
                  ))}
                </tbody>
              </table>
            }
          />
        </div>
      )}
      {tab === 'wallets' && (
        <Card title="Wallet analysis">
          <WalletAnalysis address={t.address} chain={t.chain} />
        </Card>
      )}
      {tab === 'contract' && (
        <Card title="Contract & honeypot checks" subtitle={s?.contract ? `Sources: ${s.contract.sources.join(', ')}` : undefined}>
          {s ? <ContractDetails s={s} /> : <Empty>No snapshot.</Empty>}
          {s && s.warnings.length > 0 && (
            <div className="mt-4">
              <h3 className="mb-1 text-sm font-semibold">Provider warnings</h3>
              <ul className="space-y-1 text-sm">
                {s.warnings.map((w) => (
                  <li key={`${w.source}-${w.code}`} className="text-ink-2">
                    <Pill tone={w.level === 'danger' ? 'critical' : w.level === 'warn' ? 'warning' : 'neutral'}>{w.level}</Pill> {w.message}{' '}
                    <span className="text-xs text-muted">({w.source})</span>
                  </li>
                ))}
              </ul>
            </div>
          )}
          {s && (
            <div className="mt-4 text-xs text-muted">
              Data sources:{' '}
              {s.sources.map((x) => (
                <span key={x.name} className="mr-2">
                  {x.ok ? '✓' : '✗'} {x.name}
                  {x.error ? ` (${x.error.slice(0, 60)})` : ''}
                </span>
              ))}
            </div>
          )}
        </Card>
      )}
      {tab === 'decisions' && (
        <div className="space-y-4">
          {d.decisions.length === 0 ? (
            <Empty>No decisions yet.</Empty>
          ) : (
            d.decisions.slice(0, 10).map((dec) => (
              <Card key={dec.id ?? dec.createdAt}>
                <DecisionView d={dec} />
              </Card>
            ))
          )}
        </div>
      )}
      {tab === 'activity' && (
        <div className="grid gap-5 xl:grid-cols-2">
          <Card title="Positions" padded={false}>
            <PositionsTable items={d.positions} />
          </Card>
          <Card title="Alerts" padded={false}>
            <AlertList items={d.alerts} />
          </Card>
        </div>
      )}
    </div>
  );
}
