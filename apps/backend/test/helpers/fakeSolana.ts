/**
 * A fake Solana JSON-RPC node for launch-sniper tests. Launches are built as coherent
 * `jsonParsed` transactions (pool vaults, LP mint, creator balances) in the documented RPC
 * response shapes, and the pool's vault balances can be changed or drained afterwards.
 */
import { createHash } from 'node:crypto';
import bs58 from 'bs58';
import { isOnCurve } from '../../src/adapters/solana/keys';

const SOL = 'So11111111111111111111111111111111111111112';

export const FAKE_RPC_URL = 'https://rpc.fake.test';
const TOKEN_PROGRAM = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
export const INCINERATOR = '1nc1nerator11111111111111111111111111111111';

/** Deterministic, unique valid addresses on (wallet) or off (program-derived) the ed25519 curve. */
function address(label: string, onCurve: boolean): string {
  for (let i = 0; ; i++) {
    const a = bs58.encode(createHash('sha256').update(`${label}:${i}`).digest());
    if (isOnCurve(a) === onCurve) return a;
  }
}
export const walletAddress = (seed: number | string): string => address(`wallet-${seed}`, true);
export const programAddress = (seed: number | string): string => address(`program-${seed}`, false);

export interface FakeLaunch {
  signature: string;
  mint: string;
  creator: string;
  poolOwner: string;
  baseVault: string;
  quoteVault: string;
  lpMint: string;
  /** Who ends the creation transaction holding the LP tokens. */
  lpHolder: 'creator' | 'burn' | 'program' | 'burned' | 'none';
  baseReserve: number;
  quoteReserveSol: number;
  supply: number;
  creatorTokens: number;
  mintAuthority: string | null;
  freezeAuthority: string | null;
  extensions?: { extension: string; state?: Record<string, unknown> }[];
  tokenProgram?: string;
  blockTime: number;
  creatorWalletAgeHours: number;
  failed?: boolean;
  /** An extra wallet holding this many tokens (for concentration tests). */
  whaleTokens?: number;
}

let counter = 0;

/** A clean launch: authorities revoked, LP burned to the incinerator, small creator bag. */
export function makeLaunch(overrides: Partial<FakeLaunch> = {}): FakeLaunch {
  counter += 1;
  const n = `launch-${counter}`;
  return {
    signature: `LaunchSig${counter}${'x'.repeat(60)}`.slice(0, 88),
    mint: walletAddress(`${n}-mint`),
    creator: walletAddress(`${n}-creator`),
    poolOwner: programAddress(`${n}-pool`),
    baseVault: walletAddress(`${n}-base`),
    quoteVault: walletAddress(`${n}-quote`),
    lpMint: walletAddress(`${n}-lp`),
    lpHolder: 'burn',
    baseReserve: 800_000_000,
    quoteReserveSol: 50,
    supply: 1_000_000_000,
    creatorTokens: 10_000_000,
    mintAuthority: null,
    freezeAuthority: null,
    blockTime: Math.floor(Date.now() / 1000) - 2,
    creatorWalletAgeHours: 24 * 30,
    ...overrides,
  };
}

const tokenAccount = (mint: string, owner: string, ui: number, decimals: number) => ({
  data: {
    program: 'spl-token',
    parsed: {
      type: 'account',
      info: {
        mint,
        owner,
        state: 'initialized',
        tokenAmount: {
          amount: BigInt(Math.round(ui * 10 ** decimals)).toString(),
          decimals,
          uiAmount: ui,
        },
      },
    },
    space: 165,
  },
  owner: TOKEN_PROGRAM,
  lamports: 2_039_280,
  executable: false,
});

const balance = (accountIndex: number, mint: string, owner: string, ui: number, decimals: number) => ({
  accountIndex,
  mint,
  owner,
  programId: TOKEN_PROGRAM,
  uiTokenAmount: {
    amount: BigInt(Math.round(ui * 10 ** decimals)).toString(),
    decimals,
    uiAmount: ui,
  },
});

export class FakeSolana {
  readonly launches = new Map<string, FakeLaunch>();
  private readonly vaults = new Map<
    string,
    { mint: string; owner: string; ui: number; decimals: number } | null
  >();
  readonly calls: string[] = [];

  addLaunch(l: FakeLaunch): FakeLaunch {
    this.launches.set(l.signature, l);
    this.vaults.set(l.baseVault, { mint: l.mint, owner: l.poolOwner, ui: l.baseReserve, decimals: 6 });
    this.vaults.set(l.quoteVault, { mint: SOL, owner: l.poolOwner, ui: l.quoteReserveSol, decimals: 9 });
    return l;
  }

  /** Changes a pool's reserves (e.g. price moves after launch). */
  setReserves(l: FakeLaunch, baseReserve: number, quoteReserveSol: number): void {
    this.vaults.set(l.baseVault, { mint: l.mint, owner: l.poolOwner, ui: baseReserve, decimals: 6 });
    this.vaults.set(l.quoteVault, { mint: SOL, owner: l.poolOwner, ui: quoteReserveSol, decimals: 9 });
  }

  /** Liquidity pulled: the vault accounts are closed. */
  drain(l: FakeLaunch): void {
    this.vaults.set(l.baseVault, null);
    this.vaults.set(l.quoteVault, null);
  }

