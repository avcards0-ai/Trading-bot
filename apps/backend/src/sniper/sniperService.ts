import type {
  Decision,
  PipelineStage,
  RiskCheckName,
  RiskCheckResult,
  Scalar,
  SniperAttempt,
  SniperOutcome,
  SniperSettingsView,
  SniperStatus,
  StageResult,
  TradingMode,
} from '@memeguard/shared';
import type { JupiterAdapter } from '../adapters/jupiter';
import { contractFromMint, parseMintAccount } from '../adapters/solana/inspector';
import type { SolanaRpc } from '../adapters/solana/rpc';
import type { WalletProfiler } from '../adapters/types';
import type { SniperConfig } from '../config/env';
import type { StrategyStore } from '../config/strategyStore';
import { toPosition, type Repositories, type TokenRow } from '../db/repositories';
import { Loop } from '../engine/loop';
import { estimateBuyImpactPct } from '../execution/amm';
import { errorMessage } from '../lib/errors';
import type { EventBus } from '../lib/events';
import type { Logger } from '../lib/logger';
import { fmtPrice, round } from '../lib/math';
import { evaluateExit } from '../strategy/strategy';
import { closeWithDecision } from '../trading/exitDecision';
import type { Portfolio } from '../trading/portfolio';
import type { TradeService } from '../trading/tradeService';
import { QUOTE_MINTS, liquiditySecurity, parseLaunchTransaction, type ParsedLaunch } from './launchParser';
import { LaunchListener, type LaunchSignal, type WebSocketFactory } from './listener';
import { QuotePricer, marketFromReserves, readReserves } from './pool';

export interface SniperDeps {
  config: SniperConfig;
  mode: TradingMode;
  dexFeePct: number;
  repos: Repositories;
  rpc: SolanaRpc | null;
  jupiter: JupiterAdapter;
  walletProfiler: WalletProfiler | null;
  tradeService: TradeService;
  portfolio: Portfolio;
  strategyStore: StrategyStore;
  bus: EventBus;
  logger: Logger;
  wsFactory?: WebSocketFactory;
  sleep?: (ms: number) => Promise<void>;
}

/** Where each check is reported in the decision's pipeline view. */
const STAGE_OF: Partial<Record<RiskCheckName, PipelineStage>> = {
  LAUNCH_FRESH: 'DISCOVERY',
  LAUNCH_PARSED: 'ON_CHAIN',
  MINT_AUTHORITY_REVOKED: 'CONTRACT',
  FREEZE_AUTHORITY_REVOKED: 'CONTRACT',
  NO_DANGEROUS_EXTENSIONS: 'CONTRACT',
  CREATOR_HOLDINGS: 'WALLET',
  TOP_HOLDER: 'WALLET',
  CREATOR_NO_RUG_HISTORY: 'WALLET',
  CREATOR_WALLET_AGE: 'WALLET',
  LIQUIDITY_SECURED: 'LIQUIDITY',
  MIN_LIQUIDITY: 'LIQUIDITY',
};
const STAGE_ORDER: PipelineStage[] = [
  'DISCOVERY',
  'ON_CHAIN',
  'CONTRACT',
  'WALLET',
  'LIQUIDITY',
  'RISK_CHECK',
];

interface PoolMeta {
  source: string;
  signature: string;
  baseVault: string;
  quoteVault: string;
  quoteMint: string;
  launchedAtMs: number;
  launchPriceUsd: number | null;
}

/** Thrown by `need` when a check fails; ends the checklist (first failure wins). */
class CheckFailed extends Error {
  constructor(readonly check: RiskCheckName) {
    super(check);
  }
}

const median = (xs: number[]): number | null => {
  if (xs.length === 0) return null;
  const s = [...xs].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? (s[m] as number) : ((s[m - 1] as number) + (s[m] as number)) / 2;
};

/**
 * Launch sniper (paper only). Listens for new pools in real time, runs a fail-closed checklist
 * limited to what is knowable at launch, and simulates small, short-lived entries with their own
 * budget. Its positions are priced from the pool on-chain and exited by a fast monitor.
 * It never front-runs pending transactions: it only reacts to confirmed pool creations.
 */
export class SniperService {
  private listener: LaunchListener | null = null;
  private readonly queue: LaunchSignal[] = [];
  private active = 0;
  private accepting = false;
  private readonly inFlight = new Set<Promise<unknown>>();
  private readonly monitorLoop: Loop;
  private readonly pricer: QuotePricer;
  private readonly attempts: SniperAttempt[] = [];
  private readonly lastExitFailure = new Map<number, number>();
  private readonly stats = {
    since: new Date().toISOString(),
    launchesSeen: 0,
    dropped: 0,
    analysed: 0,
    bought: 0,
    rejected: 0,
    failed: 0,
    rejectionsByCheck: {} as Partial<Record<RiskCheckName, number>>,
  };

