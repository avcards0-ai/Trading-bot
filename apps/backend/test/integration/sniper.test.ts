import { eq } from 'drizzle-orm';
import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';
import type { RiskCheckName, SniperStatus, TokenSnapshot } from '@memeguard/shared';
import { buildServer } from '../../src/api/server';
import { tokens } from '../../src/db/schema';
import type { LaunchSignal, WebSocketLike } from '../../src/sniper/listener';
import { FAKE_RPC_URL, makeLaunch, type FakeLaunch } from '../helpers/fakeSolana';
import { makeToken, type SecurityProfile } from '../helpers/fakeWorld';
import { createTestApp, type TestContext } from '../helpers/testApp';

const SNIPER_ENV = {
  SNIPER_ENABLED: 'true',
  RPC_URL: FAKE_RPC_URL,
  SNIPER_SELL_ROUTE_WAIT_SECONDS: '0',
};
const SOL_USD = 150;

function launch(
  ctx: TestContext,
  overrides: Partial<FakeLaunch> = {},
  jupiter: SecurityProfile | 'unlisted' = 'clean',
) {
  const l = ctx.world.solana.addLaunch(makeLaunch(overrides));
  if (jupiter !== 'unlisted') {
    ctx.world.add(
      makeToken({
        chain: 'solana',
        address: l.mint,
        symbol: 'SNIPE',
        priceUsd: (l.quoteReserveSol / l.baseReserve) * SOL_USD,
        profile: jupiter,
      }),
    );
  }
  return l;
}

const signal = (l: FakeLaunch): LaunchSignal => ({
  signature: l.signature,
  source: 'raydium-amm-v4',
  programId: '675kPX9MHTjS2zt1qfr1NYHuzeLXfQM9H24wFSUt1Mp8',
  slot: 1,
  detectedAt: Date.now(),
});

async function waitFor<T>(fn: () => Promise<T | null | undefined | false>, timeoutMs = 10_000): Promise<T> {
  const until = Date.now() + timeoutMs;
  for (;;) {
    const v = await fn();
    if (v) return v;
    if (Date.now() > until) throw new Error('timed out waiting for condition');
    await new Promise((r) => setTimeout(r, 25));
  }
}

describe('launch sniper checklist (integration)', () => {
  // Rejections never open positions, so these cases share one app.
  let shared: TestContext;
  beforeAll(async () => {
    shared = await createTestApp(SNIPER_ENV);
  });
  afterAll(async () => {
    await shared.close();
  });

  it.each<[string, Partial<FakeLaunch>, SecurityProfile | 'unlisted', RiskCheckName]>([
    [
      'creator can still mint',
      { mintAuthority: 'MintAuth1111111111111111111111111111111111' },
      'clean',
      'MINT_AUTHORITY_REVOKED',
    ],
    [
      'creator can freeze holders',
      { freezeAuthority: 'FreezeAuth111111111111111111111111111111111' },
      'clean',
      'FREEZE_AUTHORITY_REVOKED',
    ],
    ['creator holds the LP tokens', { lpHolder: 'creator' }, 'clean', 'LIQUIDITY_SECURED'],
    ['no LP token to verify', { lpHolder: 'none' }, 'clean', 'LIQUIDITY_SECURED'],
    ['creator kept 20% of supply', { creatorTokens: 200_000_000 }, 'clean', 'CREATOR_HOLDINGS'],
    ['a whale holds 15%', { whaleTokens: 150_000_000 }, 'clean', 'TOP_HOLDER'],
    ['creator wallet is 2 hours old', { creatorWalletAgeHours: 2 }, 'clean', 'CREATOR_WALLET_AGE'],
    ['honeypot (cannot sell back)', {}, 'honeypot', 'SELL_ROUTE'],
    ['no route yet', {}, 'unlisted', 'SELL_ROUTE'],
    ['thin pool', { quoteReserveSol: 5 }, 'clean', 'MIN_LIQUIDITY'],
    ['launch is 2 minutes old', { blockTime: Math.floor(Date.now() / 1000) - 120 }, 'clean', 'LAUNCH_FRESH'],
    [
      'permanent delegate can take tokens',
      {
        tokenProgram: 'spl-token-2022',
        extensions: [
          {
            extension: 'permanentDelegate',
            state: { delegate: 'Delegate11111111111111111111111111111111111' },
          },
        ],
      },
      'clean',
      'NO_DANGEROUS_EXTENSIONS',
    ],
    ['creation transaction failed', { failed: true }, 'clean', 'LAUNCH_PARSED'],
  ])('rejects a launch when %s', async (_name, overrides, jupiter, check) => {
    const l = launch(shared, overrides, jupiter);
    const ctx = shared;
    const attempt = await ctx.app.sniper.analyseLaunch(signal(l));

    expect(attempt.outcome).toBe('rejected');
    expect(attempt.failedCheck).toBe(check);
    expect(attempt.checks.at(-1)).toMatchObject({ check, passed: false });
    expect(await ctx.app.repos.positions.listOpen('paper')).toHaveLength(0);
    expect((await ctx.app.repos.trades.list({ limit: 5, offset: 0 })).total).toBe(0);
    if (check !== 'LAUNCH_PARSED') {
      const token = await ctx.app.repos.tokens.getByChainAddress('solana', l.mint);
      expect(token?.status).toBe('ignored');
      expect(token?.lastDecisionLabel).toBe(`SKIP — SNIPER: ${check.replace(/_/g, ' ')}`);
    }
    expect((await ctx.app.sniper.status()).stats.rejectionsByCheck[check]).toBeGreaterThanOrEqual(1);
  });
});

