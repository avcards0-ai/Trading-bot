import { z } from 'zod';
import type {
  EffectiveConfig,
  RiskLimits,
  StrategyParams,
  StrategyUpdateRequest,
  TradingMode,
} from '@memeguard/shared';
import type { StrategyConfigRepository } from '../db/repositories';
import { SUPPORTED_CHAINS } from './env';

export class StrategyValidationError extends Error {
  constructor(public readonly issues: string[]) {
    super(`Invalid strategy update:\n${issues.map((i) => `  - ${i}`).join('\n')}`);
    this.name = 'StrategyValidationError';
  }
}

const limitsSchema = z
  .object({
    maxPositionPercent: z.number().positive().max(100),
    maxDailyLossPercent: z.number().positive().max(100),
    maxDrawdownPercent: z.number().positive().max(100),
    maxOpenPositions: z.number().int().min(0).max(100),
    minLiquidityUsd: z.number().min(0),
    maxRugScore: z.number().min(0).max(100),
    maxSlippagePercent: z.number().positive().max(50),
    minTokenAgeMinutes: z.number().min(0),
    maxLiquiditySharePercent: z.number().positive().max(100),
    minPositionUsd: z.number().min(0),
    requireHoneypotCheck: z.boolean(),
    maxDataAgeSeconds: z.number().min(5),
  })
  .partial()
  .strict();

const strategySchema = z
  .object({
    name: z.string().min(1).max(80),
    autoTrade: z.boolean(),
    chains: z.array(z.enum(SUPPORTED_CHAINS)).min(1),
    stopLossPercent: z.number().min(0.5).max(95),
    takeProfitPercent: z.number().min(0.5).max(10_000),
    trailingStopPercent: z.number().min(0.5).max(95).nullable(),
    maxHoldMinutes: z
      .number()
      .min(1)
      .max(60 * 24 * 30),
    riskPerTradePercent: z.number().positive().max(100),
    minStrategyScore: z.number().min(0).max(100),
    minBuySellRatio: z.number().min(0).max(100),
    minVolume1hUsd: z.number().min(0),
    maxPriceChange5mPercent: z.number().min(0).max(10_000),
    minPriceChange1hPercent: z.number().min(-100).max(10_000),
    maxTokenAgeMinutes: z.number().min(1),
    exitOnRugScoreAbove: z.number().min(0).max(100),
    exitOnLiquidityDropPercent: z.number().min(1).max(100),
  })
  .partial()
  .strict();

export const strategyUpdateSchema = z
  .object({ limits: limitsSchema.optional(), strategy: strategySchema.optional() })
  .strict();

/** Direction in which each limit becomes stricter. */
const STRICTER: Record<keyof RiskLimits, 'lower' | 'higher' | 'true'> = {
  maxPositionPercent: 'lower',
  maxDailyLossPercent: 'lower',
  maxDrawdownPercent: 'lower',
  maxOpenPositions: 'lower',
  minLiquidityUsd: 'higher',
  maxRugScore: 'lower',
  maxSlippagePercent: 'lower',
  minTokenAgeMinutes: 'higher',
  maxLiquiditySharePercent: 'lower',
  minPositionUsd: 'higher',
  requireHoneypotCheck: 'true',
  maxDataAgeSeconds: 'lower',
};

/** Returns human-readable violations where `limits` is looser than `hard`. */
export function looserThanHard(limits: Partial<RiskLimits>, hard: RiskLimits): string[] {
  const out: string[] = [];
  for (const [k, dir] of Object.entries(STRICTER) as [keyof RiskLimits, 'lower' | 'higher' | 'true'][]) {
    const v = limits[k];
    if (v === undefined) continue;
    const h = hard[k];
    if (dir === 'lower' && (v as number) > (h as number))
      out.push(`${k}=${v} is looser than hard limit ${h} (must be <=)`);
    if (dir === 'higher' && (v as number) < (h as number))
      out.push(`${k}=${v} is looser than hard limit ${h} (must be >=)`);
    if (dir === 'true' && h === true && v === false) out.push(`${k} cannot be disabled (hard limit)`);
  }
  return out;
}

