import { z } from 'zod';
import type { Chain } from '@memeguard/shared';
import { ProviderError } from '../lib/errors';
import type { HttpClient } from '../lib/http';
import { toNum } from '../lib/math';
import { SOL_MINT } from './chains';
import type { SecuritySource, SnapshotContribution, TokenContext } from './types';

/**
 * Jupiter aggregator (Solana). https://dev.jup.ag/docs
 *   GET  /swap/v1/quote?inputMint&outputMint&amount&slippageBps
 *   POST /swap/v1/swap { quoteResponse, userPublicKey, ... }  -> base64 VersionedTransaction
 *   GET  /price/v3?ids=<mint>
 */
export const quoteSchema = z
  .object({
    inputMint: z.string(),
    inAmount: z.string(),
    outputMint: z.string(),
    outAmount: z.string(),
    otherAmountThreshold: z.string(),
    swapMode: z.string().nullish(),
    slippageBps: z.number(),
    priceImpactPct: z.union([z.string(), z.number()]),
    routePlan: z.array(z.unknown()),
  })
  .passthrough();
export type JupiterQuote = z.infer<typeof quoteSchema>;

const swapSchema = z.object({
  swapTransaction: z.string(),
  lastValidBlockHeight: z.number(),
  prioritizationFeeLamports: z.number().nullish(),
});

const priceSchema = z.record(
  z.string(),
  z.object({ usdPrice: z.number(), decimals: z.number().nullish() }).passthrough(),
);

/** Jupiter answers 400 with codes like COULD_NOT_FIND_ANY_ROUTE / TOKEN_NOT_TRADABLE when no route exists. */
export function isNoRouteError(err: unknown): boolean {
  return (
    err instanceof ProviderError &&
    (err.status === 400 || err.status === 404) &&
    /COULD_NOT_FIND_ANY_ROUTE|NO_ROUTES_FOUND|TOKEN_NOT_TRADABLE|not tradable|no route/i.test(err.message)
  );
}

export class JupiterAdapter implements SecuritySource {
  readonly name = 'jupiter';

  constructor(private readonly http: HttpClient) {}

  supports(chain: Chain): boolean {
    return chain === 'solana';
  }

  async quote(
    inputMint: string,
    outputMint: string,
    amountRaw: bigint,
    slippageBps: number,
  ): Promise<JupiterQuote | null> {
    try {
      return await this.http.get('/swap/v1/quote', {
        query: {
          inputMint,
          outputMint,
          amount: amountRaw.toString(),
          slippageBps,
          restrictIntermediateTokens: true,
        },
        schema: quoteSchema,
        // "No route" is evidence about the token, not a Jupiter outage.
        isAnswer: isNoRouteError,
      });
    } catch (err) {
      // "No route" is a meaningful answer (possible honeypot/illiquid). Any other failure
      // (auth, proxy, outage) must propagate so it is recorded as missing data, not a verdict.
      if (isNoRouteError(err)) return null;
      throw err;
    }
  }

  async buildSwap(quote: JupiterQuote, userPublicKey: string): Promise<z.infer<typeof swapSchema>> {
    return this.http.post(
      '/swap/v1/swap',
      {
        quoteResponse: quote,
        userPublicKey,
        wrapAndUnwrapSol: true,
        dynamicComputeUnitLimit: true,
        dynamicSlippage: false,
        prioritizationFeeLamports: {
          priorityLevelWithMaxLamports: { maxLamports: 2_000_000, priorityLevel: 'high' },
        },
      },
      { schema: swapSchema, retries: 1 },
    );
  }

  async priceUsd(mint: string): Promise<number | null> {
    const r = await this.http.get('/price/v3', { query: { ids: mint }, schema: priceSchema });
    return r[mint]?.usdPrice ?? null;
  }

  /**
   * Sellability probe: quote a small SOL -> token buy, then quote selling exactly those tokens
   * back. No route back, or an extreme round-trip loss, indicates a honeypot / hidden tax.
   * Limitations: quotes do not execute the token's transfer hook or freeze checks, which are
   * analysed separately from the mint account.
   */
  async inspect(ctx: TokenContext): Promise<SnapshotContribution | null> {
    const probeLamports = 50_000_000n; // 0.05 SOL
    const buy = await this.quote(SOL_MINT, ctx.address, probeLamports, 500);
    if (!buy) {
      return {
        source: 'jupiter',
        honeypot: {
          source: 'jupiter-roundtrip',
          simulated: true,
          isHoneypot: null,
          buyTaxPct: null,
          sellTaxPct: null,
          transferTaxPct: null,
          sellRouteFound: null,
          reason: 'no buy route found for probe amount',
        },
      };
    }
    const tokens = BigInt(buy.outAmount);
    const sell = tokens > 0n ? await this.quote(ctx.address, SOL_MINT, tokens, 500) : null;
    if (!sell) {
      return {
        source: 'jupiter',
        honeypot: {
          source: 'jupiter-roundtrip',
          simulated: true,
          isHoneypot: true,
          buyTaxPct: null,
          sellTaxPct: null,
          transferTaxPct: null,
          sellRouteFound: false,
          reason: 'token can be bought but no route exists to sell it back',
        },
      };
    }
    const back = Number(BigInt(sell.outAmount)) / Number(probeLamports);
    const roundTripLossPct = (1 - back) * 100;
    const impact = (toNum(buy.priceImpactPct) ?? 0) * 100 + (toNum(sell.priceImpactPct) ?? 0) * 100;
    // Loss not explained by price impact is attributed to fees/taxes (split evenly buy/sell).
    const unexplained = Math.max(0, roundTripLossPct - impact);
    return {
      source: 'jupiter',
      honeypot: {
        source: 'jupiter-roundtrip',
        simulated: true,
        isHoneypot: roundTripLossPct >= 90,
        buyTaxPct: unexplained / 2,
        sellTaxPct: unexplained / 2,
        transferTaxPct: null,
        sellRouteFound: true,
        reason:
          roundTripLossPct >= 90 ? `round trip returns only ${(back * 100).toFixed(1)}% of the input` : null,
      },
    };
  }
}
