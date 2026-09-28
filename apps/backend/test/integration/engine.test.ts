import { afterEach, describe, expect, it } from 'vitest';
import { makeToken, solAddress } from '../helpers/fakeWorld';
import { createTestApp, type TestContext } from '../helpers/testApp';

const A = solAddress(10);
const B = solAddress(11);

describe('trading engine (integration)', () => {
  let ctx: TestContext;
  afterEach(async () => {
    await ctx?.close();
  });

  it('discovers, analyses and paper-trades a new token end to end', async () => {
    ctx = await createTestApp();
    ctx.world.add(makeToken({ chain: 'solana', address: A, symbol: 'AAA' }));
    ctx.world.add(makeToken({ chain: 'solana', address: B, symbol: 'BBB', profile: 'honeypot' }));
    await ctx.app.engine.start();
    await ctx.app.engine.runOnce('discovery');
    await ctx.app.engine.drain(20_000);

    const tokens = await ctx.app.repos.tokens.list({ limit: 10, offset: 0, sort: 'rugScore', order: 'desc' });
    expect(tokens.rows.map((t) => t.symbol).sort()).toEqual(['AAA', 'BBB']);
    const bad = tokens.rows.find((t) => t.symbol === 'BBB');
    expect(bad?.lastDecisionLabel).toBe('SKIP — HIGH RUG RISK');
    const open = await ctx.app.repos.positions.listOpen('paper');
    expect(open).toHaveLength(1);
    expect(open[0]?.token.symbol).toBe('AAA');
    const skipped = await ctx.app.repos.events.list({ limit: 50, category: 'skipped' });
    expect(skipped.some((e) => e.message.includes('HIGH RUG RISK'))).toBe(true);
  });

  it('closes a position on stop loss and raises alerts', async () => {
    ctx = await createTestApp();
    ctx.world.add(makeToken({ chain: 'solana', address: A, symbol: 'AAA' }));
    const { row } = await ctx.app.repos.tokens.upsertDiscovered({
      chain: 'solana',
      address: A,
      discoveredVia: 'test',
    });
    const r = await ctx.app.pipeline.analyze({ tokenId: row.id, trigger: 'discovery', allowTrade: true });
    expect(r.position?.status).toBe('open');

    ctx.world.update(A, { priceUsd: 0.00245 * 0.7, priceChange: { m5: -30, h1: -20, h6: -10, h24: 0 } });
    await ctx.app.engine.runOnce('position-monitor');
    expect(await ctx.app.repos.positions.listOpen('paper')).toHaveLength(0);
    const [closed] = await ctx.app.repos.positions.listRecentClosed('paper', 5);
    expect(closed?.position.closeReason).toBe('stop_loss');
    expect(closed?.position.realizedPnlUsd).toBeLessThan(0);
    await ctx.app.alerts.flush();
    const alerts = await ctx.app.repos.alerts.list({ limit: 50, offset: 0 });
    expect(alerts.items.map((a) => a.type)).toEqual(expect.arrayContaining(['POSITION_OPENED', 'STOP_LOSS']));
    // Prices in messages are rounded to significant digits, not raw floats.
    const stopAlert = alerts.items.find((a) => a.type === 'STOP_LOSS');
    expect(stopAlert?.message).not.toMatch(/\d\.\d{9,}/);
  });

  it('records monitor-triggered exits as SELL decisions linked to the trade', async () => {
    ctx = await createTestApp();
    ctx.world.add(makeToken({ chain: 'solana', address: A, symbol: 'AAA' }));
    const { row } = await ctx.app.repos.tokens.upsertDiscovered({
      chain: 'solana',
      address: A,
      discoveredVia: 'test',
    });
    await ctx.app.pipeline.analyze({ tokenId: row.id, trigger: 'discovery', allowTrade: true });
    const events: string[] = [];
    const unsubscribe = ctx.app.bus.subscribe((e) => {
      if (e.type === 'decision') events.push(e.data.label);
    });
    ctx.world.update(A, { priceUsd: 0.00245 * 2 });
    await ctx.app.engine.runOnce('position-monitor');
    unsubscribe();

    const [latest] = await ctx.app.repos.decisions.listForToken(row.id, 5);
    expect(latest?.action).toBe('SELL');
    expect(latest?.label).toBe('SELL — TAKE PROFIT');
    expect(latest?.reasonCode).toBe('EXIT_TAKE_PROFIT');
    expect(latest?.executed).toBe(true);
    expect(latest?.stages.map((s) => s.stage)).toEqual(['STRATEGY', 'RISK_CHECK', 'EXECUTION']);
    const { rows } = await ctx.app.repos.trades.list({ mode: 'paper', limit: 5, offset: 0 });
    const sell = rows.find((r) => r.trade.side === 'sell')?.trade;
    expect(sell?.id).toBe(latest?.tradeId);
    expect(sell?.decisionId).toBe(latest?.id);
    expect((await ctx.app.repos.tokens.getById(row.id))?.lastDecisionLabel).toBe('SELL — TAKE PROFIT');
    expect(events).toContain('SELL — TAKE PROFIT');
  });

  it('exits immediately when liquidity is pulled and raises a liquidity-crash alert', async () => {
    ctx = await createTestApp();
    ctx.world.add(makeToken({ chain: 'solana', address: A, symbol: 'AAA' }));
    const { row } = await ctx.app.repos.tokens.upsertDiscovered({
      chain: 'solana',
      address: A,
      discoveredVia: 'test',
    });
    await ctx.app.pipeline.analyze({ tokenId: row.id, trigger: 'discovery', allowTrade: true });
    await ctx.app.engine.runOnce('position-monitor'); // baseline observation (also queues a re-analysis)
    await ctx.app.engine.drain();
    ctx.world.update(A, { liquidityUsd: 15_000 });
    await ctx.app.engine.runOnce('position-monitor');
    const [closed] = await ctx.app.repos.positions.listRecentClosed('paper', 5);
    expect(closed?.position.closeReason).toBe('liquidity_drop');
    const alerts = await ctx.app.repos.alerts.list({ limit: 50, offset: 0 });
    expect(alerts.items.map((a) => a.type)).toContain('LIQUIDITY_CRASH');
  });

  it('halts new entries when the daily loss limit is breached', async () => {
    ctx = await createTestApp({ MAX_DAILY_LOSS: '1' });
    ctx.world.add(makeToken({ chain: 'solana', address: A, symbol: 'AAA' }));
    // Simulate a realized loss of 2% of equity.
    await ctx.app.repos.accounts.adjustCash('paper', -200, -200);
    await ctx.app.engine.runOnce('metrics');
    const account = await ctx.app.repos.accounts.get('paper');
    expect(account?.halted).toBe(true);
    expect(account?.haltReason).toMatch(/daily loss/);

    const { row } = await ctx.app.repos.tokens.upsertDiscovered({
      chain: 'solana',
      address: A,
      discoveredVia: 'test',
    });
    const r = await ctx.app.pipeline.analyze({ tokenId: row.id, trigger: 'discovery', allowTrade: true });
    expect(r.decision.label).toBe('SKIP — RISK CHECK FAILED');
    expect(r.decision.riskChecks.find((c) => c.check === 'NOT_HALTED')?.passed).toBe(false);
    expect(r.trade).toBeNull();
    const alerts = await ctx.app.repos.alerts.list({ limit: 10, offset: 0, type: 'DAILY_LOSS_LIMIT' });
    expect(alerts.items).toHaveLength(1);
  });

  it('fails closed when security providers are down', async () => {
    ctx = await createTestApp();
    ctx.world.add(makeToken({ chain: 'solana', address: A, symbol: 'AAA' }));
    for (const h of ['api.gopluslabs.io', 'api.rugcheck.xyz', 'lite-api.jup.ag'])
      ctx.world.failingHosts.add(h);
    const { row } = await ctx.app.repos.tokens.upsertDiscovered({
      chain: 'solana',
      address: A,
      discoveredVia: 'test',
    });
    const r = await ctx.app.pipeline.analyze({ tokenId: row.id, trigger: 'discovery', allowTrade: true });
    expect(r.decision.action).toBe('SKIP');
    expect(r.trade).toBeNull();
    expect(r.report.missingData).toEqual(expect.arrayContaining(['contract', 'honeypot']));
  });

  it('keeps protecting open positions after the engine is stopped', async () => {
    ctx = await createTestApp();
    ctx.world.add(makeToken({ chain: 'solana', address: A, symbol: 'AAA' }));
    await ctx.app.engine.start();
    const { row } = await ctx.app.repos.tokens.upsertDiscovered({
      chain: 'solana',
      address: A,
      discoveredVia: 'test',
    });
    await ctx.app.pipeline.analyze({ tokenId: row.id, trigger: 'discovery', allowTrade: true });
    await ctx.app.engine.stop();
    expect(ctx.app.engine.loopStatus().find((l) => l.name === 'position-monitor')?.running).toBe(true);
    ctx.world.update(A, { priceUsd: 0.00245 * 2 });
    await ctx.app.engine.runOnce('position-monitor');
    const [closed] = await ctx.app.repos.positions.listRecentClosed('paper', 5);
    expect(closed?.position.closeReason).toBe('take_profit');
  });

  it('retries through provider rate limiting', async () => {
    ctx = await createTestApp();
    ctx.world.add(makeToken({ chain: 'solana', address: A, symbol: 'AAA' }));
    ctx.world.rateLimitOnce.set('api.dexscreener.com', 2);
    const { row } = await ctx.app.repos.tokens.upsertDiscovered({
      chain: 'solana',
      address: A,
      discoveredVia: 'test',
    });
    const r = await ctx.app.pipeline.analyze({
      tokenId: row.id,
      trigger: 'manual',
      allowTrade: false,
      manual: true,
    });
    expect(r.snapshot.market?.priceUsd).toBeCloseTo(0.00245);
    expect(ctx.app.providers.registry.health().find((h) => h.name === 'dexscreener')?.rateLimited).toBe(2);
  });
});
