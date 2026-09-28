export const clamp = (v: number, min: number, max: number): number => Math.min(max, Math.max(min, v));

export const round = (v: number, digits = 2): number => {
  const f = 10 ** digits;
  return Math.round(v * f) / f;
};

export const isNum = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v);

export const toNum = (v: unknown): number | null => {
  if (typeof v === 'number') return Number.isFinite(v) ? v : null;
  if (typeof v === 'string' && v.trim() !== '') {
    const n = Number(v);
    return Number.isFinite(n) ? n : null;
  }
  return null;
};

export const mean = (xs: readonly number[]): number | null =>
  xs.length === 0 ? null : xs.reduce((a, b) => a + b, 0) / xs.length;

export const stdev = (xs: readonly number[]): number | null => {
  if (xs.length < 2) return null;
  const m = mean(xs) as number;
  const variance = xs.reduce((acc, x) => acc + (x - m) ** 2, 0) / (xs.length - 1);
  return Math.sqrt(variance);
};

export const sum = (xs: readonly number[]): number => xs.reduce((a, b) => a + b, 0);

export const pctChange = (from: number | null, to: number | null): number | null => {
  if (!isNum(from) || !isNum(to) || from === 0) return null;
  return ((to - from) / Math.abs(from)) * 100;
};

/** Linear interpolation of `v` from [lo, hi] into [0, 1], clamped. */
export const scale01 = (v: number, lo: number, hi: number): number => {
  if (hi === lo) return v >= hi ? 1 : 0;
  return clamp((v - lo) / (hi - lo), 0, 1);
};

/** Seeded PRNG (mulberry32) so paper fills and backtests are reproducible. */
export function createRng(seed: string | number | null | undefined): () => number {
  if (seed === null || seed === undefined || seed === '') return Math.random;
  let h = typeof seed === 'number' ? seed >>> 0 : hashString(seed);
  return () => {
    h = (h + 0x6d2b79f5) >>> 0;
    let t = h;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function hashString(s: string): number {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}
