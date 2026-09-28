import type { HolderInfo, TradeActivity, WalletAnalysis, WalletCluster } from '@memeguard/shared';
import type { RawTrade, WalletProfile } from '../adapters/types';
import { mean, stdev } from '../lib/math';

/** Summarises raw trades into wash-trading / manipulation indicators. Pure function. */
export function computeTradeActivity(trades: RawTrade[], source: string): TradeActivity | null {
  if (trades.length === 0) return null;
  const sorted = [...trades].sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime());
  const first = sorted[0] as RawTrade;
  const last = sorted[sorted.length - 1] as RawTrade;
  const windowMinutes = Math.max(1, (last.timestamp.getTime() - first.timestamp.getTime()) / 60_000);

  const byWallet = new Map<string, { buy: number; sell: number }>();
  let buyVolumeUsd = 0;
  let sellVolumeUsd = 0;
  for (const t of sorted) {
    const w = byWallet.get(t.wallet) ?? { buy: 0, sell: 0 };
    if (t.kind === 'buy') {
      w.buy += t.volumeUsd;
      buyVolumeUsd += t.volumeUsd;
    } else {
      w.sell += t.volumeUsd;
      sellVolumeUsd += t.volumeUsd;
    }
    byWallet.set(t.wallet, w);
  }
  const total = buyVolumeUsd + sellVolumeUsd;
  let roundTripWallets = 0;
  let roundTripVolume = 0;
  let topWalletVolume = 0;
  for (const w of byWallet.values()) {
    const vol = w.buy + w.sell;
    topWalletVolume = Math.max(topWalletVolume, vol);
    if (w.buy > 0 && w.sell > 0) {
      roundTripWallets += 1;
      roundTripVolume += vol;
    }
  }
  const sizes = sorted.map((t) => t.volumeUsd);
  const m = mean(sizes);
  const sd = stdev(sizes);
  const counts = new Map<string, number>();
  for (const s of sizes) {
    const key = s.toFixed(2);
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  let repeated = 0;
  for (const c of counts.values()) if (c > 1) repeated += c;

  return {
    source,
    windowMinutes,
    tradeCount: sorted.length,
    uniqueTraders: byWallet.size,
    buyers: [...byWallet.values()].filter((w) => w.buy > 0).length,
    sellers: [...byWallet.values()].filter((w) => w.sell > 0).length,
    buyVolumeUsd,
    sellVolumeUsd,
    roundTripWallets,
    roundTripVolumeShare: total > 0 ? roundTripVolume / total : 0,
    topTraderVolumeShare: total > 0 ? topWalletVolume / total : 0,
    tradeSizeCv: m !== null && sd !== null && m > 0 ? sd / m : null,
    repeatedSizeShare: sorted.length > 0 ? repeated / sorted.length : 0,
  };
}

/** Holders that count towards concentration (pools, burns, lockers and program escrow excluded). */
export function circulatingHolders(holders: HolderInfo[], chain: string): HolderInfo[] {
  return holders.filter(
    (h) => !h.isLiquidityPool && !h.isBurn && !h.isLocked && !(chain === 'solana' && h.isContract === true),
  );
}

/**
 * Wallet-age and funding-cluster analysis over profiled top holders. Wallets funded by the same
 * source, or funded by another top holder, are grouped (union-find).
 */
export function computeWalletAnalysis(
  holders: HolderInfo[],
  profiles: Map<string, WalletProfile>,
  opts: { freshWalletAgeHours: number; now: Date; sources: string[] },
): WalletAnalysis | null {
  const analyzed = holders.filter((h) => profiles.has(h.address));
  if (analyzed.length === 0) return null;
  const cutoff = opts.now.getTime() - opts.freshWalletAgeHours * 3_600_000;
  let newWallets = 0;
  for (const h of analyzed) {
    const p = profiles.get(h.address) as WalletProfile;
    if (p.createdAt && !p.ageIsLowerBound && p.createdAt.getTime() >= cutoff) newWallets += 1;
  }

  const parent = new Map<string, string>();
  const find = (x: string): string => {
    let r = x;
    while (parent.has(r) && parent.get(r) !== r) r = parent.get(r) as string;
    parent.set(x, r);
    return r;
  };
  const union = (a: string, b: string) => {
    const ra = find(a);
    const rb = find(b);
    if (ra !== rb) parent.set(ra, rb);
  };
  const holderSet = new Set(analyzed.map((h) => h.address));
  for (const h of analyzed) {
    parent.set(h.address, parent.get(h.address) ?? h.address);
    const funder = profiles.get(h.address)?.fundedBy;
    if (!funder) continue;
    const funderKey = `funder:${funder}`;
    parent.set(funderKey, parent.get(funderKey) ?? funderKey);
    union(h.address, funderKey);
    if (holderSet.has(funder)) union(h.address, funder);
  }
  const groups = new Map<string, HolderInfo[]>();
  for (const h of analyzed) {
    const root = find(h.address);
    const list = groups.get(root) ?? [];
    list.push(h);
    groups.set(root, list);
  }
  const clusters: WalletCluster[] = [];
  for (const members of groups.values()) {
    if (members.length < 2) continue;
    const funders = members.map((m) => profiles.get(m.address)?.fundedBy).filter((f): f is string => !!f);
    const funder = mostCommon(funders) ?? members[0]?.address ?? 'unknown';
    clusters.push({
      funder,
      wallets: members.map((m) => m.address),
      combinedPercent: members.reduce((a, m) => a + m.percent, 0),
    });
  }
  clusters.sort((a, b) => b.combinedPercent - a.combinedPercent);
  return {
    sources: opts.sources,
    analyzedWallets: analyzed.length,
    newWallets,
    newWalletShare: newWallets / analyzed.length,
    clusters,
    largestClusterPercent: clusters[0]?.combinedPercent ?? 0,
  };
}

function mostCommon(xs: string[]): string | null {
  const c = new Map<string, number>();
  for (const x of xs) c.set(x, (c.get(x) ?? 0) + 1);
  let best: string | null = null;
  let n = 0;
  for (const [k, v] of c) if (v > n) [best, n] = [k, v];
  return best;
}
