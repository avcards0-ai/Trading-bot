import { describe, expect, it } from 'vitest';
import type { Anthropic } from '@anthropic-ai/sdk';
import { runBacktest } from '../../src/backtest/engine';
import { computeMetrics, maxDrawdown } from '../../src/backtest/metrics';
import { generateSyntheticDataset } from '../../src/backtest/synthetic';
import type { BacktestConfig, BacktestDataset } from '../../src/backtest/types';
import { LlmReviewer, buildReviewInput } from '../../src/analysis/llmReviewer';
import { RugDetector } from '../../src/analysis/rug/detector';
import { loadConfig } from '../../src/config/env';
import { createNullLogger } from '../../src/lib/logger';
import { NOW, cleanSnapshot } from '../helpers/snapshots';

const cfg = loadConfig({} as NodeJS.ProcessEnv);
const config = (patch: Partial<BacktestConfig> = {}): BacktestConfig => ({
  startingBalanceUsd: 10_000,
  limits: cfg.hardLimits,
  strategy: cfg.defaultStrategy,
  dexFeePct: 0.25,
  failureRate: 0,
  seed: 1,
  catastrophicLossPct: 50,
  evaluateEveryMinutes: 5,
  exitMaxSlippagePct: 15,
  assumeCleanSecurity: false,
  ...patch,
});

describe('metrics', () => {
  it('computes drawdown from the equity curve', () => {
    const dd = maxDrawdown([
      { ts: 'a', equityUsd: 100 },
      { ts: 'b', equityUsd: 120 },
      { ts: 'c', equityUsd: 90 },
      { ts: 'd', equityUsd: 130 },
    ]);
    expect(dd.pct).toBeCloseTo(25);
    expect(dd.usd).toBe(30);
  });

  it('computes win/loss statistics, profit factor and tail risk', () => {
    const t = (pnl: number) => ({
      address: 'a',
      symbol: null,
      entryTs: '',
      exitTs: '',
      entryPriceUsd: 1,
      exitPriceUsd: 1,
      sizeUsd: 100,
      pnlUsd: pnl,
      pnlPct: pnl,
      feesUsd: 1,
      exitReason: 'x',
      catastrophic: pnl <= -50,
      rugEventDuringHold: false,
    });
    const m = computeMetrics({
      startingBalanceUsd: 1000,
      endingBalanceUsd: 1030,
      trades: [t(40), t(20), t(-10), t(-20)],
      curve: [
        { ts: 'a', equityUsd: 1000 },
        { ts: 'b', equityUsd: 1030 },
      ],
      exposureSteps: 1,
      totalSteps: 2,
      tokensEvaluated: 4,
      tokensSkippedForRugRisk: 0,
      rugsAvoided: 0,
      rugsHit: 0,
    });
    expect(m.winRate).toBe(0.5);
    expect(m.profitFactor).toBe(2);
    expect(m.averageWinUsd).toBe(30);
    expect(m.averageLossUsd).toBe(-15);
    expect(m.largestLossUsd).toBe(-20);
    expect(m.largestGainUsd).toBe(40);
    expect(m.expectancyUsd).toBe(7.5);
    expect(m.cvar95Pct).toBe(-20);
    expect(m.totalReturnPct).toBe(3);
  });
});

