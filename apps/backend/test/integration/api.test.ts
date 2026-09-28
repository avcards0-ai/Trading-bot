import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { Decision, PaperTradeResponse, Position, RiskReport, ScanResponse } from '@memeguard/shared';
import { buildServer } from '../../src/api/server';
import { makeToken, solAddress } from '../helpers/fakeWorld';
import { ADMIN_KEY, createTestApp, type TestContext } from '../helpers/testApp';

const CLEAN = solAddress(1);
const HONEYPOT = solAddress(2);
const MINTABLE = solAddress(3);
const EVM_CLEAN = '0x2222222222222222222222222222222222222222';
const auth = { authorization: `Bearer ${ADMIN_KEY}` };

describe('HTTP API (integration)', () => {
  let ctx: TestContext;
  let server: FastifyInstance;

  beforeAll(async () => {
    ctx = await createTestApp();
    ctx.world.add(makeToken({ chain: 'solana', address: CLEAN, symbol: 'CLEAN' }));
    ctx.world.add(makeToken({ chain: 'solana', address: HONEYPOT, symbol: 'TRAP', profile: 'honeypot' }));
    ctx.world.add(makeToken({ chain: 'solana', address: MINTABLE, symbol: 'MINTY', profile: 'mint_freeze' }));
    ctx.world.add(makeToken({ chain: 'base', address: EVM_CLEAN, symbol: 'BASED' }));
    server = await buildServer(ctx.app);
  });

  afterAll(async () => {
    await server.close();
    await ctx.close();
  });

  it('serves health and status without auth', async () => {
    expect((await server.inject({ url: '/health' })).json()).toEqual({ status: 'ok', mode: 'paper' });
    const status = (await server.inject({ url: '/status' })).json();
    expect(status.mode).toBe('paper');
    expect(status.database.ok).toBe(true);
    expect(status.providers.map((p: { name: string }) => p.name)).toEqual(
      expect.arrayContaining(['dexscreener', 'goplus', 'rugcheck']),
    );
  });

  it('requires the admin key for administrative endpoints', async () => {
    const noKey = await server.inject({
      method: 'POST',
      url: '/scan',
      payload: { chain: 'solana', address: CLEAN },
    });
    expect(noKey.statusCode).toBe(401);
    const wrong = await server.inject({
      method: 'POST',
      url: '/strategy',
      headers: { authorization: 'Bearer nope' },
      payload: {},
    });
    expect(wrong.statusCode).toBe(401);
    const viaHeader = await server.inject({
      method: 'POST',
      url: '/engine/stop',
      headers: { 'x-api-key': ADMIN_KEY },
    });
    expect(viaHeader.statusCode).toBe(200);
  });

  it('validates addresses and bodies', async () => {
    const r = await server.inject({
      method: 'POST',
      url: '/scan',
      headers: auth,
      payload: { chain: 'solana', address: 'definitely-not-base58-address-0OIl' },
    });
    expect(r.statusCode).toBe(400);
    const r2 = await server.inject({
      method: 'POST',
      url: '/scan',
      headers: auth,
      payload: { chain: 'dogechain', address: CLEAN },
    });
    expect(r2.statusCode).toBe(400);
  });

  it('POST /scan runs the full pipeline and persists the analysis (analysis only by default)', async () => {
    const res = await server.inject({
      method: 'POST',
      url: '/scan',
      headers: auth,
      payload: { chain: 'solana', address: CLEAN },
    });
    expect(res.statusCode).toBe(200);
    const body = res.json<ScanResponse>();
    expect(body.decision.action).toBe('BUY');
    expect(body.decision.label).toBe('BUY — ANALYSIS ONLY');
    expect(body.decision.executed).toBe(false);
    expect(body.decision.stages.map((s) => s.stage)).toEqual([
      'DISCOVERY',
      'ON_CHAIN',
      'CONTRACT',
      'WALLET',
      'LIQUIDITY',
      'MARKET',
      'RUG_RISK',
      'STRATEGY',
      'RISK_CHECK',
      'EXECUTION',
    ]);
    expect(body.decision.riskChecks.every((c) => c.passed)).toBe(true);
    expect(body.risk.rugScore).toBeLessThanOrEqual(35);

    const list = (await server.inject({ url: '/tokens' })).json();
    expect(list.items.find((t: { address: string }) => t.address === CLEAN)?.lastDecision).toBe('BUY');
    const detail = (await server.inject({ url: `/tokens/${CLEAN}?chain=solana` })).json();
    expect(detail.snapshot.market.priceUsd).toBeCloseTo(0.00245);
    expect(detail.priceHistory.length).toBeGreaterThan(0);
    const risk = (await server.inject({ url: `/risk/${CLEAN}` })).json<RiskReport>();
    expect(risk.explanations.overallRisk).toMatch(/OVERALL/);
    const wallets = (await server.inject({ url: `/tokens/${CLEAN}/wallets` })).json();
    expect(wallets.holders.topHolders.length).toBeGreaterThan(5);
  });

  it('returns SKIP — HIGH RUG RISK for a honeypot and never trades it, even when trading is allowed', async () => {
    const res = await server.inject({
      method: 'POST',
      url: '/scan',
      headers: auth,
      payload: { chain: 'solana', address: HONEYPOT, allowTrade: true },
    });
    const body = res.json<ScanResponse>();
    expect(body.decision.label).toBe('SKIP — HIGH RUG RISK');
    expect(body.risk.honeypotRisk).toBe('CRITICAL');
    expect(body.risk.isLikelyScam).toBe(true);
    expect(body.decision.executed).toBe(false);
    const alerts = (await server.inject({ url: '/alerts?type=NEW_HIGH_RISK_TOKEN' })).json();
    expect(alerts.items.length).toBeGreaterThan(0);
  });

  it('rejects tokens with active mint and freeze authority', async () => {
    const body = (
      await server.inject({
        method: 'POST',
        url: '/scan',
        headers: auth,
        payload: { chain: 'solana', address: MINTABLE, allowTrade: true },
      })
    ).json<ScanResponse>();
    expect(body.decision.action).toBe('SKIP');
    expect(body.risk.contractRisk).not.toBe('LOW');
    expect(body.risk.factors.map((f) => f.id)).toEqual(
      expect.arrayContaining(['mint_authority', 'freeze_authority']),
    );
  });

  it('analyses EVM tokens through GoPlus + Honeypot.is', async () => {
    const body = (
      await server.inject({
        method: 'POST',
        url: '/scan',
        headers: auth,
        payload: { chain: 'base', address: EVM_CLEAN },
      })
    ).json<ScanResponse>();
    expect(body.risk.honeypotRisk).toBe('LOW');
    expect(body.risk.sources).toEqual(expect.arrayContaining(['security:goplus', 'security:honeypot.is']));
  });

  it('POST /strategy only accepts stricter limits', async () => {
    const looser = await server.inject({
      method: 'POST',
      url: '/strategy',
      headers: auth,
      payload: { limits: { maxRugScore: 90 } },
    });
    expect(looser.statusCode).toBe(400);
    expect(looser.json().issues[0]).toMatch(/looser than hard limit/);
    const stricter = await server.inject({
      method: 'POST',
      url: '/strategy',
      headers: auth,
      payload: { limits: { maxOpenPositions: 3 } },
    });
    expect(stricter.statusCode).toBe(200);
    expect(stricter.json().limits.maxOpenPositions).toBe(3);
    expect((await server.inject({ url: '/config' })).json().effective.version).toBeGreaterThanOrEqual(1);
  });

  it('POST /paper-trade opens and closes a paper position after passing every risk check', async () => {
    const buy = (
      await server.inject({
        method: 'POST',
        url: '/paper-trade',
        headers: auth,
        payload: { chain: 'solana', address: CLEAN, side: 'buy', amountUsd: 80 },
      })
    ).json<PaperTradeResponse>();
    expect(buy.accepted).toBe(true);
    expect(buy.trade?.status).toBe('filled');
    expect(buy.trade?.filledUsd).toBeLessThanOrEqual(80.1);
    expect(buy.position?.status).toBe('open');

    const dup = (
      await server.inject({
        method: 'POST',
        url: '/paper-trade',
        headers: auth,
        payload: { chain: 'solana', address: CLEAN, side: 'buy' },
      })
    ).json<PaperTradeResponse>();
    expect(dup.accepted).toBe(false);

    const open = (await server.inject({ url: '/positions?status=open' })).json<{ items: Position[] }>();
    expect(open.items).toHaveLength(1);
    const perf = (await server.inject({ url: '/performance' })).json();
    expect(perf.cashUsd).toBeLessThan(10_000);
    expect(perf.openPositions).toBe(1);

    const sell = (
      await server.inject({
        method: 'POST',
        url: '/paper-trade',
        headers: auth,
        payload: { chain: 'solana', address: CLEAN, side: 'sell' },
      })
    ).json<PaperTradeResponse>();
    expect(sell.accepted).toBe(true);
    expect(sell.position?.status).toBe('closed');
    expect(sell.position?.realizedPnlUsd).toBeLessThan(0); // round-trip fees and impact at an unchanged price

    const trades = (await server.inject({ url: '/trades' })).json();
    expect(trades.items.map((t: { side: string }) => t.side)).toEqual(['sell', 'buy']);
    const decisions = (await server.inject({ url: '/decisions?limit=100' })).json<{ items: Decision[] }>();
    expect(decisions.items.some((d) => d.label === 'SELL — MANUAL')).toBe(true);
  });

  it('streams server events over SSE', async () => {
    await server.listen({ port: 0, host: '127.0.0.1' });
    const address = server.addresses()[0] as { port: number };
    const controller = new AbortController();
    const res = await fetch(`http://127.0.0.1:${address.port}/events`, { signal: controller.signal });
    expect(res.headers.get('content-type')).toBe('text/event-stream');
    const reader = res.body!.pipeThrough(new TextDecoderStream()).getReader();
    ctx.app.bus.publish({ type: 'status', data: { engineRunning: true, halted: false, haltReason: null } });
    let text = '';
    while (!text.includes('event: status')) text += (await reader.read()).value ?? '';
    expect(text).toContain('"engineRunning":true');
    controller.abort();
  });

  it('runs and stores a backtest', async () => {
    const res = await server.inject({
      method: 'POST',
      url: '/backtest',
      headers: auth,
      payload: { source: 'synthetic', tokens: 40, seed: 5 },
    });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.id).toBeGreaterThan(0);
    expect(body.syntheticData).toBe(true);
    expect((await server.inject({ url: '/backtests' })).json().items).toHaveLength(1);
  });
});

describe('admin API disabled without API_KEY (fail closed)', () => {
  it('returns 503 for administrative endpoints', async () => {
    const ctx = await createTestApp({ API_KEY: '' });
    const server = await buildServer(ctx.app);
    const res = await server.inject({ method: 'POST', url: '/engine/start' });
    expect(res.statusCode).toBe(503);
    expect(res.json().error).toBe('admin_api_disabled');
    await server.close();
    await ctx.close();
  });
});

describe('POST /paper-trade in live mode', () => {
  it('is refused', async () => {
    // Build a paper app but pretend the config is live for the route guard.
    const ctx = await createTestApp();
    (ctx.app.config.trading as { mode: string }).mode = 'live';
    const server = await buildServer(ctx.app);
    const res = await server.inject({
      method: 'POST',
      url: '/paper-trade',
      headers: auth,
      payload: { chain: 'solana', address: CLEAN, side: 'buy' },
    });
    expect(res.statusCode).toBe(403);
    await server.close();
    await ctx.close();
  });
});
