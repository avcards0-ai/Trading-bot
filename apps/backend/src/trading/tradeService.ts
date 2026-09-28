import type {
  CloseReason,
  MarketData,
  Position,
  PositionSizing,
  RiskReport,
  StrategyParams,
  TokenSnapshot,
  Trade,
  TradingMode,
} from '@memeguard/shared';
import type { AlertService } from '../alerts/alertService';
import type { MarketDataProvider } from '../adapters/types';
import type { Repositories, TokenRow } from '../db/repositories';
import { toPosition, toTrade } from '../db/repositories';
import type { TradeExecutor } from '../execution/types';
import { errorMessage } from '../lib/errors';
import type { EventBus } from '../lib/events';
import type { Logger } from '../lib/logger';
import type { Portfolio } from './portfolio';
import { sellTaxOf } from './portfolio';

const buyTaxOf = (s: TokenSnapshot | null | undefined): number =>
  Math.max(0, s?.contract?.buyTaxPct ?? 0, s?.honeypot?.buyTaxPct ?? 0);

const CLOSE_ALERT: Partial<Record<CloseReason, { type: 'STOP_LOSS' | 'TAKE_PROFIT'; title: string }>> = {
  stop_loss: { type: 'STOP_LOSS', title: 'Stop loss triggered' },
  trailing_stop: { type: 'STOP_LOSS', title: 'Trailing stop triggered' },
  take_profit: { type: 'TAKE_PROFIT', title: 'Take profit triggered' },
};

export interface OpenResult {
  trade: Trade;
  position: Position | null;
}

/**
 * Executes approved decisions and keeps positions, trades, cash and alerts consistent.
 * It never decides WHETHER to trade — callers must pass a decision that cleared the RiskManager.
 * Exits are serialised per position so a stop-loss and a manual close cannot double-sell.
 */
export class TradeService {
  private readonly closing = new Set<number>();

  constructor(
    private readonly deps: {
      repos: Repositories;
      executor: TradeExecutor;
      portfolio: Portfolio;
      alerts: AlertService;
      bus: EventBus;
      logger: Logger;
      market: MarketDataProvider;
      mode: TradingMode;
      exitMaxSlippagePct: number;
    },
  ) {}

  async openPosition(args: {
    token: TokenRow;
    snapshot: TokenSnapshot;
    report: RiskReport;
    sizing: PositionSizing;
    strategy: StrategyParams;
    maxSlippagePct: number;
    decisionId: number;
    reason: string;
  }): Promise<OpenResult> {
    const { token, snapshot, sizing, strategy } = args;
    const market = snapshot.market as MarketData;
    const result = await this.deps.executor.execute({
      side: 'buy',
      chain: snapshot.chain,
      address: snapshot.address,
      decimals: snapshot.decimals,
      market,
      amountUsd: sizing.sizeUsd,
      maxSlippagePct: args.maxSlippagePct,
      taxes: { buyPct: buyTaxOf(snapshot), sellPct: sellTaxOf(snapshot) },
    });

    const tradeRow = await this.deps.repos.trades.insert({
      tokenId: token.id,
      decisionId: args.decisionId,
      mode: this.deps.mode,
      side: 'buy',
      status: result.status,
      requestedUsd: sizing.sizeUsd,
      filledUsd: result.status === 'filled' ? result.filledUsd : null,
      quantity: result.status === 'filled' ? result.quantity : null,
      priceUsd: result.avgPriceUsd,
      slippagePct: result.slippagePct,
      feeUsd: result.feeUsd,
      txHash: result.txHash,
      error: result.error,
      reason: args.reason,
      raw: result.raw ?? null,
    });
    const tokenRef = { chain: token.chain, address: token.address, symbol: token.symbol };

    if (result.status !== 'filled') {
      await this.deps.portfolio.applyCash(-result.feeUsd, -result.feeUsd);
      const trade = toTrade(tradeRow, tokenRef);
      this.deps.bus.publish({ type: 'trade', data: trade });
      await this.deps.repos.events.log('warn', 'execution', `buy failed: ${result.error}`, { tradeId: trade.id }, token.id);
      if (result.txHash && /reconcile/i.test(result.error ?? '')) {
        await this.deps.alerts.raise({
          type: 'SYSTEM_ERROR',
          severity: 'critical',
          title: 'Live buy needs reconciliation',
          message: `Buy of ${token.symbol ?? token.address} has unknown outcome (${result.error}). Tx ${result.txHash}.`,
          tokenId: token.id,
          token: tokenRef,
          dedupeKey: `reconcile:${result.txHash}`,
        });
      }
      return { trade, position: null };
    }

    const entry = result.avgPriceUsd as number;
    const positionRow = await this.deps.repos.positions.create({
      tokenId: token.id,
      mode: this.deps.mode,
      status: 'open',
      quantity: result.quantity,
      rawQuantity: result.rawQuantity,
      tokenDecimals: snapshot.decimals,
      entryPriceUsd: entry,
      costBasisUsd: result.filledUsd,
      stopLossPriceUsd: entry * (1 - strategy.stopLossPercent / 100),
      takeProfitPriceUsd: entry * (1 + strategy.takeProfitPercent / 100),
      trailingStopPercent: strategy.trailingStopPercent,
      highestPriceUsd: Math.max(entry, market.priceUsd ?? entry),
      lastPriceUsd: market.priceUsd,
      entryLiquidityUsd: market.liquidityUsd,
      entryRugScore: args.report.rugScore,
    });
    await this.deps.repos.trades.setPosition(tradeRow.id, positionRow.id);
    await this.deps.portfolio.applyCash(-result.filledUsd, 0);

    const trade = toTrade({ ...tradeRow, positionId: positionRow.id }, tokenRef);
    const position = toPosition(positionRow, tokenRef, market.priceUsd);
    this.deps.bus.publish({ type: 'trade', data: trade });
    this.deps.bus.publish({ type: 'position', data: position });
    await this.deps.alerts.raise({
      type: 'POSITION_OPENED',
      severity: 'info',
      title: `Position opened (${this.deps.mode})`,
      message: `Bought ${result.quantity.toPrecision(6)} ${token.symbol ?? ''} for $${result.filledUsd.toFixed(2)} at $${entry.toPrecision(6)}. Stop $${positionRow.stopLossPriceUsd.toPrecision(6)}, target $${positionRow.takeProfitPriceUsd.toPrecision(6)}. Rug score ${args.report.rugScore}.`,
      tokenId: token.id,
      token: tokenRef,
      data: { positionId: positionRow.id, sizeUsd: result.filledUsd, rugScore: args.report.rugScore, mode: this.deps.mode },
      dedupeKey: `POSITION_OPENED:${positionRow.id}`,
    });
    return { trade, position };
  }