  constructor(private readonly d: SniperDeps) {
    this.pricer = new QuotePricer(d.jupiter, d.logger);
    this.monitorLoop = new Loop('sniper-monitor', d.config.monitorIntervalMs, () => this.monitor(), d.logger);
  }

  /** Paper only: config validation already refuses live mode; this is the second guard. */
  get enabled(): boolean {
    return this.d.config.enabled && this.d.rpc !== null && this.d.mode === 'paper';
  }

  loopStatus() {
    return this.enabled ? [this.monitorLoop.snapshot()] : [];
  }

  /** Protective monitor for open sniper positions; runs even while new entries are stopped. */
  startProtection(): void {
    if (this.enabled) this.monitorLoop.start(true);
  }

  /** Starts listening for launches and taking new (paper) entries. */
  start(): void {
    if (!this.enabled || this.accepting) return;
    this.accepting = true;
    this.listener ??= new LaunchListener({
      url: this.d.config.wsUrl as string,
      programs: this.d.config.sources,
      onLaunch: (s) => this.submit(s),
      logger: this.d.logger,
      wsFactory: this.d.wsFactory,
    });
    this.listener.start();
    this.d.logger.info(
      { sources: this.d.config.sources.map((p) => p.name) },
      'launch sniper started (paper)',
    );
  }

  /** Stops new entries. Open sniper positions stay protected by the monitor. */
  stop(): void {
    if (!this.accepting) return;
    this.accepting = false;
    this.listener?.stop();
    this.stats.dropped += this.queue.length;
    this.queue.length = 0;
    this.d.logger.info('launch sniper stopped; open sniper positions remain protected');
  }

  async shutdown(): Promise<void> {
    this.stop();
    this.monitorLoop.stop();
    await this.monitorLoop.idle(10_000);
    const until = Date.now() + 10_000;
    while (this.inFlight.size > 0 && Date.now() < until) await new Promise((r) => setTimeout(r, 25));
  }

  /** Queues a detected launch. Old or overflowing launches are dropped: late snipes are pointless. */
  submit(signal: LaunchSignal): void {
    this.stats.launchesSeen += 1;
    if (!this.accepting) return;
    if (this.queue.length >= this.d.config.queueSize) {
      this.queue.shift();
      this.stats.dropped += 1;
    }
    this.queue.push(signal);
    this.pump();
  }

  private pump(): void {
    while (this.accepting && this.active < this.d.config.concurrency && this.queue.length > 0) {
      const signal = this.queue.shift() as LaunchSignal;
      if (Date.now() - signal.detectedAt > this.d.config.maxLaunchAgeSeconds * 1000) {
        this.stats.dropped += 1;
        continue;
      }
      this.active += 1;
      const p = this.run(signal, true)
        .catch((err) => this.d.logger.error({ err: errorMessage(err) }, 'sniper attempt crashed'))
        .finally(() => {
          this.active -= 1;
          this.inFlight.delete(p);
          this.pump();
        });
      this.inFlight.add(p);
    }
  }

  private async sleep(ms: number): Promise<void> {
    await (this.d.sleep ?? ((t: number) => new Promise((r) => setTimeout(r, t))))(ms);
  }

  // ------------------------------------------------------------------ entry

  /** Analyses one launch right away (bypassing the queue) and returns what happened. */
  async analyseLaunch(signal: LaunchSignal): Promise<SniperAttempt> {
    this.stats.launchesSeen += 1;
    return this.run(signal, false);
  }

