import type { DecisionAction, ProviderHealth, RiskLevel } from '@memeguard/shared';
import type { App } from '../app';

export interface SoakReport {
  startedAt: string;
  finishedAt: string;
  minutes: number;
  mode: 'paper';
  chains: string[];
  discovery: { tokensSeen: number; tokensAnalysed: number };
  risk: {
    byOverallRisk: Record<RiskLevel, number>;
    likelyScams: number;
    /** Most common critical findings (e.g. "Honeypot confirmed by simulation"). */
    topCriticalFlags: { flag: string; count: number }[];
    /** Data categories most often missing from analyses (missing data counts as risk). */
    topMissingData: { item: string; count: number }[];
  };
  decisions: {
    total: number;
    byAction: Record<DecisionAction, number>;
    topReasons: { reasonCode: string; label: string; count: number }[];
  };
  trading: {
    startingBalanceUsd: number;
    equityUsd: number;
    returnPct: number;
    realizedPnlUsd: number;
    unrealizedPnlUsd: number;
    buys: number;
    sells: number;
    failedTrades: number;
    openPositions: number;
    closedPositions: number;
    wins: number;
    losses: number;
  };
  providers: Pick<
    ProviderHealth,
    'name' | 'configured' | 'calls' | 'requests' | 'failures' | 'rateLimited' | 'circuitOpen' | 'lastError'
  >[];
  sniper: {
    launchesSeen: number;
    bought: number;
    rejected: number;
    medianSecondsAfterLaunch: number | null;
    medianEntryPremiumPct: number | null;
    realizedPnlUsd: number;
  } | null;
  /** Plain-language findings that need attention (data sources failing, format changes, …). */
  problems: string[];
}

const top = <K extends string>(counts: Map<K, number>, n: number) =>
  [...counts.entries()].sort((a, b) => b[1] - a[1]).slice(0, n);

const bump = <K>(m: Map<K, number>, k: K) => m.set(k, (m.get(k) ?? 0) + 1);

/**
 * Summarises what the engine did since `startedAt`: discovery, risk verdicts, decisions, paper
 * trades, and the health of every data source. Designed for a timed paper run against live data,
 * where the main unknowns are whether each provider still answers in the expected format.
 */
