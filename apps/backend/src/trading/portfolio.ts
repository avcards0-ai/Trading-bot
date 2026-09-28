import type { PerformanceSummary, RiskLimits, TokenSnapshot, TradingMode } from '@memeguard/shared';
import type { AlertService } from '../alerts/alertService';
import type { AccountRow, PositionRow, Repositories, TokenRow } from '../db/repositories';
import { estimateExitValueUsd } from '../execution/amm';
import type { TradeExecutor } from '../execution/types';
import { errorMessage } from '../lib/errors';
import type { EventBus } from '../lib/events';
import type { Logger } from '../lib/logger';
import { utcDay } from '../lib/time';
import type { AccountView } from '../risk/riskManager';

export interface PositionMark {
  position: PositionRow;
  token: TokenRow;
  priceUsd: number | null;
  markValueUsd: number;
  exitValueUsd: number;
  unrealizedPnlUsd: number;
}

export interface PortfolioState extends AccountView {
  mode: TradingMode;
  /** Mark-to-market equity at mid prices. */
  markEquityUsd: number;
  unrealizedPnlUsd: number;
  realizedPnlUsd: number;
  dailyPnlUsd: number;
  dailyPnlPct: number;
  drawdownPct: number;
  maxDrawdownPct: number;
  startingBalanceUsd: number;
  marks: PositionMark[];
}

export const sellTaxOf = (s: TokenSnapshot | null | undefined): number =>
  Math.max(0, s?.contract?.sellTaxPct ?? 0, s?.honeypot?.sellTaxPct ?? 0);

/**
 * Account accounting for the active mode.
 *  - paper: cash is the simulated wallet stored in the database
 *  - live: cash is read from the wallet's on-chain balance
 * Risk metrics (drawdown, daily P/L) use CONSERVATIVE equity: open positions are valued at what
 * a market sell would return now (price impact, fees, sell tax), not at mid price.
 */
export class Portfolio {
  private liveCash: { value: number; at: number } | null = null;

  constructor(
    private readonly deps: {
      repos: Repositories;
      mode: TradingMode;
      startingBalanceUsd: number;
      executor: TradeExecutor;
      dexFeePct: number;
      bus: EventBus;
      alerts: AlertService;
      logger: Logger;
      now?: () => Date;
    },
  ) {}

  get mode(): TradingMode {
    return this.deps.mode;
  }

  private now(): Date {
    return this.deps.now?.() ?? new Date();
  }

  async init(): Promise<AccountRow> {
    let start = this.deps.startingBalanceUsd;
    if (this.deps.mode === 'live') {
      start = await this.cashUsd(null);
    }
    return this.deps.repos.accounts.ensure(this.deps.mode, start, this.now());
  }

  private async cashUsd(account: AccountRow | null): Promise<number> {
    if (this.deps.mode === 'paper') return account?.cashUsd ?? this.deps.startingBalanceUsd;
    if (this.liveCash && Date.now() - this.liveCash.at < 20_000) return this.liveCash.value;
    if (!this.deps.executor.walletCashUsd) throw new Error('live executor cannot report wallet balance');
    const value = await this.deps.executor.walletCashUsd();
    this.liveCash = { value, at: Date.now() };
    return value;
  }

  invalidateCash(): void {
    this.liveCash = null;
  }