  /** The creation transaction in getTransaction `jsonParsed` form. */
  transactionFor(l: FakeLaunch) {
    const creatorAta = walletAddress(`ata-${l.mint}`);
    const lpAccount = walletAddress(`lp-${l.mint}`);
    const lpOwner =
      l.lpHolder === 'creator' ? l.creator : l.lpHolder === 'program' ? programAddress(777) : INCINERATOR;
    const post = [
      balance(1, l.mint, l.poolOwner, l.baseReserve, 6),
      balance(2, SOL, l.poolOwner, l.quoteReserveSol, 9),
      balance(4, l.mint, l.creator, l.creatorTokens, 6),
    ];
    if (l.lpHolder !== 'none') {
      post.push(balance(3, l.lpMint, lpOwner, l.lpHolder === 'burned' ? 0 : 1_000, 9));
    }
    return {
      blockTime: l.blockTime,
      slot: 300_000_000,
      meta: {
        err: l.failed ? { InstructionError: [0, 'Custom'] } : null,
        fee: 5000,
        preBalances: [10_000_000_000, 0, 0, 0, 0],
        postBalances: [9_000_000_000, 2_039_280, 2_039_280, 2_039_280, 2_039_280],
        preTokenBalances: [balance(4, l.mint, l.creator, l.supply, 6)],
        postTokenBalances: post,
        innerInstructions: [],
      },
      transaction: {
        signatures: [l.signature],
        message: {
          accountKeys: [
            { pubkey: l.creator, signer: true, writable: true },
            { pubkey: l.baseVault, signer: false, writable: true },
            { pubkey: l.quoteVault, signer: false, writable: true },
            { pubkey: lpAccount, signer: false, writable: true },
            { pubkey: creatorAta, signer: false, writable: true },
          ],
          instructions: [],
        },
      },
    };
  }

  private mintAccount(l: FakeLaunch) {
    return {
      data: {
        program: l.tokenProgram === 'spl-token-2022' ? 'spl-token-2022' : 'spl-token',
        parsed: {
          type: 'mint',
          info: {
            decimals: 6,
            supply: BigInt(l.supply * 1e6).toString(),
            mintAuthority: l.mintAuthority,
            freezeAuthority: l.freezeAuthority,
            isInitialized: true,
            ...(l.extensions ? { extensions: l.extensions } : {}),
          },
        },
        space: 82,
      },
      owner:
        l.tokenProgram === 'spl-token-2022' ? 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb' : TOKEN_PROGRAM,
      lamports: 1_461_600,
      executable: false,
    };
  }

  private launchByMint(mint: string): FakeLaunch | undefined {
    return [...this.launches.values()].find((l) => l.mint === mint);
  }

  private account(address: string): unknown {
    if (this.vaults.has(address)) {
      const v = this.vaults.get(address);
      return v ? tokenAccount(v.mint, v.owner, v.ui, v.decimals) : null;
    }
    const l = this.launchByMint(address);
    return l ? this.mintAccount(l) : null;
  }

  private result(method: string, params: unknown[]): unknown {
    const ctx = { context: { slot: 300_000_001 } };
    switch (method) {
      case 'getTransaction': {
        const l = this.launches.get(params[0] as string);
        return l ? this.transactionFor(l) : null;
      }
      case 'getAccountInfo':
        return { ...ctx, value: this.account(params[0] as string) };
      case 'getMultipleAccounts':
        return { ...ctx, value: (params[0] as string[]).map((a) => this.account(a)) };
      case 'getTokenLargestAccounts': {
        const l = this.launchByMint(params[0] as string);
        if (!l) return { ...ctx, value: [] };
        const vault = this.vaults.get(l.baseVault);
        const rows = [
          { address: l.baseVault, ui: vault?.ui ?? 0 },
          { address: walletAddress(`ata-${l.mint}`), ui: l.creatorTokens },
          ...(l.whaleTokens ? [{ address: walletAddress(`whale-${l.mint}`), ui: l.whaleTokens }] : []),
        ].sort((a, b) => b.ui - a.ui);
        return {
          ...ctx,
          value: rows.map((r) => ({
            address: r.address,
            amount: BigInt(Math.round(r.ui * 1e6)).toString(),
            decimals: 6,
            uiAmount: r.ui,
          })),
        };
      }
      case 'getSignaturesForAddress': {
        const l = [...this.launches.values()].find((x) => x.creator === params[0]);
        if (!l) return [];
        return [
          {
            signature: `first-tx-of-${l.creator.slice(0, 8)}`,
            slot: 1,
            err: null,
            blockTime: Math.floor(Date.now() / 1000 - l.creatorWalletAgeHours * 3600),
          },
        ];
      }
      default:
        return null;
    }
  }

  readonly handle = async (body: string): Promise<Response> => {
    const req = JSON.parse(body) as { id: number; method: string; params?: unknown[] };
    this.calls.push(req.method);
    return new Response(
      JSON.stringify({ jsonrpc: '2.0', id: req.id, result: this.result(req.method, req.params ?? []) }),
      { status: 200, headers: { 'content-type': 'application/json' } },
    );
  };
}