  /** Runs the checklist for one launch and (paper-)buys only if every check passes. */
  private async run(signal: LaunchSignal, fromStream: boolean): Promise<SniperAttempt> {
    const cfg = this.d.config;
    const attempt: SniperAttempt = {
      signature: signal.signature,
      source: signal.source,
      mint: null,
      tokenId: null,
      symbol: null,
      launchedAt: null,
      detectedAt: new Date(signal.detectedAt).toISOString(),
      decidedAt: null,
      outcome: 'rejected',
      failedCheck: null,
      reason: '',
      checks: [],
      secondsAfterLaunch: null,
      launchPriceUsd: null,
      entryPriceUsd: null,
      entryPremiumPct: null,
      liquidityUsd: null,
      positionId: null,
      decisionId: null,
    };
    const need = (check: RiskCheckName, passed: boolean, value: Scalar, limit: Scalar, message: string) => {
      attempt.checks.push({ check, passed, value, limit, message });
      if (!passed) throw new CheckFailed(check);
    };
    const rpc = this.d.rpc;
    let token: TokenRow | null = null;
    let launchAt = signal.detectedAt;
    const factors: Record<string, number | null> = {};

    try {
      if (!rpc) throw new Error('Solana RPC is not configured');
      await this.checkBudget(need);

      const tx = await this.fetchTransaction(rpc, signal.signature);
      const parsed = tx
        ? parseLaunchTransaction(signal.signature, tx)
        : ({ ok: false, reason: 'pool-creation transaction not found' } as const);
      if (!parsed.ok) {
        need('LAUNCH_PARSED', false, null, null, parsed.reason);
        return attempt; // unreachable: need() throws
      }
      const launch = parsed.launch;
      const quote = QUOTE_MINTS[launch.quoteMint]?.symbol ?? 'quote';
      need(
        'LAUNCH_PARSED',
        true,
        launch.mint,
        null,
        `New pool: ${fmtPrice(launch.baseReserve)} tokens against ${fmtPrice(launch.quoteReserve)} ${quote}.`,
      );
      attempt.mint = launch.mint;
      if (launch.blockTime) launchAt = launch.blockTime * 1000;
      attempt.launchedAt = new Date(launchAt).toISOString();
      token = (
        await this.d.repos.tokens.upsertDiscovered({
          chain: 'solana',
          address: launch.mint,
          dexId: signal.source,
          pairCreatedAt: new Date(launchAt),
          discoveredVia: 'sniper',
        })
      ).row;
      attempt.tokenId = token.id;
      attempt.symbol = token.symbol;
      const held = await this.d.repos.positions.openForToken(this.d.mode, token.id);
      need(
        'NO_DUPLICATE_POSITION',
        held === null,
        held?.id ?? null,
        null,
        held ? 'A position in this token is already open.' : 'No open position in this token.',
      );

      const age = (Date.now() - launchAt) / 1000;
      need(
        'LAUNCH_FRESH',
        age <= cfg.maxLaunchAgeSeconds,
        round(age, 1),
        cfg.maxLaunchAgeSeconds,
        `Launch is ${age.toFixed(1)}s old (limit ${cfg.maxLaunchAgeSeconds}s).`,
      );

      const lp = liquiditySecurity(launch);
      need('LIQUIDITY_SECURED', lp.secured, lp.walletHeldPercent, 0, lp.message);

      const quoteUsd = await this.pricer.usd(launch.quoteMint);
      const liquidityUsd = quoteUsd === null ? null : 2 * launch.quoteReserve * quoteUsd;
      attempt.liquidityUsd = liquidityUsd;
      attempt.launchPriceUsd = quoteUsd === null ? null : launch.launchPriceQuote * quoteUsd;
      factors.liquidityUsd = liquidityUsd;
      need(
        'MIN_LIQUIDITY',
        liquidityUsd !== null && liquidityUsd >= cfg.minLiquidityUsd,
        liquidityUsd === null ? null : round(liquidityUsd, 0),
        cfg.minLiquidityUsd,
        liquidityUsd === null
          ? `${quote} price unavailable, so the pool cannot be valued.`
          : `Pool liquidity $${liquidityUsd.toFixed(0)} (minimum $${cfg.minLiquidityUsd}).`,
      );

      const mintAccount = await rpc.getParsedAccount(launch.mint);
      const mint = mintAccount ? parseMintAccount(mintAccount) : null;
      if (!mint) {
        need('MINT_AUTHORITY_REVOKED', false, null, null, 'Mint account could not be read.');
        return attempt;
      }
      need(
        'MINT_AUTHORITY_REVOKED',
        mint.info.mintAuthority === null,
        mint.info.mintAuthority,
        null,
        mint.info.mintAuthority === null
          ? 'No one can mint more tokens.'
          : 'The creator can still mint unlimited new tokens.',
      );
      need(
        'FREEZE_AUTHORITY_REVOKED',
        mint.info.freezeAuthority === null,
        mint.info.freezeAuthority,
        null,
        mint.info.freezeAuthority === null
          ? 'No one can freeze holders.'
          : 'The creator can freeze your tokens so you cannot sell.',
      );
      const { contract } = contractFromMint(mint.program, mint.info);
      const transferTax = contract.transferTaxPct ?? 0;
      const dangerous = [...(contract.suspiciousFunctions ?? [])];
      if (mint.program === 'unknown') dangerous.push('mint is not owned by an SPL token program');
      if (transferTax > 5) dangerous.push(`transfer tax ${transferTax}%`);
      need(
        'NO_DANGEROUS_EXTENSIONS',
        dangerous.length === 0,
        dangerous.length,
        0,
        dangerous.length === 0
          ? 'No dangerous token features.'
          : `Dangerous features: ${dangerous.join('; ')}.`,
      );

      const supply = Number(mint.info.supply) / 10 ** mint.info.decimals;
      const creatorPct = supply > 0 ? (launch.creatorTokenAmount / supply) * 100 : 100;
      factors.creatorPercent = creatorPct;
      need(
        'CREATOR_HOLDINGS',
        creatorPct <= cfg.maxCreatorPercent,
        round(creatorPct, 2),
        cfg.maxCreatorPercent,
        `Creator holds ${creatorPct.toFixed(2)}% of supply (limit ${cfg.maxCreatorPercent}%).`,
      );

      const largest = await rpc.getTokenLargestAccounts(launch.mint);
      const baseVault = launch.baseVault;
      const topPct = largest
        .filter((a) => a.address !== baseVault)
        .reduce(
          (m, a) => Math.max(m, supply > 0 ? (Number(a.amount) / 10 ** a.decimals / supply) * 100 : 100),
          0,
        );
      factors.topHolderPercent = topPct;
      need(
        'TOP_HOLDER',
        topPct <= cfg.maxTopHolderPercent,
        round(topPct, 2),
        cfg.maxTopHolderPercent,
        `Largest wallet outside the pool holds ${topPct.toFixed(2)}% (limit ${cfg.maxTopHolderPercent}%).`,
      );

      const flagged = await this.d.repos.tokens.countFlaggedByDeployer('solana', launch.creator);
      need(
        'CREATOR_NO_RUG_HISTORY',
        flagged === 0,
        flagged,
        0,
        flagged === 0
          ? 'No earlier token by this creator was flagged by this bot.'
          : `This creator launched ${flagged} token(s) this bot flagged as rugged or critical-risk.`,
      );

      if (cfg.minCreatorWalletAgeHours > 0) {
        const profile = this.d.walletProfiler
          ? (await this.d.walletProfiler.profile('solana', [launch.creator])).get(launch.creator)
          : undefined;
        const ageHours = profile?.createdAt ? (Date.now() - profile.createdAt.getTime()) / 3_600_000 : null;
        factors.creatorWalletAgeHours = ageHours;
        need(
          'CREATOR_WALLET_AGE',
          ageHours !== null && ageHours >= cfg.minCreatorWalletAgeHours,
          ageHours === null ? null : round(ageHours, 1),
          cfg.minCreatorWalletAgeHours,
          ageHours === null
            ? 'Creator wallet age unknown.'
            : `Creator wallet is ${ageHours.toFixed(1)}h old${profile?.ageIsLowerBound ? ' or more' : ''} (minimum ${cfg.minCreatorWalletAgeHours}h).`,
        );
      }

      const impact = estimateBuyImpactPct(cfg.positionUsd, liquidityUsd as number, this.d.dexFeePct);
      factors.priceImpactPct = impact;
      need(
        'PRICE_IMPACT',
        impact <= cfg.maxPriceImpactPercent,
        round(impact, 3),
        cfg.maxPriceImpactPercent,
        `A $${cfg.positionUsd} buy moves the price about ${impact.toFixed(2)}% (limit ${cfg.maxPriceImpactPercent}%).`,
      );

      const route = await this.sellRoute(launch.mint, liquidityUsd);
      need('SELL_ROUTE', route.ok, route.ok, true, route.message);

      const ageNow = (Date.now() - launchAt) / 1000;
      need(
        'LAUNCH_FRESH',
        ageNow <= cfg.maxLaunchAgeSeconds,
        round(ageNow, 1),
        cfg.maxLaunchAgeSeconds,
        `Checks finished ${ageNow.toFixed(1)}s after launch (limit ${cfg.maxLaunchAgeSeconds}s).`,
      );

      // Re-check the budget and buy under a lock, so concurrent launches cannot both slip
      // under a position or trade limit. Only failures are added to the report here.
      const enteredToken = token;
      await this.withEntryLock(async () => {
        // The engine may have been stopped while this launch was being checked.
        if (fromStream && !this.accepting) {
          need('SNIPER_BUDGET', false, false, true, 'The sniper was stopped before the buy.');
        }
        await this.checkBudget((c, ok, v, l, m) => {
          if (!ok) need(c, ok, v, l, m);
        });
        await this.enter(attempt, signal, launch, enteredToken, {
          quoteUsd: quoteUsd as number,
          supply,
          launchAt,
          taxes: { buyPct: route.buyTaxPct, sellPct: route.sellTaxPct + transferTax },
          factors,
        });
      });
      return attempt;
    } catch (err) {
      if (err instanceof CheckFailed) {
        const failed = attempt.checks[attempt.checks.length - 1] as RiskCheckResult;
        attempt.failedCheck = err.check;
        attempt.reason = failed.message;
        await this.finish(attempt, 'rejected', token, launchAt, factors);
      } else {
        attempt.reason = `Error: ${errorMessage(err)}`;
        await this.finish(attempt, 'failed', token, launchAt, factors);
      }
      return attempt;
    }
  }

