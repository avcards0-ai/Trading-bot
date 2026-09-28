import { describe, expect, it } from 'vitest';
import type { RiskReport } from '@memeguard/shared';
import { RugDetector } from '../../src/analysis/rug/detector';
import { loadConfig } from '../../src/config/env';
import { estimateBuyImpactPct, simulateBuy, simulateSell } from '../../src/execution/amm';
import { PaperExecutor } from '../../src/execution/paperExecutor';
import { RiskManager, type EntryRiskInput } from '../../src/risk/riskManager';
import { computePositionSize } from '../../src/strategy/sizing';
import { evaluateEntry, evaluateExit } from '../../src/strategy/strategy';
import { NOW, cleanSnapshot, market } from '../helpers/snapshots';

const cfg = loadConfig({} as NodeJS.ProcessEnv);
const limits = cfg.hardLimits;
const strategy = cfg.defaultStrategy;
const report = (s = cleanSnapshot()): RiskReport => new RugDetector().analyze(s, { now: NOW });

describe('strategy entry', () => {
  it('buys a healthy, safe setup', () => {
    const e = evaluateEntry(cleanSnapshot(), report(), strategy, limits, NOW);
    expect(e.action).toBe('BUY');
    expect(e.score).toBeGreaterThanOrEqual(strategy.minStrategyScore);
    expect(Object.keys(e.components)).toHaveLength(6);
  });

  it('watches (HOLD) a qualifying token that is younger than MIN_TOKEN_AGE', () => {
    const s = cleanSnapshot({
      market: market({ pairCreatedAt: new Date(NOW.getTime() - 5 * 60_000).toISOString() }),
    });
    const e = evaluateEntry(s, report(s), strategy, limits, NOW);
    expect(e.action).toBe('HOLD');
    expect(e.reasonCode).toBe('WAIT_MIN_TOKEN_AGE');
  });

  it('skips when entry gates fail (sell pressure, no volume, chasing a spike)', () => {
    const s = cleanSnapshot({
      market: market({
        txns: { m5: { buys: 5, sells: 50 }, h1: { buys: 100, sells: 300 }, h6: null, h24: null },
        volumeUsd: { m5: 10, h1: 500, h6: 1000, h24: 2000 },
        priceChangePct: { m5: 80, h1: 120, h6: null, h24: null },
      }),
    });
    const e = evaluateEntry(s, report(s), strategy, limits, NOW);
    expect(e.action).toBe('SKIP');
    expect(e.reasons.join(' ')).toMatch(/buy\/sell ratio/);
    expect(e.reasons.join(' ')).toMatch(/not chasing/);
  });

  it('skips tokens outside the strategy age window and disabled chains', () => {
    const old = cleanSnapshot({
      market: market({ pairCreatedAt: new Date(NOW.getTime() - 5 * 86_400_000).toISOString() }),
    });
    expect(evaluateEntry(old, report(old), strategy, limits, NOW).reasonCode).toBe('OUTSIDE_AGE_WINDOW');
    expect(
      evaluateEntry(cleanSnapshot(), report(), { ...strategy, chains: ['base'] }, limits, NOW).reasonCode,
    ).toBe('CHAIN_DISABLED');
  });
});

describe('strategy exit', () => {
  const pos = {
    entryPriceUsd: 1,
    stopLossPriceUsd: 0.85,
    takeProfitPriceUsd: 1.4,
    trailingStopPercent: 10,
    highestPriceUsd: 1.3,
    entryLiquidityUsd: 100_000,
    openedAt: new Date(NOW.getTime() - 30 * 60_000),
  };
  const exit = (
    price: number,
    liq = 100_000,
    rep: Pick<RiskReport, 'rugScore' | 'isLikelyScam'> | null = { rugScore: 10, isLikelyScam: false },
    openedAt = pos.openedAt,
  ) => evaluateExit({ ...pos, openedAt }, price, liq, rep, strategy, NOW);

  it('exits on rug-risk escalation before anything else', () => {
    expect(exit(1.5, 100_000, { rugScore: 95, isLikelyScam: true }).reason).toBe('rug_risk_escalation');
  });
  it('exits on liquidity pulls', () => expect(exit(1.1, 40_000).reason).toBe('liquidity_drop'));
  it('exits on stop loss', () => expect(exit(0.8).reason).toBe('stop_loss'));
  it('exits on trailing stop from the high', () => expect(exit(1.15).reason).toBe('trailing_stop'));
  it('exits on take profit', () => expect(exit(1.45).reason).toBe('take_profit'));
  it('exits after max hold time', () =>
    expect(exit(1.25, 100_000, undefined, new Date(NOW.getTime() - 500 * 60_000)).reason).toBe(
      'max_hold_time',
    ));
  it('holds otherwise', () => expect(exit(1.25).action).toBe('HOLD'));
});

