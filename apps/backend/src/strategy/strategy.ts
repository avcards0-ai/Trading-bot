import type { CloseReason, RiskLimits, RiskReport, StrategyParams, TokenSnapshot } from '@memeguard/shared';
import { clamp, fmtPrice as px, scale01 } from '../lib/math';
import { computeSignals, type MarketSignals } from './signals';

/**
 * Example momentum-with-safety strategy for newly launched tokens. It is a configurable
 * rule set, NOT a guaranteed edge: backtest it (including the catastrophic-loss report) before
 * trusting it with real capital.
 *
 * Entry needs every gate to pass and a composite score >= minStrategyScore:
 *   buy pressure (25) + healthy turnover (20) + momentum (20) + not over-extended (10)
 *   + trader breadth (10) + safety margin below the rug-score limit (15)
 */

export interface EntryEvaluation {
  action: 'BUY' | 'HOLD' | 'SKIP';
  reasonCode: string;
  score: number | null;
  confidence: number;
  reasons: string[];
  signals: MarketSignals;
  components: Record<string, number>;
}

export function evaluateEntry(
  snapshot: TokenSnapshot,
  report: RiskReport,
  params: StrategyParams,
  limits: RiskLimits,
  now: Date,
): EntryEvaluation {
  const s = computeSignals(snapshot, now);
  const reasons: string[] = [];
  const base = { signals: s, components: {} as Record<string, number> };

  if (!params.chains.includes(snapshot.chain)) {
    return {
      ...base,
      action: 'SKIP',
      reasonCode: 'CHAIN_DISABLED',
      score: null,
      confidence: 1,
      reasons: [`Strategy is not enabled for ${snapshot.chain}.`],
    };
  }
  if (s.priceUsd === null || s.liquidityUsd === null) {
    return {
      ...base,
      action: 'SKIP',
      reasonCode: 'NO_MARKET_DATA',
      score: null,
      confidence: 1,
      reasons: ['No usable price/liquidity data.'],
    };
  }
  if (s.ageMinutes !== null && s.ageMinutes > params.maxTokenAgeMinutes) {
    return {
      ...base,
      action: 'SKIP',
      reasonCode: 'OUTSIDE_AGE_WINDOW',
      score: null,
      confidence: 1,
      reasons: [
        `Token is ${Math.round(s.ageMinutes)} min old; strategy targets tokens younger than ${params.maxTokenAgeMinutes} min.`,
      ],
    };
  }

  // Composite score
  const buyPressure = s.buySellRatio1h !== null ? scale01(s.buySellRatio1h, 1.0, 2.5) : 0;
  let turnover = 0;
  if (s.turnover1h !== null) {
    const t = s.turnover1h;
    turnover =
      t < 0.05 ? 0 : t < 0.2 ? scale01(t, 0.05, 0.2) : t <= 2 ? 1 : t <= 5 ? 1 - scale01(t, 2, 5) : 0;
  }
  const pc1h = s.priceChange1hPct;
  const momentum =
    pc1h === null
      ? 0
      : scale01(pc1h, params.minPriceChange1hPercent, params.minPriceChange1hPercent + 50) *
        (pc1h > 200 ? 0.5 : 1);
  const notExtended =
    s.priceChange5mPct === null ? 0.5 : 1 - scale01(s.priceChange5mPct, 0, params.maxPriceChange5mPercent);
  const breadth = s.uniqueTraders === null ? 0.5 : scale01(s.uniqueTraders, 20, 150);
  const safety = clamp(1 - report.rugScore / Math.max(1, limits.maxRugScore), 0, 1);
  const components = {
    buyPressure: buyPressure * 25,
    turnover: turnover * 20,
    momentum: momentum * 20,
    notOverextended: notExtended * 10,
    breadth: breadth * 10,
    safety: safety * 15,
  };
  const score = Math.round(Object.values(components).reduce((a, b) => a + b, 0) * 10) / 10;

  // Gates
  const failed: string[] = [];
  if (s.buySellRatio1h === null || s.buySellRatio1h < params.minBuySellRatio) {
    failed.push(`buy/sell ratio 1h ${s.buySellRatio1h?.toFixed(2) ?? 'n/a'} < ${params.minBuySellRatio}`);
  }
  if (s.volume1hUsd === null || s.volume1hUsd < params.minVolume1hUsd) {
    failed.push(`1h volume $${Math.round(s.volume1hUsd ?? 0)} < $${params.minVolume1hUsd}`);
  }
  if (s.priceChange5mPct !== null && s.priceChange5mPct > params.maxPriceChange5mPercent) {
    failed.push(
      `5m price change ${s.priceChange5mPct.toFixed(1)}% > ${params.maxPriceChange5mPercent}% (not chasing)`,
    );
  }
  if (pc1h === null || pc1h < params.minPriceChange1hPercent) {
    failed.push(`1h price change ${pc1h?.toFixed(1) ?? 'n/a'}% < ${params.minPriceChange1hPercent}%`);
  }

  const tooYoung = s.ageMinutes === null || s.ageMinutes < limits.minTokenAgeMinutes;
  if (failed.length === 0 && score >= params.minStrategyScore) {
    if (tooYoung) {
      return {
        signals: s,
        components,
        action: 'HOLD',
        reasonCode: 'WAIT_MIN_TOKEN_AGE',
        score,
        confidence: score / 100,
        reasons: [
          `Setup qualifies (score ${score}) but token age ${s.ageMinutes === null ? 'unknown' : `${Math.round(s.ageMinutes)} min`} is below MIN_TOKEN_AGE ${limits.minTokenAgeMinutes} min; watching.`,
        ],
      };
    }
    reasons.push(`Strategy score ${score} >= ${params.minStrategyScore}; all entry gates passed.`);
    return {
      signals: s,
      components,
      action: 'BUY',
      reasonCode: 'STRATEGY_ENTRY',
      score,
      confidence: score / 100,
      reasons,
    };
  }
  if (failed.length === 0) {
    const near = score >= params.minStrategyScore - 15;
    return {
      signals: s,
      components,
      action: near ? 'HOLD' : 'SKIP',
      reasonCode: near ? 'NEAR_THRESHOLD' : 'LOW_STRATEGY_SCORE',
      score,
      confidence: 1 - score / 100,
      reasons: [`Strategy score ${score} < ${params.minStrategyScore}${near ? ' (close; watching)' : ''}.`],
    };
  }
  return {
    signals: s,
    components,
    action: 'SKIP',
    reasonCode: 'ENTRY_GATES_FAILED',
    score,
    confidence: 0.8,
    reasons: failed.map((f) => `Entry gate failed: ${f}.`),
  };
}

