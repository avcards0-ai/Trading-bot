import type { Chain } from '@memeguard/shared';

export const EVM_CHAIN_IDS: Record<Exclude<Chain, 'solana'>, number> = {
  ethereum: 1,
  bsc: 56,
  base: 8453,
  arbitrum: 42161,
};

export const isEvm = (chain: Chain): chain is Exclude<Chain, 'solana'> => chain !== 'solana';

/** GeckoTerminal network identifiers. */
export const GECKO_NETWORKS: Record<Chain, string> = {
  solana: 'solana',
  ethereum: 'eth',
  bsc: 'bsc',
  base: 'base',
  arbitrum: 'arbitrum',
};

/** DexScreener chain identifiers. */
export const DEXSCREENER_CHAINS: Record<Chain, string> = {
  solana: 'solana',
  ethereum: 'ethereum',
  bsc: 'bsc',
  base: 'base',
  arbitrum: 'arbitrum',
};

export const EVM_BURN_ADDRESSES = new Set([
  '0x0000000000000000000000000000000000000000',
  '0x000000000000000000000000000000000000dead',
  '0xdead000000000000000042069420694206942069',
]);

export const SOLANA_BURN_ADDRESSES = new Set(['1nc1nerator11111111111111111111111111111111']);

export const SOL_MINT = 'So11111111111111111111111111111111111111112';

/** DEX ids (DexScreener) whose liquidity sits in a launchpad bonding curve, not withdrawable LP. */
export const BONDING_CURVE_DEXES = new Set(['pumpfun', 'moonshot', 'launchlab', 'bonk', 'believe']);

/** Well-known Solana AMM authority accounts (their token accounts are pool vaults). */
export const SOLANA_AMM_AUTHORITIES = new Set([
  '5Q544fKrFoe6tsEbD7S8EmxGTJYAKtTVhAW5Q5pge4j1', // Raydium AMM v4 authority
  'GpMZbSM2GgvTKHJirzeGfMFoaZ8UR2X7F4v8vHTvxFbL', // Raydium CPMM authority
]);

export const isBurnAddress = (chain: Chain, address: string): boolean =>
  chain === 'solana' ? SOLANA_BURN_ADDRESSES.has(address) : EVM_BURN_ADDRESSES.has(address.toLowerCase());

export const sameAddress = (
  chain: Chain,
  a: string | null | undefined,
  b: string | null | undefined,
): boolean => {
  if (!a || !b) return false;
  return chain === 'solana' ? a === b : a.toLowerCase() === b.toLowerCase();
};
