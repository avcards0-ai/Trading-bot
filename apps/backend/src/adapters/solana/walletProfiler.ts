import type { Chain, DeveloperActivity, DeveloperEvent } from '@memeguard/shared';
import { SOL_MINT } from '../chains';
import type { DeveloperActivitySource, WalletProfile, WalletProfiler } from '../types';
import { accountKeyAddress, type ParsedTransaction, type SolanaRpc } from './rpc';

type Dict = Record<string, unknown>;

const STABLE_MINTS = new Set([
  SOL_MINT,
  'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v', // USDC
  'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB', // USDT
]);

/** Finds the wallet that funded `address` in a parsed transaction (system transfer / createAccount). */
export function findFunder(tx: ParsedTransaction, address: string): string | null {
  const instructions = [
    ...tx.transaction.message.instructions,
    ...(tx.meta?.innerInstructions ?? []).flatMap((i) => i.instructions),
  ];
  for (const ix of instructions) {
    if (ix.program !== 'system') continue;
    const parsed = ix.parsed as { type?: string; info?: Dict } | undefined;
    const info = parsed?.info ?? {};
    const dest = (info.destination ?? info.newAccount) as string | undefined;
    const src = (info.source ?? info.fundingAccount ?? info.from) as string | undefined;
    if (dest === address && typeof src === 'string' && src !== address) return src;
  }
  const payer = tx.transaction.message.accountKeys[0];
  const payerAddr = payer ? accountKeyAddress(payer) : null;
  return payerAddr && payerAddr !== address ? payerAddr : null;
}

/** Net change of `mint` held by `owner` in a transaction, in UI units. */
export function tokenDelta(tx: ParsedTransaction, owner: string, mint: string): number {
  const total = (list: NonNullable<ParsedTransaction['meta']>['preTokenBalances']) =>
    (list ?? [])
      .filter((b) => b.owner === owner && b.mint === mint)
      .reduce((a, b) => a + Number(b.uiTokenAmount.amount) / 10 ** b.uiTokenAmount.decimals, 0);
  return total(tx.meta?.postTokenBalances) - total(tx.meta?.preTokenBalances);
}

/** Net native SOL change (lamports) of `owner` in a transaction, fees included. */
export function lamportDelta(tx: ParsedTransaction, owner: string): number | null {
  const keys = tx.transaction.message.accountKeys.map(accountKeyAddress);
  const idx = keys.indexOf(owner);
  if (idx < 0 || !tx.meta?.preBalances || !tx.meta.postBalances) return null;
  return (tx.meta.postBalances[idx] ?? 0) - (tx.meta.preBalances[idx] ?? 0);
}

function counterpartyFor(tx: ParsedTransaction, owner: string, mint: string): string | null {
  const owners = new Set(
    [...(tx.meta?.postTokenBalances ?? []), ...(tx.meta?.preTokenBalances ?? [])]
      .filter((b) => b.mint === mint && b.owner && b.owner !== owner)
      .map((b) => b.owner as string),
  );
  let best: { owner: string; delta: number } | null = null;
  for (const o of owners) {
    const d = tokenDelta(tx, o, mint);
    if (d > 0 && (!best || d > best.delta)) best = { owner: o, delta: d };
  }
  return best?.owner ?? null;
}

/** Did the owner receive SOL/stables in the same tx (i.e. was it a sale rather than a transfer)? */
function receivedQuote(tx: ParsedTransaction, owner: string): boolean {
  const keys = tx.transaction.message.accountKeys.map(accountKeyAddress);
  const idx = keys.indexOf(owner);
  if (idx >= 0 && tx.meta?.preBalances && tx.meta.postBalances) {
    const fee = idx === 0 ? (tx.meta.fee ?? 0) : 0;
    const lamportDelta = (tx.meta.postBalances[idx] ?? 0) - (tx.meta.preBalances[idx] ?? 0) + fee;
    if (lamportDelta > 10_000_000) return true; // > 0.01 SOL
  }
  for (const m of STABLE_MINTS) if (tokenDelta(tx, owner, m) > 0) return true;
  return false;
}

export class SolanaWalletProfiler implements WalletProfiler, DeveloperActivitySource {
  readonly name = 'solana-rpc';

