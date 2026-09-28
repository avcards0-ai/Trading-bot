import type { AlertSeverity, AlertType, MarketData, RiskReport, TokenSnapshot } from '@memeguard/shared';
import { levelRank } from '../analysis/rug/detector';
import { pctChange } from '../lib/math';

export interface AlertCandidate {
  type: AlertType;
  severity: AlertSeverity;
  title: string;
  message: string;
  data: Record<string, unknown>;
  /** Extra discriminator so distinct events of the same type are not deduplicated away. */
  key?: string;
}

export interface Observation {
  market: MarketData | null;
  snapshot?: TokenSnapshot | null;
  report?: RiskReport | null;
}

const pct = (v: number) => `${v.toFixed(1)}%`;

/** Market-only rules: cheap enough to run on every monitoring tick. */
export function marketAlerts(prev: MarketData | null, curr: MarketData | null): AlertCandidate[] {
  const out: AlertCandidate[] = [];
  if (!curr) return out;
  const liqChange = pctChange(prev?.liquidityUsd ?? null, curr.liquidityUsd);
  if (liqChange !== null && liqChange <= -50) {
    out.push({
      type: 'LIQUIDITY_CRASH',
      severity: 'critical',
      title: 'Liquidity crash',
      message: `Liquidity fell ${pct(-liqChange)} (from $${Math.round(prev?.liquidityUsd ?? 0)} to $${Math.round(curr.liquidityUsd ?? 0)}). Possible rug pull.`,
      data: { changePct: liqChange, from: prev?.liquidityUsd, to: curr.liquidityUsd },
    });
  } else if (liqChange !== null && liqChange <= -25) {
    out.push({
      type: 'LIQUIDITY_REMOVAL',
      severity: 'warning',
      title: 'Liquidity removed',
      message: `Liquidity fell ${pct(-liqChange)} since the previous observation.`,
      data: { changePct: liqChange, from: prev?.liquidityUsd, to: curr.liquidityUsd },
    });
  }
  const priceChange = pctChange(prev?.priceUsd ?? null, curr.priceUsd);
  const m5 = curr.priceChangePct.m5;
  if ((priceChange !== null && priceChange <= -40) || (m5 !== null && m5 <= -40)) {
    const drop = Math.min(priceChange ?? 0, m5 ?? 0);
    out.push({
      type: 'EXTREME_PRICE_DROP',
      severity: 'critical',
      title: 'Extreme price drop',
      message: `Price dropped ${pct(-drop)} (5m change ${m5 === null ? 'n/a' : pct(m5)}).`,
      data: { changePct: priceChange, m5, price: curr.priceUsd },
    });
  }
  const v5 = curr.volumeUsd.m5;
  const v1 = curr.volumeUsd.h1;
  const v24 = curr.volumeUsd.h24;
  const liq = curr.liquidityUsd;
  if (v5 !== null && v1 !== null && v1 > 0 && v5 > 10_000 && (v5 * 12) / v1 > 8) {
    out.push({
      type: 'ABNORMAL_VOLUME',
      severity: 'warning',
      title: 'Abnormal volume spike',
      message: `5-minute volume $${Math.round(v5)} is running ${((v5 * 12) / v1).toFixed(1)}× the hourly average rate.`,
      data: { volume5m: v5, volume1h: v1 },
    });
  } else if (v24 !== null && liq && v24 / liq > 50) {
    out.push({
      type: 'ABNORMAL_VOLUME',
      severity: 'info',
      title: 'Abnormal turnover',
      message: `24h volume is ${(v24 / liq).toFixed(0)}× liquidity (possible wash trading).`,
      data: { volume24h: v24, liquidity: liq },
    });
  }
  return out;
}