  async closePosition(args: {
    positionId: number;
    reason: CloseReason;
    detail: string;
    market?: MarketData | null;
    decisionId?: number | null;
  }): Promise<OpenResult | null> {
    if (this.closing.has(args.positionId)) return null;
    this.closing.add(args.positionId);
    try {
      const found = await this.deps.repos.positions.get(args.positionId);
      if (!found || found.position.status !== 'open') return null;
      const { position } = found;
      const token = await this.deps.repos.tokens.getById(position.tokenId);
      if (!token) return null;
      const tokenRef = { chain: token.chain, address: token.address, symbol: token.symbol };
      let market = args.market ?? null;
      if (!market || Date.now() - Date.parse(market.fetchedAt) > 60_000) {
        try {
          market = (await this.deps.market.getMarket(token.chain as never, token.address))?.market ?? market;
        } catch (err) {
          this.deps.logger.warn({ err: errorMessage(err) }, 'fresh market data unavailable for exit; using last known');
        }
      }
      if (!market) {
        await this.deps.repos.events.log('error', 'execution', 'cannot exit: no market data', { positionId: position.id }, token.id);
        return null;
      }
      const result = await this.deps.executor.execute({
        side: 'sell',
        chain: token.chain as never,
        address: token.address,
        decimals: position.tokenDecimals,
        market,
        quantity: position.quantity,
        rawQuantity: position.rawQuantity,
        maxSlippagePct: this.deps.exitMaxSlippagePct,
        taxes: { buyPct: 0, sellPct: sellTaxOf(token.latestSnapshot) },
      });
      const tradeRow = await this.deps.repos.trades.insert({
        tokenId: token.id,
        positionId: position.id,
        decisionId: args.decisionId ?? null,
        mode: this.deps.mode,
        side: 'sell',
        status: result.status,
        requestedUsd: position.quantity * (market.priceUsd ?? 0),
        filledUsd: result.status === 'filled' ? result.filledUsd : null,
        quantity: result.status === 'filled' ? result.quantity : null,
        priceUsd: result.avgPriceUsd,
        slippagePct: result.slippagePct,
        feeUsd: result.feeUsd,
        txHash: result.txHash,
        error: result.error,
        reason: `${args.reason}: ${args.detail}`,
        raw: result.raw ?? null,
      });
      const trade = toTrade(tradeRow, tokenRef);
      this.deps.bus.publish({ type: 'trade', data: trade });

      if (result.status !== 'filled') {
        await this.deps.portfolio.applyCash(-result.feeUsd, -result.feeUsd);
        await this.deps.repos.events.log('error', 'execution', `exit failed: ${result.error}`, { positionId: position.id, reason: args.reason }, token.id);
        await this.deps.alerts.raise({
          type: 'SYSTEM_ERROR',
          severity: 'critical',
          title: 'Exit failed — will retry',
          message: `Could not close ${token.symbol ?? token.address} (${args.reason}): ${result.error}. The monitor will retry on the next tick.`,
          tokenId: token.id,
          token: tokenRef,
          dedupeKey: `exit-failed:${position.id}`,
          cooldownSeconds: 300,
        });
        return { trade, position: null };
      }

      const proceeds = result.filledUsd;
      const realized = proceeds - position.costBasisUsd;
      const closed = await this.deps.repos.positions.close(position.id, {
        exitPriceUsd: result.avgPriceUsd as number,
        proceedsUsd: proceeds,
        realizedPnlUsd: realized,
        closeReason: args.reason,
      });
      if (!closed) return { trade, position: null };
      await this.deps.portfolio.applyCash(proceeds, realized);
      const dto = toPosition(closed, tokenRef);
      this.deps.bus.publish({ type: 'position', data: dto });

      const special = CLOSE_ALERT[args.reason];
      const pnlPct = (realized / position.costBasisUsd) * 100;
      await this.deps.alerts.raise({
        type: special?.type ?? 'POSITION_CLOSED',
        severity: realized < 0 && (args.reason === 'rug_risk_escalation' || args.reason === 'liquidity_drop') ? 'critical' : 'info',
        title: `${special?.title ?? 'Position closed'} (${this.deps.mode})`,
        message: `Sold ${token.symbol ?? token.address}: ${args.detail} Realized P/L ${realized >= 0 ? '+' : ''}$${realized.toFixed(2)} (${pnlPct.toFixed(1)}%).`,
        tokenId: token.id,
        token: tokenRef,
        data: { positionId: position.id, realizedPnlUsd: realized, pnlPct, reason: args.reason },
        dedupeKey: `CLOSE:${position.id}`,
      });
      return { trade, position: dto };
    } finally {
      this.closing.delete(args.positionId);
    }
  }
}
