import {
  and,
  asc,
  count,
  desc,
  eq,
  gte,
  ilike,
  inArray,
  isNull,
  lt,
  notInArray,
  or,
  sql,
  type SQL,
} from 'drizzle-orm';
import type {
  Chain,
  Decision,
  MarketData,
  RiskLevel,
  RiskReport,
  TokenListItem,
  TokenSnapshot,
  PositionSummary,
} from '@memeguard/shared';
import type { Database } from '../client';
import { tokens } from '../schema';
import { toIso } from '../../lib/time';

export type TokenRow = typeof tokens.$inferSelect;

export interface DiscoveredToken {
  chain: Chain;
  address: string;
  name?: string | null;
  symbol?: string | null;
  pairAddress?: string | null;
  dexId?: string | null;
  pairCreatedAt?: Date | null;
  discoveredVia: string;
}

export type TokenSort =
  | 'rugScore'
  | 'lastAnalyzedAt'
  | 'firstSeenAt'
  | 'liquidityUsd'
  | 'volume24hUsd'
  | 'marketCapUsd'
  | 'pairCreatedAt';

export interface TokenListQuery {
  limit: number;
  offset: number;
  sort: TokenSort;
  order: 'asc' | 'desc';
  chain?: Chain;
  risk?: RiskLevel;
  search?: string;
  analyzedOnly?: boolean;
}

export function top10Percent(snapshot: TokenSnapshot | null): number | null {
  const holders = snapshot?.holders?.topHolders.filter((h) => !h.isLiquidityPool && !h.isBurn) ?? [];
  if (holders.length === 0) return null;
  return holders.slice(0, 10).reduce((a, h) => a + h.percent, 0);
}

export function topHolderPercent(snapshot: TokenSnapshot | null): number | null {
  const h = snapshot?.holders?.topHolders.find((x) => !x.isLiquidityPool && !x.isBurn);
  return h ? h.percent : null;
}

export function buySellRatio(market: MarketData | null | undefined): number | null {
  const t = market?.txns.h1;
  if (!t) return null;
  if (t.sells === 0) return t.buys > 0 ? t.buys : null;
  return t.buys / t.sells;
}

export function toTokenListItem(row: TokenRow, openPosition: PositionSummary | null = null): TokenListItem {
  return {
    id: row.id,
    chain: row.chain as Chain,
    address: row.address,
    name: row.name,
    symbol: row.symbol,
    priceUsd: row.priceUsd,
    marketCapUsd: row.marketCapUsd,
    liquidityUsd: row.liquidityUsd,
    volume24hUsd: row.volume24hUsd,
    priceChange1hPct: row.priceChange1hPct,
    holderCount: row.holderCount,
    topHolderPercent: row.topHolderPercent,
    top10HolderPercent: row.top10HolderPercent,
    buySellRatio1h: row.buySellRatio1h,
    rugScore: row.rugScore,
    honeypotRisk: row.honeypotRisk as RiskLevel | null,
    contractRisk: row.contractRisk as RiskLevel | null,
    liquidityRisk: row.liquidityRisk as RiskLevel | null,
    walletConcentrationRisk: row.concentrationRisk as RiskLevel | null,
    overallRisk: row.overallRisk as RiskLevel | null,
    lastDecision: row.lastDecision as Decision['action'] | null,
    lastDecisionLabel: row.lastDecisionLabel,
    pairCreatedAt: toIso(row.pairCreatedAt),
    firstSeenAt: row.firstSeenAt.toISOString(),
    lastAnalyzedAt: toIso(row.lastAnalyzedAt),
    openPosition,
  };
}

export class TokensRepository {
  constructor(private readonly db: Database) {}

  async upsertDiscovered(t: DiscoveredToken): Promise<{ row: TokenRow; created: boolean }> {
    const existing = await this.getByChainAddress(t.chain, t.address);
    if (existing) {
      const patch: Partial<typeof tokens.$inferInsert> = {};
      if (!existing.name && t.name) patch.name = t.name;
      if (!existing.symbol && t.symbol) patch.symbol = t.symbol;
      if (!existing.pairAddress && t.pairAddress) patch.pairAddress = t.pairAddress;
      if (!existing.dexId && t.dexId) patch.dexId = t.dexId;
      if (!existing.pairCreatedAt && t.pairCreatedAt) patch.pairCreatedAt = t.pairCreatedAt;
      if (Object.keys(patch).length > 0) {
        const [row] = await this.db
          .update(tokens)
          .set({ ...patch, updatedAt: new Date() })
          .where(eq(tokens.id, existing.id))
          .returning();
        return { row: row ?? existing, created: false };
      }
      return { row: existing, created: false };
    }
    const [row] = await this.db
      .insert(tokens)
      .values({
        chain: t.chain,
        address: normalizeAddress(t.chain, t.address),
        name: t.name ?? null,
        symbol: t.symbol ?? null,
        pairAddress: t.pairAddress ?? null,
        dexId: t.dexId ?? null,
        pairCreatedAt: t.pairCreatedAt ?? null,
        discoveredVia: t.discoveredVia,
      })
      .onConflictDoNothing({ target: [tokens.chain, tokens.address] })
      .returning();
    if (row) return { row, created: true };
    // Lost a race with a concurrent insert.
    const again = await this.getByChainAddress(t.chain, t.address);
    if (!again) throw new Error(`token upsert failed for ${t.chain}:${t.address}`);
    return { row: again, created: false };
  }

