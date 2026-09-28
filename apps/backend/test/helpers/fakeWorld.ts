/**
 * A scriptable stand-in for every external HTTP API the adapters talk to. Responses follow each
 * provider's DOCUMENTED response schema (hand-written, not captured live), so tests exercise the
 * real adapters, HTTP client, retry logic and parsers end-to-end without network access.
 */
import type { Chain } from '@memeguard/shared';

import bs58 from 'bs58';

export const SOL = 'So11111111111111111111111111111111111111112';

/** A valid (32-byte) base58 Solana address derived from a small integer. */
export const solAddress = (n: number): string =>
  bs58.encode(new Uint8Array(32).fill(0).map((_, i) => (i === 0 ? 7 : (n * 31 + i) % 251)));

export type SecurityProfile = 'clean' | 'honeypot' | 'mint_freeze' | 'unlocked_lp' | 'high_tax';

export interface FakeToken {
  chain: Chain;
  address: string;
  symbol: string;
  name: string;
  pairAddress: string;
  dexId: string;
  priceUsd: number;
  liquidityUsd: number;
  pairCreatedAtMs: number;
  volume: { m5: number; h1: number; h6: number; h24: number };
  txns: { m5: [number, number]; h1: [number, number]; h24: [number, number] };
  priceChange: { m5: number; h1: number; h6: number; h24: number };
  profile: SecurityProfile;
  /** Holder share of the largest non-pool wallet (percent). */
  topHolderPct: number;
  creator: string;
}

export function makeToken(overrides: Partial<FakeToken> & Pick<FakeToken, 'address' | 'chain'>): FakeToken {
  return {
    symbol: 'TEST',
    name: 'Test Token',
    pairAddress: `${overrides.address.slice(0, 20)}PAIR`,
    dexId: overrides.chain === 'solana' ? 'raydium' : 'uniswap',
    priceUsd: 0.00245,
    liquidityUsd: 180_000,
    pairCreatedAtMs: Date.now() - 2 * 3_600_000,
    volume: { m5: 9_000, h1: 95_000, h6: 400_000, h24: 1_250_000 },
    txns: { m5: [40, 22], h1: [500, 250], h24: [5_200, 3_900] },
    priceChange: { m5: 2.1, h1: 30, h6: 45, h24: 60 },
    profile: 'clean',
    topHolderPct: 5,
    creator:
      overrides.chain === 'solana'
        ? 'CreatorWa11et111111111111111111111111111111'
        : '0x00000000000000000000000000000000000c0de1',
    ...overrides,
  };
}

