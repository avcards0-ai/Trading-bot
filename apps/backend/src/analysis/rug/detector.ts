import type {
  CategoryAssessment,
  LlmReview,
  RiskCategory,
  RiskFactor,
  RiskLevel,
  RiskReport,
  TokenSnapshot,
} from '@memeguard/shared';
import {
  concentrationFactors,
  contractFactors,
  dataFactors,
  developerFactors,
  honeypotFactors,
  levelFromScore,
  liquidityFactors,
  marketFactors,
  type RiskContext,
} from './factors';

export const RUG_MODEL_VERSION = 'rug-model-1.0.0';

export const CATEGORIES: RiskCategory[] = [
  'honeypot',
  'liquidity',
  'contract',
  'concentration',
  'developer',
  'market',
  'data',
];

/**
 * How strongly a maxed-out category implies a rug. Honeypot/liquidity problems are near-certain
 * loss; market-integrity and data problems are serious but less directly fatal.
 */
export const CATEGORY_WEIGHTS: Record<RiskCategory, number> = {
  honeypot: 1.0,
  liquidity: 0.9,
  contract: 0.85,
  developer: 0.85,
  concentration: 0.75,
  market: 0.6,
  data: 0.6,
};

const CATEGORY_NAMES: Record<RiskCategory, string> = {
  honeypot: 'Honeypot',
  liquidity: 'Liquidity',
  contract: 'Contract',
  concentration: 'Wallet concentration',
  developer: 'Developer',
  market: 'Market integrity',
  data: 'Data quality',
};

const LEVEL_ORDER: RiskLevel[] = ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL'];
export const maxLevel = (...levels: RiskLevel[]): RiskLevel =>
  levels.reduce((a, b) => (LEVEL_ORDER.indexOf(b) > LEVEL_ORDER.indexOf(a) ? b : a), 'LOW' as RiskLevel);
export const levelRank = (l: RiskLevel): number => LEVEL_ORDER.indexOf(l);

/** Noisy-OR: independent red flags compound but the score never exceeds 100. */
export function combineNoisyOr(points: number[]): number {
  const survive = points.reduce((acc, p) => acc * (1 - Math.min(100, Math.max(0, p)) / 100), 1);
  return (1 - survive) * 100;
}

/**
 * Weighted p-norm (p=3) across categories: dominated by the worst category while still
 * compounding several serious ones, and not inflated by many small ones.
 */
export function combineCategories(scores: Record<RiskCategory, number>, p = 3): number {
  let acc = 0;
  for (const c of CATEGORIES) acc += (CATEGORY_WEIGHTS[c] * scores[c]) ** p;
  return Math.min(100, acc ** (1 / p));
}

const round = (v: number) => Math.round(v * 10) / 10;

function assessCategory(
  category: RiskCategory,
  factors: RiskFactor[],
  emptyNote: string,
): CategoryAssessment {
  const own = factors.filter((f) => f.category === category);
  let score = combineNoisyOr(own.map((f) => f.points));
  const critical = own.some((f) => f.critical);
  if (critical) score = Math.max(score, 90);
  const level = critical ? 'CRITICAL' : levelFromScore(score);
  const ranked = [...own].sort((a, b) => b.points - a.points);
  const explanation =
    own.length === 0
      ? `${CATEGORY_NAMES[category]} risk LOW (0/100): ${emptyNote}`
      : `${CATEGORY_NAMES[category]} risk ${level} (${Math.round(score)}/100)${critical ? ' — contains a critical finding' : ''}: ` +
        ranked.map((f) => `${f.explanation} [+${Math.round(f.points)}]`).join(' ');
  return { category, score: round(score), level, explanation, factorIds: own.map((f) => f.id) };
}

