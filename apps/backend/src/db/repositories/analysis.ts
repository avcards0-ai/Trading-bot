import { and, desc, eq, gte } from 'drizzle-orm';
import type {
  Chain,
  Decision,
  LiquidityData,
  LiquidityPoint,
  MarketData,
  PricePoint,
  RiskLevel,
  RiskReport,
  RiskScorePoint,
} from '@memeguard/shared';
import type { Database } from '../client';
import { aiDecisions, liquidityHistory, priceHistory, riskScores, tokens } from '../schema';

export type DecisionRow = typeof aiDecisions.$inferSelect;

export function toDecision(
  row: DecisionRow,
  token: { chain: string; address: string; symbol: string | null },
): Decision {
  return {
    id: row.id,
    chain: token.chain as Chain,
    address: token.address,
    symbol: token.symbol,
    action: row.action,
    label: row.label,
    reasonCode: row.reasonCode,
    confidence: row.confidence,
    reasons: row.reasons,
    factors: row.factors,
    stages: row.stages,
    riskChecks: row.riskChecks,
    sizing: row.sizing ?? null,
    rugScore: row.rugScore,
    strategyScore: row.strategyScore,
    mode: row.mode,
    executed: row.executed,
    tradeId: row.tradeId,
    createdAt: row.createdAt.toISOString(),
  };
}

export class RiskScoresRepository {
  constructor(private readonly db: Database) {}

  async insert(tokenId: number, r: RiskReport): Promise<number> {
    const [row] = await this.db
      .insert(riskScores)
      .values({
        tokenId,
        rugScore: r.rugScore,
        honeypotRisk: r.honeypotRisk,
        liquidityRisk: r.liquidityRisk,
        contractRisk: r.contractRisk,
        walletConcentrationRisk: r.walletConcentrationRisk,
        developerRisk: r.developerRisk,
        marketIntegrityRisk: r.marketIntegrityRisk,
        overallRisk: r.overallRisk,
        isLikelyScam: r.isLikelyScam,
        criticalFlags: r.criticalFlags,
        dataCompleteness: r.dataCompleteness,
        modelVersion: r.modelVersion,
        report: r,
        createdAt: new Date(r.generatedAt),
      })
      .returning({ id: riskScores.id });
    if (!row) throw new Error('failed to insert risk score');
    return row.id;
  }

  async latest(tokenId: number): Promise<RiskReport | null> {
    const [row] = await this.db
      .select({ report: riskScores.report })
      .from(riskScores)
      .where(eq(riskScores.tokenId, tokenId))
      .orderBy(desc(riskScores.createdAt), desc(riskScores.id))
      .limit(1);
    return row?.report ?? null;
  }

  /** Every stored report for a token, oldest first (backtest replay). */
  async timeline(tokenId: number): Promise<{ ts: string; report: RiskReport }[]> {
    const rows = await this.db
      .select({ ts: riskScores.createdAt, report: riskScores.report })
      .from(riskScores)
      .where(eq(riskScores.tokenId, tokenId))
      .orderBy(riskScores.createdAt);
    return rows.map((r) => ({ ts: r.ts.toISOString(), report: r.report }));
  }

  async history(tokenId: number, limit: number): Promise<RiskScorePoint[]> {
    const rows = await this.db
      .select({ ts: riskScores.createdAt, rugScore: riskScores.rugScore, overall: riskScores.overallRisk })
      .from(riskScores)
      .where(eq(riskScores.tokenId, tokenId))
      .orderBy(desc(riskScores.createdAt))
      .limit(limit);
    return rows
      .reverse()
      .map((r) => ({ ts: r.ts.toISOString(), rugScore: r.rugScore, overallRisk: r.overall as RiskLevel }));
  }
}

export class DecisionsRepository {
  constructor(private readonly db: Database) {}

  async insert(tokenId: number, d: Decision): Promise<number> {
    const [row] = await this.db
      .insert(aiDecisions)
      .values({
        tokenId,
        action: d.action,
        label: d.label,
        reasonCode: d.reasonCode,
        confidence: d.confidence,
        rugScore: d.rugScore,
        strategyScore: d.strategyScore,
        mode: d.mode,
        executed: d.executed,
        tradeId: d.tradeId,
        reasons: d.reasons,
        factors: d.factors,
        stages: d.stages,
        riskChecks: d.riskChecks,
        sizing: d.sizing,
        createdAt: new Date(d.createdAt),
      })
      .returning({ id: aiDecisions.id });
    if (!row) throw new Error('failed to insert decision');
    return row.id;
  }

  async update(
    id: number,
    patch: Partial<Pick<Decision, 'label' | 'executed' | 'tradeId' | 'stages' | 'reasons'>>,
  ): Promise<void> {
    await this.db.update(aiDecisions).set(patch).where(eq(aiDecisions.id, id));
  }

