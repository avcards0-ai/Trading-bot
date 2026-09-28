import type {
  BacktestResult,
  BacktestTrade,
  CatastrophicEvent,
  MarketData,
  RiskReport,
  TokenSnapshot,
  TxnCounts,
} from '@memeguard/shared';
import { emptyContract } from '../analysis/merge';
import { RugDetector } from '../analysis/rug/detector';
import { NETWORK_FEE_USD, estimateExitValueUsd, simulateBuy, simulateSell } from '../execution/amm';
import { createRng } from '../lib/math';
import { utcDay } from '../lib/time';
import { RiskManager } from '../risk/riskManager';
import { computePositionSize } from '../strategy/sizing';
import { evaluateEntry, evaluateExit } from '../strategy/strategy';
import { computeMetrics, maxDrawdown, type EquityPoint } from './metrics';
import type { BacktestConfig, BacktestDataset, HistoricalBar, HistoricalToken, SecuritySnapshot } from './types';

const MIN = 60_000;

interface Pos {
  tokenIdx: number;
  qty: number;
  cost: number;
  entryPrice: number;
  sl: number;
  tp: number;
  highest: number;
  entryLiq: number | null;
  openedAt: Date;
  entryTs: string;
  rugDuringHold: boolean;
}

interface TokState {
  lastEvalAt: number;
  rejectedForRug: boolean;
  skippedRug: boolean;
  evaluated: boolean;
  everBought: boolean;
  lastClose: number | null;
  lastLiq: number | null;
  bars: HistoricalBar[];
  times: number[];
  eventTimes: { t: number; type: string }[];
  scamTruth: 'honeypot' | 'rug' | null;
}

/** Security data used when a dataset has none and assumeCleanSecurity=true. */
function assumedCleanSecurity(chain: TokenSnapshot['chain']): SecuritySnapshot {
  const contract = emptyContract(['assumed-clean']);
  contract.tokenProgram = chain === 'solana' ? 'spl-token' : 'evm';
  contract.isVerified = true;
  contract.ownershipRenounced = true;
  contract.mintable = false;
  contract.freezable = false;
  contract.buyTaxPct = 0;
  contract.sellTaxPct = 0;
  return {
    contract,
    liquidity: {
      sources: ['assumed-clean'],
      totalLiquidityUsd: null,
      lpLockedPercent: 0,
      lpBurnedPercent: 100,
      programControlled: false,
      creatorLpPercent: 0,
      lpHolderCount: null,
      poolCount: 1,
    },
    honeypot: {
      source: 'assumed-clean',
      simulated: true,
      isHoneypot: false,
      buyTaxPct: 0,
      sellTaxPct: 0,
      transferTaxPct: 0,
      sellRouteFound: true,
      reason: null,
    },
  };
}

