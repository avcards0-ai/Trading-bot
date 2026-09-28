import type { Chain, LoopStatus, MarketData } from '@memeguard/shared';
import type { Providers } from '../adapters';
import type { MarketQuote } from '../adapters/types';
import { marketAlerts } from '../alerts/rules';
import type { AlertService } from '../alerts/alertService';
import type { StrategyStore } from '../config/strategyStore';
import type { Repositories } from '../db/repositories';
import { toPosition } from '../db/repositories';
import { errorMessage } from '../lib/errors';
import type { EventBus } from '../lib/events';
import type { Logger } from '../lib/logger';
import { evaluateExit } from '../strategy/strategy';
import type { Portfolio } from '../trading/portfolio';
import type { TradeService } from '../trading/tradeService';
import { Loop } from './loop';
import type { AnalysisTrigger, DecisionPipeline } from './pipeline';
import { WorkQueue } from './queue';

const PRIORITY: Record<AnalysisTrigger, number> = { manual: 100, monitor: 80, discovery: 50, watchlist: 10 };

export interface EngineSettings {
  discoveryIntervalMs: number;
  monitorIntervalMs: number;
  watchlistIntervalMs: number;
  watchlistBatchSize: number;
  watchlistMaxAgeHours: number;
  metricsIntervalMs: number;
  securityRefreshMs: number;
  analysisConcurrency: number;
  maxQueueSize: number;
}

interface Job {
  trigger: AnalysisTrigger;
  forceSecurityRefresh: boolean;
}

/**
 * The autonomous trading engine:
 *  - discovery loop: pulls newly launched pools and queues them for analysis
 *  - analysis queue: runs the decision pipeline with a concurrency cap
 *  - position monitor: fast market refresh of open positions, exit rules, market alerts
 *  - watchlist loop: re-analyses young tokens (they may mature past MIN_TOKEN_AGE, or turn bad)
 *  - metrics loop: equity/drawdown bookkeeping and hard-limit halts
 */
export class TradingEngine {
  private readonly queue: WorkQueue<Job>;
  /** Discovery and watchlist: create NEW entries. Controlled by start()/stop(). */
  private readonly tradingLoops: Loop[];
  /** Position monitor and metrics: protect open positions. Always on until shutdown(). */
  private readonly protectiveLoops: Loop[];
  private running = false;
  private protecting = false;
  private lastSecurityCheck = new Map<number, number>();
  private lastMarket = new Map<number, MarketData>();

  constructor(
    private readonly d: {
      repos: Repositories;
      providers: Providers;
      pipeline: DecisionPipeline;
      portfolio: Portfolio;
      tradeService: TradeService;
      strategyStore: StrategyStore;
      alerts: AlertService;
      bus: EventBus;
      logger: Logger;
      settings: EngineSettings;
    },
  ) {
    const s = d.settings;
    this.queue = new WorkQueue<Job>(
      async (item) => {
        await this.d.pipeline.analyze({
          tokenId: item.key,
          trigger: item.payload.trigger,
          // New entries only while the engine runs; exits on held tokens always execute.
          allowTrade: this.running,
          forceSecurityRefresh: item.payload.forceSecurityRefresh,
        });
      },
      {
        concurrency: s.analysisConcurrency,
        maxSize: s.maxQueueSize,
        logger: d.logger,
        onDrop: (item) => {
          void this.d.repos.events.log('warn', 'skipped', 'analysis queue full: opportunity dropped', { trigger: item.payload.trigger }, item.key);
        },
      },
    );
    this.tradingLoops = [
      new Loop('discovery', s.discoveryIntervalMs, () => this.discover(), d.logger),
      new Loop('watchlist', s.watchlistIntervalMs, () => this.watchlist(), d.logger),
    ];
    this.protectiveLoops = [
      new Loop('position-monitor', s.monitorIntervalMs, () => this.monitor(), d.logger),
      new Loop('metrics', s.metricsIntervalMs, () => this.metrics(), d.logger),
    ];
  }

  get isRunning(): boolean {
    return this.running;
  }

  queueStats() {
    return { pending: this.queue.pending, inFlight: this.queue.inFlight };
  }

  loopStatus(): LoopStatus[] {
    return [...this.protectiveLoops, ...this.tradingLoops].map((l) => l.snapshot());
  }