describe('position sizing', () => {
  const base = {
    equityUsd: 10_000,
    cashUsd: 10_000,
    liquidityUsd: 150_000,
    priceUsd: 0.001,
    limits,
    params: strategy,
    strategyScore: 100,
    rugScore: 0,
    dexFeePct: 0.25,
    networkFeeUsd: 0.03,
  };

  it('takes the smallest cap and reports which one bound', () => {
    const s = computePositionSize(base);
    expect(s.sizeUsd).toBeLessThanOrEqual((10_000 * limits.maxPositionPercent) / 100);
    expect(s.limitingFactor).toBe('MAX_POSITION_PERCENT');
  });

  it('is limited by pool liquidity in thin pools', () => {
    const s = computePositionSize({ ...base, liquidityUsd: 5_000 });
    expect(s.limitingFactor).toBe('LIQUIDITY_SHARE');
    expect(s.sizeUsd).toBeLessThanOrEqual(50);
  });

  it('shrinks for weaker setups and higher rug scores, and never exceeds a manual request', () => {
    const weak = computePositionSize({ ...base, strategyScore: strategy.minStrategyScore, rugScore: 30 });
    expect(weak.sizeUsd).toBeLessThan(computePositionSize(base).sizeUsd);
    expect(computePositionSize({ ...base, requestedUsd: 25 }).sizeUsd).toBe(25);
  });

  it('sets stop and target from the strategy', () => {
    const s = computePositionSize(base);
    expect(s.stopLossPrice).toBeCloseTo(0.001 * (1 - strategy.stopLossPercent / 100));
    expect(s.takeProfitPrice).toBeCloseTo(0.001 * (1 + strategy.takeProfitPercent / 100));
  });
});

describe('RiskManager (fail closed)', () => {
  const rm = new RiskManager();
  const snap = cleanSnapshot();
  const good = (): EntryRiskInput => ({
    mode: 'paper',
    tradingEnabled: true,
    liveExecutionSupported: true,
    account: {
      equityUsd: 10_000,
      cashUsd: 10_000,
      peakEquityUsd: 10_000,
      dayStartEquityUsd: 10_000,
      halted: false,
      haltReason: null,
    },
    openPositions: 0,
    hasOpenPositionForToken: false,
    snapshot: snap,
    report: report(snap),
    sizing: computePositionSize({
      equityUsd: 10_000,
      cashUsd: 10_000,
      liquidityUsd: 150_000,
      priceUsd: 0.001,
      limits,
      params: strategy,
      strategyScore: 80,
      rugScore: 10,
      dexFeePct: 0.25,
      networkFeeUsd: 0.03,
    }),
    limits,
    strategy,
    networkFeeUsd: 0.03,
    llm: { required: false, failed: false, error: null },
    now: NOW,
  });

  it('approves only when every check passes', () => {
    const r = rm.evaluateEntry(good());
    expect(r.failed).toEqual([]);
    expect(r.approved).toBe(true);
  });

  const cases: [string, (i: EntryRiskInput) => void, string][] = [
    ['auto-trading disabled', (i) => (i.tradingEnabled = false), 'TRADING_ENABLED'],
    ['halted account', (i) => (i.account.halted = true), 'NOT_HALTED'],
    ['daily loss limit hit', (i) => (i.account.equityUsd = 9_400), 'MAX_DAILY_LOSS'],
    [
      'max drawdown hit',
      (i) => {
        i.account.peakEquityUsd = 20_000;
        i.account.dayStartEquityUsd = 10_000;
      },
      'MAX_DRAWDOWN',
    ],
    ['too many positions', (i) => (i.openPositions = limits.maxOpenPositions), 'MAX_OPEN_POSITIONS'],
    ['duplicate position', (i) => (i.hasOpenPositionForToken = true), 'NO_DUPLICATE_POSITION'],
    [
      'low liquidity',
      (i) => (i.snapshot = cleanSnapshot({ market: market({ liquidityUsd: 1_000 }) })),
      'MIN_LIQUIDITY',
    ],
    [
      'unknown liquidity',
      (i) => (i.snapshot = cleanSnapshot({ market: market({ liquidityUsd: null }) })),
      'MIN_LIQUIDITY',
    ],
    ['rug score too high', (i) => (i.report = { ...i.report, rugScore: 90 }), 'MAX_RUG_SCORE'],
    [
      'critical flags',
      (i) => (i.report = { ...i.report, criticalFlags: ['x'], isLikelyScam: true }),
      'NO_CRITICAL_FLAGS',
    ],
    ['honeypot unverified', (i) => (i.snapshot = cleanSnapshot({ honeypot: null })), 'HONEYPOT_VERIFIED'],
    [
      'token too young',
      (i) =>
        (i.snapshot = cleanSnapshot({
          market: market({ pairCreatedAt: new Date(NOW.getTime() - 60_000).toISOString() }),
        })),
      'MIN_TOKEN_AGE',
    ],
    [
      'unknown token age',
      (i) => (i.snapshot = cleanSnapshot({ market: market({ pairCreatedAt: null }) })),
      'MIN_TOKEN_AGE',
    ],
    [
      'stale data',
      (i) =>
        (i.snapshot = cleanSnapshot({
          market: market({ fetchedAt: new Date(NOW.getTime() - 3_600_000).toISOString() }),
        })),
      'DATA_FRESHNESS',
    ],
    ['position too small', (i) => (i.sizing = { ...i.sizing!, sizeUsd: 1 }), 'MIN_POSITION_SIZE'],
    ['position too large', (i) => (i.sizing = { ...i.sizing!, sizeUsd: 5_000 }), 'MAX_POSITION_PERCENT'],
    [
      'too large vs pool',
      (i) => {
        i.sizing = { ...i.sizing!, sizeUsd: 199 };
        i.limits = { ...limits, maxLiquiditySharePercent: 0.1 };
      },
      'LIQUIDITY_SHARE',
    ],
    ['slippage too high', (i) => (i.sizing = { ...i.sizing!, expectedSlippagePct: 9 }), 'MAX_SLIPPAGE'],
    ['not enough cash', (i) => (i.account.cashUsd = 5), 'SUFFICIENT_CASH'],
    ['no sizing at all', (i) => (i.sizing = null), 'MIN_POSITION_SIZE'],
    [
      'live chain without venue',
      (i) => {
        i.mode = 'live';
        i.liveExecutionSupported = false;
      },
      'LIVE_EXECUTION_SUPPORTED',
    ],
    [
      'required LLM review failed',
      (i) => (i.llm = { required: true, failed: true, error: 'timeout' }),
      'LLM_REVIEW',
    ],
  ];
  it.each(cases)('rejects: %s', (_name, mutate, check) => {
    const input = good();
    mutate(input);
    const r = rm.evaluateEntry(input);
    expect(r.approved).toBe(false);
    expect(r.failed.map((f) => f.check)).toContain(check);
  });

  it('treats an exception inside a check as a failure', () => {
    const input = good();
    input.account = { ...input.account, dayStartEquityUsd: Number.NaN };
    const r = rm.evaluateEntry(input);
    expect(r.approved).toBe(false);
    expect(r.failed.find((f) => f.check === 'MAX_DAILY_LOSS')?.message).toMatch(/fail-closed/);
  });
});

