import { createHash } from 'node:crypto';
import type { Chain, ContractData, HolderInfo, ProviderWarning, TokenProgram } from '@memeguard/shared';
import { BONDING_CURVE_DEXES, SOLANA_AMM_AUTHORITIES, isBurnAddress } from '../chains';
import type { SecuritySource, SnapshotContribution, TokenContext } from '../types';
import { isOnCurve } from './keys';
import type { SolanaRpc } from './rpc';

export const TOKEN_PROGRAM = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
export const TOKEN_2022_PROGRAM = 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb';

type Dict = Record<string, unknown>;

interface MintInfo {
  decimals: number;
  supply: string;
  mintAuthority: string | null;
  freezeAuthority: string | null;
  extensions: { extension: string; state?: Dict }[];
}

const str = (v: unknown): string | null => (typeof v === 'string' && v.length > 0 ? v : null);

export function parseMintAccount(account: { owner: string; data: unknown }): { program: TokenProgram; info: MintInfo } | null {
  const data = account.data as { program?: string; parsed?: { type?: string; info?: Dict } };
  if (!data || typeof data !== 'object' || !data.parsed || data.parsed.type !== 'mint' || !data.parsed.info) return null;
  const info = data.parsed.info;
  const program: TokenProgram =
    account.owner === TOKEN_PROGRAM ? 'spl-token' : account.owner === TOKEN_2022_PROGRAM ? 'spl-token-2022' : 'unknown';
  return {
    program,
    info: {
      decimals: Number(info.decimals ?? 0),
      supply: String(info.supply ?? '0'),
      mintAuthority: str(info.mintAuthority),
      freezeAuthority: str(info.freezeAuthority),
      extensions: Array.isArray(info.extensions) ? (info.extensions as { extension: string; state?: Dict }[]) : [],
    },
  };
}

/** Translate mint authorities + Token-2022 extensions into contract risk fields. */
export function contractFromMint(program: TokenProgram, info: MintInfo): {
  contract: Partial<ContractData>;
  warnings: ProviderWarning[];
} {
  const warnings: ProviderWarning[] = [];
  const contract: Partial<ContractData> = {
    tokenProgram: program,
    mintAuthority: info.mintAuthority,
    mintable: info.mintAuthority !== null,
    freezeAuthority: info.freezeAuthority,
    freezable: info.freezeAuthority !== null,
    // SPL mints are data accounts owned by the audited token programs: no custom code to verify.
    isVerified: program === 'unknown' ? false : null,
    isProxy: null,
    tokenExtensions: info.extensions.map((e) => e.extension),
    permanentDelegate: null,
    transferHook: false,
    nonTransferable: false,
    defaultAccountStateFrozen: false,
    transferFeeAuthority: null,
    suspiciousFunctions: [],
  };
  const suspicious: string[] = [];
  for (const ext of info.extensions) {
    const s = ext.state ?? {};
    switch (ext.extension) {
      case 'transferFeeConfig': {
        const newer = (s.newerTransferFee ?? {}) as Dict;
        const bps = Number(newer.transferFeeBasisPoints ?? 0);
        contract.transferTaxPct = bps / 100;
        contract.transferFeeAuthority = str(s.transferFeeConfigAuthority);
        contract.taxModifiable = contract.transferFeeAuthority !== null;
        if (contract.taxModifiable) suspicious.push('transferFeeConfig (fee authority can raise transfer tax)');
        break;
      }
      case 'permanentDelegate':
        contract.permanentDelegate = str(s.delegate);
        if (contract.permanentDelegate) {
          contract.ownerCanChangeBalance = true;
          suspicious.push('permanentDelegate (can transfer or burn tokens from any holder)');
        }
        break;
      case 'transferHook':
        contract.transferHook = str(s.programId) !== null;
        if (contract.transferHook) suspicious.push('transferHook (custom program runs on every transfer; can block sells)');
        break;
      case 'nonTransferable':
        contract.nonTransferable = true;
        suspicious.push('nonTransferable (token cannot be transferred or sold)');
        break;
      case 'defaultAccountState':
        contract.defaultAccountStateFrozen = String(s.accountState ?? '').toLowerCase() === 'frozen';
        if (contract.defaultAccountStateFrozen) suspicious.push('defaultAccountState=frozen (new holders are frozen)');
        break;
      case 'mintCloseAuthority':
        if (str(s.closeAuthority)) suspicious.push('mintCloseAuthority');
        break;
      case 'pausableConfig':
      case 'pausable':
        contract.transferPausable = str(s.authority) !== null || s.paused === true;
        if (contract.transferPausable) suspicious.push('pausable (authority can halt all transfers)');
        break;
      case 'confidentialTransferMint':
        warnings.push({ source: 'solana-rpc', code: 'confidential_transfers', level: 'info', message: 'Confidential transfers hide amounts' });
        break;
      case 'tokenMetadata':
        contract.metadataMutable = str(s.updateAuthority) !== null;
        break;
      default:
        break;
    }
  }
  contract.suspiciousFunctions = suspicious;
  if (program === 'unknown') {
    warnings.push({ source: 'solana-rpc', code: 'unknown_token_program', level: 'danger', message: 'Mint is not owned by an SPL token program' });
  }
  contract.codeHash = createHash('sha256')
    .update(
      JSON.stringify({
        program,
        mintAuthority: info.mintAuthority,
        freezeAuthority: info.freezeAuthority,
        extensions: info.extensions,
      }),
    )
    .digest('hex');
  return { contract, warnings };
}