  /** Starts position protection (monitor + metrics). Called at boot regardless of autostart. */
  startProtection(): void {
    if (this.protecting) return;
    this.protecting = true;
    this.queue.resume();
    for (const l of this.protectiveLoops) l.start(true);
  }

  /** Starts discovery and new entries. */
  async start(): Promise<void> {
    this.startProtection();
    if (this.running) return;
    this.running = true;
    for (const l of this.tradingLoops) l.start(true);
    await this.d.repos.events.log('info', 'engine', 'engine started').catch(() => undefined);
    this.d.bus.publish({ type: 'status', data: { engineRunning: true, halted: false, haltReason: null } });
    this.d.logger.info('trading engine started');
  }

  /**
   * Stops discovery and new entries. Open positions keep being monitored and their stop-loss /
   * rug-exit rules keep executing — stopping the engine never leaves positions unprotected.
   */
  async stop(): Promise<void> {
    if (!this.running) return;
    this.running = false;
    for (const l of this.tradingLoops) l.stop();
    // Awaited: closing the database with a write in flight must never happen.
    await this.d.repos.events.log('info', 'engine', 'engine stopped (position protection remains active)').catch(() => undefined);
    this.d.bus.publish({ type: 'status', data: { engineRunning: false, halted: false, haltReason: null } });
    this.d.logger.info('trading engine stopped; position protection remains active');
  }

  /** Full shutdown (process exit). */
  async shutdown(): Promise<void> {
    await this.stop();
    for (const l of this.protectiveLoops) l.stop();
    this.protecting = false;
    this.queue.stop();
    await this.queue.drain(10_000);
    // Let in-flight loop iterations (which may be mid-write) finish before the DB closes.
    await Promise.all([...this.protectiveLoops, ...this.tradingLoops].map((l) => l.idle(10_000)));
  }

  enqueue(tokenId: number, trigger: AnalysisTrigger, forceSecurityRefresh = false): boolean {
    return this.queue.enqueue(tokenId, { trigger, forceSecurityRefresh }, PRIORITY[trigger]);
  }

  async drain(timeoutMs?: number): Promise<void> {
    await this.queue.drain(timeoutMs);
  }

  /** Test/ops hook: run a loop iteration immediately. */
  async runOnce(name: 'discovery' | 'position-monitor' | 'watchlist' | 'metrics'): Promise<void> {
    await [...this.protectiveLoops, ...this.tradingLoops].find((l) => l.name === name)?.tick();
  }

  // -------------------------------------------------------------------------

  private async discover(): Promise<void> {
    const cfg = this.d.strategyStore.get();
    let found = 0;
    let queued = 0;
    for (const chain of cfg.strategy.chains) {
      for (const provider of this.d.providers.discovery.filter((p) => p.supports(chain))) {
        let pairs;
        try {
          pairs = await provider.discover(chain);
        } catch (err) {
          this.d.logger.warn({ provider: provider.name, chain, err: errorMessage(err) }, 'discovery failed');
          await this.d.repos.events.log('warn', 'discovery', `${provider.name}/${chain}: ${errorMessage(err)}`);
          continue;
        }
        for (const p of pairs) {
          found += 1;
          const { row, created } = await this.d.repos.tokens.upsertDiscovered({
            chain,
            address: p.tokenAddress,
            name: p.name,
            symbol: p.symbol,
            pairAddress: p.pairAddress,
            dexId: p.dexId,
            pairCreatedAt: p.pairCreatedAt,
            discoveredVia: p.source,
          });
          if (created || !row.lastAnalyzedAt) {
            if (this.enqueue(row.id, 'discovery')) queued += 1;
          }
        }
      }
    }
    if (found > 0) this.d.logger.info({ found, queued }, 'discovery cycle complete');
  }

