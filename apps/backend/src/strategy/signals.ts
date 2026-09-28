import type { TokenSnapshot } from '@memeguard/shared';
import { minutesBetween } from '../lib/time';

/** Market signals derived from a snapshot; shared by the strategy, pipeline and backtester. */
export interface MarketSignals {
  priceUsd: number | null;
  liquidityUsd: number | null;
  marketCapUsd: number | null;
  ageMinutes: number | null;
  volume5mUsd: number | null;
  volume1hUsd: number | null;
  volume24hUsd: number | null;
  priceChange5mPct: number | null;
  priceChange1hPct: number | null;
  buySellRatio5m: number | null;
  buySellRatio1h: number | null;
  /** 5-minute volume rate relative to the hourly average rate (1 = steady). */
  volumeAcceleration: number | null;
  /** 1h volume / liquidity. */
  turnover1h: number | null;
  uniqueTraders: number | null;
  buyVolumeShare: number | null;
  dataAgeSeconds: number | null;
}

const ratio = (t: { buys: number; sells: number } | null | undefined): number | null => {
  if (!t) return null;
  if (t.sells === 0) return t.buys > 0 ? t.buys : null;
  return t.buys / t.sells;
};

export function computeSignals(s: TokenSnapshot, now: Date): MarketSignals {
  const m = s.market;
  const liq = m?.liquidityUsd ?? s.liquidity?.totalLiquidityUsd ?? null;
  const v5 = m?.volumeUsd.m5 ?? null;
  const v1h = m?.volumeUsd.h1 ?? null;
  const t = s.trades;
  const tradeVol = t ? t.buyVolumeUsd + t.sellVolumeUsd : 0;
  return {
    priceUsd: m?.priceUsd ?? null,
    liquidityUsd: liq,
    marketCapUsd: m?.marketCapUsd ?? m?.fdvUsd ?? null,
    ageMinutes: m?.pairCreatedAt ? minutesBetween(m.pairCreatedAt, now) : null,
    volume5mUsd: v5,
    volume1hUsd: v1h,
    volume24hUsd: m?.volumeUsd.h24 ?? null,
    priceChange5mPct: m?.priceChangePct.m5 ?? null,
    priceChange1hPct: m?.priceChangePct.h1 ?? null,
    buySellRatio5m: ratio(m?.txns.m5),
    buySellRatio1h: ratio(m?.txns.h1),
    volumeAcceleration: v5 !== null && v1h !== null && v1h > 0 ? (v5 * 12) / v1h : null,
    turnover1h: v1h !== null && liq ? v1h / liq : null,
    uniqueTraders: t?.uniqueTraders ?? null,
    buyVolumeShare: t && tradeVol > 0 ? t.buyVolumeUsd / tradeVol : null,
    dataAgeSeconds: m ? (now.getTime() - Date.parse(m.fetchedAt)) / 1000 : null,
  };
}
