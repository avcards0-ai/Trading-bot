import { and, count, desc, eq, gte, sql } from 'drizzle-orm';
import type {
  Chain,
  CloseReason,
  EquityPoint,
  Position,
  PositionStrategy,
  Trade,
  TradeSide,
  TradeStatus,
  TradingMode,
} from '@memeguard/shared';
import type { Database } from '../client';
import { accounts, performanceMetrics, positions, tokens, trades } from '../schema';
import { toIso, utcDay } from '../../lib/time';

export type PositionRow = typeof positions.$inferSelect;
export type TradeRow = typeof trades.$inferSelect;
export type AccountRow = typeof accounts.$inferSelect;

type TokenRef = { id?: number; chain: string; address: string; symbol: string | null };
type TokenRefRow = { id: number; chain: string; address: string; symbol: string | null };

export function toPosition(
  row: PositionRow,
  token: TokenRef,
  currentPriceUsd: number | null = null,
): Position {
  const price = currentPriceUsd ?? row.lastPriceUsd;
  const unrealized = row.status === 'open' && price !== null ? row.quantity * price - row.costBasisUsd : null;
  return {
    id: row.id,
    strategy: row.strategy as PositionStrategy,
    tokenId: row.tokenId,
    chain: token.chain as Chain,
    address: token.address,
    symbol: token.symbol,
    mode: row.mode as TradingMode,
    status: row.status as Position['status'],
    quantity: row.quantity,
    entryPriceUsd: row.entryPriceUsd,
    costBasisUsd: row.costBasisUsd,
    currentPriceUsd: price,
    stopLossPriceUsd: row.stopLossPriceUsd,
    takeProfitPriceUsd: row.takeProfitPriceUsd,
    trailingStopPercent: row.trailingStopPercent,
    highestPriceUsd: row.highestPriceUsd,
    unrealizedPnlUsd: unrealized,
    unrealizedPnlPct:
      unrealized !== null && row.costBasisUsd > 0 ? (unrealized / row.costBasisUsd) * 100 : null,
    realizedPnlUsd: row.realizedPnlUsd,
    exitPriceUsd: row.exitPriceUsd,
    closeReason: row.closeReason as CloseReason | null,
    openedAt: row.openedAt.toISOString(),
    closedAt: toIso(row.closedAt),
  };
}

export function toTrade(row: TradeRow, token: TokenRef): Trade {
  return {
    id: row.id,
    tokenId: row.tokenId,
    positionId: row.positionId,
    decisionId: row.decisionId,
    chain: token.chain as Chain,
    address: token.address,
    symbol: token.symbol,
    mode: row.mode as TradingMode,
    side: row.side as TradeSide,
    status: row.status as TradeStatus,
    requestedUsd: row.requestedUsd,
    filledUsd: row.filledUsd,
    quantity: row.quantity,
    priceUsd: row.priceUsd,
    slippagePct: row.slippagePct,
    feeUsd: row.feeUsd,
    txHash: row.txHash,
    error: row.error,
    reason: row.reason,
    createdAt: row.createdAt.toISOString(),
  };
}

const tokenRefCols = { id: tokens.id, chain: tokens.chain, address: tokens.address, symbol: tokens.symbol };

export class PositionsRepository {
  constructor(private readonly db: Database) {}

  async create(v: typeof positions.$inferInsert): Promise<PositionRow> {
    const [row] = await this.db.insert(positions).values(v).returning();
    if (!row) throw new Error('failed to create position');
    return row;
  }

  async get(id: number): Promise<{ position: PositionRow; token: TokenRefRow } | null> {
    const [r] = await this.db
      .select({ position: positions, token: tokenRefCols })
      .from(positions)
      .innerJoin(tokens, eq(tokens.id, positions.tokenId))
      .where(eq(positions.id, id))
      .limit(1);
    return r ?? null;
  }

