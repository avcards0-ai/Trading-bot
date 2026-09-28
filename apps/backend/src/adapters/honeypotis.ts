import { z } from 'zod';
import type { Chain, ProviderWarning } from '@memeguard/shared';
import type { HttpClient } from '../lib/http';
import { toNum } from '../lib/math';
import type { SecuritySource, SnapshotContribution, TokenContext } from './types';

/**
 * Honeypot.is — simulates a real buy + sell against the token on a fork.
 * https://docs.honeypot.is  GET /v2/IsHoneypot?address=&chainID=
 * Supported: Ethereum (1), BSC (56), Base (8453). Taxes are returned in PERCENT.
 */
export const HONEYPOT_IS_BASE_URL = 'https://api.honeypot.is';

const SUPPORTED: Partial<Record<Chain, number>> = { ethereum: 1, bsc: 56, base: 8453 };

const numLike = z.union([z.number(), z.string()]).nullish();
const response = z
  .object({
    token: z
      .object({
        name: z.string().nullish(),
        symbol: z.string().nullish(),
        decimals: z.number().nullish(),
        totalHolders: z.number().nullish(),
      })
      .nullish(),
    summary: z
      .object({
        risk: z.string().nullish(),
        riskLevel: z.number().nullish(),
        flags: z
          .array(
            z
              .object({
                flag: z.string().nullish(),
                description: z.string().nullish(),
                severity: z.string().nullish(),
              })
              .passthrough(),
          )
          .nullish(),
      })
      .nullish(),
    simulationSuccess: z.boolean().nullish(),
    simulationError: z.string().nullish(),
    honeypotResult: z
      .object({ isHoneypot: z.boolean().nullish(), honeypotReason: z.string().nullish() })
      .nullish(),
    simulationResult: z
      .object({ buyTax: numLike, sellTax: numLike, transferTax: numLike })
      .partial()
      .nullish(),
    contractCode: z
      .object({
        openSource: z.boolean().nullish(),
        rootOpenSource: z.boolean().nullish(),
        isProxy: z.boolean().nullish(),
        hasProxyCalls: z.boolean().nullish(),
      })
      .partial()
      .nullish(),
  })
  .passthrough();

export class HoneypotIsAdapter implements SecuritySource {
  readonly name = 'honeypot.is';

  constructor(private readonly http: HttpClient) {}

  supports(chain: Chain): boolean {
    return SUPPORTED[chain] !== undefined;
  }

  async inspect(ctx: TokenContext): Promise<SnapshotContribution | null> {
    const chainId = SUPPORTED[ctx.chain];
    if (chainId === undefined) return null;
    const r = await this.http.get('/v2/IsHoneypot', {
      query: { address: ctx.address, chainID: chainId, pair: ctx.pairAddress ?? undefined },
      schema: response,
      nullOnStatus: [404],
    });
    if (!r) return null;
    return parseHoneypotIs(r);
  }
}

export function parseHoneypotIs(r: z.infer<typeof response>): SnapshotContribution {
  const simulated = r.simulationSuccess === true;
  const warnings: ProviderWarning[] = (r.summary?.flags ?? []).map((f) => ({
    source: 'honeypot.is',
    code: f.flag ?? 'flag',
    level:
      f.severity === 'critical' || f.severity === 'high'
        ? 'danger'
        : f.severity === 'medium'
          ? 'warn'
          : 'info',
    message: f.description ?? f.flag ?? 'flag',
  }));
  return {
    source: 'honeypot.is',
    name: r.token?.name ?? null,
    symbol: r.token?.symbol ?? null,
    decimals: r.token?.decimals ?? null,
    holders: r.token?.totalHolders ? { holderCount: r.token.totalHolders } : undefined,
    contract: {
      isVerified: r.contractCode?.openSource ?? null,
      isProxy: r.contractCode ? Boolean(r.contractCode.isProxy || r.contractCode.hasProxyCalls) : null,
    },
    honeypot: {
      source: 'honeypot.is',
      simulated,
      isHoneypot: simulated ? (r.honeypotResult?.isHoneypot ?? null) : null,
      buyTaxPct: simulated ? toNum(r.simulationResult?.buyTax) : null,
      sellTaxPct: simulated ? toNum(r.simulationResult?.sellTax) : null,
      transferTaxPct: simulated ? toNum(r.simulationResult?.transferTax) : null,
      sellRouteFound: null,
      reason:
        r.honeypotResult?.honeypotReason ?? (simulated ? null : (r.simulationError ?? 'simulation failed')),
    },
    warnings,
  };
}
