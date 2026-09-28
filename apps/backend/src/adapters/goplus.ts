import { createHash } from 'node:crypto';
import { z } from 'zod';
import type { Chain, HolderInfo, ProviderWarning } from '@memeguard/shared';
import { ProviderError, ProviderResponseError } from '../lib/errors';
import type { HttpClient } from '../lib/http';
import { toNum } from '../lib/math';
import { EVM_CHAIN_IDS, isBurnAddress, isEvm, sameAddress } from './chains';
import type { SecuritySource, SnapshotContribution, TokenContext } from './types';

/**
 * GoPlus Security API. https://docs.gopluslabs.io/reference/api-overview
 *   EVM:    GET /api/v1/token_security/{chainId}?contract_addresses=
 *   Solana: GET /api/v1/solana/token_security?contract_addresses=
 *   Auth (optional): POST /api/v1/token { app_key, time, sign = sha1(app_key + time + app_secret) }
 * Flags are strings "0"/"1"; taxes and holder percents are FRACTIONS ("0.05" = 5%).
 */
export const GOPLUS_BASE_URL = 'https://api.gopluslabs.io';

const envelope = z.object({
  code: z.number(),
  message: z.string().nullish(),
  result: z.record(z.string(), z.unknown()).nullish(),
});

const tokenResponse = z.object({
  code: z.number(),
  message: z.string().nullish(),
  result: z.object({ access_token: z.string(), expires_in: z.number() }).nullish(),
});

type Dict = Record<string, unknown>;

const flag = (v: unknown): boolean | null => {
  if (v === '1' || v === 1 || v === true) return true;
  if (v === '0' || v === 0 || v === false) return false;
  return null;
};

/** GoPlus fraction string -> percent (0-100). */
const fracToPct = (v: unknown): number | null => {
  const n = toNum(v);
  return n === null ? null : n * 100;
};

const statusFlag = (v: unknown): boolean | null =>
  v && typeof v === 'object' && 'status' in v ? flag((v as Dict).status) : flag(v);

const firstAuthority = (v: unknown): string | null => {
  if (!v || typeof v !== 'object') return null;
  const auth = (v as Dict).authority;
  if (Array.isArray(auth) && auth.length > 0) {
    const a = auth[0] as Dict;
    return typeof a?.address === 'string' ? a.address : null;
  }
  return null;
};

const isZeroOwner = (owner: string | null): boolean =>
  owner === null ||
  owner === '' ||
  /^0x0{40}$/i.test(owner) ||
  owner.toLowerCase() === '0x000000000000000000000000000000000000dead';

export class GoPlusAdapter implements SecuritySource {
  readonly name = 'goplus';
  private accessToken: { value: string; expiresAt: number } | null = null;

  constructor(
    private readonly http: HttpClient,
    private readonly creds: { appKey: string | null; appSecret: string | null } = {
      appKey: null,
      appSecret: null,
    },
    private readonly onSecret: (s: string) => void = () => undefined,
  ) {}

  supports(chain: Chain): boolean {
    return chain === 'solana' || chain in EVM_CHAIN_IDS;
  }

  private async authHeaders(): Promise<Record<string, string>> {
    if (!this.creds.appKey || !this.creds.appSecret) return {};
    if (this.accessToken && this.accessToken.expiresAt > Date.now() + 60_000) {
      return { authorization: this.accessToken.value };
    }
    const time = Math.floor(Date.now() / 1000);
    const sign = createHash('sha1')
      .update(`${this.creds.appKey}${time}${this.creds.appSecret}`)
      .digest('hex');
    const res = await this.http.post(
      '/api/v1/token',
      { app_key: this.creds.appKey, time, sign },
      { schema: tokenResponse },
    );
    if (res.code !== 1 || !res.result)
      throw new ProviderError(this.name, `auth failed: ${res.message ?? res.code}`);
    this.onSecret(res.result.access_token);
    this.accessToken = {
      value: res.result.access_token,
      expiresAt: Date.now() + res.result.expires_in * 1000,
    };
    return { authorization: res.result.access_token };
  }