  private entryLock: Promise<unknown> = Promise.resolve();

  private withEntryLock<T>(fn: () => Promise<T>): Promise<T> {
    const run = this.entryLock.then(fn, fn);
    this.entryLock = run.catch(() => undefined);
    return run;
  }

  private async checkBudget(
    need: (c: RiskCheckName, ok: boolean, v: Scalar, l: Scalar, m: string) => void,
  ): Promise<void> {
    const cfg = this.d.config;
    // The same switch that stops the main strategy's automatic entries (AUTO_TRADE / Settings).
    const autoTrade = this.d.strategyStore.get().strategy.autoTrade;
    need(
      'TRADING_ENABLED',
      autoTrade,
      autoTrade,
      true,
      autoTrade ? 'Automatic trading is on.' : 'Automatic trading is switched off (AUTO_TRADE / Settings).',
    );
    const state = await this.d.portfolio.state();
    need(
      'NOT_HALTED',
      !state.halted,
      state.halted,
      false,
      state.halted ? `Trading is halted: ${state.haltReason ?? 'risk limit'}.` : 'Trading is not halted.',
    );
    const stats = await this.d.repos.positions.strategyStats(this.d.mode, 'sniper', new Date());
    need(
      'SNIPER_MAX_OPEN',
      stats.open < cfg.maxOpenPositions,
      stats.open,
      cfg.maxOpenPositions,
      `${stats.open} sniper position(s) open (limit ${cfg.maxOpenPositions}).`,
    );
    const globalMax = this.d.strategyStore.get().limits.maxOpenPositions;
    need(
      'MAX_OPEN_POSITIONS',
      state.marks.length < globalMax,
      state.marks.length,
      globalMax,
      `${state.marks.length} position(s) open in total (limit ${globalMax}).`,
    );
    need(
      'SNIPER_DAILY_TRADES',
      stats.todayOpened < cfg.maxTradesPerDay,
      stats.todayOpened,
      cfg.maxTradesPerDay,
      `${stats.todayOpened} sniper trade(s) today (limit ${cfg.maxTradesPerDay}).`,
    );
    const openLoss = state.marks
      .filter((m) => m.position.strategy === 'sniper')
      .reduce((a, m) => a + Math.min(0, m.unrealizedPnlUsd), 0);
    const dayLoss = -(stats.todayRealizedPnlUsd + openLoss);
    need(
      'SNIPER_DAILY_LOSS',
      dayLoss < cfg.maxDailyLossUsd,
      round(dayLoss, 2),
      cfg.maxDailyLossUsd,
      `Sniper loss today $${Math.max(0, dayLoss).toFixed(2)} incl. open positions (limit $${cfg.maxDailyLossUsd}).`,
    );
    need(
      'SUFFICIENT_CASH',
      state.cashUsd >= cfg.positionUsd + 1,
      round(state.cashUsd, 2),
      cfg.positionUsd + 1,
      `Cash $${state.cashUsd.toFixed(2)} for a $${cfg.positionUsd} entry plus fees.`,
    );
  }

