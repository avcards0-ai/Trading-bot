import { z } from 'zod';
import type { Chain, MarketData, TxnCounts } from '@memeguard/shared';
import type { HttpClient } from '../lib/http';
import { toNum } from '../lib/math';
import { parseDate } from '../lib/time';
import { GECKO_NETWORKS, sameAddress } from './chains';
import type {
  DiscoveredPair,
  DiscoveryProvider,
  OhlcvBar,
  OhlcvProvider,
  RawTrade,
  TradeFeedProvider,
} from './types';

/**
 * GeckoTerminal public API (no key, ~30 req/min). https://www.geckoterminal.com/dex-api
 *   GET /networks/{network}/new_pools?include=base_token
 *   GET /networks/{network}/pools/{pool}/trades
 *   GET /networks/{network}/pools/{pool}/ohlcv/{timeframe}
 */
export const GECKOTERMINAL_BASE_URL = 'https://api.geckoterminal.com/api/v2';
export const GECKOTERMINAL_HEADERS = { accept: 'application/json;version=20230302' };

const numLike = z.union([z.number(), z.string()]).nullish();
const txWindow = z
  .object({ buys: z.number().nullish(), sells: z.number().nullish(), buyers: z.number().nullish(), sellers: z.number().nullish() })
  .nullish();

const poolSchema = z.object({
  id: z.string(),
  type: z.string(),
  attributes: z.object({
    address: z.string(),
    name: z.string().nullish(),
    pool_created_at: z.string().nullish(),
    base_token_price_usd: numLike,
    base_token_price_native_currency: numLike,
    fdv_usd: numLike,
    market_cap_usd: numLike,
    reserve_in_usd: numLike,
    price_change_percentage: z.record(z.string(), numLike).nullish(),
    volume_usd: z.record(z.string(), numLike).nullish(),
    transactions: z.record(z.string(), txWindow).nullish(),
  }),
  relationships: z
    .object({
      base_token: z.object({ data: z.object({ id: z.string() }).nullish() }).nullish(),
      quote_token: z.object({ data: z.object({ id: z.string() }).nullish() }).nullish(),
      dex: z.object({ data: z.object({ id: z.string() }).nullish() }).nullish(),
    })
    .nullish(),
});
export type GeckoPool = z.infer<typeof poolSchema>;

const includedToken = z.object({
  id: z.string(),
  type: z.string(),
  attributes: z.object({ address: z.string(), name: z.string().nullish(), symbol: z.string().nullish() }).passthrough(),
});

const poolsResponse = z.object({
  data: z.array(poolSchema),
  included: z.array(z.union([includedToken, z.object({ id: z.string(), type: z.string() }).passthrough()])).nullish(),
});

const tradesResponse = z.object({
  data: z.array(
    z.object({
      attributes: z.object({
        tx_hash: z.string(),
        tx_from_address: z.string().nullish(),
        kind: z.string(),
        volume_in_usd: numLike,
        block_timestamp: z.string(),
      }),
    }),
  ),
});

const ohlcvResponse = z.object({
  data: z.object({
    attributes: z.object({ ohlcv_list: z.array(z.array(z.number())) }),
  }),
});

/** GeckoTerminal ids look like "solana_<address>". */
export const stripNetworkPrefix = (id: string): string => {
  const i = id.indexOf('_');
  return i >= 0 ? id.slice(i + 1) : id;
};

const toTx = (w: z.infer<typeof txWindow>): TxnCounts | null =>
  w ? { buys: w.buys ?? 0, sells: w.sells ?? 0 } : null;

export function poolToMarket(p: GeckoPool, fetchedAt: Date): MarketData {
  const a = p.attributes;
  const pc = a.price_change_percentage ?? {};
  const vol = a.volume_usd ?? {};
  const tx = a.transactions ?? {};
  return {
    source: 'geckoterminal',
    pairAddress: a.address,
    dexId: p.relationships?.dex?.data?.id ?? null,
    quoteSymbol: null,
    priceUsd: toNum(a.base_token_price_usd),
    priceNative: toNum(a.base_token_price_native_currency),
    marketCapUsd: toNum(a.market_cap_usd),
    fdvUsd: toNum(a.fdv_usd),
    liquidityUsd: toNum(a.reserve_in_usd),
    volumeUsd: { m5: toNum(vol.m5), h1: toNum(vol.h1), h6: toNum(vol.h6), h24: toNum(vol.h24) },
    priceChangePct: { m5: toNum(pc.m5), h1: toNum(pc.h1), h6: toNum(pc.h6), h24: toNum(pc.h24) },
    txns: { m5: toTx(tx.m5), h1: toTx(tx.h1), h6: toTx(tx.h6 ?? null), h24: toTx(tx.h24) },
    pairCreatedAt: parseDate(a.pool_created_at)?.toISOString() ?? null,
    fetchedAt: fetchedAt.toISOString(),
  };
}

