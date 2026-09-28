import { SOLANA_AMM_AUTHORITIES, SOLANA_BURN_ADDRESSES, SOL_MINT } from '../adapters/chains';
import { isOnCurve, isValidSolanaAddress } from '../adapters/solana/keys';
import { accountKeyAddress, type ParsedTransaction } from '../adapters/solana/rpc';

/** Quote assets a new pool is paired against, with how to value them in USD. */
export const QUOTE_MINTS: Record<string, { symbol: string; stable: boolean }> = {
  [SOL_MINT]: { symbol: 'SOL', stable: false },
  EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v: { symbol: 'USDC', stable: true },
  Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB: { symbol: 'USDT', stable: true },
};

export interface LpHolding {
  owner: string;
  amount: number;
  /** Burn address, or a program-owned account (locker / launchpad) that no wallet controls. */
  secured: boolean;
}

export interface ParsedLaunch {
  signature: string;
  mint: string;
  mintDecimals: number;
  quoteMint: string;
  /** Owner of both pool vaults (the pool / AMM authority). */
  poolOwner: string;
  baseVault: string;
  quoteVault: string;
  baseReserve: number;
  quoteReserve: number;
  /** Opening price in quote units per token. */
  launchPriceQuote: number;
  /** LP token mint when one was minted in the transaction. */
  lpMint: string | null;
  lpHoldings: LpHolding[];
  /** Fee payer: the wallet that created the pool. */
  creator: string;
  creatorTokenAmount: number;
  blockTime: number | null;
  slot: number | null;
}

export type ParseResult = { ok: true; launch: ParsedLaunch } | { ok: false; reason: string };

interface Balance {
  account: string;
  mint: string;
  owner: string | null;
  amount: number;
  decimals: number;
}

/** A valid address that is off the ed25519 curve: a PDA, controlled by a program, not a key holder. */
const isProgramOwned = (address: string): boolean => isValidSolanaAddress(address) && !isOnCurve(address);

/**
 * Extracts a new pool from its creation transaction, using only balances (program-agnostic):
 * the pool is the program-owned account that ends the transaction holding both a quote asset
 * (SOL/USDC/USDT) and exactly one other token. Anything ambiguous is rejected (fail closed).
 */
export function parseLaunchTransaction(signature: string, tx: ParsedTransaction): ParseResult {
  if (tx.meta?.err) return { ok: false, reason: 'pool-creation transaction failed on-chain' };
  const keys = tx.transaction.message.accountKeys.map(accountKeyAddress);
  const creator = keys[0];
  if (!creator) return { ok: false, reason: 'transaction has no fee payer' };

  const balances: Balance[] = (tx.meta?.postTokenBalances ?? []).map((b) => ({
    account: keys[b.accountIndex] ?? '',
    mint: b.mint,
    owner: b.owner ?? null,
    amount: Number(b.uiTokenAmount.amount) / 10 ** b.uiTokenAmount.decimals,
    decimals: b.uiTokenAmount.decimals,
  }));
  const preMints = new Set((tx.meta?.preTokenBalances ?? []).map((b) => b.mint));

  // Candidate pools: program-owned (or known AMM authority) owners holding quote + one other token.
  const byOwner = new Map<string, Balance[]>();
  for (const b of balances) {
    if (!b.owner || b.amount <= 0) continue;
    const list = byOwner.get(b.owner) ?? [];
    list.push(b);
    byOwner.set(b.owner, list);
  }
  const candidates: { owner: string; base: Balance; quote: Balance }[] = [];
  for (const [owner, list] of byOwner) {
    if (!SOLANA_AMM_AUTHORITIES.has(owner) && !isProgramOwned(owner)) continue;
    const quotes = list.filter((b) => QUOTE_MINTS[b.mint]);
    const bases = list.filter((b) => !QUOTE_MINTS[b.mint]);
    if (quotes.length === 1 && bases.length === 1) {
      candidates.push({ owner, base: bases[0] as Balance, quote: quotes[0] as Balance });
    }
  }
  if (candidates.length === 0) return { ok: false, reason: 'no pool vaults found in the transaction' };
  // Several pools in one transaction (rare) cannot be attributed safely.
  const mints = new Set(candidates.map((c) => c.base.mint));
  if (mints.size > 1) return { ok: false, reason: 'transaction creates more than one pool' };
  const pool = candidates.sort((a, b) => b.quote.amount - a.quote.amount)[0] as (typeof candidates)[number];

  const mint = pool.base.mint;
  if (pool.base.amount <= 0 || pool.quote.amount <= 0)
    return { ok: false, reason: 'pool has empty reserves' };

  // LP mint: a token other than base/quote that first appears in this transaction.
  const others = [...new Set(balances.map((b) => b.mint))].filter(
    (m) => m !== mint && !QUOTE_MINTS[m] && !preMints.has(m),
  );
  const lpMint = others.length === 1 ? (others[0] as string) : null;
  const lpHoldings: LpHolding[] = lpMint
    ? balances
        .filter((b) => b.mint === lpMint && b.owner && b.amount > 0)
        .map((b) => ({
          owner: b.owner as string,
          amount: b.amount,
          secured: SOLANA_BURN_ADDRESSES.has(b.owner as string) || isProgramOwned(b.owner as string),
        }))
    : [];

  const creatorTokenAmount = balances
    .filter((b) => b.mint === mint && b.owner === creator)
    .reduce((a, b) => a + b.amount, 0);

  return {
    ok: true,
    launch: {
      signature,
      mint,
      mintDecimals: pool.base.decimals,
      quoteMint: pool.quote.mint,
      poolOwner: pool.owner,
      baseVault: pool.base.account,
      quoteVault: pool.quote.account,
      baseReserve: pool.base.amount,
      quoteReserve: pool.quote.amount,
      launchPriceQuote: pool.quote.amount / pool.base.amount,
      lpMint,
      lpHoldings,
      creator,
      creatorTokenAmount,
      blockTime: tx.blockTime ?? null,
      slot: tx.slot ?? null,
    },
  };
}

/**
 * Whether the pool's liquidity can be withdrawn by a wallet. LP tokens that were burned (none
 * left), sent to the incinerator, or held by a program account are treated as secured; LP held by
 * an ordinary wallet is not. No LP mint in the transaction means we cannot tell (not secured).
 */
export function liquiditySecurity(launch: ParsedLaunch): {
  secured: boolean;
  walletHeldPercent: number | null;
  message: string;
} {
  if (!launch.lpMint) {
    return {
      secured: false,
      walletHeldPercent: null,
      message: 'No LP token minted in the creation transaction; cannot verify the liquidity is locked.',
    };
  }
  const total = launch.lpHoldings.reduce((a, h) => a + h.amount, 0);
  if (total === 0) {
    return {
      secured: true,
      walletHeldPercent: 0,
      message: 'LP tokens were burned in the creation transaction.',
    };
  }
  const walletHeld = launch.lpHoldings.filter((h) => !h.secured).reduce((a, h) => a + h.amount, 0);
  const pct = (walletHeld / total) * 100;
  if (walletHeld === 0) {
    return {
      secured: true,
      walletHeldPercent: 0,
      message: 'All LP tokens are burned or held by a program account (locker or launchpad).',
    };
  }
  return {
    secured: false,
    walletHeldPercent: pct,
    message: `${pct.toFixed(1)}% of LP tokens sit in an ordinary wallet, which can pull the liquidity.`,
  };
}
