import { z } from 'zod';
import type { JsonRpcClient } from '../../lib/jsonRpc';

/** Typed wrapper for the Solana JSON-RPC methods this project uses. https://solana.com/docs/rpc */

const parsedAccount = z
  .object({
    data: z.union([
      z.object({ program: z.string().nullish(), parsed: z.unknown(), space: z.number().nullish() }).passthrough(),
      z.array(z.string()),
      z.string(),
    ]),
    owner: z.string(),
    lamports: z.number(),
    executable: z.boolean().nullish(),
  })
  .passthrough();
export type ParsedAccount = z.infer<typeof parsedAccount>;

const withContext = <T extends z.ZodType>(value: T) => z.object({ context: z.unknown().optional(), value });

const signatureInfo = z.object({
  signature: z.string(),
  slot: z.number(),
  err: z.unknown().nullish(),
  blockTime: z.number().nullish(),
});
export type SignatureInfo = z.infer<typeof signatureInfo>;

const tokenBalance = z
  .object({
    accountIndex: z.number(),
    mint: z.string(),
    owner: z.string().nullish(),
    uiTokenAmount: z.object({ amount: z.string(), decimals: z.number(), uiAmount: z.number().nullish() }).passthrough(),
  })
  .passthrough();
export type TokenBalance = z.infer<typeof tokenBalance>;

const parsedInstruction = z
  .object({
    program: z.string().nullish(),
    programId: z.string().nullish(),
    parsed: z.unknown().optional(),
  })
  .passthrough();

const parsedTransaction = z
  .object({
    blockTime: z.number().nullish(),
    slot: z.number().nullish(),
    meta: z
      .object({
        err: z.unknown().nullish(),
        fee: z.number().nullish(),
        preBalances: z.array(z.number()).nullish(),
        postBalances: z.array(z.number()).nullish(),
        preTokenBalances: z.array(tokenBalance).nullish(),
        postTokenBalances: z.array(tokenBalance).nullish(),
        innerInstructions: z
          .array(z.object({ index: z.number(), instructions: z.array(parsedInstruction) }).passthrough())
          .nullish(),
      })
      .passthrough()
      .nullish(),
    transaction: z
      .object({
        signatures: z.array(z.string()).nullish(),
        message: z
          .object({
            accountKeys: z.array(
              z.union([z.string(), z.object({ pubkey: z.string(), signer: z.boolean().nullish(), writable: z.boolean().nullish() }).passthrough()]),
            ),
            instructions: z.array(parsedInstruction),
          })
          .passthrough(),
      })
      .passthrough(),
  })
  .passthrough();
export type ParsedTransaction = z.infer<typeof parsedTransaction>;

export const accountKeyAddress = (k: ParsedTransaction['transaction']['message']['accountKeys'][number]): string =>
  typeof k === 'string' ? k : k.pubkey;

export class SolanaRpc {
  constructor(private readonly rpc: JsonRpcClient) {}

  get name(): string {
    return this.rpc.name;
  }

  health() {
    return this.rpc.health();
  }

  async getParsedAccount(address: string): Promise<ParsedAccount | null> {
    const r = await this.rpc.call(
      'getAccountInfo',
      [address, { encoding: 'jsonParsed', commitment: 'confirmed' }],
      withContext(parsedAccount.nullable()),
    );
    return r.value;
  }

  async getMultipleParsedAccounts(addresses: string[]): Promise<(ParsedAccount | null)[]> {
    const out: (ParsedAccount | null)[] = [];
    for (let i = 0; i < addresses.length; i += 100) {
      const r = await this.rpc.call(
        'getMultipleAccounts',
        [addresses.slice(i, i + 100), { encoding: 'jsonParsed', commitment: 'confirmed' }],
        withContext(z.array(parsedAccount.nullable())),
      );
      out.push(...r.value);
    }
    return out;
  }

  async getTokenLargestAccounts(mint: string) {
    const r = await this.rpc.call(
      'getTokenLargestAccounts',
      [mint, { commitment: 'confirmed' }],
      withContext(
        z.array(z.object({ address: z.string(), amount: z.string(), decimals: z.number(), uiAmount: z.number().nullish() })),
      ),
    );
    return r.value;
  }

  async getTokenSupply(mint: string) {
    const r = await this.rpc.call(
      'getTokenSupply',
      [mint, { commitment: 'confirmed' }],
      withContext(z.object({ amount: z.string(), decimals: z.number(), uiAmount: z.number().nullish() })),
    );
    return r.value;
  }

  async getSignaturesForAddress(address: string, opts: { limit: number; before?: string }): Promise<SignatureInfo[]> {
    return this.rpc.call(
      'getSignaturesForAddress',
      [address, { limit: opts.limit, before: opts.before, commitment: 'confirmed' }],
      z.array(signatureInfo),
    );
  }

  async getParsedTransaction(signature: string): Promise<ParsedTransaction | null> {
    return this.rpc.call(
      'getTransaction',
      [signature, { encoding: 'jsonParsed', maxSupportedTransactionVersion: 0, commitment: 'confirmed' }],
      parsedTransaction.nullable(),
    );
  }

  async getBalance(address: string): Promise<number> {
    const r = await this.rpc.call('getBalance', [address, { commitment: 'confirmed' }], withContext(z.number()));
    return r.value;
  }

  async getTokenBalanceForOwner(owner: string, mint: string): Promise<{ raw: bigint; decimals: number }> {
    const r = await this.rpc.call(
      'getTokenAccountsByOwner',
      [owner, { mint }, { encoding: 'jsonParsed', commitment: 'confirmed' }],
      withContext(z.array(z.object({ pubkey: z.string(), account: parsedAccount }))),
    );
    let raw = 0n;
    let decimals = 0;
    for (const acc of r.value) {
      const info = (acc.account.data as { parsed?: { info?: { tokenAmount?: { amount?: string; decimals?: number } } } })
        .parsed?.info?.tokenAmount;
      if (info?.amount) raw += BigInt(info.amount);
      if (typeof info?.decimals === 'number') decimals = info.decimals;
    }
    return { raw, decimals };
  }

  async sendRawTransaction(base64Tx: string): Promise<string> {
    return this.rpc.call(
      'sendTransaction',
      [base64Tx, { encoding: 'base64', skipPreflight: false, preflightCommitment: 'confirmed', maxRetries: 3 }],
      z.string(),
    );
  }

  async getSignatureStatus(signature: string): Promise<{ confirmationStatus: string | null; err: unknown } | null> {
    const r = await this.rpc.call(
      'getSignatureStatuses',
      [[signature], { searchTransactionHistory: false }],
      withContext(z.array(z.object({ confirmationStatus: z.string().nullish(), err: z.unknown().nullish() }).passthrough().nullable())),
    );
    const s = r.value[0];
    return s ? { confirmationStatus: s.confirmationStatus ?? null, err: s.err ?? null } : null;
  }

  async getBlockHeight(): Promise<number> {
    return this.rpc.call('getBlockHeight', [{ commitment: 'confirmed' }], z.number());
  }
}