  async listOpen(mode: TradingMode): Promise<{ position: PositionRow; token: TokenRefRow }[]> {
    return this.db
      .select({ position: positions, token: tokenRefCols })
      .from(positions)
      .innerJoin(tokens, eq(tokens.id, positions.tokenId))
      .where(and(eq(positions.mode, mode), eq(positions.status, 'open')))
      .orderBy(desc(positions.openedAt));
  }

  async listRecentClosed(
    mode: TradingMode,
    limit: number,
  ): Promise<{ position: PositionRow; token: TokenRefRow }[]> {
    return this.db
      .select({ position: positions, token: tokenRefCols })
      .from(positions)
      .innerJoin(tokens, eq(tokens.id, positions.tokenId))
      .where(and(eq(positions.mode, mode), eq(positions.status, 'closed')))
      .orderBy(desc(positions.closedAt))
      .limit(limit);
  }

  async listByToken(tokenId: number, limit = 20): Promise<{ position: PositionRow; token: TokenRefRow }[]> {
    return this.db
      .select({ position: positions, token: tokenRefCols })
      .from(positions)
      .innerJoin(tokens, eq(tokens.id, positions.tokenId))
      .where(eq(positions.tokenId, tokenId))
      .orderBy(desc(positions.openedAt))
      .limit(limit);
  }

  async openForToken(mode: TradingMode, tokenId: number): Promise<PositionRow | null> {
    const [row] = await this.db
      .select()
      .from(positions)
      .where(and(eq(positions.mode, mode), eq(positions.status, 'open'), eq(positions.tokenId, tokenId)))
      .limit(1);
    return row ?? null;
  }

  /** Open positions plus the most recently closed ones for one strategy (newest first). */
  async listForStrategy(
    mode: TradingMode,
    strategy: PositionStrategy,
    closedLimit: number,
  ): Promise<{ position: PositionRow; token: TokenRefRow }[]> {
    const open = await this.db
      .select({ position: positions, token: tokenRefCols })
      .from(positions)
      .innerJoin(tokens, eq(tokens.id, positions.tokenId))
      .where(and(eq(positions.mode, mode), eq(positions.strategy, strategy), eq(positions.status, 'open')))
      .orderBy(desc(positions.openedAt));
    const closed = await this.db
      .select({ position: positions, token: tokenRefCols })
      .from(positions)
      .innerJoin(tokens, eq(tokens.id, positions.tokenId))
      .where(and(eq(positions.mode, mode), eq(positions.strategy, strategy), eq(positions.status, 'closed')))
      .orderBy(desc(positions.closedAt))
      .limit(closedLimit);
    return [...open, ...closed];
  }

  /** Counts and P/L for one strategy; "today" is the current UTC day. */
  async strategyStats(
    mode: TradingMode,
    strategy: PositionStrategy,
    now: Date,
  ): Promise<{
    open: number;
    closed: number;
    wins: number;
    losses: number;
    realizedPnlUsd: number;
    todayRealizedPnlUsd: number;
    todayOpened: number;
  }> {
    const dayStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
    const [r] = await this.db
      .select({
        open: sql<number>`count(*) filter (where ${positions.status} = 'open')`,
        closed: sql<number>`count(*) filter (where ${positions.status} = 'closed')`,
        wins: sql<number>`count(*) filter (where ${positions.status} = 'closed' and ${positions.realizedPnlUsd} > 0)`,
        losses: sql<number>`count(*) filter (where ${positions.status} = 'closed' and ${positions.realizedPnlUsd} <= 0)`,
        realized: sql<number>`coalesce(sum(${positions.realizedPnlUsd}) filter (where ${positions.status} = 'closed'), 0)`,
        todayRealized: sql<number>`coalesce(sum(${positions.realizedPnlUsd}) filter (where ${positions.status} = 'closed' and ${positions.closedAt} >= ${dayStart}), 0)`,
        todayOpened: sql<number>`count(*) filter (where ${positions.openedAt} >= ${dayStart})`,
      })
      .from(positions)
      .where(and(eq(positions.mode, mode), eq(positions.strategy, strategy)));
    return {
      open: Number(r?.open ?? 0),
      closed: Number(r?.closed ?? 0),
      wins: Number(r?.wins ?? 0),
      losses: Number(r?.losses ?? 0),
      realizedPnlUsd: Number(r?.realized ?? 0),
      todayRealizedPnlUsd: Number(r?.todayRealized ?? 0),
      todayOpened: Number(r?.todayOpened ?? 0),
    };
  }

