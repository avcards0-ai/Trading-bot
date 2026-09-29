import { afterEach, describe, expect, it } from 'vitest';
import { buildSoakReport, formatSoakReport } from '../../src/soak/report';
import { makeToken, solAddress } from '../helpers/fakeWorld';
import { createTestApp, type TestContext } from '../helpers/testApp';

describe('soak test report', () => {
  let ctx: TestContext;
  afterEach(async () => {
    await ctx?.close();
  });

  it('summarises discovery, risk verdicts, decisions, paper trades and data-source health', async () => {
    ctx = await createTestApp();
    const startedAt = new Date(Date.now() - 1000);
    ctx.world.add(makeToken({ chain: 'solana', address: solAddress(60), symbol: 'GOOD' }));
    ctx.world.add(
      makeToken({ chain: 'solana', address: solAddress(61), symbol: 'TRAP', profile: 'honeypot' }),
    );
    await ctx.app.engine.start();
    await ctx.app.engine.runOnce('discovery');
    await ctx.app.engine.drain(20_000);
    await ctx.app.engine.stop();

    const r = await buildSoakReport(ctx.app, startedAt);
    expect(r.discovery).toEqual({ tokensSeen: 2, tokensAnalysed: 2 });
    expect(r.risk.likelyScams).toBe(1);
    expect(r.risk.byOverallRisk.CRITICAL).toBe(1);
    expect(r.risk.topCriticalFlags.map((f) => f.flag)).toContain('Honeypot confirmed by simulation');
    expect(r.decisions.byAction.SKIP).toBeGreaterThanOrEqual(1);
    expect(r.trading.buys).toBe(1);
    expect(r.trading.startingBalanceUsd).toBe(10_000);
    expect(r.providers.find((p) => p.name === 'dexscreener')?.requests).toBeGreaterThan(0);
    expect(r.problems).toEqual([]);
    expect(formatSoakReport(r)).toMatch(/SOAK TEST REPORT/);
  });

  it('flags failing data sources and missing data in plain language', async () => {
    ctx = await createTestApp();
    const startedAt = new Date(Date.now() - 1000);
    ctx.world.failingHosts.add('api.gopluslabs.io');
    ctx.world.add(makeToken({ chain: 'solana', address: solAddress(62), symbol: 'AAA' }));
    await ctx.app.engine.start();
    await ctx.app.engine.runOnce('discovery');
    await ctx.app.engine.drain(20_000);
    await ctx.app.engine.stop();

    const r = await buildSoakReport(ctx.app, startedAt);
    expect(r.problems.some((p) => p.startsWith('goplus:'))).toBe(true);
    expect(formatSoakReport(r)).toMatch(/! goplus:/);
  });

  it('says so when nothing was discovered (e.g. network blocked)', async () => {
    ctx = await createTestApp();
    const r = await buildSoakReport(ctx.app, new Date());
    expect(r.problems).toContain('No tokens were discovered. Check the network and DISCOVERY_SOURCES.');
  });
});
