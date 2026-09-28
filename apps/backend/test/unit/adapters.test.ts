import { ed25519 } from '@noble/curves/ed25519.js';
import bs58 from 'bs58';
import { describe, expect, it } from 'vitest';
import { quoteFromPairs, DexScreenerAdapter, type DexPair } from '../../src/adapters/dexscreener';
import { analyzeBytecode, selector } from '../../src/adapters/evm/bytecode';
import { wordToAddress } from '../../src/adapters/evm/inspector';
import { GeckoTerminalAdapter } from '../../src/adapters/geckoterminal';
import { GoPlusAdapter } from '../../src/adapters/goplus';
import { HoneypotIsAdapter } from '../../src/adapters/honeypotis';
import { JupiterAdapter, isNoRouteError } from '../../src/adapters/jupiter';
import { RugCheckAdapter } from '../../src/adapters/rugcheck';
import { contractFromMint, parseMintAccount, TOKEN_2022_PROGRAM } from '../../src/adapters/solana/inspector';
import { KeyLoadError, isOnCurve, signerFromSecret } from '../../src/adapters/solana/keys';
import { signSerializedTransaction } from '../../src/adapters/solana/transaction';
import { findFunder, tokenDelta } from '../../src/adapters/solana/walletProfiler';
import { ProviderError } from '../../src/lib/errors';
import { HttpClient } from '../../src/lib/http';
import { FakeWorld, makeToken } from '../helpers/fakeWorld';

const http = (world: FakeWorld, baseUrl: string) =>
  new HttpClient({
    name: 'test',
    baseUrl,
    ratePerMinute: 6000,
    burst: 100,
    fetchImpl: world.fetch,
    baseDelayMs: 1,
    maxDelayMs: 2,
  });

const SOL_MINT = 'MINTsoLana1111111111111111111111111111111111';
const EVM = '0x1111111111111111111111111111111111111111';

describe('DexScreener', () => {
  it('picks the deepest own pool and sums liquidity across pools', () => {
    const pair = (addr: string, liq: number, base = SOL_MINT): DexPair => ({
      chainId: 'solana',
      pairAddress: addr,
      baseToken: { address: base, symbol: 'T' },
      quoteToken: { address: 'So1', symbol: 'SOL' },
      priceUsd: '0.5',
      liquidity: { usd: liq },
      txns: { h1: { buys: 10, sells: 5 } },
      volume: { h1: 1000 },
      pairCreatedAt: 1_700_000_000_000,
    });
    const q = quoteFromPairs(
      'solana',
      SOL_MINT,
      [pair('A', 10_000), pair('B', 50_000), pair('C', 99_999, 'OTHER')],
      new Date(),
    );
    expect(q?.market.pairAddress).toBe('B');
    expect(q?.totalLiquidityUsd).toBe(60_000);
    expect(q?.poolCount).toBe(2);
    expect(q?.market.txns.h1).toEqual({ buys: 10, sells: 5 });
  });

  it('parses the tokens endpoint via the HTTP client', async () => {
    const w = new FakeWorld();
    w.add(makeToken({ chain: 'solana', address: SOL_MINT, dexId: 'pumpfun' }));
    const q = await new DexScreenerAdapter(http(w, 'https://api.dexscreener.com')).getMarket(
      'solana',
      SOL_MINT,
    );
    expect(q?.market.priceUsd).toBeCloseTo(0.00245);
    expect(q?.programControlledLiquidity).toBe(true);
    expect(q?.market.pairCreatedAt).not.toBeNull();
  });
});

describe('GeckoTerminal', () => {
  it('discovers new pools with token metadata and parses trades', async () => {
    const w = new FakeWorld();
    const t = w.add(makeToken({ chain: 'solana', address: SOL_MINT, symbol: 'NEW' }));
    const g = new GeckoTerminalAdapter(http(w, 'https://api.geckoterminal.com/api/v2'));
    const pools = await g.discover('solana');
    expect(pools[0]).toMatchObject({ tokenAddress: SOL_MINT, symbol: 'NEW', pairAddress: t.pairAddress });
    const trades = await g.getRecentTrades('solana', t.pairAddress);
    expect(trades.length).toBe(150);
    expect(trades.some((x) => x.kind === 'sell')).toBe(true);
  });
});