  /** Confirmed transactions can take a moment to be served by getTransaction. */
  private async fetchTransaction(rpc: SolanaRpc, signature: string) {
    for (let i = 0; i < 4; i++) {
      const tx = await rpc.getParsedTransaction(signature);
      if (tx) return tx;
      await this.sleep(400);
    }
    return null;
  }

  /**
   * Jupiter round trip (buy then sell back). New pools can take a few seconds to be routable, so
   * "no route yet" is retried until the wait runs out; a confirmed honeypot fails at once.
   */
  private async sellRoute(
    mint: string,
    liquidityUsd: number | null,
  ): Promise<{ ok: boolean; message: string; buyTaxPct: number; sellTaxPct: number }> {
    const waitMs = this.d.config.sellRouteWaitSeconds * 1000;
    const deadline = Date.now() + waitMs;
    for (;;) {
      const r = await this.d.jupiter.inspect({
        chain: 'solana',
        address: mint,
        pairAddress: null,
        dexId: null,
        priceUsd: null,
        liquidityUsd,
      });
      const hp = r?.honeypot;
      if (hp?.isHoneypot === true) {
        return {
          ok: false,
          message: `Honeypot: ${hp.reason ?? 'sell simulation failed'}.`,
          buyTaxPct: 0,
          sellTaxPct: 0,
        };
      }
      if (hp?.sellRouteFound === true) {
        const buy = hp.buyTaxPct ?? 0;
        const sell = hp.sellTaxPct ?? 0;
        return {
          ok: true,
          message: `Buy-and-sell-back quote works (estimated costs: buy ${buy.toFixed(1)}%, sell ${sell.toFixed(1)}%).`,
          buyTaxPct: buy,
          sellTaxPct: sell,
        };
      }
      if (Date.now() >= deadline) {
        return {
          ok: false,
          message: `No working sell route within ${this.d.config.sellRouteWaitSeconds}s${hp?.reason ? ` (${hp.reason})` : ''}.`,
          buyTaxPct: 0,
          sellTaxPct: 0,
        };
      }
      await this.sleep(1000);
    }
  }