  constructor(
    private readonly rpc: SolanaRpc,
    private readonly opts: { freshWalletAgeHours: number; maxDevTransactions?: number } = {
      freshWalletAgeHours: 72,
    },
  ) {}

  supports(chain: Chain): boolean {
    return chain === 'solana';
  }

  async profile(_chain: Chain, addresses: string[]): Promise<Map<string, WalletProfile>> {
    const out = new Map<string, WalletProfile>();
    for (const address of addresses) {
      try {
        out.set(address, await this.profileOne(address));
      } catch {
        // Individual wallet failures are tolerated; the caller sees fewer profiled wallets.
      }
    }
    return out;
  }

  private async profileOne(address: string): Promise<WalletProfile> {
    const PAGE = 1000;
    const sigs = await this.rpc.getSignaturesForAddress(address, { limit: PAGE });
    if (sigs.length === 0) return { address, createdAt: null, ageIsLowerBound: false, fundedBy: null };
    const oldest = sigs[sigs.length - 1] as (typeof sigs)[number];
    const createdAt = oldest.blockTime ? new Date(oldest.blockTime * 1000) : null;
    if (sigs.length >= PAGE) {
      // More history than one page: the true creation date is earlier; funder unknown.
      return { address, createdAt, ageIsLowerBound: true, fundedBy: null };
    }
    const tx = await this.rpc.getParsedTransaction(oldest.signature);
    return { address, createdAt, ageIsLowerBound: false, fundedBy: tx ? findFunder(tx, address) : null };
  }

  async activity(
    _chain: Chain,
    token: {
      address: string;
      totalSupply: number | null;
      decimals: number | null;
      pairAddress: string | null;
    },
    devAddress: string,
    lookbackMinutes: number,
  ): Promise<DeveloperActivity> {
    const since = Date.now() - lookbackMinutes * 60_000;
    const sigs = await this.rpc.getSignaturesForAddress(devAddress, { limit: 50 });
    const recent = sigs
      .filter((s) => !s.err && (s.blockTime ?? 0) * 1000 >= since)
      .slice(0, this.opts.maxDevTransactions ?? 15);
    const events: DeveloperEvent[] = [];
    let moved = 0;
    for (const s of recent) {
      let tx: ParsedTransaction | null;
      try {
        tx = await this.rpc.getParsedTransaction(s.signature);
      } catch {
        // A single unreadable transaction must not abort the whole activity scan.
        continue;
      }
      if (!tx || tx.meta?.err) continue;
      const delta = tokenDelta(tx, devAddress, token.address);
      if (delta === 0) continue;
      const pctSupply = token.totalSupply ? (Math.abs(delta) / token.totalSupply) * 100 : null;
      const timestamp = s.blockTime ? new Date(s.blockTime * 1000).toISOString() : null;
      if (delta < 0) {
        const sold = receivedQuote(tx, devAddress);
        moved += pctSupply ?? 0;
        events.push({
          kind: sold ? 'sell' : 'transfer_out',
          signature: s.signature,
          timestamp,
          percentOfSupply: pctSupply,
          counterparty: counterpartyFor(tx, devAddress, token.address),
        });
      } else {
        events.push({
          kind: 'transfer_in',
          signature: s.signature,
          timestamp,
          percentOfSupply: pctSupply,
          counterparty: null,
        });
      }
    }

    // Were tokens pushed to freshly created wallets (classic supply-splitting before a dump)?
    const recipients = [
      ...new Set(
        events
          .filter((e) => e.kind === 'transfer_out' && e.counterparty)
          .map((e) => e.counterparty as string),
      ),
    ].slice(0, 5);
    let fresh = 0;
    if (recipients.length > 0) {
      const profiles = await this.profile('solana', recipients);
      const cutoff = Date.now() - this.opts.freshWalletAgeHours * 3_600_000;
      for (const p of profiles.values()) {
        if (p.createdAt && !p.ageIsLowerBound && p.createdAt.getTime() >= cutoff) fresh += 1;
      }
    }

    return {
      sources: [this.name],
      devAddress,
      lookbackMinutes,
      transfersOut: events.filter((e) => e.kind === 'transfer_out').length,
      sells: events.filter((e) => e.kind === 'sell').length,
      percentOfSupplyMoved: token.totalSupply ? moved : null,
      transfersToFreshWallets: fresh,
      events,
    };
  }
}