  async countOpen(mode: TradingMode): Promise<number> {
    const [r] = await this.db
      .select({ n: count() })
      .from(positions)
      .where(and(eq(positions.mode, mode), eq(positions.status, 'open')));
    return Number(r?.n ?? 0);
  }

  async updateMark(id: number, lastPriceUsd: number, highestPriceUsd: number): Promise<void> {
    await this.db
      .update(positions)
      .set({ lastPriceUsd, highestPriceUsd, updatedAt: new Date() })
      .where(eq(positions.id, id));
  }

  /** Atomically closes an open position; returns null if it was already closed (idempotency). */
  async close(
    id: number,
    v: { exitPriceUsd: number; proceedsUsd: number; realizedPnlUsd: number; closeReason: CloseReason },
  ): Promise<PositionRow | null> {
    const now = new Date();
    const [row] = await this.db
      .update(positions)
      .set({ ...v, status: 'closed', lastPriceUsd: v.exitPriceUsd, closedAt: now, updatedAt: now })
      .where(and(eq(positions.id, id), eq(positions.status, 'open')))
      .returning();
    return row ?? null;
  }

  async closedStats(mode: TradingMode): Promise<{
    closed: number;
    wins: number;
    losses: number;
    grossProfit: number;
    grossLoss: number;
  }> {
    const [r] = await this.db
      .select({
        closed: count(),
        wins: sql<number>`count(*) filter (where ${positions.realizedPnlUsd} > 0)`,
        losses: sql<number>`count(*) filter (where ${positions.realizedPnlUsd} <= 0)`,
        grossProfit: sql<number>`coalesce(sum(${positions.realizedPnlUsd}) filter (where ${positions.realizedPnlUsd} > 0), 0)`,
        grossLoss: sql<number>`coalesce(-sum(${positions.realizedPnlUsd}) filter (where ${positions.realizedPnlUsd} <= 0), 0)`,
      })
      .from(positions)
      .where(and(eq(positions.mode, mode), eq(positions.status, 'closed')));
    return {
      closed: Number(r?.closed ?? 0),
      wins: Number(r?.wins ?? 0),
      losses: Number(r?.losses ?? 0),
      grossProfit: Number(r?.grossProfit ?? 0),
      grossLoss: Number(r?.grossLoss ?? 0),
    };
  }

  /** Realized P/L per UTC day (by close time). */
  async dailyRealized(
    mode: TradingMode,
    days: number,
  ): Promise<{ day: string; pnlUsd: number; trades: number }[]> {
    const since = new Date(Date.now() - days * 86_400_000);
    const rows = await this.db
      .select({
        day: sql<string>`to_char(${positions.closedAt} at time zone 'UTC', 'YYYY-MM-DD')`,
        pnl: sql<number>`coalesce(sum(${positions.realizedPnlUsd}), 0)`,
        n: count(),
      })
      .from(positions)
      .where(and(eq(positions.mode, mode), eq(positions.status, 'closed'), gte(positions.closedAt, since)))
      .groupBy(sql`1`)
      .orderBy(sql`1`);
    return rows.map((r) => ({ day: r.day, pnlUsd: Number(r.pnl), trades: Number(r.n) }));
  }
}

export class TradesRepository {
  constructor(private readonly db: Database) {}

  async insert(v: typeof trades.$inferInsert): Promise<TradeRow> {
    const [row] = await this.db.insert(trades).values(v).returning();
    if (!row) throw new Error('failed to insert trade');
    return row;
  }

  async setPosition(id: number, positionId: number): Promise<void> {
    await this.db.update(trades).set({ positionId }).where(eq(trades.id, id));
  }

