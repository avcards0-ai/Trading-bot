import { z } from 'zod';
import type { Chain, HolderInfo, ProviderWarning } from '@memeguard/shared';
import type { HttpClient } from '../lib/http';
import { toNum } from '../lib/math';
import { isBurnAddress, sameAddress } from './chains';
import type { SecuritySource, SnapshotContribution, TokenContext } from './types';

/**
 * RugCheck (Solana). https://api.rugcheck.xyz/swagger/index.html
 *   GET /v1/tokens/{mint}/report
 * The report schema evolves; every field is parsed defensively and unknown fields are ignored.
 */
export const RUGCHECK_BASE_URL = 'https://api.rugcheck.xyz';

const numLike = z.union([z.number(), z.string()]).nullish();

const reportSchema = z
  .object({
    mint: z.string().nullish(),
    creator: z.string().nullish(),
    tokenProgram: z.string().nullish(),
    token: z
      .object({
        mintAuthority: z.string().nullish(),
        freezeAuthority: z.string().nullish(),
        supply: numLike,
        decimals: z.number().nullish(),
      })
      .passthrough()
      .nullish(),
    tokenMeta: z
      .object({
        name: z.string().nullish(),
        symbol: z.string().nullish(),
        mutable: z.boolean().nullish(),
        updateAuthority: z.string().nullish(),
      })
      .passthrough()
      .nullish(),
    topHolders: z
      .array(
        z
          .object({
            address: z.string(),
            owner: z.string().nullish(),
            pct: numLike,
            uiAmount: numLike,
            insider: z.boolean().nullish(),
          })
          .passthrough(),
      )
      .nullish(),
    risks: z
      .array(
        z
          .object({
            name: z.string(),
            description: z.string().nullish(),
            level: z.string().nullish(),
            score: numLike,
            value: z.unknown().optional(),
          })
          .passthrough(),
      )
      .nullish(),
    markets: z
      .array(
        z
          .object({
            pubkey: z.string().nullish(),
            marketType: z.string().nullish(),
            lp: z
              .object({ lpLockedPct: numLike, lpLockedUSD: numLike, baseUSD: numLike, quoteUSD: numLike })
              .passthrough()
              .nullish(),
          })
          .passthrough(),
      )
      .nullish(),
    totalMarketLiquidity: numLike,
    totalLPProviders: numLike,
    totalHolders: numLike,
    rugged: z.boolean().nullish(),
    transferFee: z.object({ pct: numLike, authority: z.string().nullish() }).passthrough().nullish(),
    knownAccounts: z
      .record(z.string(), z.object({ name: z.string().nullish(), type: z.string().nullish() }).passthrough())
      .nullish(),
    graphInsidersDetected: numLike,
    creatorTokens: z.array(z.unknown()).nullish(),
  })
  .passthrough();

export type RugCheckReport = z.infer<typeof reportSchema>;

const NULL_AUTHORITY = new Set(['', '11111111111111111111111111111111']);
const authority = (v: string | null | undefined): string | null => (v && !NULL_AUTHORITY.has(v) ? v : null);

export class RugCheckAdapter implements SecuritySource {
  readonly name = 'rugcheck';

  constructor(private readonly http: HttpClient) {}

  supports(chain: Chain): boolean {
    return chain === 'solana';
  }

  async inspect(ctx: TokenContext): Promise<SnapshotContribution | null> {
    const r = await this.http.get(`/v1/tokens/${encodeURIComponent(ctx.address)}/report`, {
      schema: reportSchema,
      nullOnStatus: [404],
    });
    return r ? parseRugCheck(ctx, r) : null;
  }
}