  private async enter(
    attempt: SniperAttempt,
    signal: LaunchSignal,
    launch: ParsedLaunch,
    token: TokenRow,
    x: {
      quoteUsd: number;
      supply: number;
      launchAt: number;
      taxes: { buyPct: number; sellPct: number };
      factors: Record<string, number | null>;
    },
  ): Promise<void> {
    const cfg = this.d.config;
    const rpc = this.d.rpc as SolanaRpc;
    // Fresh reserves: the price has usually moved since the pool was created.
    const [reserves] = await readReserves(rpc, [
      { baseVault: launch.baseVault, quoteVault: launch.quoteVault },
    ]);
    const market = marketFromReserves({
      reserves: reserves as { base: number; quote: number },
      quoteUsd: x.quoteUsd,
      source: signal.source,
      launchedAt: new Date(x.launchAt).toISOString(),
      supply: x.supply,
    });
    if (market.priceUsd === null) throw new Error('pool emptied before entry');
    const decision = this.buildDecision(attempt, 'bought', x.factors);
    decision.id = await this.d.repos.decisions.insert(token.id, decision);
    attempt.decisionId = decision.id;

    const meta: PoolMeta = {
      source: signal.source,
      signature: signal.signature,
      baseVault: launch.baseVault,
      quoteVault: launch.quoteVault,
      quoteMint: launch.quoteMint,
      launchedAtMs: x.launchAt,
      launchPriceUsd: attempt.launchPriceUsd,
    };
    const res = await this.d.tradeService.open({
      token,
      decimals: launch.mintDecimals,
      market,
      sizeUsd: cfg.positionUsd,
      taxes: x.taxes,
      exits: {
        stopLossPercent: cfg.stopLossPercent,
        takeProfitPercent: cfg.takeProfitPercent,
        trailingStopPercent: null,
        maxHoldMinutes: cfg.maxHoldMinutes,
      },
      strategy: 'sniper',
      meta: { ...meta },
      rugScore: null,
      // Allow for the paper executor's simulated latency drift on top of the impact limit.
      maxSlippagePct: cfg.maxPriceImpactPercent + 1,
      decisionId: decision.id,
      reason: `Sniper entry: ${signal.source} launch, ${((Date.now() - x.launchAt) / 1000).toFixed(1)}s old`,
    });
    await this.d.repos.tokens.applyMarket(token.id, market);

    const seconds = (Date.now() - x.launchAt) / 1000;
    attempt.secondsAfterLaunch = round(seconds, 2);
    if (res.position) {
      attempt.positionId = res.position.id;
      attempt.entryPriceUsd = res.position.entryPriceUsd;
      if (attempt.launchPriceUsd)
        attempt.entryPremiumPct = round((res.position.entryPriceUsd / attempt.launchPriceUsd - 1) * 100, 2);
      attempt.reason = `Bought $${cfg.positionUsd} ${seconds.toFixed(1)}s after launch${
        attempt.entryPremiumPct !== null
          ? `, paying ${attempt.entryPremiumPct.toFixed(1)}% above the opening price`
          : ''
      }.`;
    } else {
      attempt.reason = `Buy failed: ${res.trade.error ?? 'unknown error'}`;
    }
    const outcome: SniperOutcome = res.position ? 'bought' : 'failed';
    x.factors.secondsAfterLaunch = attempt.secondsAfterLaunch;
    x.factors.entryPremiumPct = attempt.entryPremiumPct;
    decision.executed = res.position !== null;
    decision.tradeId = res.trade.id;
    decision.stages.push({
      stage: 'EXECUTION',
      status: res.position ? 'pass' : 'error',
      summary: attempt.reason,
      metrics: {
        tradeId: res.trade.id,
        filledUsd: res.trade.filledUsd,
        secondsAfterLaunch: attempt.secondsAfterLaunch,
        entryPremiumPct: attempt.entryPremiumPct,
      },
      durationMs: 0,
    });
    if (!res.position) decision.label = 'BUY — EXECUTION FAILED';
    decision.reasons.push(attempt.reason);
    await this.d.repos.decisions.update(decision.id, {
      label: decision.label,
      executed: decision.executed,
      tradeId: decision.tradeId,
      stages: decision.stages,
      reasons: decision.reasons,
    });
    await this.d.repos.tokens.setLastDecision(token.id, decision);
    this.d.bus.publish({ type: 'decision', data: decision });
    this.record(attempt, outcome);
  }

  private buildDecision(
    attempt: SniperAttempt,
    outcome: SniperOutcome,
    factors: Record<string, number | null>,
  ): Decision {
    const stages: StageResult[] = [];
    for (const stage of STAGE_ORDER) {
      const checks = attempt.checks.filter((c) => (STAGE_OF[c.check] ?? 'RISK_CHECK') === stage);
      const failed = checks.find((c) => !c.passed);
      stages.push({
        stage,
        status: checks.length === 0 ? 'skipped' : failed ? 'fail' : 'pass',
        summary:
          checks.length === 0
            ? 'Not reached.'
            : failed
              ? failed.message
              : checks.map((c) => c.message).join(' '),
        metrics: Object.fromEntries(checks.map((c) => [c.check, c.value])),
        durationMs: 0,
      });
    }
    const bought = outcome === 'bought';
    return {
      id: null,
      chain: 'solana',
      address: attempt.mint as string,
      symbol: attempt.symbol,
      action: bought ? 'BUY' : 'SKIP',
      label: bought
        ? 'SNIPE — BOUGHT'
        : outcome === 'failed'
          ? 'SKIP — SNIPER ERROR'
          : `SKIP — SNIPER: ${(attempt.failedCheck ?? 'CHECK').replace(/_/g, ' ')}`,
      reasonCode: bought
        ? 'SNIPER_BUY'
        : outcome === 'failed'
          ? 'SNIPER_ERROR'
          : `SNIPER_${attempt.failedCheck}`,
      confidence: 0.5,
      reasons: bought ? ['Every launch check passed.'] : [attempt.reason],
      factors,
      stages,
      riskChecks: attempt.checks,
      sizing: null,
      rugScore: null,
      strategyScore: null,
      mode: this.d.mode,
      executed: false,
      tradeId: null,
      createdAt: new Date().toISOString(),
    };
  }

