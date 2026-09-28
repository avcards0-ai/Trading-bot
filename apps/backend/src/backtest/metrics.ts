import type { BacktestMetrics, BacktestTrade } from '@memeguard/shared';
import { mean, stdev } from '../lib/math';

export interface EquityPoint {
  ts: string;
  equityUsd: number;
}

export function maxDrawdown(curve: EquityPoint[]): { pct: number; usd: number; series: number[] } {
  let peak = curve[0]?.equityUsd ?? 0;
  let maxPct = 0;
  let maxUsd = 0;
  const series: number[] = [];
  for (const p of curve) {
    peak = Math.max(peak, p.equityUsd);
    const dd = peak - p.equityUsd;
    const pct = peak > 0 ? (dd / peak) * 100 : 0;
    series.push(pct);
    if (pct > maxPct) maxPct = pct;
    if (dd > maxUsd) maxUsd = dd;
  }
  return { pct: maxPct, usd: maxUsd, series };
}

const round = (v: number | null, d = 4): number | null =>
  v === null || !Number.isFinite(v) ? null : Math.round(v * 10 ** d) / 10 ** d;

/**
 * Risk-adjusted metrics. Sharpe/Sortino are computed PER TRADE (not annualised): meme-coin
 * holding periods are minutes-to-hours and annualising them produces misleading numbers.
 */
export function computeMetrics(args: {
  startingBalanceUsd: number;
  endingBalanceUsd: number;
  trades: BacktestTrade[];
  curve: EquityPoint[];
  exposureSteps: number;
  totalSteps: number;
  tokensEvaluated: number;
  tokensSkippedForRugRisk: number;
  rugsAvoided: number;
  rugsHit: number;
}): BacktestMetrics {
  const { trades } = args;
  const pnls = trades.map((t) => t.pnlUsd);
  const rets = trades.map((t) => t.pnlPct);
  const wins = trades.filter((t) => t.pnlUsd > 0);
  const losses = trades.filter((t) => t.pnlUsd <= 0);
  const grossProfit = wins.reduce((a, t) => a + t.pnlUsd, 0);
  const grossLoss = -losses.reduce((a, t) => a + t.pnlUsd, 0);
  const dd = maxDrawdown(args.curve);
  const totalReturnPct = ((args.endingBalanceUsd - args.startingBalanceUsd) / args.startingBalanceUsd) * 100;

  const m = mean(rets);
  const sd = stdev(rets);
  const downside = rets.filter((r) => r < 0);
  const dsd = downside.length >= 2 ? Math.sqrt(downside.reduce((a, r) => a + r * r, 0) / downside.length) : null;
  const sortedRets = [...rets].sort((a, b) => a - b);
  const tailN = Math.max(1, Math.ceil(sortedRets.length * 0.05));
  const cvar = sortedRets.length > 0 ? (mean(sortedRets.slice(0, tailN)) as number) : null;

  return {
    startingBalanceUsd: round(args.startingBalanceUsd, 2) as number,
    endingBalanceUsd: round(args.endingBalanceUsd, 2) as number,
    totalReturnPct: round(totalReturnPct, 2) as number,
    maxDrawdownPct: round(dd.pct, 2) as number,
    maxDrawdownUsd: round(dd.usd, 2) as number,
    numberOfTrades: trades.length,
    winningTrades: wins.length,
    losingTrades: losses.length,
    winRate: trades.length > 0 ? round(wins.length / trades.length, 4) : null,
    averageWinUsd: wins.length > 0 ? round(grossProfit / wins.length, 2) : null,
    averageLossUsd: losses.length > 0 ? round(-grossLoss / losses.length, 2) : null,
    profitFactor: grossLoss > 0 ? round(grossProfit / grossLoss, 3) : null,
    largestLossUsd: pnls.length > 0 ? round(Math.min(...pnls), 2) : null,
    largestGainUsd: pnls.length > 0 ? round(Math.max(...pnls), 2) : null,
    expectancyUsd: pnls.length > 0 ? round(mean(pnls) as number, 2) : null,
    sharpeRatio: m !== null && sd !== null && sd > 0 ? round(m / sd, 3) : null,
    sortinoRatio: m !== null && dsd !== null && dsd > 0 ? round(m / dsd, 3) : null,
    calmarRatio: dd.pct > 0 ? round(totalReturnPct / dd.pct, 3) : null,
    cvar95Pct: round(cvar, 2),
    totalFeesUsd: round(trades.reduce((a, t) => a + t.feesUsd, 0), 2) as number,
    exposurePct: args.totalSteps > 0 ? (round((args.exposureSteps / args.totalSteps) * 100, 2) as number) : 0,
    tokensEvaluated: args.tokensEvaluated,
    tokensSkippedForRugRisk: args.tokensSkippedForRugRisk,
    rugsAvoided: args.rugsAvoided,
    rugsHit: args.rugsHit,
    catastrophicLosses: trades.filter((t) => t.catastrophic).length,
  };
}
