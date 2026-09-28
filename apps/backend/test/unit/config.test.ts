import { describe, expect, it } from 'vitest';
import {
  ConfigError,
  LIVE_TRADING_CONFIRMATION_PHRASE,
  collectSecrets,
  loadConfig,
  safeConfigView,
} from '../../src/config/env';
import {
  StrategyStore,
  StrategyValidationError,
  clampToHard,
  looserThanHard,
} from '../../src/config/strategyStore';

const env = (e: Record<string, string>) => e as NodeJS.ProcessEnv;
const LIVE_OK = {
  TRADING_MODE: 'live',
  LIVE_TRADING_CONFIRMATION: LIVE_TRADING_CONFIRMATION_PHRASE,
  WALLET_KEYPAIR_PATH: '/secure/keypair.json',
  RPC_URL: 'https://rpc.example.com/?api-key=abc123secret',
  API_KEY: 'x'.repeat(32),
  CHAINS: 'solana',
};

describe('config', () => {
  it('defaults to paper trading with auto-trade and conservative hard limits', () => {
    const c = loadConfig(env({}));
    expect(c.trading.mode).toBe('paper');
    expect(c.trading.liveArmed).toBe(false);
    expect(c.hardLimits.maxRugScore).toBe(35);
    expect(c.hardLimits.requireHoneypotCheck).toBe(true);
    expect(c.server.host).toBe('127.0.0.1');
  });

  it('arms live trading only when every requirement is met', () => {
    const c = loadConfig(env(LIVE_OK));
    expect(c.trading.mode).toBe('live');
    expect(c.trading.liveArmed).toBe(true);
  });

  it.each([
    ['missing confirmation phrase', { LIVE_TRADING_CONFIRMATION: '' }],
    ['wrong confirmation phrase', { LIVE_TRADING_CONFIRMATION: 'yes' }],
    ['no wallet', { WALLET_KEYPAIR_PATH: '' }],
    ['no RPC', { RPC_URL: '' }],
    ['no API key', { API_KEY: '' }],
    ['honeypot check disabled', { REQUIRE_HONEYPOT_CHECK: 'false' }],
    ['no live-executable chain', { CHAINS: 'base' }],
  ])('refuses to start live mode with %s (no silent fallback to paper)', (_name, patch) => {
    expect(() => loadConfig(env({ ...LIVE_OK, ...patch }))).toThrow(ConfigError);
  });

  it('rejects both wallet sources at once', () => {
    expect(() => loadConfig(env({ ...LIVE_OK, WALLET_PRIVATE_KEY: 'abc123abc123' }))).toThrow(/only one/);
  });

  it('rejects short API keys and invalid numbers', () => {
    expect(() => loadConfig(env({ API_KEY: 'short' }))).toThrow(/24 characters/);
    expect(() => loadConfig(env({ MAX_RUG_SCORE: 'abc' }))).toThrow(ConfigError);
    expect(() => loadConfig(env({ MAX_POSITION_PERCENT: '500' }))).toThrow(ConfigError);
  });

  it('requires an API key when reads are protected', () => {
    expect(() => loadConfig(env({ REQUIRE_AUTH_FOR_READS: 'true' }))).toThrow(/API_KEY/);
  });

  it('collects secrets (including URL-embedded keys) and never exposes them in the safe view', () => {
    const c = loadConfig(
      env({
        ...LIVE_OK,
        TELEGRAM_BOT_TOKEN: '123456:telegramsecrettoken',
        DATABASE_URL: 'postgres://u:dbpassw0rd@h/db',
      }),
    );
    const secrets = collectSecrets(c);
    expect(secrets).toContain(LIVE_OK.API_KEY);
    expect(secrets).toContain('123456:telegramsecrettoken');
    expect(secrets).toContain(LIVE_OK.RPC_URL);
    expect(secrets).toContain('dbpassw0rd');
    const view = JSON.stringify(safeConfigView(c));
    for (const s of secrets) expect(view).not.toContain(s);
  });
});

describe('runtime strategy limits', () => {
  const hard = loadConfig(env({})).hardLimits;

  it('flags values looser than the hard limits', () => {
    expect(looserThanHard({ maxRugScore: 80 }, hard)).toHaveLength(1);
    expect(looserThanHard({ minLiquidityUsd: 1 }, hard)).toHaveLength(1);
    expect(looserThanHard({ requireHoneypotCheck: false }, hard)).toHaveLength(1);
    expect(looserThanHard({ maxRugScore: 20, minLiquidityUsd: 50_000 }, hard)).toHaveLength(0);
  });

  it('clamps a corrupted stored config back to the hard limits', () => {
    const clamped = clampToHard(
      { ...hard, maxPositionPercent: 99, minTokenAgeMinutes: 0, requireHoneypotCheck: false },
      hard,
    );
    expect(clamped.maxPositionPercent).toBe(hard.maxPositionPercent);
    expect(clamped.minTokenAgeMinutes).toBe(hard.minTokenAgeMinutes);
    expect(clamped.requireHoneypotCheck).toBe(true);
  });

  it('persists stricter updates and rejects looser ones', async () => {
    const c = loadConfig(env({}));
    const saved: { limits: unknown; strategy: unknown }[] = [];
    const repo = {
      active: async () => null,
      save: async (limits: unknown, strategy: unknown) => {
        saved.push({ limits, strategy });
        return { version: saved.length, createdAt: new Date() };
      },
    };
    const store = new StrategyStore(repo as never, 'paper', c.hardLimits, c.defaultStrategy);
    await store.load();
    await expect(store.update({ limits: { maxDrawdownPercent: 50 } })).rejects.toBeInstanceOf(
      StrategyValidationError,
    );
    await expect(store.update({ limits: { bogus: 1 } })).rejects.toBeInstanceOf(StrategyValidationError);
    const eff = await store.update({ limits: { maxRugScore: 25 }, strategy: { stopLossPercent: 10 } });
    expect(eff.limits.maxRugScore).toBe(25);
    expect(eff.strategy.stopLossPercent).toBe(10);
    expect(eff.version).toBe(1);
  });

  it('cannot enable auto-trade at runtime when the environment disables it', async () => {
    const c = loadConfig(env({ AUTO_TRADE: 'false' }));
    const store = new StrategyStore(
      { active: async () => null, save: async () => ({ version: 1, createdAt: new Date() }) } as never,
      'paper',
      c.hardLimits,
      c.defaultStrategy,
    );
    await expect(store.update({ strategy: { autoTrade: true } })).rejects.toThrow(/AUTO_TRADE=false/);
  });
});
