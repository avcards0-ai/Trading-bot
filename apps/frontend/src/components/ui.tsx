import { clsx } from 'clsx';
import { AlertTriangle, Loader2, Table2, LineChart as ChartIcon } from 'lucide-react';
import { useState, type ReactNode } from 'react';

export function Card({
  title,
  subtitle,
  actions,
  children,
  className,
  padded = true,
}: {
  title?: ReactNode;
  subtitle?: ReactNode;
  actions?: ReactNode;
  children: ReactNode;
  className?: string;
  padded?: boolean;
}) {
  return (
    <section className={clsx('rounded-xl border border-border bg-surface', className)}>
      {(title || actions) && (
        <header className="flex flex-wrap items-start justify-between gap-2 border-b border-border px-4 py-3">
          <div className="min-w-0">
            {title && <h2 className="text-sm font-semibold text-ink">{title}</h2>}
            {subtitle && <p className="mt-0.5 text-xs text-muted">{subtitle}</p>}
          </div>
          {actions && <div className="flex items-center gap-2">{actions}</div>}
        </header>
      )}
      <div className={clsx(padded && 'p-4')}>{children}</div>
    </section>
  );
}

/** Chart card with a table-view toggle (the accessible alternative to every chart). */
export function ChartCard({
  title,
  subtitle,
  chart,
  table,
  actions,
}: {
  title: ReactNode;
  subtitle?: ReactNode;
  chart: ReactNode;
  table: ReactNode;
  actions?: ReactNode;
}) {
  const [asTable, setAsTable] = useState(false);
  return (
    <Card
      title={title}
      subtitle={subtitle}
      actions={
        <>
          {actions}
          <button
            type="button"
            onClick={() => setAsTable((v) => !v)}
            className="inline-flex items-center gap-1 rounded-md border border-border px-2 py-1 text-xs text-ink-2 hover:bg-surface-2"
            aria-pressed={asTable}
          >
            {asTable ? <ChartIcon size={14} aria-hidden /> : <Table2 size={14} aria-hidden />}
            {asTable ? 'Chart' : 'Table'}
          </button>
        </>
      }
    >
      {asTable ? <div className="max-h-80 overflow-auto">{table}</div> : chart}
    </Card>
  );
}

export function StatTile({
  label,
  value,
  delta,
  deltaGood,
  hint,
}: {
  label: string;
  value: ReactNode;
  delta?: ReactNode;
  /** true = delta is favourable, false = unfavourable, undefined = neutral */
  deltaGood?: boolean;
  hint?: ReactNode;
}) {
  return (
    <div className="rounded-xl border border-border bg-surface px-4 py-3">
      <div className="text-xs text-muted">{label}</div>
      <div className="tabular mt-1 text-xl font-semibold text-ink">{value}</div>
      {delta !== undefined && (
        <div
          className={clsx(
            'tabular mt-0.5 text-xs font-medium',
            deltaGood === undefined ? 'text-ink-2' : deltaGood ? 'text-good' : 'text-critical',
          )}
        >
          {delta}
        </div>
      )}
      {hint && <div className="mt-0.5 text-xs text-muted">{hint}</div>}
    </div>
  );
}

export function Button({
  children,
  onClick,
  variant = 'default',
  disabled,
  type = 'button',
  title,
}: {
  children: ReactNode;
  onClick?: () => void;
  variant?: 'default' | 'primary' | 'danger' | 'ghost';
  disabled?: boolean;
  type?: 'button' | 'submit';
  title?: string;
}) {
  return (
    <button
      type={type}
      onClick={onClick}
      disabled={disabled}
      title={title}
      className={clsx(
        'inline-flex items-center justify-center gap-1.5 rounded-md px-3 py-1.5 text-sm font-medium transition-colors disabled:cursor-not-allowed disabled:opacity-50',
        variant === 'primary' && 'bg-series-1 text-white hover:brightness-110',
        variant === 'danger' && 'bg-critical text-white hover:brightness-110',
        variant === 'default' && 'border border-border bg-surface-2 text-ink hover:bg-surface-3',
        variant === 'ghost' && 'text-ink-2 hover:bg-surface-2',
      )}
    >
      {children}
    </button>
  );
}

export function Spinner({ label = 'Loading' }: { label?: string }) {
  return (
    <div className="flex items-center gap-2 p-4 text-sm text-muted" role="status">
      <Loader2 size={16} className="animate-spin" aria-hidden /> {label}…
    </div>
  );
}

export function ErrorBox({ error }: { error: unknown }) {
  const msg = error instanceof Error ? error.message : String(error);
  return (
    <div
      className="flex items-start gap-2 rounded-lg border border-critical/40 bg-critical/10 p-3 text-sm text-ink"
      role="alert"
    >
      <AlertTriangle size={16} className="mt-0.5 shrink-0 text-critical" aria-hidden />
      <span>{msg}</span>
    </div>
  );
}

export function Empty({ children }: { children: ReactNode }) {
  return <div className="p-6 text-center text-sm text-muted">{children}</div>;
}

export function Th({
  children,
  className,
  align = 'left',
}: {
  children?: ReactNode;
  className?: string;
  align?: 'left' | 'right' | 'center';
}) {
  return (
    <th
      scope="col"
      className={clsx(
        'sticky top-0 z-10 whitespace-nowrap border-b border-border bg-surface px-3 py-2 text-xs font-medium text-muted',
        align === 'right' ? 'text-right' : align === 'center' ? 'text-center' : 'text-left',
        className,
      )}
    >
      {children}
    </th>
  );
}

export function Td({
  children,
  className,
  align = 'left',
}: {
  children?: ReactNode;
  className?: string;
  align?: 'left' | 'right' | 'center';
}) {
  return (
    <td
      className={clsx(
        'whitespace-nowrap border-b border-border/60 px-3 py-2 text-sm',
        align === 'right' ? 'tabular text-right' : align === 'center' ? 'text-center' : 'text-left',
        className,
      )}
    >
      {children}
    </td>
  );
}

export function Pill({
  children,
  tone = 'neutral',
}: {
  children: ReactNode;
  tone?: 'neutral' | 'blue' | 'good' | 'warning' | 'critical';
}) {
  return (
    <span
      className={clsx(
        'inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium text-ink',
        tone === 'neutral' && 'bg-surface-3',
        tone === 'blue' && 'bg-series-1/20',
        tone === 'good' && 'bg-good/20',
        tone === 'warning' && 'bg-warning/20',
        tone === 'critical' && 'bg-critical/25',
      )}
    >
      {children}
    </span>
  );
}

/** A signed value with an arrow glyph so direction is never conveyed by color alone. */
export function Signed({ value, children }: { value: number | null | undefined; children: ReactNode }) {
  if (value === null || value === undefined || !Number.isFinite(value))
    return <span className="text-muted">—</span>;
  return (
    <span className={clsx('tabular', value > 0 ? 'text-good' : value < 0 ? 'text-critical' : 'text-ink-2')}>
      {value > 0 ? '▲ ' : value < 0 ? '▼ ' : ''}
      {children}
    </span>
  );
}