/** Full-analysis rules comparing consecutive snapshots / risk reports. */
export function analysisAlerts(prev: Observation | null, curr: Observation): AlertCandidate[] {
  const out: AlertCandidate[] = [];
  const ps = prev?.snapshot ?? null;
  const cs = curr.snapshot ?? null;

  // Developer activity (new events only)
  if (cs?.developer) {
    const seen = new Set((ps?.developer?.events ?? []).map((e) => e.signature));
    const fresh = cs.developer.events.filter((e) => e.signature && !seen.has(e.signature));
    const sells = fresh.filter((e) => e.kind === 'sell');
    const outs = fresh.filter((e) => e.kind === 'transfer_out');
    const moved = [...sells, ...outs].reduce((a, e) => a + (e.percentOfSupply ?? 0), 0);
    if (sells.length > 0) {
      out.push({
        type: 'DEVELOPER_SELLING',
        severity: 'critical',
        title: 'Developer selling',
        message: `Developer wallet sold ${sells.length} time(s), ${pct(sells.reduce((a, e) => a + (e.percentOfSupply ?? 0), 0))} of supply.`,
        data: { sells: sells.length, signatures: sells.map((s) => s.signature).slice(0, 5) },
        key: sells[0]?.signature ?? undefined,
      });
    }
    if (outs.length > 0) {
      out.push({
        type: 'DEVELOPER_ACTIVITY',
        severity: 'warning',
        title: 'Developer transfers',
        message: `Developer wallet made ${outs.length} outgoing transfer(s) (${pct(outs.reduce((a, e) => a + (e.percentOfSupply ?? 0), 0))} of supply).`,
        data: { transfers: outs.length, recipients: outs.map((o) => o.counterparty).slice(0, 5) },
        key: outs[0]?.signature ?? undefined,
      });
    }
    const big = fresh.filter((e) => (e.percentOfSupply ?? 0) >= 2);
    if (big.length > 0 || moved >= 5) {
      out.push({
        type: 'MASSIVE_TRANSFER',
        severity: moved >= 5 ? 'critical' : 'warning',
        title: 'Massive wallet transfer',
        message: `Developer moved ${pct(moved)} of supply in ${fresh.length} transaction(s).`,
        data: { percentOfSupply: moved },
        key: big[0]?.signature ?? undefined,
      });
    }
  }

  // Large holder movement between snapshots
  if (ps?.holders && cs?.holders) {
    for (const h of cs.holders.topHolders.slice(0, 10)) {
      if (h.isLiquidityPool || h.isBurn) continue;
      const before = ps.holders.topHolders.find((x) => x.address === h.address);
      if (before && before.percent - h.percent >= 5) {
        out.push({
          type: 'MASSIVE_TRANSFER',
          severity: 'warning',
          title: 'Large holder reduced position',
          message: `Top holder ${h.address.slice(0, 8)}… went from ${pct(before.percent)} to ${pct(h.percent)} of supply.`,
          data: { holder: h.address, from: before.percent, to: h.percent },
          key: `holder:${h.address}`,
        });
      }
    }
  }

  // Tax changes
  const tax = (s: TokenSnapshot | null) => ({
    buy: Math.max(s?.contract?.buyTaxPct ?? -1, s?.honeypot?.buyTaxPct ?? -1),
    sell: Math.max(s?.contract?.sellTaxPct ?? -1, s?.honeypot?.sellTaxPct ?? -1),
  });
  if (ps && cs) {
    const a = tax(ps);
    const b = tax(cs);
    for (const side of ['buy', 'sell'] as const) {
      if (a[side] >= 0 && b[side] >= 0 && Math.abs(b[side] - a[side]) >= 2) {
        out.push({
          type: 'TAX_CHANGE',
          severity: b[side] > a[side] ? 'critical' : 'warning',
          title: `${side === 'buy' ? 'Buy' : 'Sell'} tax changed`,
          message: `${side} tax changed from ${pct(a[side])} to ${pct(b[side])}.`,
          data: { side, from: a[side], to: b[side] },
          key: side,
        });
      }
    }
  }

  // Contract changes
  const pc = ps?.contract;
  const cc = cs?.contract;
  if (pc && cc) {
    const changes: string[] = [];
    if (pc.codeHash && cc.codeHash && pc.codeHash !== cc.codeHash) changes.push('code/authorities hash');
    if (pc.ownerAddress && pc.ownerAddress !== cc.ownerAddress)
      changes.push(`owner ${pc.ownerAddress} -> ${cc.ownerAddress ?? 'none'}`);
    if (pc.proxyImplementation && pc.proxyImplementation !== cc.proxyImplementation)
      changes.push('proxy implementation');
    if (!pc.mintAuthority && cc.mintAuthority) changes.push('mint authority enabled');
    if (!pc.freezeAuthority && cc.freezeAuthority) changes.push('freeze authority enabled');
    if (changes.length > 0) {
      out.push({
        type: 'CONTRACT_CHANGE',
        severity: 'critical',
        title: 'Contract changed',
        message: `Detected contract changes: ${changes.join('; ')}.`,
        data: { changes },
        key: cc.codeHash ?? changes.join('|'),
      });
    }
  }

  // Rug-risk escalation
  const pr = prev?.report ?? null;
  const cr = curr.report ?? null;
  if (pr && cr) {
    const delta = cr.rugScore - pr.rugScore;
    const levelUp =
      levelRank(cr.overallRisk) > levelRank(pr.overallRisk) && levelRank(cr.overallRisk) >= levelRank('HIGH');
    if (delta >= 15 || levelUp) {
      out.push({
        type: 'RUG_RISK_ESCALATION',
        severity: cr.overallRisk === 'CRITICAL' ? 'critical' : 'warning',
        title: 'Rug risk escalated',
        message:
          `Rug score ${pr.rugScore} -> ${cr.rugScore}; overall ${pr.overallRisk} -> ${cr.overallRisk}. ${
            cr.criticalFlags.length > 0 ? `Critical: ${cr.criticalFlags.join(', ')}.` : ''
          }`.trim(),
        data: { from: pr.rugScore, to: cr.rugScore, overall: cr.overallRisk },
        key: `${cr.overallRisk}:${Math.round(cr.rugScore / 10)}`,
      });
    }
  }
  return out;
}