describe('backtest engine', () => {
  const ds = generateSyntheticDataset({ tokens: 120, seed: 11 });

  it('is deterministic for a fixed seed', () => {
    const a = runBacktest(ds, config());
    const b = runBacktest(generateSyntheticDataset({ tokens: 120, seed: 11 }), config());
    expect(a.metrics).toEqual(b.metrics);
  });

  it('reports every required metric, labels synthetic data and warns about small samples', () => {
    const r = runBacktest(ds, config());
    for (const k of [
      'startingBalanceUsd',
      'endingBalanceUsd',
      'totalReturnPct',
      'maxDrawdownPct',
      'numberOfTrades',
      'winningTrades',
      'losingTrades',
      'winRate',
      'averageWinUsd',
      'averageLossUsd',
      'profitFactor',
      'largestLossUsd',
      'largestGainUsd',
      'sharpeRatio',
      'cvar95Pct',
    ] as const) {
      expect(r.metrics).toHaveProperty(k);
    }
    expect(r.syntheticData).toBe(true);
    expect(r.warnings[0]).toMatch(/SYNTHETIC/);
  });

  it('the rug filter avoids scams whose red flags are visible at launch', () => {
    const r = runBacktest(ds, config());
    expect(r.metrics.tokensSkippedForRugRisk).toBeGreaterThan(0);
    expect(r.metrics.rugsAvoided).toBeGreaterThan(r.metrics.rugsHit);
    // Visible honeypots are always rejected.
    const hp = ds.tokens.filter((t) => t.outcome?.scenario === 'honeypot').map((t) => t.address);
    expect(r.trades.filter((t) => hp.includes(t.address))).toEqual([]);
  });

  it('explicitly reports catastrophic losses when the filter is bypassed', () => {
    const noSecurity: BacktestDataset = { ...ds, tokens: ds.tokens.map((t) => ({ ...t, security: null })) };
    const r = runBacktest(noSecurity, config({ assumeCleanSecurity: true }));
    expect(r.warnings.some((w) => /ASSUMED CLEAN/.test(w))).toBe(true);
    expect(r.metrics.catastrophicLosses).toBeGreaterThan(0);
    expect(r.catastrophicEvents.some((e) => e.kind === 'rug_while_holding')).toBe(true);
    expect(r.warnings.some((w) => /CATASTROPHIC/.test(w))).toBe(true);
  });

  it('never trades tokens lacking security data unless explicitly told to assume them clean', () => {
    const noSecurity: BacktestDataset = { ...ds, tokens: ds.tokens.map((t) => ({ ...t, security: null })) };
    expect(runBacktest(noSecurity, config()).metrics.numberOfTrades).toBe(0);
  });

  it('fills stops pessimistically when price gaps through them', () => {
    const t0 = Date.parse('2026-01-05T00:00:00Z');
    const bar = (i: number, o: number, h: number, l: number, c: number) => ({
      ts: new Date(t0 + i * 60_000).toISOString(),
      open: o,
      high: h,
      low: l,
      close: c,
      volumeUsd: 3000,
      liquidityUsd: 300_000,
      buys: 30,
      sells: 10,
    });
    const base = generateSyntheticDataset({
      tokens: 1,
      seed: 3,
      mix: { organic: 1, pump_and_dump: 0, rug_pull: 0, stealth_rug: 0, honeypot: 0, slow_bleed: 0 },
    }).tokens[0]!;
    // Steady climb (so the strategy enters), then a gap open far below the stop.
    const bars = Array.from({ length: 100 }, (_, i) =>
      bar(i, 1 + i * 0.005, 1 + i * 0.005 + 0.002, 1 + i * 0.005 - 0.002, 1 + (i + 1) * 0.005),
    );
    bars.push(bar(100, 0.5, 0.5, 0.45, 0.46));
    const r = runBacktest(
      {
        name: 'gap',
        source: 'test',
        synthetic: true,
        tokens: [
          {
            ...base,
            pairCreatedAt: new Date(t0 - 40 * 60_000).toISOString(),
            bars,
            events: [],
            outcome: null,
          },
        ],
      },
      config({
        strategy: {
          ...cfg.defaultStrategy,
          minVolume1hUsd: 1000,
          minStrategyScore: 40,
          takeProfitPercent: 500,
        },
      }),
    );
    expect(r.trades.length).toBe(1);
    expect(r.trades[0]?.exitReason).toBe('stop_loss');
    expect(r.catastrophicEvents[0]?.kind).toBe('stop_gap_through');
  });
});

describe('LLM reviewer', () => {
  const report = new RugDetector().analyze(cleanSnapshot(), { now: NOW });
  const fakeClient = (impl: () => Promise<unknown>) =>
    ({ beta: { messages: { parse: impl } } }) as unknown as Anthropic;

  it('returns a structured escalation', async () => {
    const r = new LlmReviewer({
      apiKey: 'k',
      model: 'claude-opus-5',
      timeoutMs: 1000,
      logger: createNullLogger(),
      client: fakeClient(async () => ({
        stop_reason: 'end_turn',
        model: 'claude-opus-5',
        parsed_output: { escalate: true, concerns: ['dev wallet funded 8 holders'], summary: 's' },
      })),
    });
    await expect(r.review(cleanSnapshot(), report)).resolves.toMatchObject({ escalate: true, error: null });
  });

  it('degrades to a non-escalating review with an error on refusal or failure', async () => {
    const refused = new LlmReviewer({
      apiKey: 'k',
      model: 'm',
      timeoutMs: 1000,
      logger: createNullLogger(),
      client: fakeClient(async () => ({ stop_reason: 'refusal', parsed_output: null })),
    });
    await expect(refused.review(cleanSnapshot(), report)).resolves.toMatchObject({
      escalate: false,
      error: expect.stringMatching(/declined/),
    });
    const broken = new LlmReviewer({
      apiKey: 'k',
      model: 'm',
      timeoutMs: 1000,
      logger: createNullLogger(),
      client: fakeClient(async () => {
        throw new Error('boom');
      }),
    });
    await expect(broken.review(cleanSnapshot(), report)).resolves.toMatchObject({
      escalate: false,
      error: 'boom',
    });
  });

  it('sends a bounded view of the analysis (no raw provider payloads)', () => {
    const input = buildReviewInput(cleanSnapshot(), report);
    expect(input).toHaveProperty('scores');
    expect(JSON.stringify(input).length).toBeLessThan(20_000);
  });
});
