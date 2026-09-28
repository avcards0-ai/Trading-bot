import type { PositionSizing, RiskLimits, StrategyParams } from '@memeguard/shared';
import { estimateBuyImpactPct } from '../execution/amm';
import { clamp } from '../lib/math';

export interface SizingInput {
  /** Conservative equity (open positions valued at estimated exit proceeds). */
  equityUsd: number;
  cashUsd: number;
  liquidityUsd: number;
  priceUsd: number;
  limits: RiskLimits;
  params: StrategyParams;
  strategyScore: number;
  rugScore: number;
  dexFeePct: number;
  networkFeeUsd: number;
  /** Manual request: never exceeds the computed size. */
  requestedUsd?: number | null;
  /** Additional absolute cap (live mode). */
  absoluteCapUsd?: number | null;
}

/**
 * Position size = the SMALLEST of:
 *   - MAX_POSITION_PERCENT of equity
 *   - risk-per-trade budget / (stop-loss distance + round-trip costs)
 *   - MAX_LIQUIDITY_SHARE_PERCENT of pool liquidity
 *   - available cash (minus network fee reserve)
 *   - optional absolute cap / manual request
 * then scaled down by a confidence multiplier (weaker setups and higher rug scores get less).
 */
export function computePositionSize(i: SizingInput): PositionSizing {
  const byMaxPositionPercent = (i.equityUsd * i.limits.maxPositionPercent) / 100;
  const roundTripCostPct =
    2 * i.dexFeePct + 2 * estimateBuyImpactPct(byMaxPositionPercent, i.liquidityUsd, i.dexFeePct);
  const riskBudget = (i.equityUsd * i.params.riskPerTradePercent) / 100;
  const byRiskPerTrade = riskBudget / Math.max(0.005, (i.params.stopLossPercent + roundTripCostPct) / 100);
  const byLiquidityShare = (i.liquidityUsd * i.limits.maxLiquiditySharePercent) / 100;
  const byAvailableCash = Math.max(0, i.cashUsd - 2 * i.networkFeeUsd);

  const range = Math.max(1, 100 - i.params.minStrategyScore);
  const scoreFactor = clamp(0.5 + 0.5 * ((i.strategyScore - i.params.minStrategyScore) / range), 0.5, 1);
  const rugFactor = clamp(1 - (i.rugScore / 100) * 0.5, 0.5, 1);
  const confidenceMultiplier = Math.round(scoreFactor * rugFactor * 1000) / 1000;

  const caps: [string, number][] = [
    ['MAX_POSITION_PERCENT', byMaxPositionPercent],
    ['RISK_PER_TRADE', byRiskPerTrade],
    ['LIQUIDITY_SHARE', byLiquidityShare],
    ['AVAILABLE_CASH', byAvailableCash],
  ];
  if (i.absoluteCapUsd !== null && i.absoluteCapUsd !== undefined)
    caps.push(['ABSOLUTE_CAP', i.absoluteCapUsd]);
  let [limitingFactor, size] = caps.reduce((a, b) => (b[1] < a[1] ? b : a));
  size *= confidenceMultiplier;
  if (i.requestedUsd !== null && i.requestedUsd !== undefined && i.requestedUsd < size) {
    size = i.requestedUsd;
    limitingFactor = 'REQUESTED_AMOUNT';
  }
  size = Math.max(0, Math.floor(size * 100) / 100);

  return {
    equityUsd: i.equityUsd,
    sizeUsd: size,
    byMaxPositionPercent,
    byRiskPerTrade,
    byLiquidityShare,
    byAvailableCash,
    confidenceMultiplier,
    limitingFactor,
    stopLossPrice: i.priceUsd * (1 - i.params.stopLossPercent / 100),
    takeProfitPrice: i.priceUsd * (1 + i.params.takeProfitPercent / 100),
    expectedSlippagePct: Math.round(estimateBuyImpactPct(size, i.liquidityUsd, i.dexFeePct) * 1000) / 1000,
  };
}
