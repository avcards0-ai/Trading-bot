import type {
  Chain,
  ContractData,
  DeployerProfile,
  HolderData,
  HolderInfo,
  HoneypotSimulation,
  LiquidityData,
  ProviderWarning,
} from '@memeguard/shared';
import { sameAddress } from '../adapters/chains';
import type { MarketQuote, SnapshotContribution } from '../adapters/types';

/**
 * Conservative merge of partial data from several providers:
 *  - "risky" flags: any source reporting true wins (OR)
 *  - "safety" flags (verified, renounced): any source reporting false wins
 *  - taxes / risky percentages: maximum
 *  - safety percentages (LP locked/burned): minimum
 *  - identifiers: first non-null by source priority
 */

const SOURCE_PRIORITY = ['solana-rpc', 'evm-rpc', 'etherscan', 'goplus', 'rugcheck', 'honeypot.is', 'jupiter'];

export const sourceRank = (source: string): number => {
  const i = SOURCE_PRIORITY.findIndex((p) => source === p || source.startsWith(`${p}:`));
  return i < 0 ? SOURCE_PRIORITY.length : i;
};

const byPriority = (cs: SnapshotContribution[]) => [...cs].sort((a, b) => sourceRank(a.source) - sourceRank(b.source));

const RISKY_FLAGS = [
  'isProxy',
  'hiddenOwner',
  'canTakeBackOwnership',
  'ownerCanChangeBalance',
  'mintable',
  'freezable',
  'transferPausable',
  'hasBlacklist',
  'hasWhitelist',
  'tradingCooldown',
  'antiWhaleModifiable',
  'taxModifiable',
  'personalTaxModifiable',
  'selfDestruct',
  'externalCall',
  'cannotBuy',
  'cannotSellAll',
  'flaggedHoneypot',
  'transferHook',
  'nonTransferable',
  'defaultAccountStateFrozen',
  'metadataMutable',
] as const satisfies readonly (keyof ContractData)[];

const SAFETY_FLAGS = ['isVerified', 'ownershipRenounced'] as const satisfies readonly (keyof ContractData)[];

const MAX_NUMBERS = ['buyTaxPct', 'sellTaxPct', 'transferTaxPct'] as const satisfies readonly (keyof ContractData)[];

const FIRST_STRINGS = [
  'proxyImplementation',
  'ownerAddress',
  'mintAuthority',
  'freezeAuthority',
  'permanentDelegate',
  'transferFeeAuthority',
  'codeHash',
] as const satisfies readonly (keyof ContractData)[];

export function emptyContract(sources: string[]): ContractData {
  return {
    sources,
    tokenProgram: 'unknown',
    isVerified: null,
    isProxy: null,
    proxyImplementation: null,
    ownerAddress: null,
    ownershipRenounced: null,
    hiddenOwner: null,
    canTakeBackOwnership: null,
    ownerCanChangeBalance: null,
    mintable: null,
    mintAuthority: null,
    freezable: null,
    freezeAuthority: null,
    transferPausable: null,
    hasBlacklist: null,
    hasWhitelist: null,
    tradingCooldown: null,
    antiWhaleModifiable: null,
    taxModifiable: null,
    personalTaxModifiable: null,
    selfDestruct: null,
    externalCall: null,
    buyTaxPct: null,
    sellTaxPct: null,
    transferTaxPct: null,
    cannotBuy: null,
    cannotSellAll: null,
    flaggedHoneypot: null,
    tokenExtensions: [],
    permanentDelegate: null,
    transferHook: null,
    nonTransferable: null,
    defaultAccountStateFrozen: null,
    transferFeeAuthority: null,
    metadataMutable: null,
    suspiciousFunctions: [],
    codeHash: null,
  };
}

