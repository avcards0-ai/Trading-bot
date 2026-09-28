import { and, count, desc, eq, gte, inArray, sql } from 'drizzle-orm';
import type {
  Alert,
  AlertSeverity,
  AlertType,
  BacktestResult,
  Chain,
  RiskLimits,
  StrategyParams,
} from '@memeguard/shared';
import type { Database } from '../client';
import {
  alerts,
  backtestRuns,
  eventLog,
  strategyConfigs,
  tokenWallets,
  tokens,
  transactions,
  wallets,
} from '../schema';

export type AlertRow = typeof alerts.$inferSelect;
export type WalletRow = typeof wallets.$inferSelect;

export function toAlert(
  row: AlertRow,
  token: { chain: string | null; address: string | null; symbol: string | null } | null,
): Alert {
  return {
    id: row.id,
    tokenId: row.tokenId,
    chain: (token?.chain as Chain | null) ?? null,
    address: token?.address ?? null,
    symbol: token?.symbol ?? null,
    type: row.type as AlertType,
    severity: row.severity as AlertSeverity,
    title: row.title,
    message: row.message,
    data: row.data,
    acknowledged: row.acknowledged,
    deliveredTo: row.deliveredTo,
    createdAt: row.createdAt.toISOString(),
  };
}

export class AlertsRepository {
  constructor(private readonly db: Database) {}

  async insert(v: typeof alerts.$inferInsert): Promise<AlertRow> {
    const [row] = await this.db.insert(alerts).values(v).returning();
    if (!row) throw new Error('failed to insert alert');
    return row;
  }

  async setDelivered(id: number, channels: string[]): Promise<void> {
    await this.db.update(alerts).set({ deliveredTo: channels }).where(eq(alerts.id, id));
  }

  async existsSince(dedupeKey: string, since: Date): Promise<boolean> {
    const [r] = await this.db
      .select({ n: count() })
      .from(alerts)
      .where(and(eq(alerts.dedupeKey, dedupeKey), gte(alerts.createdAt, since)));
    return Number(r?.n ?? 0) > 0;
  }

  async acknowledge(id: number): Promise<boolean> {
    const res = await this.db.update(alerts).set({ acknowledged: true }).where(eq(alerts.id, id)).returning({ id: alerts.id });
    return res.length > 0;
  }

  async acknowledgeAll(): Promise<number> {
    const res = await this.db
      .update(alerts)
      .set({ acknowledged: true })
      .where(eq(alerts.acknowledged, false))
      .returning({ id: alerts.id });
    return res.length;
  }

  async list(opts: {
    limit: number;
    offset: number;
    severity?: AlertSeverity;
    type?: AlertType;
    tokenId?: number;
    unacknowledged?: boolean;
  }): Promise<{ items: Alert[]; total: number }> {
    const conds = [];
    if (opts.severity) conds.push(eq(alerts.severity, opts.severity));
    if (opts.type) conds.push(eq(alerts.type, opts.type));
    if (opts.tokenId) conds.push(eq(alerts.tokenId, opts.tokenId));
    if (opts.unacknowledged) conds.push(eq(alerts.acknowledged, false));
    const where = conds.length > 0 ? and(...conds) : undefined;
    const rows = await this.db
      .select({ a: alerts, t: { chain: tokens.chain, address: tokens.address, symbol: tokens.symbol } })
      .from(alerts)
      .leftJoin(tokens, eq(tokens.id, alerts.tokenId))
      .where(where)
      .orderBy(desc(alerts.createdAt), desc(alerts.id))
      .limit(opts.limit)
      .offset(opts.offset);
    const [total] = await this.db.select({ n: count() }).from(alerts).where(where);
    return { items: rows.map((r) => toAlert(r.a, r.t)), total: Number(total?.n ?? 0) };
  }

  async countUnacknowledged(): Promise<number> {
    const [r] = await this.db.select({ n: count() }).from(alerts).where(eq(alerts.acknowledged, false));
    return Number(r?.n ?? 0);
  }
}