  /** Records a launch that did not lead to a position. */
  private async finish(
    attempt: SniperAttempt,
    outcome: SniperOutcome,
    token: TokenRow | null,
    launchAt: number,
    factors: Record<string, number | null>,
  ): Promise<void> {
    // Timing only means something once the launch itself was read.
    attempt.secondsAfterLaunch = attempt.launchedAt ? round((Date.now() - launchAt) / 1000, 2) : null;
    if (token && attempt.mint) {
      const decision = this.buildDecision(attempt, outcome, factors);
      attempt.decisionId = await this.d.repos.decisions.insert(token.id, decision);
      decision.id = attempt.decisionId;
      await this.d.repos.tokens.setLastDecision(token.id, decision);
      // Rejected launches are not worth the main engine's analysis budget.
      await this.d.repos.tokens.setStatus(token.id, 'ignored');
      this.d.bus.publish({ type: 'decision', data: decision });
    }
    this.record(attempt, outcome);
  }

  private record(attempt: SniperAttempt, outcome: SniperOutcome): void {
    attempt.outcome = outcome;
    attempt.decidedAt = new Date().toISOString();
    // "Analysed" = got past the budget checks to the launch itself.
    if (attempt.checks.some((c) => STAGE_OF[c.check] !== undefined)) this.stats.analysed += 1;
    if (outcome === 'bought') this.stats.bought += 1;
    else if (outcome === 'failed') this.stats.failed += 1;
    else if (outcome === 'rejected') {
      this.stats.rejected += 1;
      if (attempt.failedCheck)
        this.stats.rejectionsByCheck[attempt.failedCheck] =
          (this.stats.rejectionsByCheck[attempt.failedCheck] ?? 0) + 1;
    }
    this.attempts.unshift(attempt);
    if (this.attempts.length > 200) this.attempts.pop();
    this.d.bus.publish({ type: 'sniper.attempt', data: attempt });
    this.d.logger.info(
      {
        mint: attempt.mint,
        source: attempt.source,
        outcome,
        check: attempt.failedCheck,
        reason: attempt.reason,
      },
      'sniper attempt',
    );
  }

  // ------------------------------------------------------------------ exits

  /** Prices open sniper positions from their pool and applies the exit rules. */
  async monitor(): Promise<void> {
    const rpc = this.d.rpc;
    if (!rpc) return;
    const open = (await this.d.repos.positions.listOpen(this.d.mode)).filter(
      (o) => o.position.strategy === 'sniper',
    );
    const items = open
      .map((o) => ({ ...o, pool: o.position.meta as unknown as PoolMeta | null }))
      .filter((o) => o.pool?.baseVault && o.pool.quoteVault);
    if (items.length === 0) return;
    const reserves = await readReserves(
      rpc,
      items.map((i) => ({
        baseVault: (i.pool as PoolMeta).baseVault,
        quoteVault: (i.pool as PoolMeta).quoteVault,
      })),
    );
    const params = this.d.strategyStore.get().strategy;
    for (const [idx, item] of items.entries()) {
      const { position, token } = item;
      const pool = item.pool as PoolMeta;
      const quoteUsd = await this.pricer.usd(pool.quoteMint);
      if (quoteUsd === null) continue;
      const market = marketFromReserves({
        reserves: reserves[idx] as { base: number; quote: number },
        quoteUsd,
        source: pool.source,
        launchedAt: new Date(pool.launchedAtMs).toISOString(),
      });
      const ref = { chain: token.chain as 'solana', address: token.address, symbol: token.symbol };
      const exitDeps = {
        repos: this.d.repos,
        tradeService: this.d.tradeService,
        bus: this.d.bus,
        mode: this.d.mode,
      };
      // Nothing left in the pool: the tokens cannot be sold at any price.
      if (market.priceUsd === null || (market.liquidityUsd ?? 0) < 1) {
        await closeWithDecision(exitDeps, {
          positionId: position.id,
          tokenId: token.id,
          token: ref,
          reason: 'liquidity_drop',
          reasonCode: 'EXIT_POOL_DRAINED',
          reasons: ['The pool was emptied (liquidity pulled); the tokens can no longer be sold.'],
          trigger: 'monitor',
          writeOff: true,
        });
        continue;
      }
      const price = market.priceUsd;
      const highest = Math.max(position.highestPriceUsd, price);
      await this.d.repos.positions.updateMark(position.id, price, highest);
      await this.d.repos.tokens.applyMarket(token.id, market);
      this.d.bus.publish({
        type: 'position',
        data: toPosition({ ...position, lastPriceUsd: price, highestPriceUsd: highest }, ref, price),
      });

      const exit = evaluateExit(
        {
          entryPriceUsd: position.entryPriceUsd,
          stopLossPriceUsd: position.stopLossPriceUsd,
          takeProfitPriceUsd: position.takeProfitPriceUsd,
          trailingStopPercent: position.trailingStopPercent,
          highestPriceUsd: highest,
          entryLiquidityUsd: position.entryLiquidityUsd,
          openedAt: position.openedAt,
          maxHoldMinutes: position.maxHoldMinutes,
        },
        price,
        market.liquidityUsd,
        await this.d.repos.risk.latest(token.id),
        params,
        new Date(),
      );
      if (exit.action !== 'SELL' || !exit.reason) continue;
      // A failed exit is retried, but not every tick: each attempt is recorded as a decision.
      const lastFail = this.lastExitFailure.get(position.id);
      if (lastFail && Date.now() - lastFail < 60_000) continue;
      const { decision } = await closeWithDecision(exitDeps, {
        positionId: position.id,
        tokenId: token.id,
        token: ref,
        reason: exit.reason,
        reasonCode: exit.reasonCode,
        reasons: exit.reasons,
        trigger: 'monitor',
        metrics: exit.metrics,
        market,
      });
      if (decision.executed) this.lastExitFailure.delete(position.id);
      else this.lastExitFailure.set(position.id, Date.now());
    }
  }