describe('GoPlus', () => {
  it('parses EVM results: fractions to percent, LP burn/lock, creator', async () => {
    const w = new FakeWorld();
    w.add(makeToken({ chain: 'base', address: EVM, profile: 'high_tax' }));
    const c = await new GoPlusAdapter(http(w, 'https://api.gopluslabs.io')).inspect({
      chain: 'base',
      address: EVM,
      pairAddress: null,
      dexId: null,
      priceUsd: null,
      liquidityUsd: null,
    });
    expect(c?.contract?.sellTaxPct).toBeCloseTo(35);
    expect(c?.contract?.isVerified).toBe(true);
    expect(c?.contract?.ownershipRenounced).toBe(true);
    expect(c?.liquidity?.lpBurnedPercent).toBeCloseTo(90);
    expect(c?.liquidity?.lpLockedPercent).toBeCloseTo(10);
    expect(c?.holders?.topHolders?.[0]?.isLiquidityPool).toBe(true);
    expect(c?.deployer?.address).toBeDefined();
  });

  it('parses Solana authorities', async () => {
    const w = new FakeWorld();
    w.add(makeToken({ chain: 'solana', address: SOL_MINT, profile: 'mint_freeze' }));
    const c = await new GoPlusAdapter(http(w, 'https://api.gopluslabs.io')).inspect({
      chain: 'solana',
      address: SOL_MINT,
      pairAddress: null,
      dexId: null,
      priceUsd: null,
      liquidityUsd: null,
    });
    expect(c?.contract?.mintable).toBe(true);
    expect(c?.contract?.freezeAuthority).toMatch(/^FreezeAuth/);
  });
});

describe('RugCheck', () => {
  it('parses authorities, LP lock, pools and risks', async () => {
    const w = new FakeWorld();
    const t = w.add(makeToken({ chain: 'solana', address: SOL_MINT, profile: 'unlocked_lp' }));
    const c = await new RugCheckAdapter(http(w, 'https://api.rugcheck.xyz')).inspect({
      chain: 'solana',
      address: SOL_MINT,
      pairAddress: t.pairAddress,
      dexId: null,
      priceUsd: null,
      liquidityUsd: null,
    });
    expect(c?.liquidity?.lpLockedPercent).toBeCloseTo(2);
    expect(c?.holders?.holderCount).toBe(5231);
    expect(c?.holders?.topHolders?.find((h) => h.address === t.pairAddress)?.isLiquidityPool).toBe(true);
    expect(c?.contract?.mintable).toBe(false);
    expect(c?.reportedRugged).toBe(false);
  });

  it('returns null for unknown tokens (404) instead of throwing', async () => {
    const c = await new RugCheckAdapter(http(new FakeWorld(), 'https://api.rugcheck.xyz')).inspect({
      chain: 'solana',
      address: 'nope',
      pairAddress: null,
      dexId: null,
      priceUsd: null,
      liquidityUsd: null,
    });
    expect(c).toBeNull();
  });
});

describe('Honeypot.is', () => {
  it('parses a failed sell simulation as a honeypot', async () => {
    const w = new FakeWorld();
    w.add(makeToken({ chain: 'base', address: EVM, profile: 'honeypot' }));
    const c = await new HoneypotIsAdapter(http(w, 'https://api.honeypot.is')).inspect({
      chain: 'base',
      address: EVM,
      pairAddress: null,
      dexId: null,
      priceUsd: null,
      liquidityUsd: null,
    });
    expect(c?.honeypot).toMatchObject({ simulated: true, isHoneypot: true, sellTaxPct: 100 });
  });

  it('does not claim to support chains it cannot simulate', () => {
    expect(new HoneypotIsAdapter(http(new FakeWorld(), 'https://api.honeypot.is')).supports('arbitrum')).toBe(
      false,
    );
  });
});