  async inspect(ctx: TokenContext): Promise<SnapshotContribution | null> {
    const headers = await this.authHeaders();
    const path =
      ctx.chain === 'solana'
        ? '/api/v1/solana/token_security'
        : `/api/v1/token_security/${EVM_CHAIN_IDS[ctx.chain as keyof typeof EVM_CHAIN_IDS]}`;
    const res = await this.http.get(path, {
      query: { contract_addresses: ctx.address },
      headers,
      schema: envelope,
    });
    // code 1 = OK, 2 = partial data. Anything else is an error (4029 = rate limit).
    if (res.code === 4029) throw new ProviderError(this.name, 'rate limited (4029)', 429, true);
    if (res.code !== 1 && res.code !== 2)
      throw new ProviderResponseError(this.name, `code ${res.code}: ${res.message}`);
    const result = res.result ?? {};
    const key = Object.keys(result).find((k) => sameAddress(ctx.chain, k, ctx.address));
    if (!key) return null;
    const data = result[key] as Dict;
    return isEvm(ctx.chain) ? parseEvm(ctx, data) : parseSolana(ctx, data);
  }
}

export function parseEvm(ctx: TokenContext, d: Dict): SnapshotContribution {
  const owner = typeof d.owner_address === 'string' ? d.owner_address : null;
  const creator =
    typeof d.creator_address === 'string' && d.creator_address !== '' ? d.creator_address : null;
  const dexes = Array.isArray(d.dex) ? (d.dex as Dict[]) : [];
  const pairAddresses = new Set(
    dexes.map((x) => (typeof x.pair === 'string' ? x.pair.toLowerCase() : '')).filter(Boolean),
  );
  if (ctx.pairAddress) pairAddresses.add(ctx.pairAddress.toLowerCase());

  const holders: HolderInfo[] = (Array.isArray(d.holders) ? (d.holders as Dict[]) : [])
    .map((h) => {
      const address = String(h.address ?? '');
      return {
        address,
        percent: fracToPct(h.percent) ?? 0,
        amount: toNum(h.balance),
        isContract: flag(h.is_contract),
        isLocked: flag(h.is_locked),
        tag: typeof h.tag === 'string' && h.tag !== '' ? h.tag : null,
        isLiquidityPool: pairAddresses.has(address.toLowerCase()),
        isBurn: isBurnAddress(ctx.chain, address),
      };
    })
    .sort((a, b) => b.percent - a.percent);

  const lpHolders = Array.isArray(d.lp_holders) ? (d.lp_holders as Dict[]) : [];
  let locked = 0;
  let burned = 0;
  let creatorLp = 0;
  for (const lp of lpHolders) {
    const pct = fracToPct(lp.percent) ?? 0;
    const addr = String(lp.address ?? '');
    if (isBurnAddress(ctx.chain, addr)) burned += pct;
    else if (flag(lp.is_locked)) locked += pct;
    if (
      (creator && sameAddress(ctx.chain, addr, creator)) ||
      (owner && sameAddress(ctx.chain, addr, owner))
    ) {
      creatorLp += pct;
    }
  }
  const dexLiquidity = dexes.reduce((a, x) => a + (toNum(x.liquidity) ?? 0), 0);

  const warnings: ProviderWarning[] = [];
  if (flag(d.is_airdrop_scam)) {
    warnings.push({
      source: 'goplus',
      code: 'airdrop_scam',
      level: 'danger',
      message: 'Flagged as airdrop scam token',
    });
  }
  if (d.fake_token && typeof d.fake_token === 'object' && flag((d.fake_token as Dict).value)) {
    warnings.push({
      source: 'goplus',
      code: 'fake_token',
      level: 'danger',
      message: 'Impersonates another token (fake token)',
    });
  }

  const ownerAddr = owner === '' ? null : owner;
  return {
    source: 'goplus',
    name: typeof d.token_name === 'string' ? d.token_name : null,
    symbol: typeof d.token_symbol === 'string' ? d.token_symbol : null,
    contract: {
      tokenProgram: 'evm',
      isVerified: flag(d.is_open_source),
      isProxy: flag(d.is_proxy),
      ownerAddress: ownerAddr,
      ownershipRenounced: d.owner_address === undefined ? null : isZeroOwner(ownerAddr),
      hiddenOwner: flag(d.hidden_owner),
      canTakeBackOwnership: flag(d.can_take_back_ownership),
      ownerCanChangeBalance: flag(d.owner_change_balance),
      mintable: flag(d.is_mintable),
      transferPausable: flag(d.transfer_pausable),
      hasBlacklist: flag(d.is_blacklisted),
      hasWhitelist: flag(d.is_whitelisted),
      tradingCooldown: flag(d.trading_cooldown),
      antiWhaleModifiable: flag(d.anti_whale_modifiable),
      taxModifiable: flag(d.slippage_modifiable),
      personalTaxModifiable: flag(d.personal_slippage_modifiable),
      selfDestruct: flag(d.selfdestruct),
      externalCall: flag(d.external_call),
      buyTaxPct: fracToPct(d.buy_tax),
      sellTaxPct: fracToPct(d.sell_tax),
      transferTaxPct: fracToPct(d.transfer_tax),
      cannotBuy: flag(d.cannot_buy),
      cannotSellAll: flag(d.cannot_sell_all),
      flaggedHoneypot: flag(d.is_honeypot),
    },
    holders: {
      holderCount: toNum(d.holder_count),
      topHolders: holders,
      totalSupply: toNum(d.total_supply),
    },
    liquidity: {
      lpLockedPercent: lpHolders.length > 0 ? locked : null,
      lpBurnedPercent: lpHolders.length > 0 ? burned : null,
      creatorLpPercent: lpHolders.length > 0 ? creatorLp : null,
      lpHolderCount: toNum(d.lp_holder_count),
      totalLiquidityUsd: dexes.length > 0 ? dexLiquidity : null,
      poolCount: dexes.length > 0 ? dexes.length : null,
    },
    deployer: {
      address: creator,
      holdsPercent: fracToPct(d.creator_percent),
      honeypotWithSameCreator: flag(d.honeypot_with_same_creator),
    },
    warnings,
  };
}

