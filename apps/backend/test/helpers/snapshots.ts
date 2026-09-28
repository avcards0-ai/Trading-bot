import type { ContractData, MarketData, TokenSnapshot } from '@memeguard/shared';
import { emptyContract } from '../../src/analysis/merge';

export const NOW = new Date('2026-09-01T12:00:00Z');

export function market(patch: Partial<MarketData> = {}): MarketData {
  return {
    source: 'dexscreener',
    pairAddress: 'PAIR1',
    dexId: 'raydium',
    quoteSymbol: 'SOL',
    priceUsd: 0.001,
    priceNative: 0.00001,
    marketCapUsd: 1_000_000,
    fdvUsd: 1_000_000,
    liquidityUsd: 150_000,
    volumeUsd: { m5: 8_000, h1: 90_000, h6: 300_000, h24: 900_000 },
    priceChangePct: { m5: 2, h1: 30, h6: 40, h24: 50 },
    txns: {
      m5: { buys: 40, sells: 20 },
      h1: { buys: 500, sells: 250 },
      h6: null,
      h24: { buys: 5000, sells: 4000 },
    },
    pairCreatedAt: new Date(NOW.getTime() - 120 * 60_000).toISOString(),
    fetchedAt: NOW.toISOString(),
    ...patch,
  };
}

export function cleanContract(patch: Partial<ContractData> = {}): ContractData {
  return {
    ...emptyContract(['goplus', 'rugcheck']),
    tokenProgram: 'spl-token',
    mintable: false,
    freezable: false,
    buyTaxPct: 0,
    sellTaxPct: 0,
    codeHash: 'hash-1',
    ...patch,
  };
}

/** A token with no red flags and complete data. */
export function cleanSnapshot(patch: Partial<TokenSnapshot> = {}): TokenSnapshot {
  return {
    chain: 'solana',
    address: 'MINT1',
    name: 'Clean',
    symbol: 'CLN',
    decimals: 6,
    collectedAt: NOW.toISOString(),
    market: market(),
    contract: cleanContract(),
    holders: {
      sources: ['rugcheck'],
      holderCount: 4000,
      totalSupply: 1e9,
      topHolders: [
        { address: 'POOL', percent: 22, isLiquidityPool: true },
        ...Array.from({ length: 10 }, (_, i) => ({ address: `W${i}`, percent: 3 - i * 0.2 })),
      ],
    },
    liquidity: {
      sources: ['rugcheck'],
      totalLiquidityUsd: 150_000,
      lpLockedPercent: 0,
      lpBurnedPercent: 100,
      programControlled: false,
      creatorLpPercent: 0,
      lpHolderCount: 1,
      poolCount: 1,
    },
    honeypot: {
      source: 'jupiter-roundtrip',
      simulated: true,
      isHoneypot: false,
      buyTaxPct: 0,
      sellTaxPct: 0,
      transferTaxPct: null,
      sellRouteFound: true,
      reason: null,
    },
    deployer: {
      sources: ['rugcheck'],
      address: 'DEV1',
      walletAgeDays: 120,
      tokensCreated: 1,
      knownRugs: 0,
      honeypotWithSameCreator: false,
      holdsPercent: 0.5,
      flaggedMalicious: false,
    },
    trades: {
      source: 'geckoterminal',
      windowMinutes: 60,
      tradeCount: 150,
      uniqueTraders: 120,
      buyers: 100,
      sellers: 50,
      buyVolumeUsd: 60_000,
      sellVolumeUsd: 30_000,
      roundTripWallets: 10,
      roundTripVolumeShare: 0.08,
      topTraderVolumeShare: 0.05,
      tradeSizeCv: 0.9,
      repeatedSizeShare: 0.05,
    },
    wallets: null,
    developer: null,
    warnings: [],
    reportedRugged: false,
    sources: [{ name: 'market:dexscreener', ok: true, durationMs: 10, error: null }],
    ...patch,
  };
}