export async function buildSoakReport(
  app: App,
  startedAt: Date,
  finishedAt = new Date(),
): Promise<SoakReport> {
  const since = startedAt.getTime();
  const { repos } = app;

  const { rows } = await repos.tokens.list({ limit: 10_000, offset: 0, sort: 'firstSeenAt', order: 'desc' });
  const seen = rows.filter(
    (t) => t.firstSeenAt.getTime() >= since || (t.lastAnalyzedAt && t.lastAnalyzedAt.getTime() >= since),
  );
  const analysed = seen.filter((t) => t.lastAnalyzedAt && t.lastAnalyzedAt.getTime() >= since);

  const byOverallRisk: Record<RiskLevel, number> = { LOW: 0, MEDIUM: 0, HIGH: 0, CRITICAL: 0 };
  const flags = new Map<string, number>();
  const missing = new Map<string, number>();
  let likelyScams = 0;
  for (const t of analysed) {
    const r = await repos.risk.latest(t.id);
    if (!r) continue;
    byOverallRisk[r.overallRisk] += 1;
    if (r.isLikelyScam) likelyScams += 1;
    for (const f of r.criticalFlags) bump(flags, f);
    for (const m of r.missingData) bump(missing, m);
  }

  const decisions = (await repos.decisions.list({ limit: 50_000, offset: 0 })).filter(
    (d) => Date.parse(d.createdAt) >= since,
  );
  const byAction: Record<DecisionAction, number> = { BUY: 0, SELL: 0, HOLD: 0, SKIP: 0 };
  const reasons = new Map<string, number>();
  const labels = new Map<string, string>();
  for (const d of decisions) {
    byAction[d.action] += 1;
    bump(reasons, d.reasonCode);
    if (!labels.has(d.reasonCode)) labels.set(d.reasonCode, d.label);
  }

  const trades = (await repos.trades.list({ mode: 'paper', limit: 50_000, offset: 0 })).rows
    .map((r) => r.trade)
    .filter((t) => t.createdAt.getTime() >= since);
  const summary = await app.portfolio.summary();
  const providers = app.providers.registry.health().map((h) => ({
    name: h.name,
    configured: h.configured,
    calls: h.calls,
    requests: h.requests,
    failures: h.failures,
    rateLimited: h.rateLimited,
    circuitOpen: h.circuitOpen,
    lastError: h.lastError,
  }));

  const sniperStatus = app.sniper.enabled ? await app.sniper.status() : null;

  const problems: string[] = [];
  for (const p of providers) {
    if (!p.configured || p.calls === 0) continue;
    const rate = p.failures / p.calls;
    if (/unexpected shape|invalid|schema|expected/i.test(p.lastError ?? '')) {
      problems.push(
        `${p.name}: responses no longer match the expected format (${p.lastError}). The adapter needs updating; until then its data counts as missing.`,
      );
    } else if (rate >= 0.2) {
      problems.push(
        `${p.name}: ${p.failures} of ${p.calls} calls failed${p.lastError ? ` (last error: ${p.lastError})` : ''}.`,
      );
    }
    if (p.circuitOpen) problems.push(`${p.name}: paused after repeated failures (circuit breaker open).`);
    if (p.rateLimited > 0 && p.rateLimited / p.requests >= 0.1) {
      problems.push(
        `${p.name}: rate-limited on ${p.rateLimited} of ${p.requests} requests; consider an API key or a lower request rate.`,
      );
    }
  }
  if (seen.length === 0) problems.push('No tokens were discovered. Check the network and DISCOVERY_SOURCES.');
  else if (analysed.length === 0) problems.push('Tokens were discovered but none were analysed.');
  const topMissing = top(missing, 5);
  if (analysed.length > 0 && topMissing[0] && topMissing[0][1] / analysed.length >= 0.5) {
    problems.push(
      `"${topMissing[0][0]}" data was missing for ${topMissing[0][1]} of ${analysed.length} analysed tokens; a data source is probably failing or not configured.`,
    );
  }

  return {
    startedAt: startedAt.toISOString(),
    finishedAt: finishedAt.toISOString(),
    minutes: Math.round(((finishedAt.getTime() - since) / 60_000) * 10) / 10,
    mode: 'paper',
    chains: app.config.engine.chains,
    discovery: { tokensSeen: seen.length, tokensAnalysed: analysed.length },
    risk: {
      byOverallRisk,
      likelyScams,
      topCriticalFlags: top(flags, 8).map(([flag, count]) => ({ flag, count })),
      topMissingData: topMissing.map(([item, count]) => ({ item, count })),
    },
    decisions: {
      total: decisions.length,
      byAction,
      topReasons: top(reasons, 10).map(([reasonCode, count]) => ({
        reasonCode,
        label: labels.get(reasonCode) ?? reasonCode,
        count,
      })),
    },
    trading: {
      startingBalanceUsd: summary.startingBalanceUsd,
      equityUsd: summary.equityUsd,
      returnPct: ((summary.equityUsd - summary.startingBalanceUsd) / summary.startingBalanceUsd) * 100,
      realizedPnlUsd: summary.realizedPnlUsd,
      unrealizedPnlUsd: summary.unrealizedPnlUsd,
      buys: trades.filter((t) => t.side === 'buy' && t.status === 'filled').length,
      sells: trades.filter((t) => t.side === 'sell' && t.status === 'filled').length,
      failedTrades: trades.filter((t) => t.status !== 'filled').length,
      openPositions: summary.openPositions,
      closedPositions: summary.closedPositions,
      wins: summary.winningTrades,
      losses: summary.losingTrades,
    },
    providers,
    sniper: sniperStatus
      ? {
          launchesSeen: sniperStatus.stats.launchesSeen,
          bought: sniperStatus.stats.bought,
          rejected: sniperStatus.stats.rejected,
          medianSecondsAfterLaunch: sniperStatus.stats.medianSecondsAfterLaunch,
          medianEntryPremiumPct: sniperStatus.stats.medianEntryPremiumPct,
          realizedPnlUsd: sniperStatus.performance.realizedPnlUsd,
        }
      : null,
    problems,
  };
}