function emptyNotes(s: TokenSnapshot): Record<RiskCategory, string> {
  const liq = s.liquidity?.totalLiquidityUsd ?? s.market?.liquidityUsd;
  return {
    honeypot: `sell simulation passed (${s.honeypot?.source ?? 'n/a'}), no restrictive tax/blacklist/freeze controls detected.`,
    liquidity: `liquidity ${liq ? `$${Math.round(liq).toLocaleString('en-US')}` : 'n/a'}${
      s.liquidity?.programControlled
        ? ', held by a launchpad bonding-curve program'
        : `, LP locked/burned ${(s.liquidity?.lpLockedPercent ?? 0) + (s.liquidity?.lpBurnedPercent ?? 0)}%`
    }.`,
    contract: 'no privileged mint/freeze/upgrade/ownership controls detected.',
    concentration: 'supply is broadly distributed among non-pool wallets.',
    developer: 'no concerning deployer history or recent developer selling detected.',
    market: 'no wash-trading, abnormal-volume or crash signals.',
    data: 'all key data sources responded.',
  };
}

const KEY_DATA = ['market', 'contract', 'holders', 'liquidity', 'honeypot', 'deployer'] as const;

export interface RugDetectorOptions {
  freshWalletAgeHours: number;
}

/**
 * Deterministic, explainable rug-risk model. Every point in every score is traceable to a
 * RiskFactor with the observed value, threshold, source and a plain-language explanation.
 */
export class RugDetector {
  constructor(private readonly opts: RugDetectorOptions = { freshWalletAgeHours: 72 }) {}

  analyze(
    snapshot: TokenSnapshot,
    context: Partial<RiskContext> & { llmReview?: LlmReview | null } = {},
  ): RiskReport {
    const ctx: RiskContext = {
      now: context.now ?? new Date(),
      previous: context.previous ?? null,
      freshWalletAgeHours: context.freshWalletAgeHours ?? this.opts.freshWalletAgeHours,
    };
    const factors: RiskFactor[] = [
      ...honeypotFactors(snapshot, ctx),
      ...contractFactors(snapshot, ctx),
      ...liquidityFactors(snapshot, ctx),
      ...concentrationFactors(snapshot),
      ...developerFactors(snapshot),
      ...marketFactors(snapshot),
      ...dataFactors(snapshot, ctx),
    ];
    const llm = context.llmReview ?? null;
    if (llm?.escalate) {
      factors.push({
        id: 'llm_escalation',
        category: 'data',
        label: 'AI reviewer escalation',
        points: 60,
        severity: 'HIGH',
        critical: false,
        observed: llm.concerns.length,
        threshold: 0,
        explanation: `The LLM reviewer escalated risk: ${llm.concerns.slice(0, 3).join('; ')}`,
        sources: [llm.model],
      });
    }
    return this.buildReport(snapshot, factors, llm, ctx.now);
  }