describe('Jupiter sellability probe', () => {
  it('passes a token with routes both ways', async () => {
    const w = new FakeWorld();
    w.add(makeToken({ chain: 'solana', address: SOL_MINT }));
    const c = await new JupiterAdapter(http(w, 'https://lite-api.jup.ag')).inspect({
      chain: 'solana',
      address: SOL_MINT,
      pairAddress: null,
      dexId: null,
      priceUsd: null,
      liquidityUsd: null,
    });
    expect(c?.honeypot).toMatchObject({ simulated: true, isHoneypot: false, sellRouteFound: true });
  });

  it('flags buy-but-cannot-sell as a honeypot', async () => {
    const w = new FakeWorld();
    w.add(makeToken({ chain: 'solana', address: SOL_MINT, profile: 'honeypot' }));
    const c = await new JupiterAdapter(http(w, 'https://lite-api.jup.ag')).inspect({
      chain: 'solana',
      address: SOL_MINT,
      pairAddress: null,
      dexId: null,
      priceUsd: null,
      liquidityUsd: null,
    });
    expect(c?.honeypot).toMatchObject({ isHoneypot: true, sellRouteFound: false });
  });

  it('distinguishes "no route" from transport/auth failures', () => {
    expect(
      isNoRouteError(new ProviderError('jupiter', 'HTTP 400 {"errorCode":"COULD_NOT_FIND_ANY_ROUTE"}', 400)),
    ).toBe(true);
    expect(isNoRouteError(new ProviderError('jupiter', 'HTTP 403 forbidden', 403))).toBe(false);
    expect(isNoRouteError(new ProviderError('jupiter', 'HTTP 401 unauthorized', 401))).toBe(false);
  });
});

describe('EVM bytecode analysis', () => {
  const push4 = (sig: string) => `63${selector(sig)}`;

  it('computes canonical selectors', () => {
    expect(selector('transfer(address,uint256)')).toBe('a9059cbb');
    expect(selector('owner()')).toBe('8da5cb5b');
  });

  it('finds suspicious selectors and real opcodes but ignores PUSH data', () => {
    // PUSH32 whose data is full of 0xff (must NOT count as SELFDESTRUCT), then DELEGATECALL.
    const code = `0x${push4('blacklist(address)')}${push4('setSellFee(uint256)')}${push4('transfer(address,uint256)')}7f${'ff'.repeat(32)}f400`;
    const a = analyzeBytecode(code);
    expect(a.suspicious.map((s) => s.category).sort()).toEqual(['blacklist', 'fee_control']);
    expect(a.hasSelfDestruct).toBe(false);
    expect(a.hasDelegateCall).toBe(true);
    expect(a.codeHash).toMatch(/^0x[0-9a-f]{64}$/);
  });

  it('detects EIP-1167 minimal proxies', () => {
    const impl = 'bebebebebebebebebebebebebebebebebebebebe';
    const a = analyzeBytecode(`0x363d3d373d3d3d363d73${impl}5af43d82803e903d91602b57fd5bf3`);
    expect(a.minimalProxyTarget).toBe(`0x${impl}`);
  });

  it('decodes addresses from storage words and treats zero as none', () => {
    expect(wordToAddress(`0x${'0'.repeat(24)}${'ab'.repeat(20)}`)).toBe(`0x${'ab'.repeat(20)}`);
    expect(wordToAddress(`0x${'0'.repeat(64)}`)).toBeNull();
  });
});

