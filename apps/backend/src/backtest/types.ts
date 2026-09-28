import { z } from 'zod';
import type { Chain, RiskLimits, RiskReport, StrategyParams, TokenSnapshot } from '@memeguard/shared';

export interface HistoricalBar {
  ts: string;
  open: number;
  high: number;
  low: number;
  close: number;
  volumeUsd: number;
  liquidityUsd?: number | null;
  buys?: number | null;
  sells?: number | null;
  /** Pre-computed rolling windows (e.g. recorded snapshots) — used instead of re-aggregating bars. */
  window?: {
    volume5m?: number | null;
    volume1h?: number | null;
    volume24h?: number | null;
    buys5m?: number | null;
    sells5m?: number | null;
    buys1h?: number | null;
    sells1h?: number | null;
    priceChange5m?: number | null;
    priceChange1h?: number | null;
  };
}

export type SecuritySnapshot = Partial<
  Pick<TokenSnapshot, 'contract' | 'holders' | 'liquidity' | 'honeypot' | 'deployer' | 'wallets' | 'developer' | 'warnings' | 'reportedRugged' | 'trades'>
>;

export interface HistoricalEvent {
  ts: string;
  type: 'rug' | 'liquidity_removed' | 'dev_sell' | 'honeypot_enabled' | 'other';
  description?: string;
}

export interface HistoricalToken {
  chain: Chain;
  address: string;
  symbol: string | null;
  name?: string | null;
  pairCreatedAt: string;
  /** Point-in-time security data (as known at launch). */
  security?: SecuritySnapshot | null;
  /** Stored point-in-time risk reports (database replay) — used instead of recomputing. */
  riskTimeline?: { ts: string; report: RiskReport }[];
  bars: HistoricalBar[];
  events?: HistoricalEvent[];
  outcome?: { rugged: boolean; ruggedAt?: string | null; scenario?: string } | null;
}

export interface BacktestDataset {
  name: string;
  source: string;
  synthetic: boolean;
  notes?: string[];
  tokens: HistoricalToken[];
}

export interface BacktestConfig {
  startingBalanceUsd: number;
  limits: RiskLimits;
  strategy: StrategyParams;
  dexFeePct: number;
  failureRate: number;
  seed: string | number;
  catastrophicLossPct: number;
  /** Re-evaluate a not-yet-bought token at most this often. */
  evaluateEveryMinutes: number;
  exitMaxSlippagePct: number;
  /**
   * When a dataset has no security data, treat tokens as clean. This DISABLES the rug filter and
   * makes results optimistic; the report says so explicitly.
   */
  assumeCleanSecurity: boolean;
}

const num = z.number().finite();
const barSchema = z.object({
  ts: z.string(),
  open: num,
  high: num,
  low: num,
  close: num,
  volumeUsd: num.min(0),
  liquidityUsd: num.nullish(),
  buys: num.nullish(),
  sells: num.nullish(),
  window: z.record(z.string(), num.nullish()).optional(),
});

export const datasetSchema = z.object({
  name: z.string().default('dataset'),
  source: z.string().default('file'),
  synthetic: z.boolean().default(false),
  notes: z.array(z.string()).optional(),
  tokens: z
    .array(
      z.object({
        chain: z.enum(['solana', 'ethereum', 'bsc', 'base', 'arbitrum']),
        address: z.string().min(1),
        symbol: z.string().nullable().default(null),
        name: z.string().nullish(),
        pairCreatedAt: z.string(),
        security: z.record(z.string(), z.unknown()).nullish(),
        riskTimeline: z.array(z.object({ ts: z.string(), report: z.record(z.string(), z.unknown()) })).optional(),
        bars: z.array(barSchema).min(1),
        events: z
          .array(
            z.object({
              ts: z.string(),
              type: z.enum(['rug', 'liquidity_removed', 'dev_sell', 'honeypot_enabled', 'other']),
              description: z.string().optional(),
            }),
          )
          .optional(),
        outcome: z.object({ rugged: z.boolean(), ruggedAt: z.string().nullish(), scenario: z.string().optional() }).nullish(),
      }),
    )
    .min(1),
});