/** Defensive clamp so a corrupted stored config can never loosen hard limits. */
export function clampToHard(limits: RiskLimits, hard: RiskLimits): RiskLimits {
  const out = { ...limits };
  for (const [k, dir] of Object.entries(STRICTER) as [keyof RiskLimits, 'lower' | 'higher' | 'true'][]) {
    const h = hard[k];
    const v = limits[k];
    if (dir === 'lower') (out as Record<string, unknown>)[k] = Math.min(v as number, h as number);
    else if (dir === 'higher') (out as Record<string, unknown>)[k] = Math.max(v as number, h as number);
    else (out as Record<string, unknown>)[k] = Boolean(v) || Boolean(h);
  }
  return out;
}

/**
 * Runtime strategy/limits. Environment variables define HARD limits; runtime updates
 * (POST /strategy) are versioned in the database and may only make limits stricter.
 * The trading mode can never be changed at runtime.
 */
export class StrategyStore {
  private current: EffectiveConfig;

  constructor(
    private readonly repo: StrategyConfigRepository,
    private readonly mode: TradingMode,
    private readonly hardLimits: RiskLimits,
    private readonly defaults: StrategyParams,
  ) {
    this.current = {
      mode,
      hardLimits,
      limits: { ...hardLimits },
      strategy: { ...defaults },
      version: 0,
      updatedAt: new Date(0).toISOString(),
    };
  }

  async load(): Promise<EffectiveConfig> {
    const stored = await this.repo.active();
    if (stored) {
      const strategy = this.sanitizeStrategy({ ...this.defaults, ...stored.strategy });
      this.current = {
        mode: this.mode,
        hardLimits: this.hardLimits,
        limits: clampToHard({ ...this.hardLimits, ...stored.limits }, this.hardLimits),
        strategy,
        version: stored.version,
        updatedAt: stored.createdAt.toISOString(),
      };
    }
    return this.current;
  }

  get(): EffectiveConfig {
    return this.current;
  }

  private sanitizeStrategy(s: StrategyParams): StrategyParams {
    return {
      ...s,
      // Env AUTO_TRADE / CHAINS are ceilings.
      autoTrade: s.autoTrade && this.defaults.autoTrade,
      chains: s.chains.filter((c) => this.defaults.chains.includes(c)),
    };
  }

  async update(body: unknown): Promise<EffectiveConfig> {
    const parsed = strategyUpdateSchema.safeParse(body);
    if (!parsed.success) {
      throw new StrategyValidationError(
        parsed.error.issues.map((i) => `${i.path.join('.') || '(root)'}: ${i.message}`),
      );
    }
    const req = parsed.data as StrategyUpdateRequest;
    const issues: string[] = [];
    if (req.limits) issues.push(...looserThanHard(req.limits, this.hardLimits));
    if (req.strategy?.autoTrade === true && !this.defaults.autoTrade) {
      issues.push('autoTrade cannot be enabled at runtime because AUTO_TRADE=false in the environment');
    }
    if (req.strategy?.chains) {
      const bad = req.strategy.chains.filter((c) => !this.defaults.chains.includes(c));
      if (bad.length > 0) issues.push(`chains not enabled in CHAINS env: ${bad.join(', ')}`);
    }
    const strategy = { ...this.current.strategy, ...(req.strategy ?? {}) } as StrategyParams;
    if (strategy.exitOnRugScoreAbove < 0) issues.push('exitOnRugScoreAbove must be >= 0');
    if (issues.length > 0) throw new StrategyValidationError(issues);

    const limits = { ...this.current.limits, ...(req.limits ?? {}) } as RiskLimits;
    const saved = await this.repo.save(limits, strategy);
    this.current = {
      mode: this.mode,
      hardLimits: this.hardLimits,
      limits,
      strategy,
      version: saved.version,
      updatedAt: saved.createdAt.toISOString(),
    };
    return this.current;
  }
}