export class GeckoTerminalAdapter implements DiscoveryProvider, TradeFeedProvider, OhlcvProvider {
  readonly name = 'geckoterminal';

  constructor(private readonly http: HttpClient) {}

  supports(): boolean {
    return true;
  }

  async discover(chain: Chain): Promise<DiscoveredPair[]> {
    const res = await this.http.get(`/networks/${GECKO_NETWORKS[chain]}/new_pools`, {
      query: { include: 'base_token', page: 1 },
      schema: poolsResponse,
    });
    const tokens = new Map<string, { name: string | null; symbol: string | null; address: string }>();
    for (const inc of res.included ?? []) {
      const parsed = includedToken.safeParse(inc);
      if (parsed.success && parsed.data.type === 'token') {
        tokens.set(parsed.data.id, {
          address: parsed.data.attributes.address,
          name: parsed.data.attributes.name ?? null,
          symbol: parsed.data.attributes.symbol ?? null,
        });
      }
    }
    const out: DiscoveredPair[] = [];
    for (const pool of res.data) {
      const baseId = pool.relationships?.base_token?.data?.id;
      if (!baseId) continue;
      const tok = tokens.get(baseId);
      out.push({
        chain,
        tokenAddress: tok?.address ?? stripNetworkPrefix(baseId),
        name: tok?.name ?? null,
        symbol: tok?.symbol ?? null,
        pairAddress: pool.attributes.address,
        dexId: pool.relationships?.dex?.data?.id ?? null,
        pairCreatedAt: parseDate(pool.attributes.pool_created_at),
        liquidityUsd: toNum(pool.attributes.reserve_in_usd),
        source: this.name,
      });
    }
    return out;
  }

  /** Last ~300 trades of a pool (GeckoTerminal returns trades from the past 24h). */
  async getRecentTrades(chain: Chain, pairAddress: string): Promise<RawTrade[]> {
    const res = await this.http.get(`/networks/${GECKO_NETWORKS[chain]}/pools/${encodeURIComponent(pairAddress)}/trades`, {
      schema: tradesResponse,
    });
    const out: RawTrade[] = [];
    for (const t of res.data) {
      const a = t.attributes;
      const ts = parseDate(a.block_timestamp);
      const vol = toNum(a.volume_in_usd);
      if (!ts || vol === null || !a.tx_from_address) continue;
      if (a.kind !== 'buy' && a.kind !== 'sell') continue;
      out.push({ txHash: a.tx_hash, wallet: a.tx_from_address, kind: a.kind, volumeUsd: vol, timestamp: ts });
    }
    return out;
  }

  async getOhlcv(
    chain: Chain,
    pairAddress: string,
    opts: { timeframe: 'minute' | 'hour' | 'day'; aggregate: number; limit: number; before?: Date },
  ): Promise<OhlcvBar[]> {
    const res = await this.http.get(
      `/networks/${GECKO_NETWORKS[chain]}/pools/${encodeURIComponent(pairAddress)}/ohlcv/${opts.timeframe}`,
      {
        query: {
          aggregate: opts.aggregate,
          limit: Math.min(1000, opts.limit),
          currency: 'usd',
          before_timestamp: opts.before ? Math.floor(opts.before.getTime() / 1000) : undefined,
        },
        schema: ohlcvResponse,
      },
    );
    return res.data.attributes.ohlcv_list
      .filter((r) => r.length >= 6)
      .map((r) => ({
        ts: new Date((r[0] as number) * 1000),
        open: r[1] as number,
        high: r[2] as number,
        low: r[3] as number,
        close: r[4] as number,
        volumeUsd: r[5] as number,
      }))
      .sort((a, b) => a.ts.getTime() - b.ts.getTime());
  }

  /** Market fallback when DexScreener has no data: deepest pool for the token. */
  async getTokenPools(chain: Chain, address: string): Promise<MarketData | null> {
    const res = await this.http.get(
      `/networks/${GECKO_NETWORKS[chain]}/tokens/${encodeURIComponent(address)}/pools`,
      { schema: poolsResponse, nullOnStatus: [404] },
    );
    if (!res) return null;
    const own = res.data.filter((p) =>
      sameAddress(chain, stripNetworkPrefix(p.relationships?.base_token?.data?.id ?? ''), address),
    );
    const best = own.sort((a, b) => (toNum(b.attributes.reserve_in_usd) ?? 0) - (toNum(a.attributes.reserve_in_usd) ?? 0))[0];
    return best ? poolToMarket(best, new Date()) : null;
  }
}
