import type {
  Chain,
  Position,
  PositionSummary,
  SystemStatus,
  TokenDetail,
  TokenListItem,
} from '@memeguard/shared';
import type { App } from '../app';
import { toPosition, toTokenListItem, type TokenRow } from '../db/repositories';
import { errorMessage } from '../lib/errors';

/** Read-model assembly shared by the API routes. */

export async function openPositionSummaries(app: App): Promise<Map<number, PositionSummary>> {
  const state = await app.portfolio.state();
  return new Map(
    state.marks.map((m) => [
      m.position.tokenId,
      {
        id: m.position.id,
        quantity: m.position.quantity,
        entryPriceUsd: m.position.entryPriceUsd,
        costBasisUsd: m.position.costBasisUsd,
        unrealizedPnlUsd: m.unrealizedPnlUsd,
        unrealizedPnlPct:
          m.position.costBasisUsd > 0 ? (m.unrealizedPnlUsd / m.position.costBasisUsd) * 100 : null,
      },
    ]),
  );
}

export async function tokenItems(app: App, rows: TokenRow[]): Promise<TokenListItem[]> {
  const open = await openPositionSummaries(app);
  return rows.map((r) => toTokenListItem(r, open.get(r.id) ?? null));
}

export async function tokenDetail(app: App, row: TokenRow): Promise<TokenDetail> {
  const [items] = await tokenItems(app, [row]);
  const since = new Date(Date.now() - 7 * 86_400_000);
  const [risk, priceHistory, liquidityHistory, riskHistory, decisions, positions, alerts] = await Promise.all(
    [
      app.repos.risk.latest(row.id),
      app.repos.history.prices(row.id, { since, limit: 2000 }),
      app.repos.history.liquidity(row.id, { since, limit: 1000 }),
      app.repos.risk.history(row.id, 200),
      app.repos.decisions.listForToken(row.id, 25),
      app.repos.positions.listByToken(row.id, 20),
      app.repos.alerts.list({ limit: 25, offset: 0, tokenId: row.id }),
    ],
  );
  return {
    token: items as TokenListItem,
    snapshot: row.latestSnapshot ?? null,
    risk,
    priceHistory,
    liquidityHistory,
    riskHistory,
    decisions,
    positions: positions.map((p) => toPosition(p.position, p.token)),
    alerts: alerts.items,
  };
}

export async function listPositions(
  app: App,
  status: 'open' | 'closed' | 'all',
  limit: number,
): Promise<Position[]> {
  const out: Position[] = [];
  if (status !== 'closed') {
    const state = await app.portfolio.state();
    for (const m of state.marks) {
      out.push(
        toPosition(
          m.position,
          { chain: m.token.chain, address: m.token.address, symbol: m.token.symbol },
          m.priceUsd,
        ),
      );
    }
  }
  if (status !== 'open') {
    const closed = await app.repos.positions.listRecentClosed(app.config.trading.mode, limit);
    out.push(...closed.map((c) => toPosition(c.position, c.token)));
  }
  return out;
}

export async function systemStatus(app: App): Promise<SystemStatus> {
  let dbOk = true;
  let dbError: string | null = null;
  try {
    await app.db.ping();
  } catch (err) {
    dbOk = false;
    dbError = errorMessage(err);
  }
  const account = dbOk ? await app.repos.accounts.get(app.config.trading.mode) : null;
  const cfg = app.strategyStore.get();
  return {
    version: app.config.version,
    mode: app.config.trading.mode,
    liveTradingArmed: app.config.trading.liveArmed,
    engineRunning: app.engine.isRunning,
    autoTrade: cfg.strategy.autoTrade,
    halted: account?.halted ?? false,
    haltReason: account?.haltReason ?? null,
    uptimeSeconds: Math.round((Date.now() - app.startedAt.getTime()) / 1000),
    database: { ok: dbOk, driver: app.db.driver, error: dbError },
    loops: app.engine.loopStatus(),
    providers: app.providers.registry.health(),
    notifiers: app.alerts.notifierStatus(app.notifierConfig),
    queue: {
      pending: app.engine.queueStats().pending,
      inFlight: app.engine.queueStats().inFlight + app.pipeline.inFlight,
    },
    llmReviewer: { enabled: app.llm !== null, model: app.llm?.model ?? null },
    startedAt: app.startedAt.toISOString(),
  };
}

export async function findToken(app: App, address: string, chain?: Chain): Promise<TokenRow | null> {
  return app.repos.tokens.getByAddress(address, chain);
}