export function parseSolana(ctx: TokenContext, d: Dict): SnapshotContribution {
  const holders: HolderInfo[] = (Array.isArray(d.holders) ? (d.holders as Dict[]) : [])
    .map((h) => {
      const address = String(h.account ?? h.address ?? '');
      return {
        address,
        percent: fracToPct(h.percent) ?? 0,
        amount: toNum(h.balance),
        isLocked: flag(h.is_locked),
        tag: typeof h.tag === 'string' && h.tag !== '' ? h.tag : null,
        isLiquidityPool: false,
        isBurn: isBurnAddress(ctx.chain, address),
      };
    })
    .sort((a, b) => b.percent - a.percent);

  const creators = Array.isArray(d.creators) ? (d.creators as Dict[]) : [];
  const creator = creators.find((c) => typeof c.address === 'string');
  const maliciousCreator = creators.some((c) => flag(c.malicious_address) === true);
  const transferHookList = Array.isArray(d.transfer_hook) ? d.transfer_hook : [];

  const warnings: ProviderWarning[] = [];
  if (statusFlag(d.closable)) {
    warnings.push({
      source: 'goplus',
      code: 'closable',
      level: 'warn',
      message: 'Mint account can be closed by an authority',
    });
  }
  if (maliciousCreator) {
    warnings.push({
      source: 'goplus',
      code: 'malicious_creator',
      level: 'danger',
      message: 'Creator address flagged as malicious',
    });
  }

  return {
    source: 'goplus',
    contract: {
      mintable: statusFlag(d.mintable),
      mintAuthority: firstAuthority(d.mintable),
      freezable: statusFlag(d.freezable),
      freezeAuthority: firstAuthority(d.freezable),
      ownerCanChangeBalance: statusFlag(d.balance_mutable_authority),
      nonTransferable: flag(d.non_transferable),
      defaultAccountStateFrozen:
        d.default_account_state === undefined ? null : flag(d.default_account_state) === true,
      transferHook: transferHookList.length > 0 ? true : d.transfer_hook === undefined ? null : false,
      metadataMutable: statusFlag(d.metadata_mutable),
      taxModifiable: statusFlag(d.transfer_fee_upgradable),
    },
    holders: {
      topHolders: holders,
      holderCount: toNum(d.holder_count),
      totalSupply: toNum(d.total_supply),
    },
    deployer: {
      address: typeof creator?.address === 'string' ? creator.address : null,
      flaggedMalicious: creators.length > 0 ? maliciousCreator : null,
    },
    warnings,
  };
}
