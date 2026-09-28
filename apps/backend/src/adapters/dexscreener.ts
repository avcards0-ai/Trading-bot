import { z } from 'zod';
import type { Chain, MarketData, TxnCounts } from '@memeguard/shared';
import type { HttpClient } from '../lib/http';
import { toNum } from '../lib/math';
import { BONDING_CURVE_DEXES, DEXSCREENER_CHAINS, sameAddress } from './chains';
import type { DiscoveredPair, DiscoveryProvider, MarketDataProvider, MarketQuote } from './types';

/**
 * DexScreener public API (no key). https://docs.dexscreener.com/api/reference
 *   GET /tokens/v1/{chainId}/{addresses}      (<=30 addresses, 300 req/min)
 *   GET /token-profiles/latest/v1             (60 req/min)
 *   GET /token-boosts/latest/v1               (60 req/min)
 */
export const DEXSCREENER_BASE_URL = 'https://api.dexscreener.com';

const numLike = z.union([z.number(), z.string()]).nullish();
const txn = z.object({ buys: z.number().nullish(), sells: z.number().nullish() }).nullish();
const windows = z
  .object({ m5: numLike, h1: numLike, h6: numLike, h24: numLike })
  .partial()
  .nullish();

export const dexPairSchema = z.object({
  chainId: z.string(),
  dexId: z.string().nullish(),
  url: z.string().nullish(),
  pairAddress: z.string(),
  labels: z.array(z.string()).nullish(),
  baseToken: z.object({ address: z.string(), name: z.string().nullish(), symbol: z.string().nullish() }),
  quoteToken: z.object({ address: z.string(), name: z.string().nullish(), symbol: z.string().nullish() }),
  priceNative: numLike,
  priceUsd: numLike,
  txns: z.object({ m5: txn, h1: txn, h6: txn, h24: txn }).partial().nullish(),
  volume: windows,
  priceChange: windows,
  liquidity: z.object({ usd: numLike, base: numLike, quote: numLike }).partial().nullish(),
  fdv: numLike,
  marketCap: numLike,
  pairCreatedAt: numLike,
});
export type DexPair = z.infer<typeof dexPairSchema>;

const pairsResponse = z.array(dexPairSchema);
const profilesResponse = z.array(
  z.object({ chainId: z.string(), tokenAddress: z.string(), url: z.string().nullish() }).passthrough(),
);

const toTxn = (t: z.infer<typeof txn>): TxnCounts | null =>
  t && (t.buys !== null || t.sells !== null) ? { buys: t.buys ?? 0, sells: t.sells ?? 0 } : null;

export function pairToMarket(p: DexPair, fetchedAt: Date): MarketData {
  return {
    source: 'dexscreener',
    pairAddress: p.pairAddress,
    dexId: p.dexId ?? null,
    quoteSymbol: p.quoteToken.symbol ?? null,
    priceUsd: toNum(p.priceUsd),
    priceNative: toNum(p.priceNative),
    marketCapUsd: toNum(p.marketCap),
    fdvUsd: toNum(p.fdv),
    liquidityUsd: toNum(p.liquidity?.usd),
    volumeUsd: {
      m5: toNum(p.volume?.m5),
      h1: toNum(p.volume?.h1),
      h6: toNum(p.volume?.h6),
      h24: toNum(p.volume?.h24),
    },
    priceChangePct: {
      m5: toNum(p.priceChange?.m5),
      h1: toNum(p.priceChange?.h1),
      h6: toNum(p.priceChange?.h6),
      h24: toNum(p.priceChange?.h24),
    },
    txns: {
      m5: toTxn(p.txns?.m5),
      h1: toTxn(p.txns?.h1),
      h6: toTxn(p.txns?.h6),
      h24: toTxn(p.txns?.h24),
    },
    pairCreatedAt: toNum(p.pairCreatedAt) ? new Date(toNum(p.pairCreatedAt) as number).toISOString() : null,
    fetchedAt: fetchedAt.toISOString(),
  };
}

/** Pick the deepest pool where the token is the base asset and aggregate liquidity across pools. */
export function quoteFromPairs(chain: Chain, address: string, pairs: DexPair[], fetchedAt: Date): MarketQuote | null {
  const own = pairs.filter((p) => sameAddress(chain, p.baseToken.address, address));
  if (own.length === 0) return null;
  const sorted = [...own].sort((a, b) => (toNum(b.liquidity?.usd) ?? 0) - (toNum(a.liquidity?.usd) ?? 0));
  const main = sorted[0] as DexPair;
  const total = own.reduce((acc, p) => acc + (toNum(p.liquidity?.usd) ?? 0), 0);
  return {
    market: pairToMarket(main, fetchedAt),
    totalLiquidityUsd: own.some((p) => toNum(p.liquidity?.usd) !== null) ? total : null,
    poolCount: own.length,
    name: main.baseToken.name ?? null,
    symbol: main.baseToken.symbol ?? null,
    programControlledLiquidity: BONDING_CURVE_DEXES.has((main.dexId ?? '').toLowerCase()),
  };
}

export class DexScreenerAdapter implements MarketDataProvider, DiscoveryProvider {
  readonly name = 'dexscreener';

  constructor(
    private readonly http: HttpClient,
    private readonly now: () => Date = () => new Date(),
  ) {}

  supports(): boolean {
    return true;
  }

  async getMarket(chain: Chain, address: string): Promise<MarketQuote | null> {
    const map = await this.getMarkets(chain, [address]);
    return map.get(address) ?? map.get(address.toLowerCase()) ?? null;
  }

  async getMarkets(chain: Chain, addresses: string[]): Promise<Map<string, MarketQuote>> {
    const out = new Map<string, MarketQuote>();
    const unique = [...new Set(addresses)];
    for (let i = 0; i < unique.length; i += 30) {
      const batch = unique.slice(i, i + 30);
      const pairs = await this.http.get(
        `/tokens/v1/${DEXSCREENER_CHAINS[chain]}/${batch.map(encodeURIComponent).join(',')}`,
        { schema: pairsResponse },
      );
      const fetchedAt = this.now();
      for (const address of batch) {
        const q = quoteFromPairs(chain, address, pairs, fetchedAt);
        if (q) out.set(address, q);
      }
    }
    return out;
  }

  /**
   * DexScreener has no public "new pairs" endpoint; latest token profiles and boosts are the
   * freshest public feeds. Results are enriched with pair data so age/liquidity are known.
   */
  async discover(chain: Chain): Promise<DiscoveredPair[]> {
    const [profiles, boosts] = await Promise.all([
      this.http.get('/token-profiles/latest/v1', { schema: profilesResponse }),
      this.http.get('/token-boosts/latest/v1', { schema: profilesResponse }).catch(() => []),
    ]);
    const chainId = DEXSCREENER_CHAINS[chain];
    const addresses = [
      ...new Set([...profiles, ...boosts].filter((p) => p.chainId === chainId).map((p) => p.tokenAddress)),
    ].slice(0, 30);
    if (addresses.length === 0) return [];
    const markets = await this.getMarkets(chain, addresses);
    const out: DiscoveredPair[] = [];
    for (const address of addresses) {
      const q = markets.get(address);
      out.push({
        chain,
        tokenAddress: address,
        name: q?.name ?? null,
        symbol: q?.symbol ?? null,
        pairAddress: q?.market.pairAddress ?? null,
        dexId: q?.market.dexId ?? null,
        pairCreatedAt: q?.market.pairCreatedAt ? new Date(q.market.pairCreatedAt) : null,
        liquidityUsd: q?.market.liquidityUsd ?? null,
        source: this.name,
      });
    }
    return out;
  }
}