  async list(opts: {
    mode?: TradingMode;
    limit: number;
    offset: number;
    tokenId?: number;
  }): Promise<{ rows: { trade: TradeRow; token: TokenRefRow }[]; total: number }> {
    const conds = [];
    if (opts.mode) conds.push(eq(trades.mode, opts.mode));
    if (opts.tokenId) conds.push(eq(trades.tokenId, opts.tokenId));
    const where = conds.length > 0 ? and(...conds) : undefined;
    const rows = await this.db
      .select({ trade: trades, token: tokenRefCols })
      .from(trades)
      .innerJoin(tokens, eq(tokens.id, trades.tokenId))
      .where(where)
      .orderBy(desc(trades.createdAt), desc(trades.id))
      .limit(opts.limit)
      .offset(opts.offset);
    const [total] = await this.db.select({ n: count() }).from(trades).where(where);
    return { rows, total: Number(total?.n ?? 0) };
  }

  async countFilled(mode: TradingMode): Promise<number> {
    const [r] = await this.db
      .select({ n: count() })
      .from(trades)
      .where(and(eq(trades.mode, mode), eq(trades.status, 'filled')));
    return Number(r?.n ?? 0);
  }
}

export class AccountsRepository {
  constructor(private readonly db: Database) {}

  async get(mode: TradingMode): Promise<AccountRow | null> {
    const [row] = await this.db.select().from(accounts).where(eq(accounts.mode, mode)).limit(1);
    return row ?? null;
  }

  async ensure(mode: TradingMode, startingBalanceUsd: number, now: Date): Promise<AccountRow> {
    const existing = await this.get(mode);
    if (existing) return existing;
    await this.db
      .insert(accounts)
      .values({
        mode,
        startingBalanceUsd,
        cashUsd: startingBalanceUsd,
        peakEquityUsd: startingBalanceUsd,
        day: utcDay(now),
        dayStartEquityUsd: startingBalanceUsd,
      })
      .onConflictDoNothing({ target: accounts.mode });
    const row = await this.get(mode);
    if (!row) throw new Error(`failed to create ${mode} account`);
    return row;
  }

  async update(mode: TradingMode, patch: Partial<typeof accounts.$inferInsert>): Promise<AccountRow> {
    const [row] = await this.db
      .update(accounts)
      .set({ ...patch, updatedAt: new Date() })
      .where(eq(accounts.mode, mode))
      .returning();
    if (!row) throw new Error(`account ${mode} not found`);
    return row;
  }

  /** Atomic cash adjustment (positive = credit). Returns the new balance. */
  async adjustCash(mode: TradingMode, deltaUsd: number, realizedDeltaUsd = 0): Promise<AccountRow> {
    const [row] = await this.db
      .update(accounts)
      .set({
        cashUsd: sql`${accounts.cashUsd} + ${deltaUsd}`,
        realizedPnlUsd: sql`${accounts.realizedPnlUsd} + ${realizedDeltaUsd}`,
        updatedAt: new Date(),
      })
      .where(eq(accounts.mode, mode))
      .returning();
    if (!row) throw new Error(`account ${mode} not found`);
    return row;
  }
}

export class PerformanceRepository {
  constructor(private readonly db: Database) {}

  async insert(v: typeof performanceMetrics.$inferInsert): Promise<void> {
    await this.db.insert(performanceMetrics).values(v);
  }

  async curve(mode: TradingMode, limit: number): Promise<EquityPoint[]> {
    const rows = await this.db
      .select()
      .from(performanceMetrics)
      .where(eq(performanceMetrics.mode, mode))
      .orderBy(desc(performanceMetrics.ts))
      .limit(limit);
    return rows.reverse().map((r) => ({
      ts: r.ts.toISOString(),
      equityUsd: r.equityUsd,
      cashUsd: r.cashUsd,
      unrealizedPnlUsd: r.unrealizedPnlUsd,
      realizedPnlUsd: r.realizedPnlUsd,
      drawdownPct: r.drawdownPct,
    }));
  }
}
