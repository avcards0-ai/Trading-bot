import { afterEach, describe, expect, it, vi } from 'vitest';
import type { ParsedTransaction } from '../../src/adapters/solana/rpc';
import {
  ConfigError,
  LIVE_TRADING_CONFIRMATION_PHRASE,
  collectSecrets,
  deriveWsUrl,
  loadConfig,
} from '../../src/config/env';
import { createNullLogger } from '../../src/lib/logger';
import { liquiditySecurity, parseLaunchTransaction } from '../../src/sniper/launchParser';
import { LaunchListener, type LaunchSignal, type WebSocketLike } from '../../src/sniper/listener';
import { KNOWN_LAUNCH_PROGRAMS, parseLaunchSources } from '../../src/sniper/programs';
import { FakeSolana, makeLaunch, walletAddress, type FakeLaunch } from '../helpers/fakeSolana';

const env = (e: Record<string, string>) => e as NodeJS.ProcessEnv;
const SNIPER_ON = { SNIPER_ENABLED: 'true', RPC_URL: 'https://rpc.example.com/?api-key=abc123secret' };

describe('sniper configuration', () => {
  it('is off by default', () => {
    const c = loadConfig(env({}));
    expect(c.sniper.enabled).toBe(false);
    expect(c.sniper.sources.map((s) => s.name)).toEqual(['raydium-amm-v4', 'raydium-cpmm', 'pumpswap']);
  });

  it('derives the WebSocket endpoint from RPC_URL and treats it as a secret', () => {
    const c = loadConfig(env(SNIPER_ON));
    expect(c.sniper.wsUrl).toBe('wss://rpc.example.com/?api-key=abc123secret');
    expect(collectSecrets(c)).toContain(c.sniper.wsUrl);
    expect(deriveWsUrl('http://127.0.0.1:8899')).toBe('ws://127.0.0.1:8899');
    expect(deriveWsUrl(null)).toBeNull();
  });

  it('refuses to start without a Solana RPC endpoint', () => {
    expect(() => loadConfig(env({ SNIPER_ENABLED: 'true' }))).toThrow(/RPC_URL/);
  });

  it('refuses to run in live mode (paper only)', () => {
    expect(() =>
      loadConfig(
        env({
          ...SNIPER_ON,
          TRADING_MODE: 'live',
          LIVE_TRADING_CONFIRMATION: LIVE_TRADING_CONFIRMATION_PHRASE,
          WALLET_KEYPAIR_PATH: '/secure/keypair.json',
          API_KEY: 'x'.repeat(32),
          CHAINS: 'solana',
        }),
      ),
    ).toThrow(/paper-only/);
  });

  it('requires solana in CHAINS', () => {
    expect(() => loadConfig(env({ ...SNIPER_ON, CHAINS: 'base' }))).toThrow(ConfigError);
  });

  it('accepts known sources and name=programId, rejects the rest', () => {
    const custom = parseLaunchSources('pumpswap, meteora=Eo7WjKq67rjJQSZxS6z3YkapzY3eMj6Xy8X5EQVn5UaB');
    expect(custom.map((s) => s.name)).toEqual(['pumpswap', 'meteora']);
    expect(custom[1]?.programId).toBe('Eo7WjKq67rjJQSZxS6z3YkapzY3eMj6Xy8X5EQVn5UaB');
    expect(() => parseLaunchSources('nope')).toThrow(/unknown launch source/);
    expect(() => parseLaunchSources('x=not-base58!')).toThrow(/invalid launch source/);
    expect(() => loadConfig(env({ SNIPER_SOURCES: 'nope' }))).toThrow(ConfigError);
  });
});

const tx = (l: FakeLaunch) => new FakeSolana().transactionFor(l) as unknown as ParsedTransaction;

