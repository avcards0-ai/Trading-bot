import type { Alert, AlertSeverity } from '@memeguard/shared';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { clsx } from 'clsx';
import { AlertOctagon, AlertTriangle, Check, Info } from 'lucide-react';
import { useState } from 'react';
import { Link } from 'react-router-dom';
import { tokenHref } from '../components/tables';
import { Button, Card, Empty, ErrorBox, Spinner } from '../components/ui';
import { api } from '../lib/api';
import { dateTime, timeAgo } from '../lib/format';

const SEVERITY: Record<AlertSeverity, { Icon: typeof Info; cls: string; label: string }> = {
  info: { Icon: Info, cls: 'text-series-1', label: 'Info' },
  warning: { Icon: AlertTriangle, cls: 'text-warning', label: 'Warning' },
  critical: { Icon: AlertOctagon, cls: 'text-critical', label: 'Critical' },
};

const TYPES = [
  'LIQUIDITY_REMOVAL',
  'LIQUIDITY_CRASH',
  'MASSIVE_TRANSFER',
  'DEVELOPER_SELLING',
  'DEVELOPER_ACTIVITY',
  'EXTREME_PRICE_DROP',
  'TAX_CHANGE',
  'CONTRACT_CHANGE',
  'ABNORMAL_VOLUME',
  'RUG_RISK_ESCALATION',
  'NEW_HIGH_RISK_TOKEN',
  'TRADING_OPPORTUNITY',
  'POSITION_OPENED',
  'POSITION_CLOSED',
  'STOP_LOSS',
  'TAKE_PROFIT',
  'DAILY_LOSS_LIMIT',
  'MAX_DRAWDOWN',
  'SYSTEM_ERROR',
];

export function AlertList({ items, onAck }: { items: Alert[]; onAck?: (a: Alert) => void }) {
  if (items.length === 0) return <Empty>No alerts.</Empty>;
  return (
    <ul className="divide-y divide-border/60">
      {items.map((a) => {
        const s = SEVERITY[a.severity];
        return (
          <li key={a.id} className={clsx('flex gap-3 px-4 py-3', a.acknowledged && 'opacity-60')}>
            <s.Icon size={16} className={clsx('mt-0.5 shrink-0', s.cls)} aria-label={s.label} />
            <div className="min-w-0 flex-1">
              <div className="flex flex-wrap items-center gap-x-2 text-sm">
                <span className="font-medium text-ink">{a.title}</span>
                {a.address && (
                  <Link
                    to={tokenHref({ chain: a.chain ?? 'solana', address: a.address })}
                    className="text-series-1 hover:underline"
                  >
                    {a.symbol ?? a.address.slice(0, 8)}
                  </Link>
                )}
                <span className="font-mono text-[10px] text-muted">{a.type}</span>
              </div>
              <p className="mt-0.5 text-sm text-ink-2">{a.message}</p>
              <div className="mt-0.5 text-xs text-muted" title={dateTime(a.createdAt)}>
                {s.label} · {timeAgo(a.createdAt)}
                {a.deliveredTo.length > 0 && ` · sent to ${a.deliveredTo.join(', ')}`}
              </div>
            </div>
            {onAck && !a.acknowledged && (
              <button
                type="button"
                onClick={() => onAck(a)}
                className="self-start rounded-md border border-border px-2 py-1 text-xs text-ink-2 hover:bg-surface-2"
                title="Acknowledge"
              >
                <Check size={13} aria-label="Acknowledge" />
              </button>
            )}
          </li>
        );
      })}
    </ul>
  );
}

export function AlertsPage() {
  const qc = useQueryClient();
  const [severity, setSeverity] = useState<string>('');
  const [type, setType] = useState<string>('');
  const [unackOnly, setUnackOnly] = useState(false);
  const [page, setPage] = useState(0);
  const q = useQuery({
    queryKey: ['alerts', severity, type, unackOnly, page],
    queryFn: () =>
      api.alerts({
        limit: 50,
        offset: page * 50,
        severity: severity || undefined,
        type: type || undefined,
        unacknowledged: unackOnly || undefined,
      }),
    refetchInterval: 30_000,
  });
  const ack = useMutation({
    mutationFn: (id: number) => api.ackAlert(id),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['alerts'] }),
  });
  const ackAll = useMutation({
    mutationFn: api.ackAll,
    onSuccess: () => qc.invalidateQueries({ queryKey: ['alerts'] }),
  });

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end gap-3">
        <h1 className="mr-auto text-lg font-semibold">Alert center</h1>
        <label className="text-xs text-muted">
          Severity
          <select
            value={severity}
            onChange={(e) => {
              setSeverity(e.target.value);
              setPage(0);
            }}
            className="ml-2 rounded-md border border-border bg-surface-2 px-2 py-1 text-sm text-ink"
          >
            <option value="">All</option>
            <option value="critical">Critical</option>
            <option value="warning">Warning</option>
            <option value="info">Info</option>
          </select>
        </label>
        <label className="text-xs text-muted">
          Type
          <select
            value={type}
            onChange={(e) => {
              setType(e.target.value);
              setPage(0);
            }}
            className="ml-2 rounded-md border border-border bg-surface-2 px-2 py-1 text-sm text-ink"
          >
            <option value="">All</option>
            {TYPES.map((t) => (
              <option key={t} value={t}>
                {t.replace(/_/g, ' ').toLowerCase()}
              </option>
            ))}
          </select>
        </label>
        <label className="flex items-center gap-2 text-xs text-muted">
          <input type="checkbox" checked={unackOnly} onChange={(e) => setUnackOnly(e.target.checked)} />{' '}
          Unacknowledged only
        </label>
        <Button onClick={() => ackAll.mutate()} disabled={ackAll.isPending}>
          Acknowledge all
        </Button>
      </div>
      {(ack.error || ackAll.error) && <ErrorBox error={ack.error ?? ackAll.error} />}
      <Card
        padded={false}
        title={q.data ? `${q.data.total} alerts · ${q.data.unacknowledged} unacknowledged` : 'Alerts'}
      >
        {q.isLoading ? (
          <Spinner />
        ) : q.error ? (
          <div className="p-4">
            <ErrorBox error={q.error} />
          </div>
        ) : (
          <AlertList items={q.data?.items ?? []} onAck={(a) => ack.mutate(a.id)} />
        )}
      </Card>
      <div className="flex justify-end gap-2">
        <Button disabled={page === 0} onClick={() => setPage((p) => p - 1)}>
          Previous
        </Button>
        <Button disabled={!q.data || (page + 1) * 50 >= q.data.total} onClick={() => setPage((p) => p + 1)}>
          Next
        </Button>
      </div>
    </div>
  );
}
