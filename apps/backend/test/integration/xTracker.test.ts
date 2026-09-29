import { afterEach, describe, expect, it } from 'vitest';
import type { SocialStatus } from '@memeguard/shared';
import { buildServer } from '../../src/api/server';
import { walletAddress } from '../helpers/fakeSolana';
import { makeToken, solAddress } from '../helpers/fakeWorld';
import { createTestApp, type TestContext } from '../helpers/testApp';

const X_ENV = { X_BEARER_TOKEN: 'test-x-bearer-token-0123456789', X_TRACKED_ACCOUNTS: 'caller,ghost' };
const BASE_TOKEN = '0x4444444444444444444444444444444444444444';

describe('X tracker (integration)', () => {
  let ctx: TestContext;
  afterEach(async () => {
    await ctx?.close();
  });

  it('turns a tracked account’s post into a recorded mention, an alert and a full analysis', async () => {
    ctx = await createTestApp(X_ENV);
    const CA = solAddress(70);
    ctx.world.add(makeToken({ chain: 'solana', address: CA, symbol: 'CALLED' }));
    ctx.world.x.addUser('caller', { followers: 120_000 });
    ctx.world.x.post('caller', `new gem, CA: ${CA} 🚀`);
    ctx.app.engine.startProtection(); // runs queued analyses; discovery stays off
    await ctx.app.xTracker.poll();
    await ctx.app.engine.drain(20_000);

    const token = await ctx.app.repos.tokens.getByChainAddress('solana', CA);
    expect(token?.discoveredVia).toBe('x:@caller');
    expect(token?.lastDecisionLabel).toBeTruthy(); // analysed by the normal pipeline
    const [mention] = await ctx.app.repos.social.listRecent(5);
    expect(mention).toMatchObject({
      authorHandle: 'caller',
      authorFollowers: 120_000,
      address: CA,
      symbol: 'CALLED',
    });
    await ctx.app.alerts.flush();
    const alerts = await ctx.app.repos.alerts.list({ limit: 10, offset: 0, type: 'SOCIAL_MENTION' });
    expect(alerts.items[0]?.title).toBe('@caller posted a token');

    // The next poll only asks for newer posts and never records the same post twice.
    await ctx.app.xTracker.poll();
    expect(await ctx.app.repos.social.listRecent(5)).toHaveLength(1);

    const status = await ctx.app.xTracker.status();
    expect(status.trackedAccounts.find((a) => a.handle === 'ghost')).toMatchObject({
      found: false,
      lastError: 'Account not found or suspended',
    });
    expect(status.mostMentioned[0]).toMatchObject({ address: CA, mentions: 1, accounts: ['caller'] });
  });

  it('confirms link-only addresses and resolves the chain of EVM addresses', async () => {
    ctx = await createTestApp(X_ENV);
    const TOKEN = solAddress(71);
    const POOL = walletAddress('some-pool');
    ctx.world.add(makeToken({ chain: 'solana', address: TOKEN, symbol: 'LINKED' }));
    ctx.world.add(makeToken({ chain: 'base', address: BASE_TOKEN, symbol: 'BASED' }));
    ctx.world.x.addUser('caller');
    ctx.world.x.post('caller', 'chart 👇', {
      urls: [`https://dexscreener.com/solana/${TOKEN}`, `https://dexscreener.com/solana/${POOL}`],
    });
    ctx.world.x.post('caller', `on base: ${BASE_TOKEN}`);
    await ctx.app.xTracker.poll();

    const found = (await ctx.app.repos.social.listRecent(10)).map((m) => `${m.chain}:${m.address}`).sort();
    expect(found).toEqual([`base:${BASE_TOKEN}`, `solana:${TOKEN}`]);
  });

  it('adds X evidence to the rug model: missing official account and coordinated promotion', async () => {
    ctx = await createTestApp(X_ENV);
    const CA = solAddress(72);
    ctx.world.add(makeToken({ chain: 'solana', address: CA, symbol: 'HYPE', xHandle: 'HypeOfficial' }));
    ctx.world.x.addMentions(
      CA,
      Array.from({ length: 8 }, (_, i) => ({
        username: `shill${i}`,
        followers: 3,
        ageDays: 2,
        text: `$HYPE is the next 1000x, get in now ${CA}`,
      })),
    );
    const { row } = await ctx.app.repos.tokens.upsertDiscovered({
      chain: 'solana',
      address: CA,
      discoveredVia: 'test',
    });
    const r = await ctx.app.pipeline.analyze({
      tokenId: row.id,
      trigger: 'manual',
      manual: true,
      allowTrade: false,
    });

    expect(r.snapshot.social).toMatchObject({ uniqueAuthors: 8, freshAuthorShare: 1, duplicateTextShare: 1 });
    expect(r.snapshot.social?.officialAccount?.status).toBe('not_found');
    const ids = r.report.factors.map((f) => f.id);
    expect(ids).toEqual(expect.arrayContaining(['x_account_missing', 'x_coordinated_promotion']));
  });

  it('respects the hourly search budget without penalising tokens', async () => {
    ctx = await createTestApp({ ...X_ENV, X_MAX_SEARCHES_PER_HOUR: '1' });
    const [a, b] = [solAddress(73), solAddress(74)];
    for (const addr of [a, b]) ctx.world.add(makeToken({ chain: 'solana', address: addr }));
    const analyse = async (addr: string) => {
      const { row } = await ctx.app.repos.tokens.upsertDiscovered({
        chain: 'solana',
        address: addr,
        discoveredVia: 'test',
      });
      return ctx.app.pipeline.analyze({
        tokenId: row.id,
        trigger: 'manual',
        manual: true,
        allowTrade: false,
      });
    };
    expect((await analyse(a)).snapshot.social).not.toBeNull();
    const second = await analyse(b);
    expect(second.snapshot.social).toBeNull();
    expect(second.report.missingData).not.toContain('social');
    expect((await ctx.app.xTracker.status()).mentionSearch).toMatchObject({ usedLastHour: 1, maxPerHour: 1 });
  });

  it('is off without a bearer token and says how to turn it on', async () => {
    ctx = await createTestApp();
    const CA = solAddress(75);
    ctx.world.add(makeToken({ chain: 'solana', address: CA }));
    const { row } = await ctx.app.repos.tokens.upsertDiscovered({
      chain: 'solana',
      address: CA,
      discoveredVia: 'test',
    });
    const r = await ctx.app.pipeline.analyze({
      tokenId: row.id,
      trigger: 'manual',
      manual: true,
      allowTrade: false,
    });
    expect(r.snapshot.social).toBeNull();
    expect(ctx.world.x.calls).toEqual([]);

    const server = await buildServer(ctx.app);
    const api = (await server.inject({ url: '/social' })).json() as SocialStatus;
    expect(api.enabled).toBe(false);
    expect(api.disabledReason).toMatch(/X_BEARER_TOKEN/);
    await server.close();
  });
});