export class SolanaInspector implements SecuritySource {
  readonly name = 'solana-rpc';

  constructor(private readonly rpc: SolanaRpc) {}

  supports(chain: Chain): boolean {
    return chain === 'solana';
  }

  async inspect(ctx: TokenContext): Promise<SnapshotContribution | null> {
    const account = await this.rpc.getParsedAccount(ctx.address);
    if (!account) {
      return {
        source: this.name,
        warnings: [{ source: this.name, code: 'mint_not_found', level: 'danger', message: 'Mint account does not exist' }],
      };
    }
    const mint = parseMintAccount(account);
    if (!mint) {
      return {
        source: this.name,
        contract: { tokenProgram: 'unknown' },
        warnings: [{ source: this.name, code: 'not_a_mint', level: 'danger', message: 'Address is not an SPL mint account' }],
      };
    }
    const { contract, warnings } = contractFromMint(mint.program, mint.info);
    const holders = await this.holders(ctx, mint.info);
    return {
      source: this.name,
      decimals: mint.info.decimals,
      contract,
      holders,
      warnings,
    };
  }

  private async holders(ctx: TokenContext, info: MintInfo): Promise<SnapshotContribution['holders']> {
    const supplyRaw = BigInt(info.supply);
    if (supplyRaw === 0n) return { topHolders: [], totalSupply: 0 };
    const largest = await this.rpc.getTokenLargestAccounts(ctx.address);
    const accounts = await this.rpc.getMultipleParsedAccounts(largest.map((l) => l.address));
    const byOwner = new Map<string, { raw: bigint; tokenAccount: string }>();
    largest.forEach((l, i) => {
      const acc = accounts[i];
      const parsed = (acc?.data as { parsed?: { info?: { owner?: string } } } | undefined)?.parsed?.info;
      const owner = parsed?.owner ?? l.address;
      const prev = byOwner.get(owner);
      byOwner.set(owner, { raw: (prev?.raw ?? 0n) + BigInt(l.amount), tokenAccount: l.address });
    });
    const bondingCurveDex = BONDING_CURVE_DEXES.has((ctx.dexId ?? '').toLowerCase());
    let assignedCurve = false;
    const topHolders: HolderInfo[] = [...byOwner.entries()]
      .map(([owner, v]) => ({ owner, raw: v.raw }))
      .sort((a, b) => (b.raw > a.raw ? 1 : b.raw < a.raw ? -1 : 0))
      .map(({ owner, raw }) => {
        const percent = Number((raw * 1_000_000n) / supplyRaw) / 10_000;
        const pda = !isOnCurve(owner);
        let isLiquidityPool = SOLANA_AMM_AUTHORITIES.has(owner) || owner === ctx.pairAddress;
        // The largest program-owned holder of a bonding-curve token is the curve itself.
        if (!isLiquidityPool && pda && bondingCurveDex && !assignedCurve) {
          isLiquidityPool = true;
          assignedCurve = true;
        }
        return {
          address: owner,
          percent,
          amount: Number(raw) / 10 ** info.decimals,
          isContract: pda,
          tag: isLiquidityPool ? 'liquidity pool / bonding curve' : pda ? 'program-owned account (PDA)' : null,
          isLiquidityPool,
          isBurn: isBurnAddress('solana', owner),
        };
      });
    return { topHolders, totalSupply: Number(supplyRaw) / 10 ** info.decimals };
  }
}
