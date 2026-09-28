import type { Chain, ContractData, HolderInfo } from '@memeguard/shared';
import { emptyContract } from '../analysis/merge';
import { createRng } from '../lib/math';
import type { BacktestDataset, HistoricalBar, HistoricalEvent, HistoricalToken, SecuritySnapshot } from './types';

/**
 * SYNTHETIC scenario generator. Produces labelled token histories so the backtester, rug model
 * and risk limits can be exercised deterministically (tests, demos, stress checks).
 * Synthetic results say nothing about real-market profitability — the dataset is flagged
 * `synthetic: true` and every report built from it carries that warning.
 */

export type Scenario = 'organic' | 'pump_and_dump' | 'rug_pull' | 'stealth_rug' | 'honeypot' | 'slow_bleed';

export const DEFAULT_MIX: Record<Scenario, number> = {
  organic: 0.35,
  pump_and_dump: 0.15,
  rug_pull: 0.2,
  stealth_rug: 0.08,
  honeypot: 0.1,
  slow_bleed: 0.12,
};

export interface SyntheticOptions {
  tokens: number;
  seed: string | number;
  hours?: number;
  barMinutes?: number;
  start?: Date;
  mix?: Partial<Record<Scenario, number>>;
}

function gaussian(rng: () => number): number {
  const u = Math.max(1e-12, rng());
  const v = rng();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
}

const b58 = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
function fakeAddress(rng: () => number, chain: Chain): string {
  if (chain === 'solana') return Array.from({ length: 44 }, () => b58[Math.floor(rng() * b58.length)]).join('');
  return `0x${Array.from({ length: 40 }, () => '0123456789abcdef'[Math.floor(rng() * 16)]).join('')}`;
}

function holders(rng: () => number, top: number, top10: number): HolderInfo[] {
  const out: HolderInfo[] = [{ address: 'POOL', percent: 20, isLiquidityPool: true }];
  let rest = Math.max(0, top10 - top);
  out.push({ address: `W0-${Math.floor(rng() * 1e6)}`, percent: top });
  for (let i = 1; i < 10; i++) {
    const p = i === 9 ? rest : Math.min(rest, (rest / (10 - i)) * (0.6 + rng() * 0.8));
    rest -= p;
    out.push({ address: `W${i}-${Math.floor(rng() * 1e6)}`, percent: Math.max(0.05, Math.min(p, top)) });
  }
  return out.sort((a, b) => b.percent - a.percent);
}

function security(rng: () => number, chain: Chain, scenario: Scenario): SecuritySnapshot {
  const c: ContractData = emptyContract(['synthetic']);
  c.tokenProgram = chain === 'solana' ? 'spl-token' : 'evm';
  c.isVerified = chain === 'solana' ? null : true;
  c.ownershipRenounced = chain === 'solana' ? null : true;
  c.mintable = false;
  c.freezable = false;
  c.buyTaxPct = 0;
  c.sellTaxPct = 0;
  let lpLocked = 0;
  let lpBurned = 100;
  let top = 3 + rng() * 5;
  let top10 = 18 + rng() * 12;
  let honeypot = { isHoneypot: false, sellTaxPct: 0, sellRouteFound: true as boolean | null };
  let deployerHolds = rng() * 3;

  switch (scenario) {
    case 'pump_and_dump':
      top = 9 + rng() * 8;
      top10 = 35 + rng() * 20;
      deployerHolds = 4 + rng() * 6;
      break;
    case 'rug_pull': {
      // Visible red flags (the model should reject these).
      const flag = Math.floor(rng() * 3);
      if (flag === 0) {
        lpBurned = rng() * 20;
        lpLocked = 0;
      } else if (flag === 1) {
        if (chain === 'solana') {
          c.mintable = true;
          c.mintAuthority = 'MintAuth111111111111111111111111111111111';
        } else {
          c.mintable = true;
          c.ownershipRenounced = false;
          c.ownerAddress = '0x000000000000000000000000000000000000beef';
        }
      } else {
        deployerHolds = 18 + rng() * 15;
        top = deployerHolds;
        top10 = 55 + rng() * 20;
      }
      break;
    }
    case 'stealth_rug':
      // Looks clean at launch; the rug is not detectable from launch-time data.
      break;
    case 'honeypot':
      if (rng() < 0.5) honeypot = { isHoneypot: true, sellTaxPct: 100, sellRouteFound: false };
      else {
        c.sellTaxPct = 60 + rng() * 39;
        honeypot = { isHoneypot: false, sellTaxPct: c.sellTaxPct, sellRouteFound: true };
      }
      break;
    default:
      break;
  }
  return {
    contract: c,
    holders: { sources: ['synthetic'], holderCount: Math.floor(300 + rng() * 3000), topHolders: holders(rng, top, top10), totalSupply: 1_000_000_000 },
    liquidity: {
      sources: ['synthetic'],
      totalLiquidityUsd: null,
      lpLockedPercent: lpLocked,
      lpBurnedPercent: lpBurned,
      programControlled: false,
      creatorLpPercent: 0,
      lpHolderCount: 1,
      poolCount: 1,
    },
    honeypot: {
      source: 'synthetic',
      simulated: true,
      isHoneypot: honeypot.isHoneypot,
      buyTaxPct: 0,
      sellTaxPct: honeypot.sellTaxPct,
      transferTaxPct: 0,
      sellRouteFound: honeypot.sellRouteFound,
      reason: honeypot.isHoneypot ? 'synthetic honeypot: sell reverted' : null,
    },
    deployer: {
      sources: ['synthetic'],
      address: `DEV-${Math.floor(rng() * 1e9)}`,
      walletAgeDays: 5 + rng() * 300,
      tokensCreated: Math.floor(rng() * 3),
      knownRugs: 0,
      honeypotWithSameCreator: false,
      holdsPercent: deployerHolds,
      flaggedMalicious: false,
    },
    warnings: [],
    reportedRugged: false,
  };
}

