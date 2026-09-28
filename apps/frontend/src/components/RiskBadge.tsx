import type { DecisionAction, RiskLevel } from '@memeguard/shared';
import { clsx } from 'clsx';
import { AlertOctagon, AlertTriangle, CheckCircle2, Info, MinusCircle, ShoppingCart, TrendingDown, Eye } from 'lucide-react';

/**
 * Risk levels use the fixed status palette. Warning (MEDIUM) and serious (HIGH) are too close
 * to separate by hue alone, so every level ALWAYS renders a distinct icon + text label.
 */
export const LEVEL_STYLE: Record<RiskLevel, { color: string; bg: string; Icon: typeof Info; label: string }> = {
  LOW: { color: 'text-good', bg: 'bg-good/15', Icon: CheckCircle2, label: 'Low' },
  MEDIUM: { color: 'text-warning', bg: 'bg-warning/15', Icon: Info, label: 'Medium' },
  HIGH: { color: 'text-serious', bg: 'bg-serious/15', Icon: AlertTriangle, label: 'High' },
  CRITICAL: { color: 'text-critical', bg: 'bg-critical/20', Icon: AlertOctagon, label: 'Critical' },
};

export const LEVEL_HEX: Record<RiskLevel, string> = {
  LOW: '#0ca30c',
  MEDIUM: '#fab219',
  HIGH: '#ec835a',
  CRITICAL: '#d03b3b',
};

export const levelForScore = (score: number): RiskLevel =>
  score >= 75 ? 'CRITICAL' : score >= 50 ? 'HIGH' : score >= 25 ? 'MEDIUM' : 'LOW';

export function RiskBadge({ level, compact = false }: { level: RiskLevel | null | undefined; compact?: boolean }) {
  if (!level) return <span className="text-xs text-muted">—</span>;
  const s = LEVEL_STYLE[level];
  return (
    <span className={clsx('inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium text-ink', s.bg)} title={`${s.label} risk`}>
      <s.Icon size={12} className={s.color} aria-hidden />
      {compact ? s.label : level}
    </span>
  );
}

export function RugScore({ score }: { score: number | null | undefined }) {
  if (score === null || score === undefined) return <span className="text-xs text-muted">—</span>;
  const level = levelForScore(score);
  const s = LEVEL_STYLE[level];
  return (
    <span className="tabular inline-flex items-center gap-1.5 text-sm font-semibold text-ink" title={`Rug score ${score}/100 (${s.label})`}>
      <s.Icon size={13} className={s.color} aria-hidden />
      {Math.round(score)}
    </span>
  );
}

const ACTION_STYLE: Record<DecisionAction, { Icon: typeof Info; cls: string }> = {
  BUY: { Icon: ShoppingCart, cls: 'bg-series-1/20' },
  SELL: { Icon: TrendingDown, cls: 'bg-serious/20' },
  HOLD: { Icon: Eye, cls: 'bg-surface-3' },
  SKIP: { Icon: MinusCircle, cls: 'bg-surface-3' },
};

export function DecisionBadge({ action, label }: { action: DecisionAction | null | undefined; label?: string | null }) {
  if (!action) return <span className="text-xs text-muted">—</span>;
  const s = ACTION_STYLE[action];
  return (
    <span className={clsx('inline-flex max-w-[16rem] items-center gap-1 truncate rounded-md px-2 py-0.5 text-xs font-medium text-ink', s.cls)} title={label ?? action}>
      <s.Icon size={12} aria-hidden className="shrink-0" />
      <span className="truncate">{label ?? action}</span>
    </span>
  );
}