describe('launch sniper (integration)', () => {
  let ctx: TestContext;
  afterEach(async () => {
    await ctx?.close();
  });

  it('buys a clean launch in paper mode and records the decision, trade and position', async () => {
    ctx = await createTestApp(SNIPER_ENV);
    const l = launch(ctx);
    const attempt = await ctx.app.sniper.analyseLaunch(signal(l));

    expect(attempt.outcome).toBe('bought');
    expect(attempt.checks.every((c) => c.passed)).toBe(true);
    expect(attempt.checks.map((c) => c.check)).toEqual(
      expect.arrayContaining<RiskCheckName>([
        'LAUNCH_PARSED',
        'LAUNCH_FRESH',
        'LIQUIDITY_SECURED',
        'MIN_LIQUIDITY',
        'MINT_AUTHORITY_REVOKED',
        'FREEZE_AUTHORITY_REVOKED',
        'NO_DANGEROUS_EXTENSIONS',
        'CREATOR_HOLDINGS',
        'TOP_HOLDER',
        'CREATOR_NO_RUG_HISTORY',
        'CREATOR_WALLET_AGE',
        'PRICE_IMPACT',
        'SELL_ROUTE',
      ]),
    );
    expect(attempt.secondsAfterLaunch).toBeGreaterThanOrEqual(2);
    expect(attempt.entryPremiumPct).toBeGreaterThan(0);
    expect(attempt.entryPremiumPct).toBeLessThan(5);

    const [open] = await ctx.app.repos.positions.listOpen('paper');
    expect(open?.position).toMatchObject({
      strategy: 'sniper',
      maxHoldMinutes: 10,
      costBasisUsd: expect.any(Number),
    });
    expect(open?.position.costBasisUsd).toBeCloseTo(25, 0);
    expect(open?.position.meta).toMatchObject({ baseVault: l.baseVault, quoteVault: l.quoteVault });

    const [decision] = await ctx.app.repos.decisions.listForToken(open!.token.id, 5);
    expect(decision).toMatchObject({
      action: 'BUY',
      label: 'SNIPE — BOUGHT',
      executed: true,
      reasonCode: 'SNIPER_BUY',
    });
    const { rows } = await ctx.app.repos.trades.list({ mode: 'paper', limit: 5, offset: 0 });
    expect(rows[0]?.trade).toMatchObject({ side: 'buy', status: 'filled', decisionId: decision?.id });
    expect((await ctx.app.repos.tokens.getById(open!.token.id))?.status).toBe('watching');

    const status = await ctx.app.sniper.status();
    expect(status.stats).toMatchObject({ bought: 1, analysed: 1, rejected: 0 });
    expect(status.performance.openPositions).toBe(1);
    expect(status.positions[0]?.strategy).toBe('sniper');
    expect(status.stats.medianSecondsAfterLaunch).toBeGreaterThanOrEqual(2);
  });

  it('takes profit from the on-chain pool price', async () => {
    ctx = await createTestApp(SNIPER_ENV);
    const l = launch(ctx);
    await ctx.app.sniper.analyseLaunch(signal(l));
    ctx.world.solana.setReserves(l, l.baseReserve / 1.3, l.quoteReserveSol * 1.3); // price x1.69
    await ctx.app.sniper.monitor();

    expect(await ctx.app.repos.positions.listOpen('paper')).toHaveLength(0);
    const [closed] = await ctx.app.repos.positions.listRecentClosed('paper', 1);
    expect(closed?.position.closeReason).toBe('take_profit');
    expect(closed?.position.realizedPnlUsd).toBeGreaterThan(0);
    const [decision] = await ctx.app.repos.decisions.listForToken(closed!.token.id, 1);
    expect(decision?.label).toBe('SELL — TAKE PROFIT');
  });

  it('writes the position off when the pool is drained (tokens cannot be sold)', async () => {
    ctx = await createTestApp(SNIPER_ENV);
    const l = launch(ctx);
    await ctx.app.sniper.analyseLaunch(signal(l));
    const cashBefore = (await ctx.app.portfolio.state()).cashUsd;
    ctx.world.solana.drain(l);
    await ctx.app.sniper.monitor();

    const [closed] = await ctx.app.repos.positions.listRecentClosed('paper', 1);
    expect(closed?.position.closeReason).toBe('liquidity_drop');
    expect(closed?.position.realizedPnlUsd).toBeCloseTo(-closed!.position.costBasisUsd);
    expect((await ctx.app.portfolio.state()).cashUsd).toBeCloseTo(cashBefore);
    const [decision] = await ctx.app.repos.decisions.listForToken(closed!.token.id, 1);
    expect(decision?.label).toBe('SELL — WRITTEN OFF (POOL DRAINED)');
    await ctx.app.alerts.flush();
    const alerts = await ctx.app.repos.alerts.list({ limit: 10, offset: 0 });
    expect(alerts.items.some((a) => a.title.startsWith('Position written off'))).toBe(true);
  });

  it('rejects a creator whose earlier token this bot flagged as a rug', async () => {
    ctx = await createTestApp(SNIPER_ENV);
    const l = launch(ctx);
    const { row } = await ctx.app.repos.tokens.upsertDiscovered({
      chain: 'solana',
      address: makeLaunch().mint,
      discoveredVia: 'test',
    });
    await ctx.app.db.db
      .update(tokens)
      .set({ rugScore: 95, latestSnapshot: { deployer: { address: l.creator } } as unknown as TokenSnapshot })
      .where(eq(tokens.id, row.id));
    const attempt = await ctx.app.sniper.analyseLaunch(signal(l));
    expect(attempt.failedCheck).toBe('CREATOR_NO_RUG_HISTORY');
  });

  it('keeps to its own budget: open-position and daily-loss limits', async () => {
    ctx = await createTestApp({
      ...SNIPER_ENV,
      SNIPER_MAX_OPEN_POSITIONS: '1',
      SNIPER_MAX_DAILY_LOSS_USD: '20',
    });
    const first = launch(ctx);
    expect((await ctx.app.sniper.analyseLaunch(signal(first))).outcome).toBe('bought');
    const second = await ctx.app.sniper.analyseLaunch(signal(launch(ctx)));
    expect(second.failedCheck).toBe('SNIPER_MAX_OPEN');

    // Lose the first position entirely ($25 > $20 daily limit): no more sniping today.
    ctx.world.solana.drain(first);
    await ctx.app.sniper.monitor();
    const third = await ctx.app.sniper.analyseLaunch(signal(launch(ctx)));
    expect(third.failedCheck).toBe('SNIPER_DAILY_LOSS');
  });

  it('respects the auto-trade switch (AUTO_TRADE=false stops sniper entries too)', async () => {
    ctx = await createTestApp({ ...SNIPER_ENV, AUTO_TRADE: 'false' });
    const attempt = await ctx.app.sniper.analyseLaunch(signal(launch(ctx)));
    expect(attempt.failedCheck).toBe('TRADING_ENABLED');
    expect(await ctx.app.repos.positions.listOpen('paper')).toHaveLength(0);
  });

  it('leaves sniper positions to the sniper monitor, not the main one', async () => {
    ctx = await createTestApp(SNIPER_ENV);
    const l = launch(ctx);
    await ctx.app.sniper.analyseLaunch(signal(l));
    // Market-data sites (DexScreener) would show a crash, but the pool on-chain is unchanged.
    ctx.world.update(l.mint, { priceUsd: 1e-12 });
    await ctx.app.engine.runOnce('position-monitor');
    expect(await ctx.app.repos.positions.listOpen('paper')).toHaveLength(1);
  });

  it('runs end to end: WebSocket launch -> checks -> paper buy, visible through the API', async () => {
    const sockets: FakeSocket[] = [];
    ctx = await createTestApp(SNIPER_ENV, {
      wsFactory: () => {
        const s = new FakeSocket();
        sockets.push(s);
        return s;
      },
    });
    const l = launch(ctx);
    await ctx.app.engine.start();
    const ws = sockets[0]!;
    ws.onopen?.({});
    expect(ws.sent.map((m) => m.method)).toEqual(['logsSubscribe', 'logsSubscribe', 'logsSubscribe']);
    ws.message({ jsonrpc: '2.0', id: 1, result: 7 });
    ws.message({
      jsonrpc: '2.0',
      method: 'logsNotification',
      params: {
        subscription: 7,
        result: {
          context: { slot: 1 },
          value: {
            signature: l.signature,
            err: null,
            logs: ['Program log: initialize2: InitializeInstruction2'],
          },
        },
      },
    });
    const status = await waitFor(async () => {
      const s = await ctx.app.sniper.status();
      return s.stats.bought === 1 ? s : null;
    });
    expect(status).toMatchObject({ enabled: true, running: true, mode: 'paper' });
    expect(status.listener.connected).toBe(true);

    const server = await buildServer(ctx.app);
    const api = (await server.inject({ url: '/sniper' })).json() as SniperStatus;
    expect(api.recent[0]).toMatchObject({ signature: l.signature, outcome: 'bought', mint: l.mint });
    expect(api.settings?.positionUsd).toBe(25);
    expect(JSON.stringify(api)).not.toContain('rpc.fake.test');
    await server.close();

    await ctx.app.engine.stop();
    expect(ws.closed).toBe(true);
    expect((await ctx.app.sniper.status()).running).toBe(false);
  });

  it('reports itself as off when not enabled', async () => {
    ctx = await createTestApp();
    const server = await buildServer(ctx.app);
    const api = (await server.inject({ url: '/sniper' })).json() as SniperStatus;
    expect(api).toMatchObject({ enabled: false, running: false, settings: null });
    expect(api.disabledReason).toMatch(/SNIPER_ENABLED=true/);
    await server.close();
  });
});

class FakeSocket implements WebSocketLike {
  onopen: ((ev: unknown) => void) | null = null;
  onmessage: ((ev: { data: unknown }) => void) | null = null;
  onclose: ((ev: unknown) => void) | null = null;
  onerror: ((ev: unknown) => void) | null = null;
  readonly sent: { method: string }[] = [];
  closed = false;
  send(data: string) {
    this.sent.push(JSON.parse(data));
  }
  close() {
    if (this.closed) return;
    this.closed = true;
    this.onclose?.({});
  }
  message(obj: unknown) {
    this.onmessage?.({ data: JSON.stringify(obj) });
  }
}
