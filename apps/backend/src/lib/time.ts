export type Clock = () => Date;

export const systemClock: Clock = () => new Date();

export const minutesBetween = (from: Date | string, to: Date | string): number =>
  (new Date(to).getTime() - new Date(from).getTime()) / 60_000;

/** UTC calendar day, e.g. "2026-09-28". */
export const utcDay = (d: Date): string => d.toISOString().slice(0, 10);

export const toIso = (d: Date | string | null | undefined): string | null =>
  d === null || d === undefined ? null : new Date(d).toISOString();

export const parseDate = (v: unknown): Date | null => {
  if (v === null || v === undefined || v === '') return null;
  const d = typeof v === 'number' ? new Date(v) : new Date(String(v));
  return Number.isNaN(d.getTime()) ? null : d;
};