const usd = (v: number) => `${v < 0 ? '-' : ''}$${Math.abs(v).toFixed(2)}`;

/** Human-readable version of the report for the terminal. */
export function formatSoakReport(r: SoakReport): string {
  const lines: string[] = [];
  const row = (k: string, v: string) => lines.push(`  ${k.padEnd(28)} ${v}`);
  lines.push(`\nSOAK TEST REPORT  (${r.minutes} min, PAPER mode, chains: ${r.chains.join(', ')})`);
  lines.push('\n  Discovery and risk');
  row('Tokens discovered', String(r.discovery.tokensSeen));
  row('Tokens analysed', String(r.discovery.tokensAnalysed));
  row(
    'Overall risk',
    `LOW ${r.risk.byOverallRisk.LOW} · MEDIUM ${r.risk.byOverallRisk.MEDIUM} · HIGH ${r.risk.byOverallRisk.HIGH} · CRITICAL ${r.risk.byOverallRisk.CRITICAL}`,
  );
  row('Likely scams', String(r.risk.likelyScams));
  for (const f of r.risk.topCriticalFlags.slice(0, 5)) row(`  ${f.count}×`, f.flag);
  if (r.risk.topMissingData.length > 0)
    row('Most often missing data', r.risk.topMissingData.map((m) => `${m.item} (${m.count})`).join(', '));
  lines.push('\n  Decisions');
  row(
    'Total',
    `${r.decisions.total}  (BUY ${r.decisions.byAction.BUY} · SELL ${r.decisions.byAction.SELL} · HOLD ${r.decisions.byAction.HOLD} · SKIP ${r.decisions.byAction.SKIP})`,
  );
  for (const d of r.decisions.topReasons.slice(0, 6)) row(`  ${d.count}×`, d.label);
  lines.push('\n  Paper trading');
  row(
    'Equity',
    `${usd(r.trading.equityUsd)} (start ${usd(r.trading.startingBalanceUsd)}, ${r.trading.returnPct >= 0 ? '+' : ''}${r.trading.returnPct.toFixed(2)}%)`,
  );
  row('Realized / open P/L', `${usd(r.trading.realizedPnlUsd)} / ${usd(r.trading.unrealizedPnlUsd)}`);
  row('Buys / sells / failed', `${r.trading.buys} / ${r.trading.sells} / ${r.trading.failedTrades}`);
  row(
    'Positions open / closed',
    `${r.trading.openPositions} / ${r.trading.closedPositions} (${r.trading.wins} W, ${r.trading.losses} L)`,
  );
  if (r.sniper) {
    lines.push('\n  Launch sniper');
    row(
      'Launches seen / bought',
      `${r.sniper.launchesSeen} / ${r.sniper.bought} (${r.sniper.rejected} skipped)`,
    );
    row(
      'Median time to buy',
      r.sniper.medianSecondsAfterLaunch === null ? 'n/a' : `${r.sniper.medianSecondsAfterLaunch}s`,
    );
    row(
      'Median paid above open',
      r.sniper.medianEntryPremiumPct === null ? 'n/a' : `${r.sniper.medianEntryPremiumPct}%`,
    );
    row('Sniper realized P/L', usd(r.sniper.realizedPnlUsd));
  }
  lines.push('\n  Data sources (calls / failed / rate-limited responses)');
  for (const p of r.providers) {
    row(
      p.name,
      p.configured
        ? `${p.calls} / ${p.failures} / ${p.rateLimited}${p.circuitOpen ? '  PAUSED' : ''}`
        : 'not configured',
    );
  }
  lines.push('\n  Problems');
  if (r.problems.length === 0) lines.push('  none found');
  for (const p of r.problems) lines.push(`  ! ${p}`);
  lines.push(
    '\n  A short run shows whether the pipeline works on real data. It is far too short to judge profitability.',
  );
  return lines.join('\n');
}
