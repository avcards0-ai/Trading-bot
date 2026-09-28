import type {
  CloseReason,
  Decision,
  DecisionAction,
  LlmReview,
  PipelineStage,
  Position,
  RiskLevel,
  RiskReport,
  Scalar,
  StageResult,
  StageStatus,
  TokenSnapshot,
  Trade,
  TradingMode,
} from '@memeguard/shared';
import { analysisAlerts, marketAlerts, type AlertCandidate } from '../alerts/rules';
import type { AlertService } from '../alerts/alertService';
import { circulatingHolders } from '../analysis/activity';
import type { SnapshotCollector } from '../analysis/collector';
import type { LlmReviewer } from '../analysis/llmReviewer';
import type { RugDetector } from '../analysis/rug/detector';
import type { StrategyStore } from '../config/strategyStore';
import type { Repositories, TokenRow } from '../db/repositories';
import { toTokenListItem } from '../db/repositories';
import type { TradeExecutor } from '../execution/types';
import { errorMessage } from '../lib/errors';
import type { EventBus } from '../lib/events';
import type { Logger } from '../lib/logger';
import type { RiskManager } from '../risk/riskManager';
import { computePositionSize } from '../strategy/sizing';
import { evaluateEntry, evaluateExit } from '../strategy/strategy';
import type { Portfolio } from '../trading/portfolio';
import type { TradeService } from '../trading/tradeService';

export type AnalysisTrigger = 'discovery' | 'watchlist' | 'manual' | 'monitor';

export interface AnalyzeRequest {
  tokenId: number;
  trigger: AnalysisTrigger;
  /** May this analysis place an order (still subject to every risk check)? */
  allowTrade: boolean;
  /** Manual API request: bypasses only the auto-trade switch, never the risk checks. */
  manual?: boolean;
  requestedUsd?: number | null;
  forceSecurityRefresh?: boolean;
  /**
   * Manual trade: proceed to the risk checks even without a strategy entry signal.
   * Never bypasses the rug-risk gate or any risk check.
   */
  bypassStrategy?: boolean;
}

export interface AnalyzeResult {
  decision: Decision;
  report: RiskReport;
  snapshot: TokenSnapshot;
  trade: Trade | null;
  position: Position | null;
}

export interface PipelineDeps {
  repos: Repositories;
  collector: SnapshotCollector;
  detector: RugDetector;
  llm: LlmReviewer | null;
  llmRequired: boolean;
  strategyStore: StrategyStore;
  riskManager: RiskManager;
  portfolio: Portfolio;
  tradeService: TradeService;
  executor: TradeExecutor;
  alerts: AlertService;
  bus: EventBus;
  logger: Logger;
  settings: {
    mode: TradingMode;
    liveMaxPositionUsd: number;
    dexFeePct: number;
    securityRefreshMs: number;
  };
  now?: () => Date;
}

const LEVEL_STATUS: Record<RiskLevel, StageStatus> = {
  LOW: 'pass',
  MEDIUM: 'warn',
  HIGH: 'fail',
  CRITICAL: 'fail',
};
const worse = (a: RiskLevel, b: RiskLevel): RiskLevel =>
  ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL'].indexOf(a) >= ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL'].indexOf(b)
    ? a
    : b;
const r = (v: number | null | undefined, d = 2): number | null =>
  v === null || v === undefined || !Number.isFinite(v) ? null : Math.round(v * 10 ** d) / 10 ** d;

/**
 * TOKEN DISCOVERY -> ON-CHAIN -> CONTRACT -> WALLET -> LIQUIDITY -> MARKET -> RUG RISK
 *   -> STRATEGY -> RISK CHECK -> EXECUTION (paper/live)
 *
 * Every run produces a persisted Decision (BUY / SELL / HOLD / SKIP) with per-stage results,
 * the numeric factors that produced it, and every risk check. Nothing is executed unless the
 * RiskManager approves; likely scams short-circuit to "SKIP — HIGH RUG RISK".
 */