  private async watchlist(): Promise<void> {
    const s = this.d.settings;
    const mode = this.d.portfolio.mode;
    const open = await this.d.repos.positions.listOpen(mode);
    const heldIds = open.map((o) => o.position.tokenId);
    const expired = await this.d.repos.tokens.expireOld(s.watchlistMaxAgeHours, heldIds);
    if (expired > 0) this.d.logger.debug({ expired }, 'expired stale watchlist tokens');
    const due = await this.d.repos.tokens.dueForReanalysis({
      maxAgeHours: s.watchlistMaxAgeHours,
      olderThan: new Date(Date.now() - s.watchlistIntervalMs),
      limit: s.watchlistBatchSize,
      excludeIds: [...heldIds, ...this.queue.keys()],
    });
    for (const t of due) {
      // Confirmed scams are re-checked rarely; everything else on the normal cadence.
      if (t.rugScore !== null && t.rugScore >= 90 && t.lastAnalyzedAt && Date.now() - t.lastAnalyzedAt.getTime() < s.securityRefreshMs * 3) continue;
      this.enqueue(t.id, 'watchlist');
    }
  }

  private async monitor(): Promise<void> {
    const mode = this.d.portfolio.mode;
    const open = await this.d.repos.positions.listOpen(mode);
    if (open.length === 0) return;
    const cfg = this.d.strategyStore.get();
    const byChain = new Map<Chain, typeof open>();
    for (const o of open) {
      const list = byChain.get(o.token.chain as Chain) ?? [];
      list.push(o);
      byChain.set(o.token.chain as Chain, list);
    }
    for (const [chain, list] of byChain) {
      let quotes: Map<string, MarketQuote>;
      try {
        quotes = await this.d.providers.market.getMarkets(chain, list.map((o) => o.token.address));
      } catch (err) {
        this.d.logger.warn({ chain, err: errorMessage(err) }, 'monitor market refresh failed');
        continue;
      }
      for (const { position, token } of list) {
        const q = quotes.get(token.address);
        const market = q?.market ?? null;
        const prev = this.lastMarket.get(token.id) ?? null;
        if (market) {
          this.lastMarket.set(token.id, market);
          await this.d.repos.history.recordMarket(token.id, market);
          await this.d.repos.tokens.applyMarket(token.id, market);
          const price = market.priceUsd;
          if (price !== null) {
            const highest = Math.max(position.highestPriceUsd, price);
            await this.d.repos.positions.updateMark(position.id, price, highest);
            position.lastPriceUsd = price;
            position.highestPriceUsd = highest;
          }
          const ref = { chain: token.chain, address: token.address, symbol: token.symbol };
          for (const c of marketAlerts(prev, market)) {
            await this.d.alerts.raise({ ...c, tokenId: token.id, token: ref, dedupeKey: `${c.type}:${token.id}`, cooldownSeconds: 300 });
          }
          this.d.bus.publish({ type: 'position', data: toPosition(position, ref, price) });
        }

        const report = await this.d.repos.risk.latest(token.id);
        const exit = evaluateExit(
          {
            entryPriceUsd: position.entryPriceUsd,
            stopLossPriceUsd: position.stopLossPriceUsd,
            takeProfitPriceUsd: position.takeProfitPriceUsd,
            trailingStopPercent: position.trailingStopPercent,
            highestPriceUsd: position.highestPriceUsd,
            entryLiquidityUsd: position.entryLiquidityUsd,
            openedAt: position.openedAt,
          },
          market?.priceUsd ?? position.lastPriceUsd,
          market?.liquidityUsd ?? null,
          report,
          cfg.strategy,
          new Date(),
        );
        if (exit.action === 'SELL' && exit.reason) {
          this.d.logger.info({ positionId: position.id, reason: exit.reason }, 'exit rule triggered');
          await this.d.tradeService.closePosition({ positionId: position.id, reason: exit.reason, detail: exit.reasons.join(' '), market });
          continue;
        }
        // Periodic full re-analysis (security + rug score) of held tokens.
        const last = this.lastSecurityCheck.get(token.id) ?? 0;
        if (Date.now() - last > this.d.settings.securityRefreshMs) {
          this.lastSecurityCheck.set(token.id, Date.now());
          this.enqueue(token.id, 'monitor', true);
        }
      }
    }
  }

  private async metrics(): Promise<void> {
    const cfg = this.d.strategyStore.get();
    const state = await this.d.portfolio.tick(cfg.limits);
    const stats = await this.d.repos.positions.closedStats(this.d.portfolio.mode);
    await this.d.portfolio.recordMetrics(state, stats.closed > 0 ? stats.wins / stats.closed : null);
    if (state.halted) {
      this.d.bus.publish({ type: 'status', data: { engineRunning: this.running, halted: true, haltReason: state.haltReason } });
    }
  }
}
