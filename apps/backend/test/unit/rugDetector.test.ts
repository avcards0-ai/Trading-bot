import { describe, expect, it } from 'vitest';
import { RugDetector, combineCategories, combineNoisyOr, maxLevel } from '../../src/analysis/rug/detector';
import { NOW, cleanContract, cleanSnapshot, market } from '../helpers/snapshots';

const detector = new RugDetector({ freshWalletAgeHours: 72 });
const analyze = (s = cleanSnapshot(), prev = null as ReturnType<typeof cleanSnapshot> | null) =>
  detector.analyze(s, { now: NOW, previous: prev });

describe('RugDetector', () => {
  it('scores a clean, fully-verified token as low risk', () => {
    const r = analyze();
    expect(r.rugScore).toBeLessThan(20);
    expect(r.overallRisk).toBe('LOW');
    expect(r.isLikelyScam).toBe(false);
    expect(r.honeypotRisk).toBe('LOW');
    expect(r.missingData).toEqual([]);
  });

  it('produces every required output with an explanation', () => {
    const r = analyze();
    for (const key of [
      'rugScore',
      'honeypotRisk',
      'liquidityRisk',
      'contractRisk',
      'walletConcentrationRisk',
      'overallRisk',
    ] as const) {
      expect(r.explanations[key].length).toBeGreaterThan(20);
    }
    expect(r.explanations.rugScore).toMatch(/RUG_SCORE/);
  });

  it('flags a confirmed honeypot as CRITICAL / likely scam', () => {
    const r = analyze(
      cleanSnapshot({
        honeypot: {
          source: 'honeypot.is',
          simulated: true,
          isHoneypot: true,
          buyTaxPct: 0,
          sellTaxPct: 100,
          transferTaxPct: 0,
          sellRouteFound: false,
          reason: 'sell reverted',
        },
      }),
    );
    expect(r.honeypotRisk).toBe('CRITICAL');
    expect(r.overallRisk).toBe('CRITICAL');
    expect(r.isLikelyScam).toBe(true);
    expect(r.rugScore).toBeGreaterThanOrEqual(90);
    expect(r.criticalFlags).toContain('Honeypot confirmed by simulation');
  });

  it('treats confiscatory sell tax as a honeypot', () => {
    const r = analyze(cleanSnapshot({ contract: cleanContract({ sellTaxPct: 60 }) }));
    expect(r.isLikelyScam).toBe(true);
    expect(r.factors.find((f) => f.id === 'sell_tax')?.critical).toBe(true);
  });

  it('rates active mint + freeze authority as high risk', () => {
    const r = analyze(
      cleanSnapshot({
        contract: cleanContract({
          mintable: true,
          mintAuthority: 'AUTH',
          freezable: true,
          freezeAuthority: 'AUTH',
        }),
      }),
    );
    expect(['HIGH', 'CRITICAL']).toContain(r.contractRisk);
    expect(['HIGH', 'CRITICAL']).toContain(r.honeypotRisk);
    expect(r.rugScore).toBeGreaterThan(35);
    expect(r.explanations.contractRisk).toMatch(/Mint authority/);
  });

  it('flags permanent delegates / owner balance control as critical', () => {
    const r = analyze(
      cleanSnapshot({
        contract: cleanContract({ ownerCanChangeBalance: true, permanentDelegate: 'DELEGATE' }),
      }),
    );
    expect(r.isLikelyScam).toBe(true);
    expect(r.contractRisk).toBe('CRITICAL');
  });

  it('flags unlocked LP and creator-held LP', () => {
    const s = cleanSnapshot();
    s.liquidity = { ...s.liquidity!, lpLockedPercent: 5, lpBurnedPercent: 0, creatorLpPercent: 80 };
    const r = analyze(s);
    expect(['HIGH', 'CRITICAL']).toContain(r.liquidityRisk);
    expect(r.factors.map((f) => f.id)).toEqual(expect.arrayContaining(['lp_unlocked', 'creator_lp']));
  });

  it('treats a launchpad bonding curve as program-controlled liquidity (no LP-lock penalty)', () => {
    const s = cleanSnapshot();
    s.liquidity = { ...s.liquidity!, lpLockedPercent: null, lpBurnedPercent: null, programControlled: true };
    expect(analyze(s).factors.find((f) => f.id === 'lp_lock_unknown')).toBeUndefined();
  });

  it('flags extreme supply concentration and coordinated wallet clusters', () => {
    const s = cleanSnapshot({
      holders: {
        sources: ['x'],
        holderCount: 90,
        totalSupply: 1e9,
        topHolders: [
          { address: 'WHALE', percent: 55 },
          { address: 'W2', percent: 20 },
        ],
      },
      wallets: {
        sources: ['rpc'],
        analyzedWallets: 8,
        newWallets: 6,
        newWalletShare: 0.75,
        clusters: [{ funder: 'F', wallets: ['A', 'B', 'C'], combinedPercent: 25 }],
        largestClusterPercent: 25,
      },
    });
    const r = analyze(s);
    expect(r.walletConcentrationRisk).toBe('CRITICAL');
    expect(r.factors.map((f) => f.id)).toEqual(
      expect.arrayContaining(['top_holder', 'wallet_cluster', 'fresh_wallets', 'holder_count']),
    );
  });

  it('flags developer selling and deployer rug history', () => {
    const r = analyze(
      cleanSnapshot({
        deployer: {
          sources: ['x'],
          address: 'DEV',
          walletAgeDays: 0.2,
          tokensCreated: 40,
          knownRugs: 2,
          honeypotWithSameCreator: false,
          holdsPercent: 25,
          flaggedMalicious: false,
        },
        developer: {
          sources: ['rpc'],
          devAddress: 'DEV',
          lookbackMinutes: 60,
          transfersOut: 3,
          sells: 2,
          percentOfSupplyMoved: 8,
          transfersToFreshWallets: 2,
          events: [],
        },
      }),
    );
    expect(r.developerRisk).toBe('CRITICAL');
    expect(r.isLikelyScam).toBe(true);
  });

  it('detects wash-trading patterns and abnormal volume', () => {
    const r = analyze(
      cleanSnapshot({
        market: market({ volumeUsd: { m5: 90_000, h1: 200_000, h6: 1e6, h24: 12_000_000 } }),
        trades: {
          source: 'g',
          windowMinutes: 30,
          tradeCount: 200,
          uniqueTraders: 12,
          buyers: 12,
          sellers: 12,
          buyVolumeUsd: 1e5,
          sellVolumeUsd: 1e5,
          roundTripWallets: 12,
          roundTripVolumeShare: 0.9,
          topTraderVolumeShare: 0.5,
          tradeSizeCv: 0.05,
          repeatedSizeShare: 0.7,
        },
      }),
    );
    expect(['HIGH', 'CRITICAL']).toContain(r.marketIntegrityRisk);
    expect(r.factors.map((f) => f.id)).toEqual(
      expect.arrayContaining(['wash_round_trips', 'uniform_sizes', 'volume_liquidity', 'few_unique_traders']),
    );
  });

  it('fails closed: missing data is never scored as LOW risk', () => {
    const r = analyze(
      cleanSnapshot({
        market: null,
        contract: null,
        holders: null,
        liquidity: null,
        honeypot: null,
        deployer: null,
        trades: null,
      }),
    );
    expect(r.rugScore).toBeGreaterThan(35);
    expect(r.contractRisk).not.toBe('LOW');
    expect(r.honeypotRisk).not.toBe('LOW');
    expect(r.liquidityRisk).not.toBe('LOW');
    expect(r.walletConcentrationRisk).not.toBe('LOW');
    expect(r.missingData).toEqual(expect.arrayContaining(['market', 'contract', 'holders', 'honeypot']));
    expect(r.dataCompleteness).toBe(0);
  });

  it('treats an unverified sell simulation as elevated honeypot risk', () => {
    const r = analyze(cleanSnapshot({ honeypot: null }));
    expect(r.factors.find((f) => f.id === 'honeypot_unverified')).toBeDefined();
    expect(r.honeypotRisk).toBe('MEDIUM');
  });

  it('uses history: liquidity pulls, tax hikes and contract changes', () => {
    const prev = cleanSnapshot();
    const cur = cleanSnapshot({
      market: market({ liquidityUsd: 40_000 }),
      contract: cleanContract({ sellTaxPct: 12, codeHash: 'hash-2' }),
    });
    cur.liquidity = { ...cur.liquidity!, totalLiquidityUsd: 40_000 };
    const r = analyze(cur, prev);
    const ids = r.factors.map((f) => f.id);
    expect(ids).toEqual(expect.arrayContaining(['liquidity_drop', 'tax_changed', 'code_changed']));
    expect(r.liquidityRisk).toBe('CRITICAL');
  });

  it('marks already-rugged tokens as critical', () => {
    expect(analyze(cleanSnapshot({ reportedRugged: true })).isLikelyScam).toBe(true);
  });

  it('lets an LLM review escalate but never lower risk', () => {
    const base = detector.analyze(cleanSnapshot(), { now: NOW });
    const escalated = detector.analyze(cleanSnapshot(), {
      now: NOW,
      llmReview: { model: 'm', escalate: true, concerns: ['c'], summary: 's', error: null },
    });
    const benign = detector.analyze(cleanSnapshot(), {
      now: NOW,
      llmReview: { model: 'm', escalate: false, concerns: [], summary: 's', error: null },
    });
    expect(escalated.rugScore).toBeGreaterThan(base.rugScore);
    expect(benign.rugScore).toBe(base.rugScore);
  });
});

describe('score combination', () => {
  it('noisy-OR compounds independent flags without exceeding 100', () => {
    expect(combineNoisyOr([])).toBe(0);
    expect(combineNoisyOr([50, 50])).toBe(75);
    expect(combineNoisyOr([100, 10])).toBe(100);
  });

  it('p-norm is dominated by the worst category and not inflated by many small ones', () => {
    const small = {
      honeypot: 10,
      liquidity: 10,
      contract: 10,
      concentration: 10,
      developer: 10,
      market: 10,
      data: 10,
    };
    expect(combineCategories(small)).toBeLessThan(20);
    expect(combineCategories({ ...small, honeypot: 100 })).toBe(100);
    const two = combineCategories({ ...small, liquidity: 60, contract: 60 });
    expect(two).toBeGreaterThan(60);
  });

  it('maxLevel picks the most severe', () => {
    expect(maxLevel('LOW', 'HIGH', 'MEDIUM')).toBe('HIGH');
  });
});