export class DecisionPipeline {
  private readonly inflight = new Map<number, Promise<AnalyzeResult>>();

  constructor(private readonly d: PipelineDeps) {}

  private now(): Date {
    return this.d.now?.() ?? new Date();
  }

  analyze(req: AnalyzeRequest): Promise<AnalyzeResult> {
    const existing = this.inflight.get(req.tokenId);
    if (existing) return existing;
    const p = this.run(req).finally(() => this.inflight.delete(req.tokenId));
    this.inflight.set(req.tokenId, p);
    return p;
  }

  get inFlight(): number {
    return this.inflight.size;
  }

  private async run(req: AnalyzeRequest): Promise<AnalyzeResult> {
    const token = await this.d.repos.tokens.getById(req.tokenId);
    if (!token) throw new Error(`token ${req.tokenId} not found`);
    try {
      return await this.execute(token, req);
    } catch (err) {
      await this.d.repos.events
        .log('error', 'pipeline', `analysis failed: ${errorMessage(err)}`, { trigger: req.trigger }, token.id)
        .catch(() => undefined);
      throw err;
    }
  }

  private async execute(token: TokenRow, req: AnalyzeRequest): Promise<AnalyzeResult> {
    const { repos } = this.d;
    const cfg = this.d.strategyStore.get();
    const mode = this.d.settings.mode;
    const now = this.now();
    const stages: StageResult[] = [];
    const add = (
      stage: PipelineStage,
      status: StageStatus,
      summary: string,
      metrics: Record<string, Scalar>,
      ms: number,
    ) => stages.push({ stage, status, summary, metrics, durationMs: Math.round(ms) });

    // DISCOVERY
    add(
      'DISCOVERY',
      'pass',
      `Token ${token.symbol ?? token.address} via ${token.discoveredVia} (${req.trigger}).`,
      {
        chain: token.chain,
        address: token.address,
        discoveredVia: token.discoveredVia,
        trigger: req.trigger,
      },
      0,
    );

    // ON-CHAIN collection
    const t0 = Date.now();
    const previous = token.latestSnapshot ?? null;
    const previousReport = previous ? await repos.risk.latest(token.id) : null;
    const refreshSecurity =
      req.forceSecurityRefresh === true ||
      !previous ||
      !token.lastSecurityAt ||
      now.getTime() - token.lastSecurityAt.getTime() > this.d.settings.securityRefreshMs;
    const snapshot = await this.d.collector.collect({
      chain: token.chain as TokenSnapshot['chain'],
      address: token.address,
      hint: {
        name: token.name,
        symbol: token.symbol,
        pairAddress: token.pairAddress,
        dexId: token.dexId,
        pairCreatedAt: token.pairCreatedAt,
      },
      previous,
      refreshSecurity,
    });
    const okSources = snapshot.sources.filter((s) => s.ok).length;
    add(
      'ON_CHAIN',
      snapshot.market === null ? 'fail' : okSources === snapshot.sources.length ? 'pass' : 'warn',
      `${okSources}/${snapshot.sources.length} data sources responded${refreshSecurity ? '' : ' (security data reused from cache)'}.`,
      {
        sourcesOk: okSources,
        sourcesFailed: snapshot.sources.length - okSources,
        securityRefreshed: refreshSecurity,
        holderCount: snapshot.holders?.holderCount ?? null,
        totalSupply: snapshot.holders?.totalSupply ?? null,
      },
      Date.now() - t0,
    );

    // Deterministic rug analysis (+ optional LLM escalation)
    const t1 = Date.now();
    let report = this.d.detector.analyze(snapshot, { now, previous });
    let llmReview: LlmReview | null = null;
    if (this.d.llm && !report.isLikelyScam && report.rugScore <= cfg.limits.maxRugScore) {
      llmReview = await this.d.llm.review(snapshot, report);
      report = this.d.detector.analyze(snapshot, { now, previous, llmReview });
    }
    const rugMs = Date.now() - t1;
    const cat = report.categories;

    const c = snapshot.contract;
    add(
      'CONTRACT',
      c ? LEVEL_STATUS[worse(report.contractRisk, report.honeypotRisk)] : 'fail',
      c
        ? `Contract ${report.contractRisk}, honeypot ${report.honeypotRisk}.`
        : `No contract data available (unverifiable); contract ${report.contractRisk}, honeypot ${report.honeypotRisk}.`,
      {
        tokenProgram: c?.tokenProgram ?? null,
        verified: c?.isVerified ?? null,
        proxy: c?.isProxy ?? null,
        mintable: c?.mintable ?? null,
        freezable: c?.freezable ?? null,
        ownershipRenounced: c?.ownershipRenounced ?? null,
        buyTaxPct: r(Math.max(c?.buyTaxPct ?? -1, snapshot.honeypot?.buyTaxPct ?? -1)),
        sellTaxPct: r(Math.max(c?.sellTaxPct ?? -1, snapshot.honeypot?.sellTaxPct ?? -1)),
        honeypot: snapshot.honeypot?.isHoneypot ?? null,
        sellRouteFound: snapshot.honeypot?.sellRouteFound ?? null,
        suspiciousFunctions: c?.suspiciousFunctions.length ?? 0,
        contractScore: cat.contract.score,
        honeypotScore: cat.honeypot.score,
      },
      0,
    );

    const circ = snapshot.holders ? circulatingHolders(snapshot.holders.topHolders, snapshot.chain) : [];
    add(
      'WALLET',
      snapshot.holders ? LEVEL_STATUS[worse(report.walletConcentrationRisk, report.developerRisk)] : 'fail',
      `${snapshot.holders ? '' : 'Holder data unavailable. '}Concentration ${report.walletConcentrationRisk}, developer ${report.developerRisk}.`,
      {
        holderCount: snapshot.holders?.holderCount ?? null,
        topHolderPct: r(circ[0]?.percent),
        top10Pct: r(circ.slice(0, 10).reduce((a, h) => a + h.percent, 0)),
        largestClusterPct: r(snapshot.wallets?.largestClusterPercent),
        freshWalletShare: r(snapshot.wallets?.newWalletShare, 3),
        deployer: snapshot.deployer?.address ?? null,
        deployerHoldsPct: r(snapshot.deployer?.holdsPercent),
        devSells: snapshot.developer?.sells ?? null,
        devSupplyMovedPct: r(snapshot.developer?.percentOfSupplyMoved),
        concentrationScore: cat.concentration.score,
        developerScore: cat.developer.score,
      },
      0,
    );

    const liq = snapshot.liquidity;
    const mcap = snapshot.market?.marketCapUsd ?? snapshot.market?.fdvUsd ?? null;
    add(
      'LIQUIDITY',
      LEVEL_STATUS[report.liquidityRisk],
      `Liquidity ${report.liquidityRisk}.`,
      {
        liquidityUsd: r(liq?.totalLiquidityUsd ?? snapshot.market?.liquidityUsd, 0),
        lpLockedPct: r(liq?.lpLockedPercent),
        lpBurnedPct: r(liq?.lpBurnedPercent),
        programControlled: liq?.programControlled ?? null,
        pools: liq?.poolCount ?? null,
        liquidityToMcap: mcap && liq?.totalLiquidityUsd ? r(liq.totalLiquidityUsd / mcap, 4) : null,
        liquidityScore: cat.liquidity.score,
      },
      0,
    );

    const m = snapshot.market;
    const tr = snapshot.trades;
    add(
      'MARKET',
      LEVEL_STATUS[report.marketIntegrityRisk],
      `Market integrity ${report.marketIntegrityRisk}.`,
      {
        priceUsd: m?.priceUsd ?? null,
        marketCapUsd: r(mcap, 0),
        volume1hUsd: r(m?.volumeUsd.h1, 0),
        volume24hUsd: r(m?.volumeUsd.h24, 0),
        priceChange5mPct: r(m?.priceChangePct.m5),
        priceChange1hPct: r(m?.priceChangePct.h1),
        buys1h: m?.txns.h1?.buys ?? null,
        sells1h: m?.txns.h1?.sells ?? null,
        tradesSampled: tr?.tradeCount ?? null,
        uniqueTraders: tr?.uniqueTraders ?? null,
        roundTripVolumeShare: r(tr?.roundTripVolumeShare, 3),
        marketScore: cat.market.score,
      },
      0,
    );

    const highRugRisk =
      report.isLikelyScam || report.overallRisk === 'CRITICAL' || report.rugScore > cfg.limits.maxRugScore;
    add(
      'RUG_RISK',
      highRugRisk ? 'fail' : LEVEL_STATUS[report.overallRisk],
      `RUG_SCORE ${report.rugScore}, OVERALL ${report.overallRisk}${report.isLikelyScam ? ' — LIKELY SCAM' : ''}.`,
      {
        rugScore: report.rugScore,
        overallRisk: report.overallRisk,
        likelyScam: report.isLikelyScam,
        criticalFlags: report.criticalFlags.length,
        dataCompleteness: report.dataCompleteness,
        maxRugScore: cfg.limits.maxRugScore,
        llmEscalated: llmReview?.escalate ?? null,
      },
      rugMs,
    );

    const factors: Record<string, number | null> = {
      rugScore: report.rugScore,
      honeypotScore: cat.honeypot.score,
      liquidityScore: cat.liquidity.score,
      contractScore: cat.contract.score,
      concentrationScore: cat.concentration.score,
      developerScore: cat.developer.score,
      marketScore: cat.market.score,
      dataScore: cat.data.score,
      dataCompleteness: report.dataCompleteness,
    };

    let action: DecisionAction;
    let label: string;
    let reasonCode: string;
    let confidence: number;
    const reasons: string[] = [];
    let strategyScore: number | null = null;
    let sizing: Decision['sizing'] = null;
    let riskChecks: Decision['riskChecks'] = [];
    let execute:
      (() => Promise<{ trade: Trade | null; position: Position | null; error: string | null }>) | null = null;

    const openPosition = await repos.positions.openForToken(mode, token.id);

    if (openPosition) {
      // Held token: exit rules (rug escalation, liquidity pull, SL/TP, time).
      const exit = evaluateExit(
        {
          entryPriceUsd: openPosition.entryPriceUsd,
          stopLossPriceUsd: openPosition.stopLossPriceUsd,
          takeProfitPriceUsd: openPosition.takeProfitPriceUsd,
          trailingStopPercent: openPosition.trailingStopPercent,
          highestPriceUsd: Math.max(openPosition.highestPriceUsd, m?.priceUsd ?? 0),
          entryLiquidityUsd: openPosition.entryLiquidityUsd,
          openedAt: openPosition.openedAt,
        },
        m?.priceUsd ?? null,
        m?.liquidityUsd ?? null,
        report,
        cfg.strategy,
        now,
      );
      Object.assign(
        factors,
        Object.fromEntries(
          Object.entries(exit.metrics).map(([k, v]) => [`position_${k}`, v === null ? null : r(v, 6)]),
        ),
      );
      add(
        'STRATEGY',
        exit.action === 'SELL' ? 'fail' : 'pass',
        exit.reasons.join(' '),
        { ...exit.metrics, positionId: openPosition.id },
        0,
      );
      add('RISK_CHECK', 'skipped', 'Exits are protective and are not blocked by entry risk checks.', {}, 0);
      if (exit.action === 'SELL') {
        action = 'SELL';
        reasonCode = exit.reasonCode;
        label =
          exit.reason === 'rug_risk_escalation'
            ? 'SELL — HIGH RUG RISK'
            : `SELL — ${(exit.reason ?? 'exit').replace(/_/g, ' ').toUpperCase()}`;
        confidence = 0.9;
        reasons.push(...exit.reasons);
        const mayExecute = req.trigger !== 'manual' || req.allowTrade;
        if (mayExecute) {
          execute = async () => {
            const res = await this.d.tradeService.closePosition({
              positionId: openPosition.id,
              reason: exit.reason as CloseReason,
              detail: exit.reasons.join(' '),
              market: m,
            });
            return {
              trade: res?.trade ?? null,
              position: res?.position ?? null,
              error: res?.position ? null : (res?.trade?.error ?? 'exit not completed'),
            };
          };
        }
      } else {
        action = 'HOLD';
        reasonCode = exit.reasonCode;
        label = 'HOLD — POSITION OPEN';
        confidence = 0.6;
        reasons.push(...exit.reasons);
      }
    } else if (highRugRisk) {
      action = 'SKIP';
      label = 'SKIP — HIGH RUG RISK';
      reasonCode = report.isLikelyScam
        ? 'LIKELY_SCAM'
        : report.overallRisk === 'CRITICAL'
          ? 'CRITICAL_RISK'
          : 'RUG_SCORE_ABOVE_LIMIT';
      confidence = report.isLikelyScam ? 0.95 : 0.8;
      reasons.push(
        report.isLikelyScam
          ? `Likely scam: ${report.criticalFlags.join(', ') || `rug score ${report.rugScore}`}.`
          : `Rug score ${report.rugScore} exceeds MAX_RUG_SCORE ${cfg.limits.maxRugScore} (overall ${report.overallRisk}).`,
      );
      reasons.push(report.explanations.overallRisk);
      add('STRATEGY', 'skipped', 'Not evaluated: high rug risk.', {}, 0);
      add('RISK_CHECK', 'skipped', 'Not evaluated: high rug risk.', {}, 0);
    } else {
      const entry = evaluateEntry(snapshot, report, cfg.strategy, cfg.limits, now);
      strategyScore = entry.score;
      for (const [k, v] of Object.entries(entry.components)) factors[`strategy_${k}`] = r(v);
      for (const [k, v] of Object.entries(entry.signals))
        factors[`signal_${k}`] = typeof v === 'number' ? r(v, 4) : null;
      factors.strategyScore = entry.score;
      add(
        'STRATEGY',
        entry.action === 'BUY' ? 'pass' : entry.action === 'HOLD' ? 'warn' : 'fail',
        entry.reasons.join(' '),
        {
          score: entry.score,
          action: entry.action,
          minScore: cfg.strategy.minStrategyScore,
          ...entry.components,
        },
        0,
      );
      reasons.push(...entry.reasons);

      const manualOverride =
        entry.action !== 'BUY' &&
        req.manual === true &&
        req.bypassStrategy === true &&
        entry.reasonCode !== 'NO_MARKET_DATA';
      if (manualOverride) {
        reasons.push(
          `Manual request: strategy signal was ${entry.action} (${entry.reasonCode}); proceeding to risk checks as requested.`,
        );
      }
      if (entry.action !== 'BUY' && !manualOverride) {
        action = entry.action;
        reasonCode = entry.reasonCode;
        label =
          entry.action === 'HOLD'
            ? 'HOLD — WATCHING'
            : entry.reasonCode === 'NO_MARKET_DATA'
              ? 'SKIP — NO MARKET DATA'
              : 'SKIP — STRATEGY CRITERIA NOT MET';
        confidence = entry.confidence;
        add('RISK_CHECK', 'skipped', 'Not evaluated: no entry signal.', {}, 0);
      } else {
        // RISK CHECK
        const t2 = Date.now();
        const state = await this.d.portfolio.state();
        const chainSupported = this.d.executor.supports(snapshot.chain);
        const fee = this.d.executor.networkFeeUsd(snapshot.chain);
        sizing = computePositionSize({
          equityUsd: state.equityUsd,
          cashUsd: state.cashUsd,
          liquidityUsd: m?.liquidityUsd ?? 0,
          priceUsd: m?.priceUsd ?? 0,
          limits: cfg.limits,
          params: cfg.strategy,
          strategyScore: entry.score ?? 0,
          rugScore: report.rugScore,
          dexFeePct: this.d.settings.dexFeePct,
          networkFeeUsd: fee,
          requestedUsd: req.requestedUsd ?? null,
          absoluteCapUsd: mode === 'live' ? this.d.settings.liveMaxPositionUsd : null,
        });
        factors.positionSizeUsd = r(sizing.sizeUsd);
        factors.expectedSlippagePct = sizing.expectedSlippagePct;
        const evaluation = this.d.riskManager.evaluateEntry({
          mode,
          tradingEnabled: req.manual === true || cfg.strategy.autoTrade,
          liveExecutionSupported: chainSupported,
          account: state,
          openPositions: state.marks.length,
          hasOpenPositionForToken: false,
          snapshot,
          report,
          sizing,
          limits: cfg.limits,
          strategy: cfg.strategy,
          networkFeeUsd: fee,
          llm: {
            required: this.d.llmRequired,
            failed: this.d.llmRequired && (llmReview === null || llmReview.error !== null),
            error: llmReview?.error ?? (this.d.llm ? null : 'LLM reviewer not configured'),
          },
          now,
        });
        riskChecks = evaluation.checks;
        add(
          'RISK_CHECK',
          evaluation.approved ? 'pass' : 'fail',
          evaluation.approved
            ? `All ${evaluation.checks.length} risk checks passed.`
            : `${evaluation.failed.length} risk check(s) failed: ${evaluation.failed.map((f) => f.check).join(', ')}.`,
          {
            passed: evaluation.checks.length - evaluation.failed.length,
            failed: evaluation.failed.length,
            sizeUsd: sizing.sizeUsd,
            limitingFactor: sizing.limitingFactor,
          },
          Date.now() - t2,
        );
        if (!evaluation.approved) {
          action = 'SKIP';
          label = 'SKIP — RISK CHECK FAILED';
          reasonCode = `RISK_${evaluation.failed[0]?.check ?? 'UNKNOWN'}`;
          confidence = 0.9;
          reasons.push(...evaluation.failed.map((f) => `Risk check ${f.check} failed: ${f.message}`));
        } else {
          action = 'BUY';
          reasonCode = 'ENTRY_APPROVED';
          confidence = entry.confidence;
          label = req.allowTrade ? 'BUY' : 'BUY — ANALYSIS ONLY';
          reasons.push(
            `Position size $${sizing.sizeUsd.toFixed(2)} (limited by ${sizing.limitingFactor}); expected impact ${sizing.expectedSlippagePct}%.`,
          );
          if (req.allowTrade) {
            const approvedSizing = sizing;
            execute = async () => {
              const res = await this.d.tradeService.openPosition({
                token,
                snapshot,
                report,
                sizing: approvedSizing,
                strategy: cfg.strategy,
                maxSlippagePct: cfg.limits.maxSlippagePercent,
                decisionId: decisionId as number,
                reason: `Strategy entry (score ${entry.score}, rug ${report.rugScore})`,
              });
              return {
                trade: res.trade,
                position: res.position,
                error: res.position ? null : res.trade.error,
              };
            };
          }
        }
      }
    }

    // Persist risk + preliminary decision before any execution (trades reference the decision).
    await repos.risk.insert(token.id, report);
    const decision: Decision = {
      id: null,
      chain: snapshot.chain,
      address: snapshot.address,
      symbol: snapshot.symbol,
      action,
      label,
      reasonCode,
      confidence: Math.round(confidence * 1000) / 1000,
      reasons,
      factors,
      stages,
      riskChecks,
      sizing,
      rugScore: report.rugScore,
      strategyScore,
      mode,
      executed: false,
      tradeId: null,
      createdAt: now.toISOString(),
    };
    if (!execute) {
      add(
        'EXECUTION',
        'skipped',
        action === 'BUY' ? 'Analysis only: trading not requested.' : `No order: decision is ${label}.`,
        {},
        0,
      );
    }
    const decisionId: number = await repos.decisions.insert(token.id, decision);
    decision.id = decisionId;

    let trade: Trade | null = null;
    let position: Position | null = null;
    if (execute) {
      const t3 = Date.now();
      try {
        const res = await execute();
        trade = res.trade;
        position = res.position;
        const ok = res.error === null && trade?.status === 'filled';
        decision.executed = ok;
        decision.tradeId = trade?.id ?? null;
        add(
          'EXECUTION',
          ok ? 'pass' : 'error',
          ok
            ? `${mode.toUpperCase()} ${trade?.side} filled: $${trade?.filledUsd?.toFixed(2)} @ ${trade?.priceUsd}.`
            : `Execution failed: ${res.error}`,
          {
            tradeId: trade?.id ?? null,
            status: trade?.status ?? null,
            filledUsd: trade?.filledUsd ?? null,
            slippagePct: r(trade?.slippagePct ?? null),
            feeUsd: r(trade?.feeUsd ?? null),
          },
          Date.now() - t3,
        );
        if (!ok) {
          decision.label = `${action} — EXECUTION FAILED`;
          decision.reasons.push(`Execution failed: ${res.error}`);
        }
      } catch (err) {
        add('EXECUTION', 'error', `Execution error: ${errorMessage(err)}`, {}, Date.now() - t3);
        decision.label = `${action} — EXECUTION FAILED`;
        decision.reasons.push(`Execution error: ${errorMessage(err)}`);
        await repos.events.log('error', 'execution', errorMessage(err), { decisionId }, token.id);
      }
      await repos.decisions.update(decisionId, {
        executed: decision.executed,
        tradeId: decision.tradeId,
        stages: decision.stages,
        reasons: decision.reasons,
      });
    }

    // Persist token state, history, wallets.
    const updated = await repos.tokens.applyAnalysis(token.id, snapshot, report, decision, refreshSecurity);
    if (snapshot.market) await repos.history.recordMarket(token.id, snapshot.market);
    if (
      refreshSecurity &&
      snapshot.liquidity &&
      (snapshot.liquidity.lpLockedPercent !== null || snapshot.liquidity.lpBurnedPercent !== null)
    ) {
      await repos.history.recordLiquidity(token.id, snapshot.liquidity, now);
    }
    await this.persistWallets(token.id, snapshot).catch((err) =>
      this.d.logger.warn({ err: errorMessage(err) }, 'wallet persistence failed'),
    );
    if (action === 'SKIP') {
      await repos.events.log(
        'info',
        'skipped',
        `${label}: ${reasons[0] ?? ''}`.slice(0, 500),
        { reasonCode, trigger: req.trigger },
        token.id,
      );
    }

    // Alerts + realtime events
    await this.raiseAlerts(
      updated,
      snapshot,
      report,
      decision,
      previous,
      previousReport,
      openPosition !== null,
    ).catch((err) => this.d.logger.warn({ err: errorMessage(err) }, 'alert generation failed'));
    const openSummary =
      position && position.status === 'open'
        ? {
            id: position.id,
            quantity: position.quantity,
            entryPriceUsd: position.entryPriceUsd,
            costBasisUsd: position.costBasisUsd,
            unrealizedPnlUsd: position.unrealizedPnlUsd,
            unrealizedPnlPct: position.unrealizedPnlPct,
          }
        : null;
    this.d.bus.publish({ type: 'token.analyzed', data: { token: toTokenListItem(updated, openSummary) } });
    this.d.bus.publish({ type: 'decision', data: decision });
    this.d.logger.info(
      {
        token: `${snapshot.chain}:${snapshot.address}`,
        symbol: snapshot.symbol,
        action: decision.action,
        label: decision.label,
        rugScore: report.rugScore,
        trigger: req.trigger,
      },
      'decision',
    );
    return { decision, report, snapshot, trade, position };
  }