describe('AMM model and paper execution', () => {
  it('computes constant-product price impact', () => {
    expect(estimateBuyImpactPct(1_000, 200_000, 0)).toBeCloseTo(1, 5);
    const b = simulateBuy(1_000, 1, 200_000, 0.25, 0);
    expect(b.avgPriceUsd).toBeGreaterThan(1);
    const s = simulateSell(b.tokensOut, 1, 200_000, 0.25, 0);
    expect(s.usdOut).toBeLessThan(1_000);
  });

  it('applies token taxes', () => {
    const noTax = simulateBuy(100, 1, 1e6, 0, 0).tokensOut;
    expect(simulateBuy(100, 1, 1e6, 0, 10).tokensOut).toBeCloseTo(noTax * 0.9, 6);
  });

  const exec = new PaperExecutor({ dexFeePct: 0.25, failureRate: 0, seed: 1, maxLatencyDriftPct: 0 });
  const req = {
    chain: 'solana' as const,
    address: 'M',
    decimals: 6,
    market: market({ priceUsd: 1, liquidityUsd: 200_000 }),
    maxSlippagePct: 3,
    taxes: { buyPct: 0, sellPct: 0 },
  };

  it('fills buys with slippage and fees accounted', async () => {
    const r = await exec.execute({ ...req, side: 'buy', amountUsd: 500 });
    expect(r.status).toBe('filled');
    expect(r.filledUsd).toBeCloseTo(500.03, 2);
    expect(r.slippagePct).toBeGreaterThan(0);
    expect(r.feeUsd).toBeGreaterThan(1);
  });

  it('reverts when price impact exceeds the slippage tolerance (fee still charged)', async () => {
    const r = await exec.execute({ ...req, side: 'buy', amountUsd: 20_000, maxSlippagePct: 3 });
    expect(r.status).toBe('failed');
    expect(r.error).toMatch(/slippage tolerance exceeded/);
    expect(r.feeUsd).toBeGreaterThan(0);
  });

  it('rejects orders larger than the pool can absorb', async () => {
    const r = await exec.execute({ ...req, side: 'buy', amountUsd: 50_000, maxSlippagePct: 50 });
    expect(r.error).toMatch(/insufficient liquidity/);
  });

  it('simulates random transaction failures deterministically', async () => {
    const flaky = new PaperExecutor({ dexFeePct: 0.25, failureRate: 1, seed: 7 });
    const r = await flaky.execute({ ...req, side: 'buy', amountUsd: 100 });
    expect(r.status).toBe('failed');
    expect(r.error).toMatch(/simulated failure/);
  });

  it('sells into the pool net of sell tax', async () => {
    const r = await exec.execute({ ...req, side: 'sell', quantity: 100, taxes: { buyPct: 0, sellPct: 10 } });
    expect(r.status).toBe('filled');
    expect(r.filledUsd).toBeLessThan(90);
  });
});