export function mergeContract(contribs: SnapshotContribution[]): ContractData | null {
  const withContract = byPriority(contribs).filter((c) => c.contract && Object.keys(c.contract).length > 0);
  if (withContract.length === 0) return null;
  const out = emptyContract(withContract.map((c) => c.source));
  for (const { contract } of withContract) {
    const c = contract as Partial<ContractData>;
    if (c.tokenProgram && out.tokenProgram === 'unknown') out.tokenProgram = c.tokenProgram;
    for (const k of RISKY_FLAGS) {
      const v = c[k];
      if (v === true) out[k] = true;
      else if (v === false && out[k] === null) out[k] = false;
    }
    for (const k of SAFETY_FLAGS) {
      const v = c[k];
      if (v === false) out[k] = false;
      else if (v === true && out[k] === null) out[k] = true;
    }
    for (const k of MAX_NUMBERS) {
      const v = c[k];
      if (typeof v === 'number' && Number.isFinite(v)) out[k] = Math.max(out[k] ?? v, v);
    }
    for (const k of FIRST_STRINGS) {
      const v = c[k];
      if (typeof v === 'string' && v.length > 0 && out[k] === null) out[k] = v;
    }
    if (c.tokenExtensions) out.tokenExtensions = [...new Set([...out.tokenExtensions, ...c.tokenExtensions])];
    if (c.suspiciousFunctions) {
      out.suspiciousFunctions = [...new Set([...out.suspiciousFunctions, ...c.suspiciousFunctions])];
    }
  }
  // An authority that exists is by definition not renounced/removed.
  if (out.mintAuthority) out.mintable = true;
  if (out.freezeAuthority) out.freezable = true;
  return out;
}

export function mergeHolders(chain: Chain, contribs: SnapshotContribution[]): HolderData | null {
  const withHolders = byPriority(contribs).filter((c) => c.holders);
  if (withHolders.length === 0) return null;
  const primary = withHolders.find((c) => (c.holders?.topHolders?.length ?? 0) > 0);
  const base: HolderInfo[] = (primary?.holders?.topHolders ?? []).map((h) => ({ ...h }));
  // Enrich primary list with labels from other sources (LP, lockers, insiders).
  for (const c of withHolders) {
    if (c === primary) continue;
    for (const other of c.holders?.topHolders ?? []) {
      const h = base.find((b) => sameAddress(chain, b.address, other.address));
      if (!h) continue;
      h.isLiquidityPool = Boolean(h.isLiquidityPool || other.isLiquidityPool);
      h.isBurn = Boolean(h.isBurn || other.isBurn);
      if (other.isLocked) h.isLocked = true;
      if (other.isInsider) h.isInsider = true;
      if (h.isContract === null || h.isContract === undefined) h.isContract = other.isContract ?? null;
      if (!h.tag && other.tag) h.tag = other.tag;
    }
  }
  base.sort((a, b) => b.percent - a.percent);
  const counts = withHolders.map((c) => c.holders?.holderCount).filter((n): n is number => typeof n === 'number');
  const supply = withHolders.map((c) => c.holders?.totalSupply).find((n): n is number => typeof n === 'number');
  return {
    sources: withHolders.map((c) => c.source),
    holderCount: counts.length > 0 ? Math.max(...counts) : null,
    topHolders: base,
    totalSupply: supply ?? null,
  };
}