  async state(): Promise<PortfolioState> {
    const account = (await this.deps.repos.accounts.get(this.deps.mode)) ?? (await this.init());
    const open = await this.deps.repos.positions.listOpen(this.deps.mode);
    const tokens = new Map(
      (await this.deps.repos.tokens.getMany(open.map((o) => o.position.tokenId))).map((t) => [t.id, t]),
    );
    let cash: number;
    try {
      cash = await this.cashUsd(account);
    } catch (err) {
      // Fail closed: if the live balance is unknown, report zero spendable cash.
      this.deps.logger.error({ err: errorMessage(err) }, 'could not read wallet balance; treating cash as 0');
      cash = 0;
    }
    const marks: PositionMark[] = open.map(({ position }) => {
      const token = tokens.get(position.tokenId) as TokenRow;
      const price = position.lastPriceUsd ?? token?.priceUsd ?? null;
      const mark = price !== null ? position.quantity * price : position.costBasisUsd;
      const exit =
        estimateExitValueUsd(
          position.quantity,
          price,
          token?.liquidityUsd ?? null,
          this.deps.dexFeePct,
          sellTaxOf(token?.latestSnapshot),
        ) ?? 0;
      return {
        position,
        token,
        priceUsd: price,
        markValueUsd: mark,
        exitValueUsd: exit,
        unrealizedPnlUsd: mark - position.costBasisUsd,
      };
    });
    const markEquity = cash + marks.reduce((a, m) => a + m.markValueUsd, 0);
    const conservative = cash + marks.reduce((a, m) => a + m.exitValueUsd, 0);
    const peak = Math.max(account.peakEquityUsd, conservative);
    const drawdownPct = peak > 0 ? ((peak - conservative) / peak) * 100 : 0;
    const daily = conservative - account.dayStartEquityUsd;
    return {
      mode: this.deps.mode,
      equityUsd: conservative,
      markEquityUsd: markEquity,
      cashUsd: cash,
      peakEquityUsd: peak,
      dayStartEquityUsd: account.dayStartEquityUsd,
      halted: account.halted,
      haltReason: account.haltReason,
      unrealizedPnlUsd: marks.reduce((a, m) => a + m.unrealizedPnlUsd, 0),
      realizedPnlUsd: account.realizedPnlUsd,
      dailyPnlUsd: daily,
      dailyPnlPct: account.dayStartEquityUsd > 0 ? (daily / account.dayStartEquityUsd) * 100 : 0,
      drawdownPct,
      maxDrawdownPct: Math.max(account.maxDrawdownPct, drawdownPct),
      startingBalanceUsd: account.startingBalanceUsd,
      marks,
    };
  }

  /** Paper: move simulated cash. Live: cash is re-read from chain; only realized P/L is tracked. */
  async applyCash(deltaUsd: number, realizedDeltaUsd: number): Promise<void> {
    if (this.deps.mode === 'paper') {
      await this.deps.repos.accounts.adjustCash('paper', deltaUsd, realizedDeltaUsd);
    } else {
      await this.deps.repos.accounts.adjustCash('live', 0, realizedDeltaUsd);
      this.invalidateCash();
    }
  }

  async halt(reason: string, clearsOnNewDay: boolean): Promise<void> {
    await this.deps.repos.accounts.update(this.deps.mode, {
      halted: true,
      haltReason: reason,
      haltedAt: this.now(),
      haltClearsOnNewDay: clearsOnNewDay,
    });
    await this.deps.repos.events.log('warn', 'risk', `trading halted: ${reason}`);
    this.deps.logger.warn({ reason }, 'trading halted');
  }

  async resume(): Promise<void> {
    const s = await this.state();
    await this.deps.repos.accounts.update(this.deps.mode, {
      halted: false,
      haltReason: null,
      haltedAt: null,
      haltClearsOnNewDay: false,
      // Reset the drawdown reference so the same breach doesn't immediately re-halt.
      peakEquityUsd: s.equityUsd,
    });
    await this.deps.repos.events.log('info', 'risk', 'trading resumed by administrator');
  }