export interface OpenPositionView {
  entryPriceUsd: number;
  stopLossPriceUsd: number;
  takeProfitPriceUsd: number;
  trailingStopPercent: number | null;
  highestPriceUsd: number;
  entryLiquidityUsd: number | null;
  openedAt: Date;
}

export interface ExitEvaluation {
  action: 'SELL' | 'HOLD';
  reason: CloseReason | null;
  reasonCode: string;
  reasons: string[];
  metrics: Record<string, number | null>;
}

/**
 * Exit rules, in priority order: rug escalation, liquidity pull, stop loss, trailing stop,
 * take profit, max hold time. Pure — used by the live position monitor and the backtester.
 */
export function evaluateExit(
  pos: OpenPositionView,
  price: number | null,
  liquidityUsd: number | null,
  report: Pick<RiskReport, 'rugScore' | 'isLikelyScam'> | null,
  params: StrategyParams,
  now: Date,
): ExitEvaluation {
  const pnlPct = price !== null ? ((price - pos.entryPriceUsd) / pos.entryPriceUsd) * 100 : null;
  const heldMin = (now.getTime() - pos.openedAt.getTime()) / 60_000;
  const liqDrop =
    pos.entryLiquidityUsd && liquidityUsd !== null
      ? ((pos.entryLiquidityUsd - liquidityUsd) / pos.entryLiquidityUsd) * 100
      : null;
  const metrics = {
    price,
    pnlPct,
    heldMinutes: heldMin,
    liquidityDropPct: liqDrop,
    rugScore: report?.rugScore ?? null,
  };
  const sell = (reason: CloseReason, code: string, why: string): ExitEvaluation => ({
    action: 'SELL',
    reason,
    reasonCode: code,
    reasons: [why],
    metrics,
  });

  if (report && (report.isLikelyScam || report.rugScore >= params.exitOnRugScoreAbove)) {
    return sell(
      'rug_risk_escalation',
      'EXIT_RUG_RISK',
      `Rug score ${report.rugScore} reached exit threshold ${params.exitOnRugScoreAbove}${report.isLikelyScam ? ' (likely scam)' : ''}.`,
    );
  }
  if (liqDrop !== null && liqDrop >= params.exitOnLiquidityDropPercent) {
    return sell(
      'liquidity_drop',
      'EXIT_LIQUIDITY_DROP',
      `Liquidity fell ${liqDrop.toFixed(1)}% since entry (limit ${params.exitOnLiquidityDropPercent}%).`,
    );
  }
  if (price === null) {
    return {
      action: 'HOLD',
      reason: null,
      reasonCode: 'NO_PRICE',
      reasons: ['No current price; holding until data returns.'],
      metrics,
    };
  }
  if (price <= pos.stopLossPriceUsd) {
    return sell(
      'stop_loss',
      'EXIT_STOP_LOSS',
      `Price $${px(price)} <= stop loss $${px(pos.stopLossPriceUsd)}.`,
    );
  }
  if (pos.trailingStopPercent && pos.highestPriceUsd > pos.entryPriceUsd) {
    const trail = pos.highestPriceUsd * (1 - pos.trailingStopPercent / 100);
    if (price <= trail) {
      return sell(
        'trailing_stop',
        'EXIT_TRAILING_STOP',
        `Price $${px(price)} fell ${pos.trailingStopPercent}% from high $${px(pos.highestPriceUsd)}.`,
      );
    }
  }
  if (price >= pos.takeProfitPriceUsd) {
    return sell(
      'take_profit',
      'EXIT_TAKE_PROFIT',
      `Price $${px(price)} >= take profit $${px(pos.takeProfitPriceUsd)}.`,
    );
  }
  if (heldMin >= params.maxHoldMinutes) {
    return sell(
      'max_hold_time',
      'EXIT_MAX_HOLD',
      `Held ${Math.round(heldMin)} min >= max ${params.maxHoldMinutes} min.`,
    );
  }
  return {
    action: 'HOLD',
    reason: null,
    reasonCode: 'HOLD_POSITION',
    reasons: [
      `Holding: P/L ${pnlPct?.toFixed(2)}%, stop $${px(pos.stopLossPriceUsd)}, target $${px(pos.takeProfitPriceUsd)}.`,
    ],
    metrics,
  };
}
