import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { walletAddress } from '../helpers/fakeSolana';
import { makeToken } from '../helpers/fakeWorld';
import { createTestApp, type TestContext } from '../helpers/testApp';

/**
 * Runs against a real PostgreSQL server when TEST_DATABASE_URL is set (e.g. in CI or docker
 * compose). Skipped otherwise; the rest of the suite uses embedded PGlite.
 */
const url = process.env.TEST_DATABASE_URL;

describe.skipIf(!url)('PostgreSQL (real server)', () => {
  let ctx: TestContext;
  // A fresh token per run: the database persists between runs, and a position left open by an
  // earlier run would (correctly) be exited instead of analysed for entry.
  const A = walletAddress(`pg-${Date.now()}`);

  beforeAll(async () => {
    ctx = await createTestApp({ DATABASE_URL: url as string });
    // Start from an empty schema state for this token.
    ctx.world.add(makeToken({ chain: 'solana', address: A, symbol: 'PG' }));
  });

  afterAll(async () => {
    await ctx?.close();
  });

  it('migrates, analyses, trades and aggregates on Postgres', async () => {
    expect(ctx.app.db.driver).toBe('postgres');
    const { row } = await ctx.app.repos.tokens.upsertDiscovered({
      chain: 'solana',
      address: A,
      discoveredVia: 'pg-test',
    });
    const r = await ctx.app.pipeline.analyze({
      tokenId: row.id,
      trigger: 'manual',
      allowTrade: true,
      manual: true,
    });
    expect(['BUY', 'SKIP', 'HOLD']).toContain(r.decision.action);
    const summary = await ctx.app.portfolio.summary();
    expect(summary.mode).toBe('paper');
    const stats = await ctx.app.repos.positions.closedStats('paper');
    expect(stats.closed).toBeGreaterThanOrEqual(0);
    const saved = await ctx.app.strategyStore.update({ limits: { maxOpenPositions: 2 } });
    expect(saved.version).toBeGreaterThanOrEqual(1);
  });
});