  private async persistWallets(tokenId: number, s: TokenSnapshot): Promise<void> {
    const { repos } = this.d;
    const holders = s.holders ? circulatingHolders(s.holders.topHolders, s.chain).slice(0, 10) : [];
    const clusterOf = new Map<string, string>();
    for (const cl of s.wallets?.clusters ?? []) for (const w of cl.wallets) clusterOf.set(w, cl.funder);
    for (const h of holders) {
      const w = await repos.wallets.upsert({
        chain: s.chain,
        address: h.address,
        label: h.isInsider ? 'insider' : 'top_holder',
      });
      await repos.wallets.link(tokenId, w.id, 'top_holder', h.percent, clusterOf.get(h.address) ?? null);
    }
    if (s.deployer?.address) {
      const w = await repos.wallets.upsert({
        chain: s.chain,
        address: s.deployer.address,
        label: 'deployer',
      });
      await repos.wallets.link(tokenId, w.id, 'deployer', s.deployer.holdsPercent, null);
    }
    const events = s.developer?.events.filter((e) => e.signature) ?? [];
    if (events.length > 0) {
      await repos.transactions.insertNew(
        events.map((e) => ({
          chain: s.chain,
          tokenId,
          txHash: e.signature as string,
          wallet: s.developer?.devAddress ?? null,
          kind: e.kind,
          percentOfSupply: e.percentOfSupply,
          counterparty: e.counterparty,
          source: s.developer?.sources.join(',') ?? 'unknown',
          blockTime: e.timestamp ? new Date(e.timestamp) : null,
        })),
      );
    }
  }

