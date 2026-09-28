import { createApp, type App, type AppOverrides } from '../../src/app';
import { loadConfig } from '../../src/config/env';
import { createNullLogger } from '../../src/lib/logger';
import { FakeWorld } from './fakeWorld';

export const ADMIN_KEY = 'test-admin-key-0123456789abcdef-xyz';

export interface TestContext {
  app: App;
  world: FakeWorld;
  close(): Promise<void>;
}

/** Full application wired to an in-memory PGlite database and a FakeWorld of external APIs. */
export async function createTestApp(
  env: Record<string, string> = {},
  overrides: Partial<AppOverrides> = {},
): Promise<TestContext> {
  const world = new FakeWorld();
  const config = loadConfig({
    NODE_ENV: 'test',
    DATABASE_URL: 'pglite://memory',
    API_KEY: ADMIN_KEY,
    PAPER_FAILURE_RATE: '0',
    PAPER_RANDOM_SEED: 'test-seed',
    ENGINE_AUTOSTART: 'false',
    CHAINS: 'solana,base',
    SOURCE_TIMEOUT_MS: '5000',
    ALERT_COOLDOWN_SECONDS: '0',
    ...env,
  } as NodeJS.ProcessEnv);
  const app = await createApp(config, {
    logger: createNullLogger(),
    fetchImpl: world.fetch,
    notifiers: [],
    ...overrides,
  });
  return {
    app,
    world,
    close: () => app.close(),
  };
}