export function mergeLiquidity(
  contribs: SnapshotContribution[],
  quote: MarketQuote | null,
): LiquidityData | null {
  const withLiq = byPriority(contribs).filter((c) => c.liquidity);
  if (withLiq.length === 0 && !quote) return null;
  const minOf = (k: 'lpLockedPercent' | 'lpBurnedPercent') => {
    const vals = withLiq.map((c) => c.liquidity?.[k]).filter((v): v is number => typeof v === 'number');
    return vals.length > 0 ? Math.min(...vals) : null;
  };
  const maxOf = (k: 'creatorLpPercent' | 'lpHolderCount' | 'poolCount') => {
    const vals = withLiq.map((c) => c.liquidity?.[k]).filter((v): v is number => typeof v === 'number');
    return vals.length > 0 ? Math.max(...vals) : null;
  };
  const providerLiquidity = withLiq
    .map((c) => c.liquidity?.totalLiquidityUsd)
    .find((v): v is number => typeof v === 'number');
  return {
    sources: [...(quote ? [quote.market.source] : []), ...withLiq.map((c) => c.source)],
    totalLiquidityUsd: quote?.totalLiquidityUsd ?? quote?.market.liquidityUsd ?? providerLiquidity ?? null,
    lpLockedPercent: minOf('lpLockedPercent'),
    lpBurnedPercent: minOf('lpBurnedPercent'),
    programControlled: quote?.programControlledLiquidity ?? false,
    creatorLpPercent: maxOf('creatorLpPercent'),
    lpHolderCount: maxOf('lpHolderCount'),
    poolCount: quote?.poolCount ?? maxOf('poolCount'),
  };
}

export function mergeHoneypot(contribs: SnapshotContribution[]): HoneypotSimulation | null {
  const sims = contribs.map((c) => c.honeypot).filter((h): h is HoneypotSimulation => !!h);
  if (sims.length === 0) return null;
  const confirmed = sims.find((s) => s.isHoneypot === true);
  const simulated = sims.filter((s) => s.simulated && s.isHoneypot !== null);
  const pick = confirmed ?? simulated[0] ?? sims[0] as HoneypotSimulation;
  const maxOf = (k: 'buyTaxPct' | 'sellTaxPct' | 'transferTaxPct') => {
    const vals = sims.map((s) => s[k]).filter((v): v is number => typeof v === 'number');
    return vals.length > 0 ? Math.max(...vals) : null;
  };
  return {
    ...pick,
    buyTaxPct: maxOf('buyTaxPct'),
    sellTaxPct: maxOf('sellTaxPct'),
    transferTaxPct: maxOf('transferTaxPct'),
    sellRouteFound: sims.some((s) => s.sellRouteFound === false)
      ? false
      : sims.some((s) => s.sellRouteFound === true)
        ? true
        : null,
  };
}

export function mergeDeployer(chain: Chain, contribs: SnapshotContribution[]): DeployerProfile | null {
  const withDep = byPriority(contribs).filter((c) => c.deployer && Object.keys(c.deployer).length > 0);
  if (withDep.length === 0) return null;
  const out: DeployerProfile = {
    sources: withDep.map((c) => c.source),
    address: null,
    walletAgeDays: null,
    tokensCreated: null,
    knownRugs: null,
    honeypotWithSameCreator: null,
    holdsPercent: null,
    flaggedMalicious: null,
  };
  for (const { deployer } of withDep) {
    const d = deployer as Partial<DeployerProfile>;
    if (!out.address && d.address) out.address = chain === 'solana' ? d.address : d.address.toLowerCase();
    for (const k of ['walletAgeDays'] as const) {
      if (typeof d[k] === 'number') out[k] = out[k] === null ? (d[k] as number) : Math.min(out[k] as number, d[k] as number);
    }
    for (const k of ['tokensCreated', 'knownRugs', 'holdsPercent'] as const) {
      if (typeof d[k] === 'number') out[k] = Math.max(out[k] ?? 0, d[k] as number);
    }
    for (const k of ['honeypotWithSameCreator', 'flaggedMalicious'] as const) {
      if (d[k] === true) out[k] = true;
      else if (d[k] === false && out[k] === null) out[k] = false;
    }
  }
  return out;
}

export function mergeWarnings(contribs: SnapshotContribution[]): ProviderWarning[] {
  const seen = new Set<string>();
  const out: ProviderWarning[] = [];
  for (const c of contribs) {
    for (const w of c.warnings ?? []) {
      const key = `${w.source}:${w.code}`;
      if (!seen.has(key)) {
        seen.add(key);
        out.push(w);
      }
    }
  }
  return out;
}