  async getById(id: number): Promise<TokenRow | null> {
    const [row] = await this.db.select().from(tokens).where(eq(tokens.id, id)).limit(1);
    return row ?? null;
  }

  async getByChainAddress(chain: Chain, address: string): Promise<TokenRow | null> {
    const [row] = await this.db
      .select()
      .from(tokens)
      .where(and(eq(tokens.chain, chain), eq(tokens.address, normalizeAddress(chain, address))))
      .limit(1);
    return row ?? null;
  }

  /** Address lookup without a chain: EVM addresses can exist on several chains, prefer the freshest. */
  async getByAddress(address: string, chain?: Chain): Promise<TokenRow | null> {
    if (chain) return this.getByChainAddress(chain, address);
    const [row] = await this.db
      .select()
      .from(tokens)
      .where(or(eq(tokens.address, address), eq(tokens.address, address.toLowerCase())))
      .orderBy(sql`${tokens.lastAnalyzedAt} desc nulls last`)
      .limit(1);
    return row ?? null;
  }

  async getMany(ids: number[]): Promise<TokenRow[]> {
    if (ids.length === 0) return [];
    return this.db.select().from(tokens).where(inArray(tokens.id, ids));
  }

  async applyAnalysis(
    id: number,
    snapshot: TokenSnapshot,
    report: RiskReport,
    decision: Pick<Decision, 'action' | 'label'>,
    securityRefreshed: boolean,
  ): Promise<TokenRow> {
    const m = snapshot.market;
    const now = new Date();
    const [row] = await this.db
      .update(tokens)
      .set({
        name: snapshot.name ?? undefined,
        symbol: snapshot.symbol ?? undefined,
        decimals: snapshot.decimals ?? undefined,
        pairAddress: m?.pairAddress ?? undefined,
        dexId: m?.dexId ?? undefined,
        pairCreatedAt: m?.pairCreatedAt ? new Date(m.pairCreatedAt) : undefined,
        latestSnapshot: snapshot,
        priceUsd: m?.priceUsd ?? null,
        marketCapUsd: m?.marketCapUsd ?? m?.fdvUsd ?? null,
        liquidityUsd: m?.liquidityUsd ?? snapshot.liquidity?.totalLiquidityUsd ?? null,
        volume24hUsd: m?.volumeUsd.h24 ?? null,
        priceChange1hPct: m?.priceChangePct.h1 ?? null,
        holderCount: snapshot.holders?.holderCount ?? null,
        topHolderPercent: topHolderPercent(snapshot),
        top10HolderPercent: top10Percent(snapshot),
        buySellRatio1h: buySellRatio(m),
        rugScore: report.rugScore,
        overallRisk: report.overallRisk,
        honeypotRisk: report.honeypotRisk,
        contractRisk: report.contractRisk,
        liquidityRisk: report.liquidityRisk,
        concentrationRisk: report.walletConcentrationRisk,
        lastDecision: decision.action,
        lastDecisionLabel: decision.label,
        lastAnalyzedAt: now,
        ...(securityRefreshed ? { lastSecurityAt: now } : {}),
        updatedAt: now,
      })
      .where(eq(tokens.id, id))
      .returning();
    if (!row) throw new Error(`token ${id} not found`);
    return row;
  }

  async applyMarket(id: number, market: MarketData): Promise<void> {
    await this.db
      .update(tokens)
      .set({
        priceUsd: market.priceUsd,
        marketCapUsd: market.marketCapUsd ?? market.fdvUsd,
        liquidityUsd: market.liquidityUsd,
        volume24hUsd: market.volumeUsd.h24,
        priceChange1hPct: market.priceChangePct.h1,
        buySellRatio1h: buySellRatio(market),
        updatedAt: new Date(),
      })
      .where(eq(tokens.id, id));
  }

