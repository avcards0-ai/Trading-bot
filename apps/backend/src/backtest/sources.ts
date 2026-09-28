import fs from 'node:fs';
import type { Chain, RiskReport } from '@memeguard/shared';
import type { Repositories } from '../db/repositories';
import {
  datasetSchema,
  type BacktestDataset,
  type HistoricalBar,
  type HistoricalToken,
  type SecuritySnapshot,
} from './types';

/** Load a dataset from a JSON file (schema: see backtest/types.ts and README). */
export function loadDatasetFromFile(path: string): BacktestDataset {
  const raw = JSON.parse(fs.readFileSync(path, 'utf8')) as unknown;
  const parsed = datasetSchema.safeParse(raw);
  if (!parsed.success) {
    const issue = parsed.error.issues[0];
    throw new Error(`Invalid dataset ${path}: ${issue?.path.join('.')}: ${issue?.message}`);
  }
  return {
    ...parsed.data,
    tokens: parsed.data.tokens.map((t) => ({
      ...t,
      security: (t.security as SecuritySnapshot | null | undefined) ?? null,
      riskTimeline: t.riskTimeline?.map((r) => ({ ts: r.ts, report: r.report as unknown as RiskReport })),
    })) as HistoricalToken[],
  };
}

/**
 * Replay what THIS system recorded: price/liquidity snapshots plus the point-in-time risk reports
 * produced at the time. Snapshots are irregular and carry no intrabar highs/lows, so stops are
 * only evaluated at recorded prices (the report warns about this).
 */
export async function loadDatasetFromDatabase(
  repos: Repositories,
  opts: { limit: number; minPoints: number },
): Promise<BacktestDataset> {
  const { rows } = await repos.tokens.list({
    limit: opts.limit,
    offset: 0,
    sort: 'firstSeenAt',
    order: 'desc',
    analyzedOnly: true,
  });
  const tokens: HistoricalToken[] = [];
  for (const t of rows) {
    const prices = await repos.history.rawPrices(t.id);
    if (prices.length < opts.minPoints) continue;
    const liquidity = await repos.history.rawLiquidity(t.id);
    const timeline = await repos.risk.timeline(t.id);
    let li = 0;
    let lastLiq: number | null = null;
    let prevClose: number | null = null;
    const bars: HistoricalBar[] = [];
    for (const p of prices) {
      if (p.priceUsd === null) continue;
      while (li < liquidity.length && (liquidity[li] as (typeof liquidity)[number]).ts <= p.ts) {
        lastLiq = (liquidity[li] as (typeof liquidity)[number]).liquidityUsd ?? lastLiq;
        li += 1;
      }
      const open = prevClose ?? p.priceUsd;
      bars.push({
        ts: p.ts.toISOString(),
        open,
        high: Math.max(open, p.priceUsd),
        low: Math.min(open, p.priceUsd),
        close: p.priceUsd,
        volumeUsd: 0,
        liquidityUsd: lastLiq,
        window: {
          volume5m: p.volume5mUsd,
          volume1h: p.volume1hUsd,
          volume24h: p.volume24hUsd,
          buys5m: p.buys5m,
          sells5m: p.sells5m,
          buys1h: p.buys1h,
          sells1h: p.sells1h,
          priceChange5m: p.priceChange5mPct,
          priceChange1h: p.priceChange1hPct,
        },
      });
      prevClose = p.priceUsd;
    }
    if (bars.length < opts.minPoints) continue;
    tokens.push({
      chain: t.chain as Chain,
      address: t.address,
      symbol: t.symbol,
      name: t.name,
      pairCreatedAt: (t.pairCreatedAt ?? t.firstSeenAt).toISOString(),
      security: null,
      riskTimeline: timeline,
      bars,
      events: [],
      outcome: null,
    });
  }
  return {
    name: `database-replay-${new Date().toISOString().slice(0, 10)}`,
    source: 'database',
    synthetic: false,
    notes: [
      'Replays recorded snapshots and the risk reports the live system produced at the time.',
      'Snapshots are irregular and have no intrabar highs/lows: stop losses are evaluated at recorded prices only.',
      'Survivorship: only tokens this instance discovered and recorded are included; outcomes (rugged or not) are unlabeled.',
    ],
    tokens,
  };
}