/** Rolling-window market view at bar index i, built only from data available at that time. */
export function marketAt(tok: HistoricalToken, st: TokState, i: number): MarketData {
  const bar = st.bars[i] as HistoricalBar;
  const t = st.times[i] as number;
  const since = (ms: number) => {
    let vol = 0;
    let buys = 0;
    let sells = 0;
    let hasTx = false;
    for (let j = i; j >= 0 && (st.times[j] as number) > t - ms; j--) {
      const b = st.bars[j] as HistoricalBar;
      vol += b.volumeUsd;
      if (b.buys !== null && b.buys !== undefined && b.sells !== null && b.sells !== undefined) {
        hasTx = true;
        buys += b.buys;
        sells += b.sells;
      }
    }
    return { vol, tx: hasTx ? ({ buys, sells } as TxnCounts) : null };
  };
  const changeOver = (ms: number) => {
    let ref = (st.bars[0] as HistoricalBar).open;
    for (let j = i; j >= 0; j--) {
      if ((st.times[j] as number) <= t - ms) {
        ref = (st.bars[j] as HistoricalBar).close;
        break;
      }
    }
    return ref > 0 ? ((bar.close - ref) / ref) * 100 : null;
  };
  const w = bar.window ?? {};
  const m5 = since(5 * MIN);
  const h1 = since(60 * MIN);
  const h6 = since(360 * MIN);
  const h24 = since(1440 * MIN);
  const liq = bar.liquidityUsd ?? st.lastLiq;
  const tx = (b: number | null | undefined, s: number | null | undefined, fallback: TxnCounts | null) =>
    b !== null && b !== undefined && s !== null && s !== undefined ? { buys: b, sells: s } : fallback;
  return {
    source: 'backtest',
    pairAddress: null,
    dexId: null,
    quoteSymbol: null,
    priceUsd: bar.close,
    priceNative: null,
    marketCapUsd: null,
    fdvUsd: null,
    liquidityUsd: liq ?? null,
    volumeUsd: {
      m5: w.volume5m ?? m5.vol,
      h1: w.volume1h ?? h1.vol,
      h6: h6.vol,
      h24: w.volume24h ?? h24.vol,
    },
    priceChangePct: {
      m5: w.priceChange5m ?? changeOver(5 * MIN),
      h1: w.priceChange1h ?? changeOver(60 * MIN),
      h6: changeOver(360 * MIN),
      h24: changeOver(1440 * MIN),
    },
    txns: {
      m5: tx(w.buys5m, w.sells5m, m5.tx),
      h1: tx(w.buys1h, w.sells1h, h1.tx),
      h6: h6.tx,
      h24: h24.tx,
    },
    pairCreatedAt: tok.pairCreatedAt,
    fetchedAt: new Date(t).toISOString(),
  };
}

/**
 * Replays historical token data through the SAME rug detector, strategy, position sizing and
 * risk manager used live. Fill assumptions are deliberately pessimistic:
 *  - if a bar touches both the stop and the target, the stop is assumed to fill first
 *  - stops gap: if a bar opens below the stop, the fill is at the open (often far worse)
 *  - rug events exit into the collapsed pool at the bar's low
 *  - honeypot tokens cannot be sold at all (100% loss)
 */