  /** Records a decision made outside the analysis pipeline (monitor exits, manual closes). */
  async setLastDecision(id: number, decision: Pick<Decision, 'action' | 'label'>): Promise<void> {
    await this.db
      .update(tokens)
      .set({ lastDecision: decision.action, lastDecisionLabel: decision.label, updatedAt: new Date() })
      .where(eq(tokens.id, id));
  }

  async setStatus(id: number, status: 'watching' | 'ignored' | 'expired'): Promise<void> {
    await this.db.update(tokens).set({ status, updatedAt: new Date() }).where(eq(tokens.id, id));
  }

  async list(q: TokenListQuery): Promise<{ rows: TokenRow[]; total: number }> {
    const where: SQL[] = [];
    if (q.chain) where.push(eq(tokens.chain, q.chain));
    if (q.risk) where.push(eq(tokens.overallRisk, q.risk));
    if (q.analyzedOnly) where.push(sql`${tokens.lastAnalyzedAt} is not null`);
    if (q.search) {
      const s = `%${q.search.replace(/[%_]/g, '')}%`;
      const cond = or(ilike(tokens.symbol, s), ilike(tokens.name, s), ilike(tokens.address, s));
      if (cond) where.push(cond);
    }
    const whereSql = where.length > 0 ? and(...where) : undefined;
    const col = {
      rugScore: tokens.rugScore,
      lastAnalyzedAt: tokens.lastAnalyzedAt,
      firstSeenAt: tokens.firstSeenAt,
      liquidityUsd: tokens.liquidityUsd,
      volume24hUsd: tokens.volume24hUsd,
      marketCapUsd: tokens.marketCapUsd,
      pairCreatedAt: tokens.pairCreatedAt,
    }[q.sort];
    const orderSql = q.order === 'asc' ? sql`${col} asc nulls last` : sql`${col} desc nulls last`;
    const rows = await this.db
      .select()
      .from(tokens)
      .where(whereSql)
      .orderBy(orderSql, desc(tokens.id))
      .limit(q.limit)
      .offset(q.offset);
    const [totalRow] = await this.db.select({ n: count() }).from(tokens).where(whereSql);
    return { rows, total: Number(totalRow?.n ?? 0) };
  }

  /**
   * Tokens due for re-analysis: still young enough to be interesting, not ignored, least recently
   * analysed first. Likely scams are skipped once confirmed twice to save provider quota.
   */
  async dueForReanalysis(opts: {
    maxAgeHours: number;
    olderThan: Date;
    limit: number;
    excludeIds: number[];
  }): Promise<TokenRow[]> {
    const since = new Date(Date.now() - opts.maxAgeHours * 3_600_000);
    const conds: SQL[] = [
      eq(tokens.status, 'watching'),
      or(isNull(tokens.lastAnalyzedAt), lt(tokens.lastAnalyzedAt, opts.olderThan)) as SQL,
      or(isNull(tokens.pairCreatedAt), gte(tokens.pairCreatedAt, since)) as SQL,
      gte(tokens.firstSeenAt, since),
    ];
    if (opts.excludeIds.length > 0) conds.push(notInArray(tokens.id, opts.excludeIds));
    return this.db
      .select()
      .from(tokens)
      .where(and(...conds))
      .orderBy(sql`${tokens.lastAnalyzedAt} asc nulls first`, asc(tokens.id))
      .limit(opts.limit);
  }

  /** Stop re-analysing stale tokens. Tokens with open positions must be passed in `keepIds`. */
  async expireOld(maxAgeHours: number, keepIds: number[]): Promise<number> {
    const since = new Date(Date.now() - maxAgeHours * 3_600_000);
    const conds: SQL[] = [eq(tokens.status, 'watching'), lt(tokens.firstSeenAt, since)];
    if (keepIds.length > 0) conds.push(notInArray(tokens.id, keepIds));
    const res = await this.db
      .update(tokens)
      .set({ status: 'expired', updatedAt: new Date() })
      .where(and(...conds))
      .returning({ id: tokens.id });
    return res.length;
  }

  async countAll(): Promise<number> {
    const [r] = await this.db.select({ n: count() }).from(tokens);
    return Number(r?.n ?? 0);
  }
}

/** EVM addresses are case-insensitive: store lowercase. Solana base58 is case-sensitive. */
export function normalizeAddress(chain: Chain, address: string): string {
  return chain === 'solana' ? address.trim() : address.trim().toLowerCase();
}