  // ------------------------------------------------------------------ status

  private settingsView(): SniperSettingsView {
    const c = this.d.config;
    return {
      sources: c.sources.map((p) => ({ name: p.name, programId: p.programId })),
      positionUsd: c.positionUsd,
      maxOpenPositions: c.maxOpenPositions,
      maxTradesPerDay: c.maxTradesPerDay,
      maxDailyLossUsd: c.maxDailyLossUsd,
      stopLossPercent: c.stopLossPercent,
      takeProfitPercent: c.takeProfitPercent,
      maxHoldMinutes: c.maxHoldMinutes,
      maxLaunchAgeSeconds: c.maxLaunchAgeSeconds,
      minLiquidityUsd: c.minLiquidityUsd,
      maxCreatorPercent: c.maxCreatorPercent,
      maxTopHolderPercent: c.maxTopHolderPercent,
      minCreatorWalletAgeHours: c.minCreatorWalletAgeHours,
      maxPriceImpactPercent: c.maxPriceImpactPercent,
      sellRouteWaitSeconds: c.sellRouteWaitSeconds,
    };
  }

  async status(): Promise<SniperStatus> {
    const perf = await this.d.repos.positions.strategyStats(this.d.mode, 'sniper', new Date());
    const rows = await this.d.repos.positions.listForStrategy(this.d.mode, 'sniper', 200);
    // Entry timing comes from stored positions, so it survives restarts.
    const timing = rows
      .map(({ position }) => position.meta as unknown as PoolMeta | null)
      .map((meta, i) => ({ meta, position: (rows[i] as (typeof rows)[number]).position }))
      .filter((r) => r.meta?.launchedAtMs);
    const seconds = timing.map(
      (r) => (r.position.openedAt.getTime() - (r.meta as PoolMeta).launchedAtMs) / 1000,
    );
    const premiums = timing
      .filter((r) => (r.meta as PoolMeta).launchPriceUsd)
      .map((r) => (r.position.entryPriceUsd / ((r.meta as PoolMeta).launchPriceUsd as number) - 1) * 100);
    return {
      enabled: this.enabled,
      mode: 'paper',
      running: this.accepting,
      disabledReason: this.enabled
        ? null
        : !this.d.config.enabled
          ? 'The sniper is off. Set SNIPER_ENABLED=true in .env to turn it on (paper trading only).'
          : 'RPC_URL is not configured.',
      listener: this.listener?.status() ?? {
        connected: false,
        reconnects: 0,
        lastMessageAt: null,
        lastError: null,
      },
      settings: this.d.config.enabled ? this.settingsView() : null,
      stats: {
        ...this.stats,
        rejectionsByCheck: { ...this.stats.rejectionsByCheck },
        medianSecondsAfterLaunch: median(seconds) === null ? null : round(median(seconds) as number, 2),
        medianEntryPremiumPct: median(premiums) === null ? null : round(median(premiums) as number, 2),
      },
      performance: {
        openPositions: perf.open,
        closedPositions: perf.closed,
        wins: perf.wins,
        losses: perf.losses,
        realizedPnlUsd: perf.realizedPnlUsd,
        todayRealizedPnlUsd: perf.todayRealizedPnlUsd,
        todayTrades: perf.todayOpened,
      },
      recent: this.attempts.slice(0, 100),
      positions: rows.slice(0, 50).map((r) => toPosition(r.position, r.token)),
    };
  }
}