export function runBacktest(dataset: BacktestDataset, config: BacktestConfig): BacktestResult {
  const startedAt = new Date();
  const detector = new RugDetector({ freshWalletAgeHours: 72 });
  const riskManager = new RiskManager();
  const rng = createRng(config.seed);
  const warnings: string[] = [];

  if (dataset.synthetic) {
    warnings.push('SYNTHETIC DATA: results demonstrate engine behaviour only and are NOT evidence of real-world profitability.');
  }
  const noSecurity = dataset.tokens.filter((t) => !t.security && !t.riskTimeline?.length).length;
  if (noSecurity > 0) {
    warnings.push(
      config.assumeCleanSecurity
        ? `${noSecurity} token(s) have no security data and were ASSUMED CLEAN: the rug filter was not exercised for them and results are optimistic.`
        : `${noSecurity} token(s) have no security data; they are treated as unverifiable (fail-closed) and will not be traded.`,
    );
  }
  if (dataset.tokens.some((t) => t.bars.some((b) => b.liquidityUsd === undefined || b.liquidityUsd === null))) {
    warnings.push('Some bars lack liquidity; the last known liquidity is carried forward (liquidity pulls between observations are missed).');
  }
  warnings.push('Exits are assumed to fill even when price impact exceeds EXIT_MAX_SLIPPAGE; in reality a collapsing pool may not be exitable at all.');

  const states: TokState[] = dataset.tokens.map((tok) => {
    const bars = [...tok.bars].sort((a, b) => Date.parse(a.ts) - Date.parse(b.ts));
    const scenario = tok.outcome?.scenario;
    return {
      lastEvalAt: -Infinity,
      rejectedForRug: false,
      skippedRug: false,
      evaluated: false,
      everBought: false,
      lastClose: null,
      lastLiq: null,
      bars,
      times: bars.map((b) => Date.parse(b.ts)),
      eventTimes: (tok.events ?? []).map((e) => ({ t: Date.parse(e.ts), type: e.type })),
      scamTruth:
        scenario === 'honeypot' || (tok.events ?? []).some((e) => e.type === 'honeypot_enabled')
          ? 'honeypot'
          : tok.outcome?.rugged
            ? 'rug'
            : null,
    };
  });

  // Global timeline
  const timeline: { t: number; k: number; i: number }[] = [];
  states.forEach((s, k) => s.times.forEach((t, i) => timeline.push({ t, k, i })));
  timeline.sort((a, b) => a.t - b.t || a.k - b.k);

  let cash = config.startingBalanceUsd;
  const positions = new Map<number, Pos>();
  const trades: BacktestTrade[] = [];
  const events: CatastrophicEvent[] = [];
  const curve: EquityPoint[] = [];
  let peak = cash;
  let day = '';
  let dayStart = cash;
  let halted: 'daily' | 'drawdown' | null = null;
  let drawdownBreached = false;
  let exposureSteps = 0;
  let steps = 0;

  const conservativeEquity = () => {
    let eq = cash;
    for (const p of positions.values()) {
      const st = states[p.tokenIdx] as TokState;
      eq += estimateExitValueUsd(p.qty, st.lastClose, st.lastLiq, config.dexFeePct, 0) ?? 0;
    }
    return eq;
  };
  const markEquity = () => {
    let eq = cash;
    for (const p of positions.values()) eq += p.qty * ((states[p.tokenIdx] as TokState).lastClose ?? 0);
    return eq;
  };

  const securityFor = (tok: HistoricalToken): SecuritySnapshot | null =>
    tok.security ?? (config.assumeCleanSecurity ? assumedCleanSecurity(tok.chain) : null);

  const reportAt = (tok: HistoricalToken, snapshot: TokenSnapshot, t: number): RiskReport | null => {
    if (tok.riskTimeline?.length) {
      let found: RiskReport | null = null;
      for (const e of tok.riskTimeline) if (Date.parse(e.ts) <= t) found = e.report;
      return found;
    }
    return detector.analyze(snapshot, { now: new Date(t) });
  };

  const closePos = (k: number, price: number, liq: number | null, reason: string, ts: string, stopGap: boolean) => {
    const p = positions.get(k) as Pos;
    const tok = dataset.tokens[k] as HistoricalToken;
    const st = states[k] as TokState;
    const fee = NETWORK_FEE_USD[tok.chain];
    const sellTax = Math.max(0, securityFor(tok)?.contract?.sellTaxPct ?? 0, securityFor(tok)?.honeypot?.sellTaxPct ?? 0);
    let proceeds: number;
    if (st.scamTruth === 'honeypot') {
      proceeds = 0; // sells are impossible
    } else if (!liq || liq <= 0 || price <= 0) {
      proceeds = 0;
    } else {
      proceeds = Math.max(0, simulateSell(p.qty, price, liq, config.dexFeePct, sellTax).usdOut - fee);
    }
    cash += proceeds;
    const pnl = proceeds - p.cost;
    const pnlPct = (pnl / p.cost) * 100;
    const catastrophic = pnlPct <= -config.catastrophicLossPct || p.rugDuringHold || stopGap || st.scamTruth === 'honeypot';
    trades.push({
      address: tok.address,
      symbol: tok.symbol,
      entryTs: p.entryTs,
      exitTs: ts,
      entryPriceUsd: p.entryPrice,
      exitPriceUsd: p.qty > 0 ? proceeds / p.qty : 0,
      sizeUsd: p.cost,
      pnlUsd: Math.round(pnl * 100) / 100,
      pnlPct: Math.round(pnlPct * 100) / 100,
      feesUsd: Math.round((p.cost * config.dexFeePct) / 100 + (proceeds * config.dexFeePct) / 100 + 2 * fee),
      exitReason: st.scamTruth === 'honeypot' ? `${reason} (honeypot: sell impossible)` : reason,
      catastrophic,
      rugEventDuringHold: p.rugDuringHold || st.scamTruth === 'honeypot',
    });
    if (catastrophic) {
      const kind: CatastrophicEvent['kind'] = p.rugDuringHold || st.scamTruth ? 'rug_while_holding' : stopGap ? 'stop_gap_through' : 'catastrophic_trade_loss';
      events.push({
        address: tok.address,
        symbol: tok.symbol,
        ts,
        kind,
        lossUsd: Math.round(-pnl * 100) / 100,
        lossPct: Math.round(-pnlPct * 100) / 100,
        description:
          kind === 'rug_while_holding'
            ? `${st.scamTruth === 'honeypot' ? 'Honeypot' : 'Rug pull'} while holding: lost ${(-pnlPct).toFixed(1)}% of a $${p.cost.toFixed(2)} position.`
            : kind === 'stop_gap_through'
              ? `Price gapped through the stop loss; exit at $${price.toPrecision(4)} vs stop $${p.sl.toPrecision(4)} (${(-pnlPct).toFixed(1)}% loss).`
              : `Single trade lost ${(-pnlPct).toFixed(1)}% (>= ${config.catastrophicLossPct}% threshold).`,
      });
    }
    positions.delete(k);
  };

  let idx = 0;
  while (idx < timeline.length) {
    const t = (timeline[idx] as { t: number }).t;
    const group: { k: number; i: number }[] = [];
    while (idx < timeline.length && (timeline[idx] as { t: number }).t === t) {
      const e = timeline[idx] as { k: number; i: number };
      group.push({ k: e.k, i: e.i });
      idx += 1;
    }
    const now = new Date(t);
    const ts = now.toISOString();
    const today = utcDay(now);
    if (today !== day) {
      day = today;
      dayStart = conservativeEquity();
      if (halted === 'daily') halted = null;
    }

    for (const { k, i } of group) {
      const tok = dataset.tokens[k] as HistoricalToken;
      const st = states[k] as TokState;
      const bar = st.bars[i] as HistoricalBar;
      const prevT = i > 0 ? (st.times[i - 1] as number) : -Infinity;
      if (bar.liquidityUsd !== undefined && bar.liquidityUsd !== null) st.lastLiq = bar.liquidityUsd;
      st.lastClose = bar.close;
      const liq = st.lastLiq;

      const pos = positions.get(k);
      if (pos) {
        const rugNow = st.eventTimes.some((e) => (e.type === 'rug' || e.type === 'liquidity_removed') && e.t > prevT && e.t <= t);
        if (rugNow) {
          pos.rugDuringHold = true;
          closePos(k, bar.low, liq, 'rug_event', ts, false);
          continue;
        }
        const view = {
          entryPriceUsd: pos.entryPrice,
          stopLossPriceUsd: pos.sl,
          takeProfitPriceUsd: pos.tp,
          trailingStopPercent: config.strategy.trailingStopPercent,
          highestPriceUsd: pos.highest,
          entryLiquidityUsd: pos.entryLiq,
          openedAt: pos.openedAt,
        };
        const low = evaluateExit(view, bar.low, liq, null, config.strategy, now);
        if (low.action === 'SELL' && low.reason !== 'max_hold_time' && low.reason !== 'take_profit') {
          if (low.reason === 'stop_loss') {
            const gap = bar.open < pos.sl;
            const price = gap ? bar.open : pos.sl;
            closePos(k, price, liq, 'stop_loss', ts, gap && price < pos.sl * 0.9);
          } else if (low.reason === 'trailing_stop') {
            const trail = pos.highest * (1 - (config.strategy.trailingStopPercent ?? 0) / 100);
            closePos(k, bar.open < trail ? bar.open : trail, liq, 'trailing_stop', ts, false);
          } else {
            closePos(k, bar.close, liq, low.reason ?? 'exit', ts, false);
          }
          continue;
        }
        const high = evaluateExit(view, bar.high, liq, null, config.strategy, now);
        if (high.action === 'SELL' && high.reason === 'take_profit') {
          closePos(k, bar.open > pos.tp ? bar.open : pos.tp, liq, 'take_profit', ts, false);
          continue;
        }
        const close = evaluateExit(view, bar.close, liq, null, config.strategy, now);
        if (close.action === 'SELL') {
          closePos(k, bar.close, liq, close.reason ?? 'exit', ts, false);
          continue;
        }
        pos.highest = Math.max(pos.highest, bar.high);
        continue;
      }

      // Entry evaluation
      if (st.rejectedForRug || st.everBought || halted) continue;
      const ageMin = (t - Date.parse(tok.pairCreatedAt)) / MIN;
      if (ageMin > config.strategy.maxTokenAgeMinutes) continue;
      if (t - st.lastEvalAt < config.evaluateEveryMinutes * MIN) continue;
      st.lastEvalAt = t;
      st.evaluated = true;

      const sec = securityFor(tok);
      const market = marketAt(tok, st, i);
      const snapshot: TokenSnapshot = {
        chain: tok.chain,
        address: tok.address,
        name: tok.name ?? null,
        symbol: tok.symbol,
        decimals: null,
        collectedAt: ts,
        market,
        contract: sec?.contract ?? null,
        holders: sec?.holders ?? null,
        liquidity: sec?.liquidity ? { ...sec.liquidity, totalLiquidityUsd: liq ?? null } : null,
        honeypot: sec?.honeypot ?? null,
        deployer: sec?.deployer ?? null,
        trades: sec?.trades ?? null,
        wallets: sec?.wallets ?? null,
        developer: sec?.developer ?? null,
        warnings: sec?.warnings ?? [],
        reportedRugged: sec?.reportedRugged ?? null,
        sources: [{ name: 'backtest', ok: true, durationMs: 0, error: null }],
      };
      const report = reportAt(tok, snapshot, t);
      if (!report) continue;
      if (report.isLikelyScam || report.overallRisk === 'CRITICAL' || report.rugScore > config.limits.maxRugScore) {
        // Security data is static per token, so a rug rejection is final.
        if (!tok.riskTimeline?.length) st.rejectedForRug = true;
        st.skippedRug = true;
        continue;
      }
      const entry = evaluateEntry(snapshot, report, config.strategy, config.limits, now);
      if (entry.action !== 'BUY') continue;

      const eq = conservativeEquity();
      const fee = NETWORK_FEE_USD[tok.chain];
      const sizing = computePositionSize({
        equityUsd: eq,
        cashUsd: cash,
        liquidityUsd: liq ?? 0,
        priceUsd: bar.close,
        limits: config.limits,
        params: config.strategy,
        strategyScore: entry.score ?? 0,
        rugScore: report.rugScore,
        dexFeePct: config.dexFeePct,
        networkFeeUsd: fee,
      });
      const risk = riskManager.evaluateEntry({
        mode: 'paper',
        tradingEnabled: true,
        liveExecutionSupported: true,
        account: { equityUsd: eq, cashUsd: cash, peakEquityUsd: Math.max(peak, eq), dayStartEquityUsd: dayStart, halted: false, haltReason: null },
        openPositions: positions.size,
        hasOpenPositionForToken: false,
        snapshot,
        report,
        sizing,
        limits: config.limits,
        strategy: config.strategy,
        networkFeeUsd: fee,
        llm: { required: false, failed: false, error: null },
        now,
      });
      if (!risk.approved) continue;
      if (rng() < config.failureRate) {
        cash -= fee; // failed tx still pays network fee
        continue;
      }
      const buyTax = Math.max(0, sec?.contract?.buyTaxPct ?? 0, sec?.honeypot?.buyTaxPct ?? 0);
      const sim = simulateBuy(sizing.sizeUsd, bar.close, liq ?? 0, config.dexFeePct, buyTax);
      if (!(sim.tokensOut > 0)) continue;
      const cost = sizing.sizeUsd + fee;
      cash -= cost;
      const entryPrice = cost / sim.tokensOut;
      positions.set(k, {
        tokenIdx: k,
        qty: sim.tokensOut,
        cost,
        entryPrice,
        sl: entryPrice * (1 - config.strategy.stopLossPercent / 100),
        tp: entryPrice * (1 + config.strategy.takeProfitPercent / 100),
        highest: Math.max(entryPrice, bar.close),
        entryLiq: liq ?? null,
        openedAt: now,
        entryTs: ts,
        rugDuringHold: false,
      });
      st.everBought = true;
    }

    // Bookkeeping after each timestamp
    steps += 1;
    if (positions.size > 0) exposureSteps += 1;
    const cons = conservativeEquity();
    peak = Math.max(peak, cons);
    const ddPct = peak > 0 ? ((peak - cons) / peak) * 100 : 0;
    if (!halted && cons - dayStart <= -(dayStart * config.limits.maxDailyLossPercent) / 100) halted = 'daily';
    if (ddPct >= config.limits.maxDrawdownPercent) {
      halted = 'drawdown';
      if (!drawdownBreached) {
        drawdownBreached = true;
        events.push({
          address: '',
          symbol: null,
          ts,
          kind: 'drawdown_breach',
          lossUsd: Math.round((peak - cons) * 100) / 100,
          lossPct: Math.round(ddPct * 100) / 100,
          description: `Portfolio drawdown reached ${ddPct.toFixed(1)}% (limit ${config.limits.maxDrawdownPercent}%); new entries halted for the rest of the run.`,
        });
      }
    }
    curve.push({ ts, equityUsd: markEquity() });
  }

  // Close anything still open at the last known price.
  for (const k of [...positions.keys()]) {
    const st = states[k] as TokState;
    const lastTs = new Date(st.times[st.times.length - 1] as number).toISOString();
    closePos(k, st.lastClose ?? 0, st.lastLiq, 'end_of_data', lastTs, false);
  }
  if (curve.length > 0) curve.push({ ts: (curve[curve.length - 1] as EquityPoint).ts, equityUsd: cash });

  const skippedRug = states.filter((s) => s.skippedRug).length;
  const scams = dataset.tokens.map((t, k) => ({ t, s: states[k] as TokState })).filter((x) => x.t.outcome?.rugged || x.s.scamTruth);
  const metrics = computeMetrics({
    startingBalanceUsd: config.startingBalanceUsd,
    endingBalanceUsd: cash,
    trades,
    curve,
    exposureSteps,
    totalSteps: steps,
    tokensEvaluated: states.filter((s) => s.evaluated).length,
    tokensSkippedForRugRisk: skippedRug,
    rugsAvoided: scams.filter((x) => !x.s.everBought).length,
    rugsHit: scams.filter((x) => x.s.everBought).length,
  });
  if (metrics.numberOfTrades < 30) {
    warnings.push(`Only ${metrics.numberOfTrades} trades: too few for statistically meaningful conclusions.`);
  }
  if (metrics.catastrophicLosses > 0) {
    warnings.push(`${metrics.catastrophicLosses} CATASTROPHIC trade(s) occurred — see catastrophicEvents. Do not judge this strategy by total return alone.`);
  }
  if (drawdownBreached) warnings.push('The MAX_DRAWDOWN limit was breached during the run; live trading would have halted.');

  const dd = maxDrawdown(curve);
  const stride = Math.max(1, Math.ceil(curve.length / 1500));
  const sampled = curve
    .map((p, j) => ({ ts: p.ts, equityUsd: Math.round(p.equityUsd * 100) / 100, drawdownPct: Math.round((dd.series[j] ?? 0) * 100) / 100 }))
    .filter((_, j) => j % stride === 0 || j === curve.length - 1);

  return {
    id: null,
    name: dataset.name,
    source: dataset.source,
    syntheticData: dataset.synthetic,
    startedAt: startedAt.toISOString(),
    finishedAt: new Date().toISOString(),
    metrics,
    trades,
    catastrophicEvents: events,
    equityCurve: sampled,
    warnings,
    config: {
      startingBalanceUsd: config.startingBalanceUsd,
      limits: config.limits,
      strategy: config.strategy,
      dexFeePct: config.dexFeePct,
      failureRate: config.failureRate,
      seed: config.seed,
      catastrophicLossPct: config.catastrophicLossPct,
      evaluateEveryMinutes: config.evaluateEveryMinutes,
      assumeCleanSecurity: config.assumeCleanSecurity,
      tokens: dataset.tokens.length,
      notes: dataset.notes ?? [],
    },
  };
}