export class StrategyConfigRepository {
  constructor(private readonly db: Database) {}

  async active(): Promise<{ version: number; limits: RiskLimits; strategy: StrategyParams; createdAt: Date } | null> {
    const [row] = await this.db
      .select()
      .from(strategyConfigs)
      .where(eq(strategyConfigs.active, true))
      .orderBy(desc(strategyConfigs.version))
      .limit(1);
    return row ? { version: row.version, limits: row.limits, strategy: row.strategy, createdAt: row.createdAt } : null;
  }

  async save(limits: RiskLimits, strategy: StrategyParams): Promise<{ version: number; createdAt: Date }> {
    return this.db.transaction(async (tx) => {
      const [latest] = await tx
        .select({ v: sql<number>`coalesce(max(${strategyConfigs.version}), 0)` })
        .from(strategyConfigs);
      const version = Number(latest?.v ?? 0) + 1;
      await tx.update(strategyConfigs).set({ active: false }).where(eq(strategyConfigs.active, true));
      const [row] = await tx
        .insert(strategyConfigs)
        .values({ version, limits, strategy, active: true })
        .returning({ createdAt: strategyConfigs.createdAt });
      return { version, createdAt: row?.createdAt ?? new Date() };
    });
  }
}

export type EventLevel = 'debug' | 'info' | 'warn' | 'error';

export class EventLogRepository {
  constructor(private readonly db: Database) {}

  async log(
    level: EventLevel,
    category: string,
    message: string,
    data: Record<string, unknown> = {},
    tokenId: number | null = null,
  ): Promise<void> {
    await this.db.insert(eventLog).values({ level, category, message, data, tokenId });
  }

  async list(opts: { limit: number; category?: string; level?: EventLevel }) {
    const conds = [];
    if (opts.category) conds.push(eq(eventLog.category, opts.category));
    if (opts.level) conds.push(eq(eventLog.level, opts.level));
    const rows = await this.db
      .select()
      .from(eventLog)
      .where(conds.length > 0 ? and(...conds) : undefined)
      .orderBy(desc(eventLog.createdAt), desc(eventLog.id))
      .limit(opts.limit);
    return rows.map((r) => ({ ...r, createdAt: r.createdAt.toISOString() }));
  }
}

export class BacktestRepository {
  constructor(private readonly db: Database) {}

  async insert(result: BacktestResult): Promise<number> {
    const [row] = await this.db
      .insert(backtestRuns)
      .values({
        name: result.name,
        source: result.source,
        synthetic: result.syntheticData,
        config: result.config,
        result,
      })
      .returning({ id: backtestRuns.id });
    if (!row) throw new Error('failed to insert backtest');
    return row.id;
  }

  async list(limit: number) {
    const rows = await this.db
      .select({
        id: backtestRuns.id,
        name: backtestRuns.name,
        source: backtestRuns.source,
        synthetic: backtestRuns.synthetic,
        createdAt: backtestRuns.createdAt,
        metrics: sql<BacktestResult['metrics']>`${backtestRuns.result} -> 'metrics'`,
      })
      .from(backtestRuns)
      .orderBy(desc(backtestRuns.createdAt))
      .limit(limit);
    return rows.map((r) => ({ ...r, createdAt: r.createdAt.toISOString() }));
  }

  async get(id: number): Promise<BacktestResult | null> {
    const [row] = await this.db.select().from(backtestRuns).where(eq(backtestRuns.id, id)).limit(1);
    return row ? { ...row.result, id: row.id } : null;
  }
}

export interface WalletUpsert {
  chain: Chain;
  address: string;
  label?: string | null;
  walletCreatedAt?: Date | null;
  ageIsLowerBound?: boolean;
  fundedBy?: string | null;
  riskFlags?: string[];
  metadata?: Record<string, unknown>;
}

export class WalletsRepository {
  constructor(private readonly db: Database) {}