export function parseRugCheck(ctx: TokenContext, r: RugCheckReport): SnapshotContribution {
  const known = r.knownAccounts ?? {};
  const marketKeys = new Set((r.markets ?? []).map((m) => m.pubkey).filter((x): x is string => !!x));
  const holders: HolderInfo[] = (r.topHolders ?? [])
    .map((h) => {
      const owner = h.owner ?? h.address;
      const knownType = (known[owner]?.type ?? known[h.address]?.type ?? '').toUpperCase();
      return {
        address: owner,
        percent: toNum(h.pct) ?? 0,
        amount: toNum(h.uiAmount),
        isInsider: h.insider ?? null,
        tag: known[owner]?.name ?? null,
        isLiquidityPool:
          knownType === 'AMM' || marketKeys.has(owner) || sameAddress('solana', owner, ctx.pairAddress),
        isLocked: knownType === 'LOCKER' ? true : null,
        isBurn: isBurnAddress('solana', owner),
      };
    })
    .sort((a, b) => b.percent - a.percent);

  // Liquidity-weighted LP lock across markets.
  let weight = 0;
  let lockedWeighted = 0;
  for (const m of r.markets ?? []) {
    const usd = (toNum(m.lp?.baseUSD) ?? 0) + (toNum(m.lp?.quoteUSD) ?? 0);
    const pct = toNum(m.lp?.lpLockedPct);
    if (pct === null) continue;
    const w = usd > 0 ? usd : 1;
    weight += w;
    lockedWeighted += pct * w;
  }

  const warnings: ProviderWarning[] = (r.risks ?? []).map((risk) => ({
    source: 'rugcheck',
    code: risk.name.toLowerCase().replace(/[^a-z0-9]+/g, '_'),
    level: risk.level === 'danger' ? 'danger' : risk.level === 'warn' ? 'warn' : 'info',
    message: risk.description ? `${risk.name}: ${risk.description}` : risk.name,
  }));

  const creatorHistoryRug = (r.risks ?? []).some((x) => /creator.*(rug|history)/i.test(x.name));
  const creator = r.creator ?? null;
  const creatorHolder = creator ? holders.find((h) => h.address === creator) : undefined;
  const transferFeePct = toNum(r.transferFee?.pct);

  return {
    source: 'rugcheck',
    name: r.tokenMeta?.name ?? null,
    symbol: r.tokenMeta?.symbol ?? null,
    decimals: r.token?.decimals ?? null,
    contract: {
      tokenProgram:
        r.tokenProgram === 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb'
          ? 'spl-token-2022'
          : r.tokenProgram === 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA'
            ? 'spl-token'
            : undefined,
      mintAuthority: r.token ? authority(r.token.mintAuthority) : undefined,
      mintable: r.token ? authority(r.token.mintAuthority) !== null : undefined,
      freezeAuthority: r.token ? authority(r.token.freezeAuthority) : undefined,
      freezable: r.token ? authority(r.token.freezeAuthority) !== null : undefined,
      metadataMutable: r.tokenMeta?.mutable ?? undefined,
      transferTaxPct: transferFeePct !== null && transferFeePct > 0 ? transferFeePct : undefined,
      transferFeeAuthority: authority(r.transferFee?.authority) ?? undefined,
    },
    holders: {
      topHolders: holders,
      holderCount: toNum(r.totalHolders),
      totalSupply:
        r.token &&
        toNum(r.token.supply) !== null &&
        r.token.decimals !== null &&
        r.token.decimals !== undefined
          ? (toNum(r.token.supply) as number) / 10 ** r.token.decimals
          : null,
    },
    liquidity: {
      totalLiquidityUsd: toNum(r.totalMarketLiquidity),
      lpLockedPercent: weight > 0 ? lockedWeighted / weight : null,
      lpHolderCount: toNum(r.totalLPProviders),
      poolCount: r.markets ? r.markets.length : null,
    },
    deployer: {
      address: creator,
      tokensCreated: r.creatorTokens ? r.creatorTokens.length : null,
      knownRugs: creatorHistoryRug ? 1 : null,
      holdsPercent: creator ? (creatorHolder?.percent ?? 0) : null,
    },
    warnings,
    reportedRugged: r.rugged ?? null,
  };
}