describe('Solana mint inspection', () => {
  it('parses Token-2022 extensions into risks', () => {
    const parsed = parseMintAccount({
      owner: TOKEN_2022_PROGRAM,
      data: {
        program: 'spl-token-2022',
        parsed: {
          type: 'mint',
          info: {
            decimals: 6,
            supply: '1000000000000',
            mintAuthority: null,
            freezeAuthority: null,
            extensions: [
              {
                extension: 'permanentDelegate',
                state: { delegate: 'Delegate1111111111111111111111111111111111' },
              },
              {
                extension: 'transferFeeConfig',
                state: {
                  transferFeeConfigAuthority: 'FeeAuth',
                  newerTransferFee: { transferFeeBasisPoints: 500 },
                },
              },
              { extension: 'transferHook', state: { programId: 'Hook111', authority: 'HookAuth' } },
              { extension: 'defaultAccountState', state: { accountState: 'frozen' } },
            ],
          },
        },
      },
    });
    expect(parsed?.program).toBe('spl-token-2022');
    const { contract } = contractFromMint(parsed!.program, parsed!.info);
    expect(contract.ownerCanChangeBalance).toBe(true);
    expect(contract.transferTaxPct).toBe(5);
    expect(contract.taxModifiable).toBe(true);
    expect(contract.transferHook).toBe(true);
    expect(contract.defaultAccountStateFrozen).toBe(true);
    expect(contract.mintable).toBe(false);
    expect(contract.suspiciousFunctions?.length).toBe(4);
  });

  it('flags mints not owned by an SPL token program', () => {
    const parsed = parseMintAccount({
      owner: 'EvilProgram',
      data: { parsed: { type: 'mint', info: { decimals: 0, supply: '1' } } },
    });
    expect(parsed?.program).toBe('unknown');
    expect(contractFromMint('unknown', parsed!.info).warnings[0]?.code).toBe('unknown_token_program');
  });

  it('identifies program-derived (off-curve) owners such as AMM authorities', () => {
    expect(isOnCurve('5Q544fKrFoe6tsEbD7S8EmxGTJYAKtTVhAW5Q5pge4j1')).toBe(false);
    const pub = bs58.encode(ed25519.getPublicKey(ed25519.utils.randomSecretKey()));
    expect(isOnCurve(pub)).toBe(true);
  });

  it('extracts funders and token deltas from parsed transactions', () => {
    const tx = {
      transaction: {
        message: {
          accountKeys: [{ pubkey: 'Payer' }, { pubkey: 'Wallet' }],
          instructions: [
            {
              program: 'system',
              parsed: { type: 'transfer', info: { source: 'Funder', destination: 'Wallet', lamports: 1e9 } },
            },
          ],
        },
      },
      meta: {
        preTokenBalances: [
          { accountIndex: 2, mint: 'M', owner: 'Wallet', uiTokenAmount: { amount: '5000000', decimals: 6 } },
        ],
        postTokenBalances: [
          { accountIndex: 2, mint: 'M', owner: 'Wallet', uiTokenAmount: { amount: '2000000', decimals: 6 } },
        ],
      },
    };
    expect(findFunder(tx as never, 'Wallet')).toBe('Funder');
    expect(tokenDelta(tx as never, 'Wallet', 'M')).toBeCloseTo(-3);
  });
});

describe('wallet keys and transaction signing', () => {
  const seed = new Uint8Array(32).map((_, i) => i + 7);
  const pub = ed25519.getPublicKey(seed);
  const full = new Uint8Array([...seed, ...pub]);

  it('loads base58 and JSON keys and verifies the public half', () => {
    const a = signerFromSecret(bs58.encode(full));
    const b = signerFromSecret(JSON.stringify(Array.from(full)));
    expect(a.publicKey).toBe(bs58.encode(pub));
    expect(b.publicKey).toBe(a.publicKey);
    const corrupted = new Uint8Array(full);
    corrupted[40] = (corrupted[40] ?? 0) ^ 1;
    expect(() => signerFromSecret(bs58.encode(corrupted))).toThrow(KeyLoadError);
    expect(() => signerFromSecret('not-a-key!!')).toThrow(KeyLoadError);
  });

  it('never includes the key material in error messages', () => {
    const bad = bs58.encode(full.slice(0, 40));
    try {
      signerFromSecret(bad);
    } catch (e) {
      expect((e as Error).message).not.toContain(bad);
    }
  });

  /** Minimal v0 transaction: 1 required signer (fee payer) + 1 program key, no instructions. */
  function buildTx(feePayer: Uint8Array): string {
    const message = new Uint8Array([
      0x80,
      1,
      0,
      1,
      2,
      ...feePayer,
      ...new Uint8Array(32).fill(9),
      ...new Uint8Array(32).fill(3),
      0,
      0,
    ]);
    return Buffer.from(new Uint8Array([1, ...new Uint8Array(64), ...message])).toString('base64');
  }

  it('signs a transaction where the wallet is the fee payer', () => {
    const signer = signerFromSecret(bs58.encode(full));
    const txB64 = buildTx(pub);
    const { signedBase64, signature } = signSerializedTransaction(txB64, signer);
    const signed = Buffer.from(signedBase64, 'base64');
    const sig = signed.subarray(1, 65);
    expect(bs58.encode(sig)).toBe(signature);
    expect(ed25519.verify(sig, signed.subarray(65), pub)).toBe(true);
  });

  it('refuses to sign a transaction the wallet is not the fee payer of', () => {
    const signer = signerFromSecret(bs58.encode(full));
    expect(() => signSerializedTransaction(buildTx(new Uint8Array(32).fill(5)), signer)).toThrow(
      /not a required signer/,
    );
  });
});