  async listForToken(tokenId: number, limit: number): Promise<Decision[]> {
    const rows = await this.db
      .select({ d: aiDecisions, t: { chain: tokens.chain, address: tokens.address, symbol: tokens.symbol } })
      .from(aiDecisions)
      .innerJoin(tokens, eq(tokens.id, aiDecisions.tokenId))
      .where(eq(aiDecisions.tokenId, tokenId))
      .orderBy(desc(aiDecisions.createdAt), desc(aiDecisions.id))
      .limit(limit);
    return rows.map((r) => toDecision(r.d, r.t));
  }

  async list(opts: { limit: number; offset: number; action?: Decision['action'] }): Promise<Decision[]> {
    const rows = await this.db
      .select({ d: aiDecisions, t: { chain: tokens.chain, address: tokens.address, symbol: tokens.symbol } })
      .from(aiDecisions)
      .innerJoin(tokens, eq(tokens.id, aiDecisions.tokenId))
      .where(opts.action ? eq(aiDecisions.action, opts.action) : undefined)
      .orderBy(desc(aiDecisions.createdAt), desc(aiDecisions.id))
      .limit(opts.limit)
      .offset(opts.offset);
    return rows.map((r) => toDecision(r.d, r.t));
  }
}

export class HistoryRepository {
  constructor(private readonly db: Database) {}

  async recordMarket(tokenId: number, m: MarketData): Promise<void> {
    const ts = new Date(m.fetchedAt);
    await this.db.insert(priceHistory).values({
      tokenId,
      ts,
      priceUsd: m.priceUsd,
      marketCapUsd: m.marketCapUsd,
      fdvUsd: m.fdvUsd,
      volume5mUsd: m.volumeUsd.m5,
      volume1hUsd: m.volumeUsd.h1,
      volume24hUsd: m.volumeUsd.h24,
      buys5m: m.txns.m5?.buys ?? null,
      sells5m: m.txns.m5?.sells ?? null,
      buys1h: m.txns.h1?.buys ?? null,
      sells1h: m.txns.h1?.sells ?? null,
      priceChange5mPct: m.priceChangePct.m5,
      priceChange1hPct: m.priceChangePct.h1,
      source: m.source,
    });
    if (m.liquidityUsd !== null) {
      await this.db
        .insert(liquidityHistory)
        .values({ tokenId, ts, liquidityUsd: m.liquidityUsd, source: m.source });
    }
  }

  async recordLiquidity(tokenId: number, l: LiquidityData, at: Date): Promise<void> {
    await this.db.insert(liquidityHistory).values({
      tokenId,
      ts: at,
      liquidityUsd: l.totalLiquidityUsd,
      lpLockedPercent: l.lpLockedPercent,
      lpBurnedPercent: l.lpBurnedPercent,
      source: l.sources.join(','),
    });
  }

  async prices(tokenId: number, opts: { since?: Date; limit: number }): Promise<PricePoint[]> {
    const rows = await this.db
      .select()
      .from(priceHistory)
      .where(
        opts.since
          ? and(eq(priceHistory.tokenId, tokenId), gte(priceHistory.ts, opts.since))
          : eq(priceHistory.tokenId, tokenId),
      )
      .orderBy(desc(priceHistory.ts))
      .limit(opts.limit);
    return rows.reverse().map((r) => ({
      ts: r.ts.toISOString(),
      priceUsd: r.priceUsd,
      marketCapUsd: r.marketCapUsd,
      volume5mUsd: r.volume5mUsd,
      volume1hUsd: r.volume1hUsd,
      buys5m: r.buys5m,
      sells5m: r.sells5m,
    }));
  }

  async liquidity(tokenId: number, opts: { since?: Date; limit: number }): Promise<LiquidityPoint[]> {
    const rows = await this.db
      .select()
      .from(liquidityHistory)
      .where(
        opts.since
          ? and(eq(liquidityHistory.tokenId, tokenId), gte(liquidityHistory.ts, opts.since))
          : eq(liquidityHistory.tokenId, tokenId),
      )
      .orderBy(desc(liquidityHistory.ts))
      .limit(opts.limit);
    return rows.reverse().map((r) => ({
      ts: r.ts.toISOString(),
      liquidityUsd: r.liquidityUsd,
      lpLockedPercent: r.lpLockedPercent,
    }));
  }

  /** Full raw rows for backtest replay. */
  async rawPrices(tokenId: number): Promise<(typeof priceHistory.$inferSelect)[]> {
    return this.db
      .select()
      .from(priceHistory)
      .where(eq(priceHistory.tokenId, tokenId))
      .orderBy(priceHistory.ts);
  }

  async rawLiquidity(tokenId: number): Promise<(typeof liquidityHistory.$inferSelect)[]> {
    return this.db
      .select()
      .from(liquidityHistory)
      .where(eq(liquidityHistory.tokenId, tokenId))
      .orderBy(liquidityHistory.ts);
  }
}