  /**
   * Periodic bookkeeping: day rollover, peak/drawdown tracking, and hard-limit enforcement
   * (daily loss -> halt until next UTC day; max drawdown -> halt until manual resume).
   */
  async tick(limits: RiskLimits): Promise<PortfolioState> {
    const now = this.now();
    let account = (await this.deps.repos.accounts.get(this.deps.mode)) ?? (await this.init());
    let s = await this.state();
    const today = utcDay(now);
    if (account.day !== today) {
      account = await this.deps.repos.accounts.update(this.deps.mode, {
        day: today,
        dayStartEquityUsd: s.equityUsd,
        ...(account.halted && account.haltClearsOnNewDay
          ? { halted: false, haltReason: null, haltedAt: null, haltClearsOnNewDay: false }
          : {}),
      });
      s = await this.state();
    }
    await this.deps.repos.accounts.update(this.deps.mode, {
      peakEquityUsd: s.peakEquityUsd,
      maxDrawdownPct: s.maxDrawdownPct,
      ...(this.deps.mode === 'live' ? { cashUsd: s.cashUsd } : {}),
    });

    if (!s.halted) {
      const floor = -(account.dayStartEquityUsd * limits.maxDailyLossPercent) / 100;
      if (s.dailyPnlUsd <= floor) {
        await this.halt(
          `daily loss limit reached (${s.dailyPnlUsd.toFixed(2)} USD <= ${floor.toFixed(2)} USD)`,
          true,
        );
        await this.deps.alerts.raise({
          type: 'DAILY_LOSS_LIMIT',
          severity: 'critical',
          title: 'Daily loss limit reached',
          message: `Daily P/L ${s.dailyPnlUsd.toFixed(2)} USD breached the ${limits.maxDailyLossPercent}% limit. New entries are halted until the next UTC day.`,
          data: { dailyPnlUsd: s.dailyPnlUsd, limitPct: limits.maxDailyLossPercent },
          dedupeKey: `DAILY_LOSS_LIMIT:${today}`,
        });
      } else if (s.drawdownPct >= limits.maxDrawdownPercent) {
        await this.halt(
          `max drawdown reached (${s.drawdownPct.toFixed(2)}% >= ${limits.maxDrawdownPercent}%)`,
          false,
        );
        await this.deps.alerts.raise({
          type: 'MAX_DRAWDOWN',
          severity: 'critical',
          title: 'Maximum drawdown reached',
          message: `Drawdown ${s.drawdownPct.toFixed(2)}% breached the ${limits.maxDrawdownPercent}% limit. Trading is halted until manually resumed.`,
          data: { drawdownPct: s.drawdownPct },
          dedupeKey: `MAX_DRAWDOWN:${today}`,
        });
      }
      s = await this.state();
    }
    return s;
  }

  async recordMetrics(s: PortfolioState, winRate: number | null): Promise<void> {
    await this.deps.repos.performance.insert({
      mode: this.deps.mode,
      ts: this.now(),
      equityUsd: s.markEquityUsd,
      conservativeEquityUsd: s.equityUsd,
      cashUsd: s.cashUsd,
      unrealizedPnlUsd: s.unrealizedPnlUsd,
      realizedPnlUsd: s.realizedPnlUsd,
      dailyPnlUsd: s.dailyPnlUsd,
      drawdownPct: s.drawdownPct,
      openPositions: s.marks.length,
      winRate,
    });
    this.deps.bus.publish({
      type: 'performance',
      data: {
        equityUsd: s.markEquityUsd,
        dailyPnlUsd: s.dailyPnlUsd,
        drawdownPct: s.drawdownPct,
        halted: s.halted,
      },
    });
  }

  async summary(): Promise<PerformanceSummary> {
    const s = await this.state();
    const stats = await this.deps.repos.positions.closedStats(this.deps.mode);
    const curve = await this.deps.repos.performance.curve(this.deps.mode, 500);
    const daily = await this.deps.repos.positions.dailyRealized(this.deps.mode, 30);
    const trades = await this.deps.repos.trades.countFilled(this.deps.mode);
    return {
      mode: this.deps.mode,
      startingBalanceUsd: s.startingBalanceUsd,
      cashUsd: s.cashUsd,
      equityUsd: s.markEquityUsd,
      conservativeEquityUsd: s.equityUsd,
      peakEquityUsd: s.peakEquityUsd,
      realizedPnlUsd: s.realizedPnlUsd,
      unrealizedPnlUsd: s.unrealizedPnlUsd,
      dailyPnlUsd: s.dailyPnlUsd,
      dailyPnlPct: s.dailyPnlPct,
      drawdownPct: s.drawdownPct,
      maxDrawdownPct: s.maxDrawdownPct,
      totalTrades: trades,
      closedPositions: stats.closed,
      winningTrades: stats.wins,
      losingTrades: stats.losses,
      winRate: stats.closed > 0 ? stats.wins / stats.closed : null,
      averageWinUsd: stats.wins > 0 ? stats.grossProfit / stats.wins : null,
      averageLossUsd: stats.losses > 0 ? -stats.grossLoss / stats.losses : null,
      profitFactor: stats.grossLoss > 0 ? stats.grossProfit / stats.grossLoss : null,
      openPositions: s.marks.length,
      halted: s.halted,
      haltReason: s.haltReason,
      equityCurve: curve,
      dailyPnl: daily,
    };
  }
}
