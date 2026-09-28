const compact = new Intl.NumberFormat('en-US', { notation: 'compact', maximumFractionDigits: 2 });

export function usd(v: number | null | undefined, opts: { compact?: boolean; sign?: boolean } = {}): string {
  if (v === null || v === undefined || !Number.isFinite(v)) return '—';
  const sign = opts.sign && v > 0 ? '+' : v < 0 ? '−' : '';
  const a = Math.abs(v);
  if (opts.compact && a >= 10_000) return `${sign}$${compact.format(a)}`;
  return `${sign}$${a.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

/** Meme-coin prices span 1e-12..1e4: tiny prices use the subscript zero-count form, e.g. $0.0₅123. */
export function price(v: number | null | undefined): string {
  if (v === null || v === undefined || !Number.isFinite(v)) return '—';
  if (v === 0) return '$0';
  if (v >= 1) return `$${v.toLocaleString('en-US', { maximumFractionDigits: 4 })}`;
  if (v >= 0.0001) return `$${v.toPrecision(4)}`;
  const exp = Math.floor(Math.log10(v));
  const zeros = -exp - 1;
  const digits = Math.round(v * 10 ** (-exp + 3))
    .toString()
    .replace(/0+$/, '');
  const sub = String(zeros).replace(/\d/g, (d) => '₀₁₂₃₄₅₆₇₈₉'[Number(d)] as string);
  return `$0.0${sub}${digits}`;
}

export function pct(v: number | null | undefined, opts: { sign?: boolean; digits?: number } = {}): string {
  if (v === null || v === undefined || !Number.isFinite(v)) return '—';
  const d = opts.digits ?? 1;
  const s = opts.sign && v > 0 ? '+' : v < 0 ? '−' : '';
  return `${s}${Math.abs(v).toFixed(d)}%`;
}

export function num(v: number | null | undefined, digits = 0): string {
  if (v === null || v === undefined || !Number.isFinite(v)) return '—';
  return Math.abs(v) >= 100_000
    ? compact.format(v)
    : v.toLocaleString('en-US', { maximumFractionDigits: digits });
}

export function ratio(v: number | null | undefined): string {
  if (v === null || v === undefined || !Number.isFinite(v)) return '—';
  return `${v.toFixed(2)}×`;
}

export function shortAddr(a: string | null | undefined, n = 4): string {
  if (!a) return '—';
  return a.length > 2 * n + 3 ? `${a.slice(0, n + 2)}…${a.slice(-n)}` : a;
}

export function timeAgo(iso: string | null | undefined): string {
  if (!iso) return '—';
  const s = (Date.now() - Date.parse(iso)) / 1000;
  if (s < 0) return 'just now';
  if (s < 60) return `${Math.floor(s)}s ago`;
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  if (s < 86_400) return `${Math.floor(s / 3600)}h ago`;
  return `${Math.floor(s / 86_400)}d ago`;
}

export function age(iso: string | null | undefined): string {
  if (!iso) return '—';
  const m = (Date.now() - Date.parse(iso)) / 60_000;
  if (m < 60) return `${Math.max(0, Math.floor(m))}m`;
  if (m < 1440) return `${Math.floor(m / 60)}h ${Math.floor(m % 60)}m`;
  return `${Math.floor(m / 1440)}d`;
}

export function dateTime(iso: string | null | undefined): string {
  if (!iso) return '—';
  return new Date(iso).toLocaleString('en-US', {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

export const explorerUrl = (chain: string, address: string): string => {
  switch (chain) {
    case 'solana':
      return `https://solscan.io/token/${address}`;
    case 'ethereum':
      return `https://etherscan.io/token/${address}`;
    case 'bsc':
      return `https://bscscan.com/token/${address}`;
    case 'base':
      return `https://basescan.org/token/${address}`;
    case 'arbitrum':
      return `https://arbiscan.io/token/${address}`;
    default:
      return '#';
  }
};
