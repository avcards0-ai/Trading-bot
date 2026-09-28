import type {
  Chain,
  CloseReason,
  Decision,
  MarketData,
  Scalar,
  StageResult,
  TradingMode,
} from '@memeguard/shared';
import type { Repositories } from '../db/repositories';
import type { EventBus } from '../lib/events';
import { round } from '../lib/math';
import type { OpenResult, TradeService } from './tradeService';

export interface ExitDecisionDeps {
  repos: Repositories;
  tradeService: TradeService;
  bus: EventBus;
  mode: TradingMode;
}

export interface ExitDecisionRequest {
  positionId: number;
  tokenId: number;
  token: { chain: Chain; address: string; symbol: string | null };
  reason: CloseReason;
  reasonCode: string;
  reasons: string[];
  /** 'monitor': an exit rule fired; 'manual': an operator asked for the close. */
  trigger: 'monitor' | 'manual';
  metrics?: Record<string, number | null>;
  rugScore?: number | null;
  market?: MarketData | null;
}

export const exitLabel = (reason: CloseReason): string =>
  reason === 'rug_risk_escalation'
    ? 'SELL — HIGH RUG RISK'
    : `SELL — ${reason.replace(/_/g, ' ').toUpperCase()}`;

const roundMetrics = (m: Record<string, number | null>): Record<string, Scalar> =>
  Object.fromEntries(Object.entries(m).map(([k, v]) => [k, v === null ? null : round(v, 6)]));

/**
 * Closes a position outside the analysis pipeline (position monitor, manual API close) and
 * records it like every other decision: an ai_decisions row linked to the sell trade, the
 * token's last decision, and a realtime `decision` event.
 */
export async function closeWithDecision(
  d: ExitDecisionDeps,
  req: ExitDecisionRequest,
): Promise<{ decision: Decision; result: OpenResult | null }> {
  const stages: StageResult[] = [
    {
      stage: 'STRATEGY',
      status: req.trigger === 'manual' ? 'skipped' : 'fail',
      summary: req.trigger === 'manual' ? 'Manual close requested by an operator.' : req.reasons.join(' '),
      metrics: { ...roundMetrics(req.metrics ?? {}), positionId: req.positionId },
      durationMs: 0,
    },
    {
      stage: 'RISK_CHECK',
      status: 'skipped',
      summary: 'Exits are protective and are not blocked by entry risk checks.',
      metrics: {},
      durationMs: 0,
    },
  ];
  const decision: Decision = {
    id: null,
    chain: req.token.chain,
    address: req.token.address,
    symbol: req.token.symbol,
    action: 'SELL',
    label: exitLabel(req.reason),
    reasonCode: req.reasonCode,
    confidence: req.trigger === 'manual' ? 1 : 0.9,
    reasons: [...req.reasons],
    factors: req.metrics ?? {},
    stages,
    riskChecks: [],
    sizing: null,
    rugScore: req.rugScore ?? null,
    strategyScore: null,
    mode: d.mode,
    executed: false,
    tradeId: null,
    createdAt: new Date().toISOString(),
  };
  const decisionId = await d.repos.decisions.insert(req.tokenId, decision);
  decision.id = decisionId;

  const started = Date.now();
  let result: OpenResult | null = null;
  let error: string | null = null;
  try {
    result = await d.tradeService.closePosition({
      positionId: req.positionId,
      reason: req.reason,
      detail: req.reasons.join(' '),
      market: req.market ?? null,
      decisionId,
    });
    if (!result) error = 'exit not attempted (position busy, already closed, or no market data)';
    else if (!result.position) error = result.trade.error ?? 'exit not completed';
  } catch (err) {
    error = err instanceof Error ? err.message : String(err);
  }

  const trade = result?.trade ?? null;
  decision.executed = error === null;
  decision.tradeId = trade?.id ?? null;
  stages.push({
    stage: 'EXECUTION',
    status: error === null ? 'pass' : 'error',
    summary:
      error === null
        ? `${d.mode.toUpperCase()} sell filled: $${trade?.filledUsd?.toFixed(2)}.`
        : `Sell failed: ${error}`,
    metrics: {
      tradeId: trade?.id ?? null,
      status: trade?.status ?? null,
      filledUsd: trade?.filledUsd ?? null,
      slippagePct: trade?.slippagePct === null || !trade ? null : round(trade.slippagePct, 4),
    },
    durationMs: Date.now() - started,
  });
  if (error !== null) {
    decision.label = 'SELL — EXECUTION FAILED';
    decision.reasons.push(`Execution failed: ${error}`);
  }
  await d.repos.decisions.update(decisionId, {
    label: decision.label,
    executed: decision.executed,
    tradeId: decision.tradeId,
    stages: decision.stages,
    reasons: decision.reasons,
  });
  // A failed exit leaves the position open; keep the token's label truthful either way.
  await d.repos.tokens.setLastDecision(req.tokenId, decision);
  d.bus.publish({ type: 'decision', data: decision });
  return { decision, result };
}