  private async raiseAlerts(
    token: TokenRow,
    snapshot: TokenSnapshot,
    report: RiskReport,
    decision: Decision,
    previous: TokenSnapshot | null,
    previousReport: RiskReport | null,
    held: boolean,
  ): Promise<void> {
    const ref = { chain: token.chain, address: token.address, symbol: token.symbol };
    const raise = (c: AlertCandidate) =>
      this.d.alerts.raise({
        type: c.type,
        severity: c.severity,
        title: c.title,
        message: c.message,
        tokenId: token.id,
        token: ref,
        data: c.data,
        dedupeKey: `${c.type}:${token.id}${c.key ? `:${c.key}` : ''}`,
      });

    if (!previousReport && report.isLikelyScam) {
      await raise({
        type: 'NEW_HIGH_RISK_TOKEN',
        severity: 'warning',
        title: 'New high-risk token',
        message: `Rug score ${report.rugScore} (${report.overallRisk}). ${report.criticalFlags.slice(0, 3).join(', ') || report.explanations.overallRisk}`,
        data: { rugScore: report.rugScore, overall: report.overallRisk },
      });
    }
    if (decision.action === 'BUY') {
      await raise({
        type: 'TRADING_OPPORTUNITY',
        severity: 'info',
        title: decision.executed ? 'Trade opportunity executed' : 'Trading opportunity',
        message: `${decision.label}: strategy score ${decision.strategyScore}, rug score ${report.rugScore}. ${decision.reasons.slice(-1)[0] ?? ''}`,
        data: {
          strategyScore: decision.strategyScore,
          rugScore: report.rugScore,
          executed: decision.executed,
        },
        key: String(decision.id),
      });
    }
    // Change-based alerts: always for held tokens; otherwise only when the token did not already
    // look like a scam (avoids alert spam from tokens we already rejected).
    if (previous && (held || !previousReport?.isLikelyScam)) {
      // Market rules share dedupe keys with the position monitor, so a liquidity pull detected by
      // either path alerts exactly once.
      const candidates = [
        ...marketAlerts(previous.market, snapshot.market),
        ...analysisAlerts(
          { market: previous.market, snapshot: previous, report: previousReport },
          { market: snapshot.market, snapshot, report },
        ),
      ];
      for (const c of candidates) await raise(c);
    }
  }
}