  private buildReport(s: TokenSnapshot, factors: RiskFactor[], llm: LlmReview | null, now: Date): RiskReport {
    const notes = emptyNotes(s);
    const categories = Object.fromEntries(
      CATEGORIES.map((c) => [c, assessCategory(c, factors, notes[c])]),
    ) as Record<RiskCategory, CategoryAssessment>;
    const scores = Object.fromEntries(CATEGORIES.map((c) => [c, categories[c].score])) as Record<
      RiskCategory,
      number
    >;

    const criticalFactors = factors.filter((f) => f.critical);
    let rugScore = combineCategories(scores);
    if (criticalFactors.length > 0) rugScore = Math.max(rugScore, 90);
    rugScore = round(rugScore);

    const core = maxLevel(
      categories.honeypot.level,
      categories.liquidity.level,
      categories.contract.level,
      categories.concentration.level,
      categories.developer.level,
    );
    const overallRisk = maxLevel(levelFromScore(rugScore), core);
    const isLikelyScam =
      criticalFactors.length > 0 ||
      rugScore >= 75 ||
      categories.honeypot.level === 'CRITICAL' ||
      s.reportedRugged === true;

    const missingData = KEY_DATA.filter((k) => {
      if (k === 'honeypot') return !(s.honeypot?.simulated && s.honeypot.isHoneypot !== null);
      if (k === 'liquidity') {
        return (
          !s.liquidity ||
          (!s.liquidity.programControlled &&
            s.liquidity.lpLockedPercent === null &&
            s.liquidity.lpBurnedPercent === null)
        );
      }
      if (k === 'deployer') return !s.deployer?.address;
      return s[k] === null;
    }) as string[];
    const dataCompleteness = round((KEY_DATA.length - missingData.length) / KEY_DATA.length);

    const ranked = CATEGORIES.map((c) => ({ c, weighted: CATEGORY_WEIGHTS[c] * scores[c] })).sort(
      (a, b) => b.weighted - a.weighted,
    );
    const drivers = ranked.filter((r) => r.weighted >= 10).slice(0, 3);
    const rugExplanation =
      `RUG_SCORE ${rugScore}/100 = weighted cube-root-of-cubes of category scores (worst categories dominate): ` +
      CATEGORIES.map((c) => `${CATEGORY_NAMES[c]} ${Math.round(scores[c])}×${CATEGORY_WEIGHTS[c]}`).join(
        ', ',
      ) +
      '.' +
      (criticalFactors.length > 0
        ? ` Floor of 90 applied because of critical findings: ${criticalFactors.map((f) => f.label).join(', ')}.`
        : '') +
      (drivers.length > 0
        ? ` Main drivers: ${drivers.map((d) => CATEGORY_NAMES[d.c]).join(', ')}.`
        : ' No significant drivers.');

    const worstCore = (
      ['honeypot', 'liquidity', 'contract', 'concentration', 'developer'] as RiskCategory[]
    ).sort(
      (a, b) => levelRank(categories[b].level) - levelRank(categories[a].level) || scores[b] - scores[a],
    )[0] as RiskCategory;
    const topFactors = [...factors].sort((a, b) => b.points - a.points).slice(0, 3);
    const overallExplanation =
      `OVERALL ${overallRisk}: the higher of the rug-score level (${levelFromScore(rugScore)}) and the worst core category ` +
      `(${CATEGORY_NAMES[worstCore]} ${categories[worstCore].level}).` +
      (topFactors.length > 0
        ? ` Top factors: ${topFactors.map((f) => `${f.label} (+${Math.round(f.points)})`).join('; ')}.`
        : '') +
      (isLikelyScam ? ' Classified as a LIKELY SCAM / RUG — never trade.' : '') +
      (missingData.length > 0 ? ` Missing data (treated as risk): ${missingData.join(', ')}.` : '');

    const sources = [...new Set(s.sources.filter((x) => x.ok).map((x) => x.name))];

    return {
      chain: s.chain,
      address: s.address,
      modelVersion: RUG_MODEL_VERSION,
      generatedAt: now.toISOString(),
      rugScore,
      honeypotRisk: categories.honeypot.level,
      liquidityRisk: categories.liquidity.level,
      contractRisk: categories.contract.level,
      walletConcentrationRisk: categories.concentration.level,
      developerRisk: categories.developer.level,
      marketIntegrityRisk: categories.market.level,
      overallRisk,
      isLikelyScam,
      criticalFlags: criticalFactors.map((f) => f.label),
      categories,
      factors,
      explanations: {
        rugScore: rugExplanation,
        honeypotRisk: categories.honeypot.explanation,
        liquidityRisk: categories.liquidity.explanation,
        contractRisk: categories.contract.explanation,
        walletConcentrationRisk: `${categories.concentration.explanation}${
          categories.developer.factorIds.length > 0 ? ` Developer: ${categories.developer.explanation}` : ''
        }`,
        overallRisk: overallExplanation,
      },
      dataCompleteness,
      missingData,
      sources,
      llmReview: llm,
    };
  }
}
