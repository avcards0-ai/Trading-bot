import type { MarketData } from '@memeguard/shared';
import type { JupiterAdapter } from '../adapters/jupiter';
import type { SolanaRpc } from '../adapters/solana/rpc';
import { errorMessage } from '../lib/errors';
import type { Logger } from '../lib/logger';
import { QUOTE_MINTS } from './launchParser';

export interface Reserves {
  base: number;
  quote: number;
}

const uiAmount = (acc: { data: unknown } | null): number | null => {
  if (!acc) return null;
  const amt = (acc.data as { parsed?: { info?: { tokenAmount?: { amount?: string; decimals?: number } } } })
    ?.parsed?.info?.tokenAmount;
  if (!amt?.amount || typeof amt.decimals !== 'number') return null;
  return Number(amt.amount) / 10 ** amt.decimals;
};

/**
 * Current balances of pool vaults, read directly from chain (market-data sites take a while to
 * index new pools). A vault that no longer exists counts as empty: the pool was drained/closed.
 * Returns one entry per requested pair, or throws if the RPC call itself fails.
 */
export async function readReserves(
  rpc: SolanaRpc,
  pools: { baseVault: string; quoteVault: string }[],
): Promise<Reserves[]> {
  const accounts = await rpc.getMultipleParsedAccounts(pools.flatMap((p) => [p.baseVault, p.quoteVault]));
  return pools.map((_, i) => ({
    base: uiAmount(accounts[i * 2] ?? null) ?? 0,
    quote: uiAmount(accounts[i * 2 + 1] ?? null) ?? 0,
  }));
}

/** USD value of the quote assets new pools pair against. Stablecoins are $1; SOL is cached. */
export class QuotePricer {
  private sol: { usd: number; at: number } | null = null;

  constructor(
    private readonly jupiter: JupiterAdapter,
    private readonly logger: Logger,
    private readonly opts: { ttlMs?: number; maxStaleMs?: number } = {},
  ) {}

  async usd(quoteMint: string): Promise<number | null> {
    const q = QUOTE_MINTS[quoteMint];
    if (!q) return null;
    if (q.stable) return 1;
    const now = Date.now();
    if (this.sol && now - this.sol.at < (this.opts.ttlMs ?? 30_000)) return this.sol.usd;
    try {
      const usd = await this.jupiter.priceUsd(quoteMint);
      if (usd !== null && usd > 0) {
        this.sol = { usd, at: now };
        return usd;
      }
    } catch (err) {
      this.logger.warn({ err: errorMessage(err) }, 'SOL price unavailable');
    }
    // A slightly old price is fine for sizing; a very old one is not (fail closed).
    if (this.sol && now - this.sol.at < (this.opts.maxStaleMs ?? 300_000)) return this.sol.usd;
    return null;
  }
}

/** A MarketData view of a pool computed from its reserves (no volume or change history yet). */
export function marketFromReserves(args: {
  reserves: Reserves;
  quoteUsd: number;
  source: string;
  launchedAt: string | null;
  supply?: number | null;
}): MarketData {
  const { base, quote } = args.reserves;
  const priceUsd = base > 0 && quote > 0 ? (quote * args.quoteUsd) / base : null;
  const nothing = { m5: null, h1: null, h6: null, h24: null };
  return {
    source: 'onchain-pool',
    pairAddress: null,
    dexId: args.source,
    quoteSymbol: null,
    priceUsd,
    priceNative: base > 0 ? quote / base : null,
    marketCapUsd: priceUsd !== null && args.supply ? priceUsd * args.supply : null,
    fdvUsd: null,
    liquidityUsd: 2 * quote * args.quoteUsd,
    volumeUsd: nothing,
    priceChangePct: nothing,
    txns: nothing,
    pairCreatedAt: args.launchedAt,
    fetchedAt: new Date().toISOString(),
  };
}
