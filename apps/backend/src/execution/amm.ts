import type { Chain } from '@memeguard/shared';

/**
 * Constant-product (x*y=k) AMM model used to estimate price impact for sizing and to simulate
 * paper fills. The pool is approximated as 50/50 by value: quote reserve = liquidityUsd / 2.
 * Concentrated-liquidity pools can be deeper near the current price, so this is conservative.
 */

/** Typical network cost per swap in USD (priority fees included). Used for paper trading only. */
export const NETWORK_FEE_USD: Record<Chain, number> = {
  solana: 0.03,
  base: 0.05,
  arbitrum: 0.1,
  bsc: 0.15,
  ethereum: 4,
};

export interface BuySimulation {
  tokensOut: number;
  avgPriceUsd: number;
  /** Price impact vs mid, percent (excludes the DEX fee). */
  priceImpactPct: number;
  dexFeeUsd: number;
}

export interface SellSimulation {
  usdOut: number;
  avgPriceUsd: number;
  priceImpactPct: number;
  dexFeeUsd: number;
  taxUsd: number;
}

/** Expected price impact (percent) of buying `usd` worth of tokens. */
export function estimateBuyImpactPct(usd: number, liquidityUsd: number, dexFeePct: number): number {
  const quote = liquidityUsd / 2;
  if (quote <= 0) return Number.POSITIVE_INFINITY;
  return ((usd * (1 - dexFeePct / 100)) / quote) * 100;
}

export function simulateBuy(
  usd: number,
  midPriceUsd: number,
  liquidityUsd: number,
  dexFeePct: number,
  buyTaxPct: number,
): BuySimulation {
  const quote = liquidityUsd / 2;
  const base = quote / midPriceUsd;
  const dexFeeUsd = usd * (dexFeePct / 100);
  const x = usd - dexFeeUsd;
  const grossTokens = (base * x) / (quote + x);
  const tokensOut = grossTokens * (1 - Math.min(99.99, Math.max(0, buyTaxPct)) / 100);
  return {
    tokensOut,
    avgPriceUsd: tokensOut > 0 ? usd / tokensOut : Number.POSITIVE_INFINITY,
    priceImpactPct: (x / quote) * 100,
    dexFeeUsd,
  };
}

export function simulateSell(
  tokens: number,
  midPriceUsd: number,
  liquidityUsd: number,
  dexFeePct: number,
  sellTaxPct: number,
): SellSimulation {
  const quote = liquidityUsd / 2;
  const base = quote / midPriceUsd;
  const taxTokens = tokens * (Math.min(99.99, Math.max(0, sellTaxPct)) / 100);
  const q = tokens - taxTokens;
  const grossUsd = (quote * q) / (base + q);
  const dexFeeUsd = grossUsd * (dexFeePct / 100);
  const usdOut = grossUsd - dexFeeUsd;
  const midValue = tokens * midPriceUsd;
  return {
    usdOut,
    avgPriceUsd: tokens > 0 ? usdOut / tokens : 0,
    priceImpactPct: midValue > 0 ? ((q * midPriceUsd - grossUsd) / (q * midPriceUsd)) * 100 : 0,
    dexFeeUsd,
    taxUsd: taxTokens * midPriceUsd,
  };
}

/** Conservative liquidation value of a position (what a market sell would return now). */
export function estimateExitValueUsd(
  tokens: number,
  midPriceUsd: number | null,
  liquidityUsd: number | null,
  dexFeePct: number,
  sellTaxPct: number,
): number | null {
  if (midPriceUsd === null || midPriceUsd <= 0) return null;
  if (liquidityUsd === null || liquidityUsd <= 0) return 0;
  return simulateSell(tokens, midPriceUsd, liquidityUsd, dexFeePct, sellTaxPct).usdOut;
}