export function generateSyntheticDataset(opts: SyntheticOptions): BacktestDataset {
  const rng = createRng(opts.seed);
  const hours = opts.hours ?? 8;
  const barMin = opts.barMinutes ?? 1;
  const nBars = Math.floor((hours * 60) / barMin);
  const start = (opts.start ?? new Date('2026-01-05T00:00:00Z')).getTime();
  const mix = { ...DEFAULT_MIX, ...(opts.mix ?? {}) };
  const scenarios = Object.entries(mix) as [Scenario, number][];
  const totalW = scenarios.reduce((a, [, w]) => a + w, 0);
  const pick = (): Scenario => {
    let x = rng() * totalW;
    for (const [s, w] of scenarios) {
      x -= w;
      if (x <= 0) return s;
    }
    return 'organic';
  };

  const tokens: HistoricalToken[] = [];
  for (let n = 0; n < opts.tokens; n++) {
    const scenario = pick();
    const chain: Chain = rng() < 0.7 ? 'solana' : 'base';
    const launch = start + Math.floor(rng() * 72 * 60) * 60_000;
    let price = 10 ** -(3 + rng() * 4);
    let liq = Math.exp(Math.log(20_000) + rng() * (Math.log(400_000) - Math.log(20_000)));
    const liq0 = liq;
    const p0 = price;
    const rugAt = scenario === 'rug_pull' || scenario === 'stealth_rug' ? 45 + Math.floor(rng() * (nBars - 90)) : -1;
    const pumpLen = 60 + Math.floor(rng() * 90);
    const bars: HistoricalBar[] = [];
    const events: HistoricalEvent[] = [];

    for (let i = 0; i < nBars; i++) {
      const t = launch + i * barMin * 60_000;
      let mu = 0;
      let sigma = 0.02;
      switch (scenario) {
        case 'organic':
          mu = 0.0006;
          sigma = 0.022;
          break;
        case 'pump_and_dump':
          mu = i < pumpLen ? 0.009 : i < pumpLen + 60 ? -0.022 : -0.002;
          sigma = 0.025;
          break;
        case 'rug_pull':
        case 'stealth_rug':
          mu = i < rugAt ? 0.003 : 0;
          sigma = i < rugAt ? 0.02 : 0.005;
          break;
        case 'honeypot':
          mu = 0.004;
          sigma = 0.012;
          break;
        case 'slow_bleed':
          mu = -0.0015;
          sigma = 0.015;
          break;
      }
      const open = price;
      let ret = mu * barMin + sigma * Math.sqrt(barMin) * gaussian(rng);
      if (i === rugAt) {
        ret = Math.log(0.02 + rng() * 0.03);
        liq *= 0.01;
        events.push({ ts: new Date(t).toISOString(), type: 'rug', description: 'liquidity removed by deployer' });
      }
      price = open * Math.exp(ret);
      if (i !== rugAt && !(rugAt >= 0 && i > rugAt)) liq = liq0 * Math.sqrt(price / p0);
      const wiggle = Math.abs(gaussian(rng)) * sigma * 0.5;
      const high = Math.max(open, price) * (1 + wiggle);
      const low = Math.min(open, price) * (1 - Math.abs(gaussian(rng)) * sigma * 0.5);
      const volume = liq * (0.002 + rng() * 0.008) * (1 + Math.abs(ret) * 25);
      const txCount = Math.max(1, Math.round(volume / (150 + rng() * 250)));
      const buyShare = scenario === 'honeypot' ? 0.97 : Math.min(0.9, Math.max(0.1, 0.5 + ret * 12 + gaussian(rng) * 0.05));
      const buys = Math.round(txCount * buyShare);
      bars.push({
        ts: new Date(t).toISOString(),
        open,
        high,
        low: Math.max(low, 1e-18),
        close: price,
        volumeUsd: volume,
        liquidityUsd: liq,
        buys,
        sells: txCount - buys,
      });
    }
    if (scenario === 'honeypot') events.push({ ts: new Date(launch).toISOString(), type: 'honeypot_enabled' });
    const rugged = scenario === 'rug_pull' || scenario === 'stealth_rug' || scenario === 'honeypot';
    tokens.push({
      chain,
      address: fakeAddress(rng, chain),
      symbol: `SYN${n}`,
      name: `Synthetic ${scenario} ${n}`,
      pairCreatedAt: new Date(launch).toISOString(),
      security: security(rng, chain, scenario),
      bars,
      events,
      outcome: { rugged, ruggedAt: rugAt >= 0 ? (bars[rugAt]?.ts ?? null) : null, scenario },
    });
  }
  return {
    name: `synthetic-${opts.tokens}-seed-${opts.seed}`,
    source: 'synthetic',
    synthetic: true,
    notes: [
      'Synthetic scenarios: organic, pump_and_dump, rug_pull (visible red flags), stealth_rug (clean-looking at launch), honeypot, slow_bleed.',
      'Generated with a seeded PRNG; results are reproducible but not representative of real markets.',
    ],
    tokens,
  };
}