const json = (body: unknown, status = 200, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json', ...headers } });

function holders(t: FakeToken) {
  // pool first, then a descending distribution whose largest wallet = topHolderPct
  const list: { address: string; pct: number; pool?: boolean }[] = [
    { address: t.pairAddress, pct: 20, pool: true },
  ];
  let p = t.topHolderPct;
  for (let i = 0; i < 10; i++) {
    list.push({ address: `Holder${i}${t.address.slice(0, 6)}`, pct: Math.max(0.3, p) });
    p = p * 0.75;
  }
  return list;
}

export class FakeWorld {
  readonly tokens = new Map<string, FakeToken>();
  readonly calls: string[] = [];
  /** Hosts that should answer with an error (to exercise fail-closed paths). */
  readonly failingHosts = new Set<string>();
  /** Force a number of 429 responses before succeeding, per host. */
  readonly rateLimitOnce = new Map<string, number>();

  add(t: FakeToken): FakeToken {
    this.tokens.set(t.address, t);
    return t;
  }

  update(address: string, patch: Partial<FakeToken>): void {
    const t = this.tokens.get(address);
    if (!t) throw new Error(`unknown token ${address}`);
    Object.assign(t, patch);
  }

  readonly fetch = async (input: string, init?: RequestInit): Promise<Response> => {
    const url = new URL(input);
    this.calls.push(`${init?.method ?? 'GET'} ${url.host}${url.pathname}`);
    if (this.failingHosts.has(url.host)) return json({ error: 'upstream unavailable' }, 503);
    const limited = this.rateLimitOnce.get(url.host) ?? 0;
    if (limited > 0) {
      this.rateLimitOnce.set(url.host, limited - 1);
      return json({ error: 'rate limited' }, 429, { 'retry-after': '0' });
    }
    switch (url.host) {
      case 'api.dexscreener.com':
        return this.dexscreener(url);
      case 'api.geckoterminal.com':
        return this.gecko(url);
      case 'api.gopluslabs.io':
        return this.goplus(url);
      case 'api.rugcheck.xyz':
        return this.rugcheck(url);
      case 'api.honeypot.is':
        return this.honeypotIs(url);
      case 'lite-api.jup.ag':
        return this.jupiter(url);
      case 'api.telegram.org':
      case 'discord.com':
        return json({ ok: true });
      default:
        return json({ error: `unhandled host ${url.host}` }, 404);
    }
  };

  // ---------------------------------------------------------------- DexScreener
  private pair(t: FakeToken) {
    return {
      chainId: t.chain,
      dexId: t.dexId,
      url: `https://dexscreener.com/${t.chain}/${t.pairAddress}`,
      pairAddress: t.pairAddress,
      baseToken: { address: t.address, name: t.name, symbol: t.symbol },
      quoteToken:
        t.chain === 'solana'
          ? { address: SOL, name: 'Wrapped SOL', symbol: 'SOL' }
          : { address: '0x4200000000000000000000000000000000000006', name: 'Wrapped Ether', symbol: 'WETH' },
      priceNative: String(t.priceUsd / 150),
      priceUsd: String(t.priceUsd),
      txns: {
        m5: { buys: t.txns.m5[0], sells: t.txns.m5[1] },
        h1: { buys: t.txns.h1[0], sells: t.txns.h1[1] },
        h6: { buys: t.txns.h1[0] * 4, sells: t.txns.h1[1] * 4 },
        h24: { buys: t.txns.h24[0], sells: t.txns.h24[1] },
      },
      volume: t.volume,
      priceChange: t.priceChange,
      liquidity: {
        usd: t.liquidityUsd,
        base: t.liquidityUsd / 2 / t.priceUsd,
        quote: t.liquidityUsd / 2 / 150,
      },
      fdv: t.priceUsd * 1_000_000_000,
      marketCap: t.priceUsd * 1_000_000_000,
      pairCreatedAt: t.pairCreatedAtMs,
    };
  }

  private dexscreener(url: URL): Response {
    const m = /^\/tokens\/v1\/([^/]+)\/(.+)$/.exec(url.pathname);
    if (m) {
      const addresses = decodeURIComponent(m[2] as string).split(',');
      const pairs = addresses
        .map((a) =>
          [...this.tokens.values()].find(
            (t) => t.address.toLowerCase() === a.toLowerCase() && t.chain === m[1],
          ),
        )
        .filter((t): t is FakeToken => !!t)
        .map((t) => this.pair(t));
      return json(pairs);
    }
    if (url.pathname === '/token-profiles/latest/v1' || url.pathname === '/token-boosts/latest/v1') {
      return json(
        [...this.tokens.values()].map((t) => ({
          url: `https://dexscreener.com/${t.chain}/${t.address}`,
          chainId: t.chain,
          tokenAddress: t.address,
        })),
      );
    }
    return json({ error: 'not found' }, 404);
  }

  // ---------------------------------------------------------------- GeckoTerminal
  private gecko(url: URL): Response {
    const trades = /^\/api\/v2\/networks\/[^/]+\/pools\/([^/]+)\/trades$/.exec(url.pathname);
    if (trades) {
      const t = [...this.tokens.values()].find(
        (x) => x.pairAddress === decodeURIComponent(trades[1] as string),
      );
      if (!t) return json({ data: [] });
      const now = Date.now();
      // 150 organic trades from 120 distinct wallets with varied sizes.
      const data = Array.from({ length: 150 }, (_, i) => ({
        id: `trade-${i}`,
        type: 'trade',
        attributes: {
          tx_hash: `tx${i}${t.address.slice(0, 5)}`,
          tx_from_address: `Trader${i % 120}`,
          kind: i % 3 === 0 ? 'sell' : 'buy',
          volume_in_usd: String(50 + ((i * 37) % 900)),
          block_timestamp: new Date(now - i * 20_000).toISOString(),
        },
      }));
      return json({ data });
    }
    const pools = /^\/api\/v2\/networks\/([^/]+)\/new_pools$/.exec(url.pathname);
    if (pools) {
      const network = pools[1];
      const list = [...this.tokens.values()].filter(
        (t) => (t.chain === 'ethereum' ? 'eth' : t.chain) === network,
      );
      return json({
        data: list.map((t) => ({
          id: `${network}_${t.pairAddress}`,
          type: 'pool',
          attributes: {
            address: t.pairAddress,
            name: `${t.symbol} / SOL`,
            pool_created_at: new Date(t.pairCreatedAtMs).toISOString(),
            base_token_price_usd: String(t.priceUsd),
            reserve_in_usd: String(t.liquidityUsd),
          },
          relationships: {
            base_token: { data: { id: `${network}_${t.address}`, type: 'token' } },
            dex: { data: { id: t.dexId, type: 'dex' } },
          },
        })),
        included: list.map((t) => ({
          id: `${network}_${t.address}`,
          type: 'token',
          attributes: { address: t.address, name: t.name, symbol: t.symbol },
        })),
      });
    }
    return json({ errors: [{ status: '404', title: 'Not Found' }] }, 404);
  }

  // ---------------------------------------------------------------- GoPlus
  private goplus(url: URL): Response {
    const address = url.searchParams.get('contract_addresses') ?? '';
    const t = [...this.tokens.values()].find((x) => x.address.toLowerCase() === address.toLowerCase());
    if (!t) return json({ code: 1, message: 'OK', result: {} });
    const hs = holders(t);
    if (url.pathname.startsWith('/api/v1/solana/')) {
      const bad = t.profile === 'mint_freeze';
      return json({
        code: 1,
        message: 'OK',
        result: {
          [t.address]: {
            mintable: {
              status: bad ? '1' : '0',
              authority: bad
                ? [{ address: 'MintAuth1111111111111111111111111111111111', malicious_address: 0 }]
                : [],
            },
            freezable: {
              status: bad ? '1' : '0',
              authority: bad
                ? [{ address: 'FreezeAuth11111111111111111111111111111111', malicious_address: 0 }]
                : [],
            },
            closable: { status: '0', authority: [] },
            balance_mutable_authority: { status: '0', authority: [] },
            non_transferable: '0',
            default_account_state: '0',
            transfer_hook: [],
            metadata_mutable: { status: '0', metadata_upgrade_authority: [] },
            transfer_fee_upgradable: { status: '0' },
            creators: [{ address: t.creator, malicious_address: 0 }],
            holders: hs.map((h) => ({
              account: h.address,
              balance: String(h.pct * 1e7),
              percent: String(h.pct / 100),
              is_locked: 0,
              tag: '',
              token_account: `${h.address}ATA`,
            })),
            total_supply: '1000000000',
            holder_count: '5231',
          },
        },
      });
    }
    const lpLocked = t.profile === 'unlocked_lp' ? '0' : '1';
    const tax = t.profile === 'high_tax' ? '0.35' : '0.02';
    return json({
      code: 1,
      message: 'OK',
      result: {
        [t.address.toLowerCase()]: {
          token_name: t.name,
          token_symbol: t.symbol,
          total_supply: '1000000000',
          holder_count: '4210',
          is_open_source: '1',
          is_proxy: '0',
          is_mintable: '0',
          owner_address: '0x0000000000000000000000000000000000000000',
          creator_address: t.creator,
          creator_percent: '0.000000',
          hidden_owner: '0',
          can_take_back_ownership: '0',
          owner_change_balance: '0',
          selfdestruct: '0',
          external_call: '0',
          is_honeypot: t.profile === 'honeypot' ? '1' : '0',
          cannot_buy: '0',
          cannot_sell_all: '0',
          buy_tax: tax,
          sell_tax: tax,
          transfer_pausable: '0',
          is_blacklisted: '0',
          is_whitelisted: '0',
          trading_cooldown: '0',
          anti_whale_modifiable: '0',
          slippage_modifiable: '0',
          personal_slippage_modifiable: '0',
          honeypot_with_same_creator: '0',
          dex: [{ name: 'UniswapV2', liquidity: String(t.liquidityUsd), pair: t.pairAddress }],
          holders: hs.map((h) => ({
            address: h.pool ? t.pairAddress : h.address.toLowerCase(),
            tag: h.pool ? 'UniswapV2' : '',
            is_contract: h.pool ? 1 : 0,
            balance: String(h.pct * 1e7),
            percent: String(h.pct / 100),
            is_locked: 0,
          })),
          lp_holder_count: '2',
          lp_total_supply: '1000',
          lp_holders: [
            {
              address: '0x000000000000000000000000000000000000dead',
              tag: 'Null Address',
              is_contract: 0,
              balance: '900',
              percent: lpLocked === '1' ? '0.9' : '0.05',
              is_locked: 1,
            },
            {
              address: '0x663a5c229c09b049e36dcc11a9b0d4a8eb9db214',
              tag: 'UNCX',
              is_contract: 1,
              balance: '100',
              percent: lpLocked === '1' ? '0.1' : '0.0',
              is_locked: 1,
            },
          ],
        },
      },
    });
  }

  // ---------------------------------------------------------------- RugCheck
  private rugcheck(url: URL): Response {
    const m = /^\/v1\/tokens\/([^/]+)\/report$/.exec(url.pathname);
    const t = m ? this.tokens.get(decodeURIComponent(m[1] as string)) : undefined;
    if (!t) return json({ error: 'not found' }, 404);
    const bad = t.profile === 'mint_freeze';
    const hs = holders(t);
    return json({
      mint: t.address,
      creator: t.creator,
      tokenProgram: 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA',
      token: {
        mintAuthority: bad ? 'MintAuth1111111111111111111111111111111111' : null,
        freezeAuthority: bad ? 'FreezeAuth11111111111111111111111111111111' : null,
        supply: 1_000_000_000_000_000,
        decimals: 6,
      },
      tokenMeta: { name: t.name, symbol: t.symbol, mutable: false, updateAuthority: null },
      topHolders: hs.map((h) => ({
        address: `${h.address}ATA`,
        owner: h.address,
        pct: h.pct,
        uiAmount: h.pct * 1e7,
        insider: false,
      })),
      risks: bad
        ? [
            {
              name: 'Freeze Authority still enabled',
              description: 'Tokens can be frozen',
              level: 'danger',
              score: 7500,
            },
            {
              name: 'Mint Authority still enabled',
              description: 'More tokens can be minted',
              level: 'danger',
              score: 7500,
            },
          ]
        : [],
      markets: [
        {
          pubkey: t.pairAddress,
          marketType: 'raydium',
          lp: {
            lpLockedPct: t.profile === 'unlocked_lp' ? 2 : 100,
            baseUSD: t.liquidityUsd / 2,
            quoteUSD: t.liquidityUsd / 2,
          },
        },
      ],
      totalMarketLiquidity: t.liquidityUsd,
      totalLPProviders: 1,
      totalHolders: 5231,
      rugged: false,
      knownAccounts: { [t.pairAddress]: { name: 'Raydium', type: 'AMM' } },
    });
  }

  // ---------------------------------------------------------------- Honeypot.is
  private honeypotIs(url: URL): Response {
    const address = url.searchParams.get('address') ?? '';
    const t = [...this.tokens.values()].find((x) => x.address.toLowerCase() === address.toLowerCase());
    if (!t) return json({ error: 'not found' }, 404);
    const hp = t.profile === 'honeypot';
    const tax = t.profile === 'high_tax' ? 35 : 2;
    return json({
      token: { name: t.name, symbol: t.symbol, decimals: 18, address: t.address, totalHolders: 4210 },
      summary: { risk: hp ? 'honeypot' : 'low', riskLevel: hp ? 100 : 1, flags: [] },
      simulationSuccess: true,
      honeypotResult: { isHoneypot: hp, ...(hp ? { honeypotReason: 'Sell transaction reverted' } : {}) },
      simulationResult: { buyTax: tax, sellTax: hp ? 100 : tax, transferTax: 0 },
      contractCode: { openSource: true, rootOpenSource: true, isProxy: false, hasProxyCalls: false },
    });
  }

  // ---------------------------------------------------------------- Jupiter
  private jupiter(url: URL): Response {
    if (url.pathname === '/swap/v1/quote') {
      const input = url.searchParams.get('inputMint') ?? '';
      const output = url.searchParams.get('outputMint') ?? '';
      const amount = BigInt(url.searchParams.get('amount') ?? '0');
      const tokenAddr = input === SOL ? output : input;
      const t = this.tokens.get(tokenAddr);
      if (!t) return json({ error: 'The token is not tradable', errorCode: 'TOKEN_NOT_TRADABLE' }, 400);
      const selling = input !== SOL;
      if (selling && t.profile === 'honeypot') {
        return json({ error: 'Could not find any route', errorCode: 'COULD_NOT_FIND_ANY_ROUTE' }, 400);
      }
      // 0.25% fee each way, tiny impact: token has 6 decimals, SOL = $150.
      const tokensPerLamport = (150 / 1e9 / t.priceUsd) * 1e6;
      const out = selling
        ? (Number(amount) / tokensPerLamport) * 0.9975
        : Number(amount) * tokensPerLamport * 0.9975;
      return json({
        inputMint: input,
        inAmount: amount.toString(),
        outputMint: output,
        outAmount: BigInt(Math.floor(out)).toString(),
        otherAmountThreshold: BigInt(Math.floor(out * 0.95)).toString(),
        swapMode: 'ExactIn',
        slippageBps: Number(url.searchParams.get('slippageBps') ?? 50),
        priceImpactPct: '0.0004',
        routePlan: [{ swapInfo: { ammKey: t.pairAddress, label: 'Raydium' }, percent: 100 }],
      });
    }
    if (url.pathname === '/price/v3') {
      return json({ [SOL]: { usdPrice: 150, decimals: 9 } });
    }
    return json({ error: 'not found' }, 404);
  }
}