describe('launch transaction parser', () => {
  it('finds the new token, the pool vaults, reserves, creator and burned LP', () => {
    const l = makeLaunch();
    const r = parseLaunchTransaction(l.signature, tx(l));
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.launch).toMatchObject({
      mint: l.mint,
      creator: l.creator,
      poolOwner: l.poolOwner,
      baseVault: l.baseVault,
      quoteVault: l.quoteVault,
      baseReserve: l.baseReserve,
      quoteReserve: l.quoteReserveSol,
      lpMint: l.lpMint,
      creatorTokenAmount: l.creatorTokens,
      blockTime: l.blockTime,
    });
    expect(r.launch.launchPriceQuote).toBeCloseTo(l.quoteReserveSol / l.baseReserve);
    expect(liquiditySecurity(r.launch).secured).toBe(true);
  });

  it.each([
    ['burned in the transaction', 'burned', true],
    ['held by a program account', 'program', true],
    ['held by the creator wallet', 'creator', false],
    ['not minted at all (cannot verify)', 'none', false],
  ] as const)('liquidity %s -> secured=%s', (_name, lpHolder, secured) => {
    const l = makeLaunch({ lpHolder });
    const r = parseLaunchTransaction(l.signature, tx(l));
    if (!r.ok) throw new Error(r.reason);
    const s = liquiditySecurity(r.launch);
    expect(s.secured).toBe(secured);
    if (lpHolder === 'creator') expect(s.walletHeldPercent).toBe(100);
  });

  it('rejects failed transactions and pools it cannot attribute', () => {
    const failed = makeLaunch({ failed: true });
    expect(parseLaunchTransaction(failed.signature, tx(failed))).toMatchObject({ ok: false });
    // Vaults owned by an ordinary wallet are not a pool.
    const walletOwned = makeLaunch({ poolOwner: walletAddress('not-a-pda') });
    expect(parseLaunchTransaction(walletOwned.signature, tx(walletOwned))).toEqual({
      ok: false,
      reason: 'no pool vaults found in the transaction',
    });
  });
});

class FakeSocket implements WebSocketLike {
  onopen: ((ev: unknown) => void) | null = null;
  onmessage: ((ev: { data: unknown }) => void) | null = null;
  onclose: ((ev: unknown) => void) | null = null;
  onerror: ((ev: unknown) => void) | null = null;
  readonly sent: { id: number; method: string; params: unknown[] }[] = [];
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

const notify = (sub: number, signature: string, logs: string[], err: unknown = null) => ({
  jsonrpc: '2.0',
  method: 'logsNotification',
  params: { subscription: sub, result: { context: { slot: 9 }, value: { signature, err, logs } } },
});

describe('launch listener', () => {
  afterEach(() => vi.useRealTimers());

  function setup() {
    const sockets: FakeSocket[] = [];
    const signals: LaunchSignal[] = [];
    const listener = new LaunchListener({
      url: 'wss://rpc.example.com/?api-key=secret',
      programs: [KNOWN_LAUNCH_PROGRAMS['raydium-amm-v4']!, KNOWN_LAUNCH_PROGRAMS.pumpswap!],
      onLaunch: (s) => signals.push(s),
      logger: createNullLogger(),
      wsFactory: () => {
        const s = new FakeSocket();
        sockets.push(s);
        return s;
      },
    });
    return { sockets, signals, listener };
  }

  it('subscribes to every program and emits only pool creations', () => {
    const { sockets, signals, listener } = setup();
    listener.start();
    const ws = sockets[0]!;
    ws.onopen?.({});
    expect(ws.sent.map((m) => m.method)).toEqual(['logsSubscribe', 'logsSubscribe']);
    expect(ws.sent[0]?.params[0]).toEqual({ mentions: ['675kPX9MHTjS2zt1qfr1NYHuzeLXfQM9H24wFSUt1Mp8'] });
    ws.message({ jsonrpc: '2.0', id: 1, result: 11 });
    ws.message({ jsonrpc: '2.0', id: 2, result: 22 });

    ws.message(notify(11, 'swapSig', ['Program log: ray_log: swap']));
    ws.message(notify(11, 'createSig', ['Program log: initialize2: InitializeInstruction2 { nonce: 254 }']));
    ws.message(notify(11, 'createSig', ['Program log: initialize2: InitializeInstruction2 { nonce: 254 }']));
    ws.message(
      notify(22, 'failedSig', ['Program log: Instruction: CreatePool'], { InstructionError: [0, 1] }),
    );
    ws.message(notify(22, 'pumpSig', ['Program log: Instruction: CreatePool']));
    ws.message(notify(99, 'unknownSub', ['Program log: Instruction: CreatePool']));

    expect(signals.map((s) => [s.signature, s.source])).toEqual([
      ['createSig', 'raydium-amm-v4'],
      ['pumpSig', 'pumpswap'],
    ]);
    expect(listener.status().connected).toBe(true);
    listener.stop();
  });

  it('reconnects with backoff after a disconnect and stops cleanly', () => {
    vi.useFakeTimers();
    const { sockets, listener } = setup();
    listener.start();
    sockets[0]!.onopen?.({});
    sockets[0]!.close();
    expect(listener.status()).toMatchObject({ connected: false, reconnects: 1 });
    vi.advanceTimersByTime(1000);
    expect(sockets).toHaveLength(2);
    sockets[1]!.onopen?.({});
    expect(sockets[1]!.sent).toHaveLength(2);
    listener.stop();
    vi.advanceTimersByTime(60_000);
    expect(sockets).toHaveLength(2);
    // The API key in the URL never reaches the reported status.
    expect(JSON.stringify(listener.status())).not.toContain('secret');
  });
});