  async getMany(chain: Chain, addresses: string[]): Promise<Map<string, WalletRow>> {
    if (addresses.length === 0) return new Map();
    const rows = await this.db
      .select()
      .from(wallets)
      .where(and(eq(wallets.chain, chain), inArray(wallets.address, addresses)));
    return new Map(rows.map((r) => [r.address, r]));
  }

  async upsert(w: WalletUpsert): Promise<WalletRow> {
    const values = {
      chain: w.chain,
      address: w.address,
      label: w.label ?? null,
      walletCreatedAt: w.walletCreatedAt ?? null,
      ageIsLowerBound: w.ageIsLowerBound ?? false,
      fundedBy: w.fundedBy ?? null,
      riskFlags: w.riskFlags ?? [],
      metadata: w.metadata ?? {},
    };
    const set: Partial<typeof wallets.$inferInsert> = { updatedAt: new Date() };
    if (w.label !== undefined) set.label = w.label;
    if (w.walletCreatedAt !== undefined) set.walletCreatedAt = w.walletCreatedAt;
    if (w.ageIsLowerBound !== undefined) set.ageIsLowerBound = w.ageIsLowerBound;
    if (w.fundedBy !== undefined) set.fundedBy = w.fundedBy;
    if (w.riskFlags !== undefined) set.riskFlags = w.riskFlags;
    if (w.metadata !== undefined) set.metadata = w.metadata;
    const [row] = await this.db
      .insert(wallets)
      .values(values)
      .onConflictDoUpdate({ target: [wallets.chain, wallets.address], set })
      .returning();
    if (!row) throw new Error('wallet upsert failed');
    return row;
  }

  async link(tokenId: number, walletId: number, role: string, percent: number | null, clusterFunder: string | null) {
    await this.db
      .insert(tokenWallets)
      .values({ tokenId, walletId, role, percent, clusterFunder })
      .onConflictDoUpdate({
        target: [tokenWallets.tokenId, tokenWallets.walletId, tokenWallets.role],
        set: { percent, clusterFunder, updatedAt: new Date() },
      });
  }

  async listForToken(tokenId: number) {
    const rows = await this.db
      .select({ link: tokenWallets, wallet: wallets })
      .from(tokenWallets)
      .innerJoin(wallets, eq(wallets.id, tokenWallets.walletId))
      .where(eq(tokenWallets.tokenId, tokenId))
      .orderBy(sql`${tokenWallets.percent} desc nulls last`);
    return rows.map((r) => ({
      address: r.wallet.address,
      role: r.link.role,
      percent: r.link.percent,
      clusterFunder: r.link.clusterFunder,
      label: r.wallet.label,
      walletCreatedAt: r.wallet.walletCreatedAt?.toISOString() ?? null,
      ageIsLowerBound: r.wallet.ageIsLowerBound,
      fundedBy: r.wallet.fundedBy,
      riskFlags: r.wallet.riskFlags,
    }));
  }
}

export class TransactionsRepository {
  constructor(private readonly db: Database) {}

  /** Inserts observed transactions, ignoring ones already recorded. Returns the newly inserted ones. */
  async insertNew(rows: (typeof transactions.$inferInsert)[]): Promise<(typeof transactions.$inferSelect)[]> {
    if (rows.length === 0) return [];
    return this.db
      .insert(transactions)
      .values(rows)
      .onConflictDoNothing({ target: [transactions.chain, transactions.txHash, transactions.kind] })
      .returning();
  }

  async listForToken(tokenId: number, limit: number) {
    const rows = await this.db
      .select()
      .from(transactions)
      .where(eq(transactions.tokenId, tokenId))
      .orderBy(sql`${transactions.blockTime} desc nulls last`)
      .limit(limit);
    return rows.map((r) => ({
      ...r,
      blockTime: r.blockTime?.toISOString() ?? null,
      createdAt: r.createdAt.toISOString(),
    }));
  }
}
