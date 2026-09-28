import { useQuery } from '@tanstack/react-query';
import { clsx } from 'clsx';
import {
  Activity,
  Bell,
  Briefcase,
  FlaskConical,
  Gauge,
  LayoutDashboard,
  ListOrdered,
  Server,
  Settings,
  ShieldAlert,
  ShieldCheck,
  X,
} from 'lucide-react';
import type { ReactNode } from 'react';
import { NavLink } from 'react-router-dom';
import { useLive } from '../hooks/useLive';
import { api } from '../lib/api';

const NAV = [
  { to: '/', label: 'Dashboard', Icon: LayoutDashboard, end: true },
  { to: '/tokens', label: 'Live feed', Icon: Activity },
  { to: '/leaderboard', label: 'Risk leaderboard', Icon: ListOrdered },
  { to: '/positions', label: 'Positions & trades', Icon: Briefcase },
  { to: '/performance', label: 'Performance', Icon: Gauge },
  { to: '/backtest', label: 'Backtesting', Icon: FlaskConical },
  { to: '/alerts', label: 'Alert center', Icon: Bell },
  { to: '/system', label: 'System status', Icon: Server },
  { to: '/settings', label: 'Configuration', Icon: Settings },
];

function ConnectionDot() {
  const { connection } = useLive();
  const label = connection === 'open' ? 'Live' : connection === 'connecting' ? 'Connecting' : 'Reconnecting';
  return (
    <span className="inline-flex items-center gap-1.5 text-xs text-ink-2" title="Real-time event stream">
      <span
        className={clsx('inline-block h-2 w-2 rounded-full', connection === 'open' ? 'bg-good' : connection === 'connecting' ? 'bg-warning' : 'bg-critical')}
        aria-hidden
      />
      {label}
    </span>
  );
}

function Toasts() {
  const { toasts, dismissToast } = useLive();
  if (toasts.length === 0) return null;
  return (
    <div className="fixed bottom-4 right-4 z-50 flex w-[22rem] max-w-[calc(100vw-2rem)] flex-col gap-2" aria-live="assertive">
      {toasts.map((t) => (
        <div key={t.id} className="rounded-lg border border-border bg-surface-2 p-3 shadow-xl">
          <div className="flex items-start gap-2">
            <ShieldAlert size={16} className={clsx('mt-0.5 shrink-0', t.severity === 'critical' ? 'text-critical' : 'text-series-1')} aria-hidden />
            <div className="min-w-0 flex-1">
              <div className="text-sm font-semibold text-ink">
                {t.title}
                {t.symbol ? ` — ${t.symbol}` : ''}
              </div>
              <p className="mt-0.5 line-clamp-3 text-xs text-ink-2">{t.message}</p>
            </div>
            <button type="button" onClick={() => dismissToast(t.id)} className="text-muted hover:text-ink" aria-label="Dismiss">
              <X size={14} />
            </button>
          </div>
        </div>
      ))}
    </div>
  );
}

export function Layout({ children }: { children: ReactNode }) {
  const status = useQuery({ queryKey: ['status'], queryFn: api.status, refetchInterval: 15_000 });
  const alerts = useQuery({ queryKey: ['alerts', 'badge'], queryFn: () => api.alerts({ limit: 1, unacknowledged: true }), refetchInterval: 30_000 });
  const s = status.data;
  const unread = alerts.data?.unacknowledged ?? 0;

  return (
    <div className="flex min-h-full flex-col lg:flex-row">
      <aside className="border-b border-border bg-surface lg:sticky lg:top-0 lg:h-screen lg:w-60 lg:shrink-0 lg:border-b-0 lg:border-r">
        <div className="flex items-center gap-2 px-4 py-4">
          <ShieldCheck size={22} className="text-series-1" aria-hidden />
          <div>
            <div className="text-sm font-semibold text-ink">MemeGuard</div>
            <div className="text-[11px] text-muted">Rug detection · risk-gated trading</div>
          </div>
        </div>
        <nav className="flex gap-1 overflow-x-auto px-2 pb-2 lg:flex-col lg:overflow-visible" aria-label="Main">
          {NAV.map(({ to, label, Icon, end }) => (
            <NavLink
              key={to}
              to={to}
              end={end}
              className={({ isActive }) =>
                clsx(
                  'flex shrink-0 items-center gap-2 rounded-md px-3 py-2 text-sm',
                  isActive ? 'bg-surface-3 text-ink' : 'text-ink-2 hover:bg-surface-2 hover:text-ink',
                )
              }
            >
              <Icon size={16} aria-hidden />
              <span className="whitespace-nowrap">{label}</span>
              {to === '/alerts' && unread > 0 && (
                <span className="tabular ml-auto rounded-full bg-critical px-1.5 text-[10px] font-semibold text-white">{unread > 99 ? '99+' : unread}</span>
              )}
            </NavLink>
          ))}
        </nav>
      </aside>

      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex flex-wrap items-center gap-3 border-b border-border bg-bg/90 px-4 py-2.5 backdrop-blur lg:px-6">
          {s && (
            <span
              className={clsx(
                'rounded-md px-2 py-0.5 text-xs font-bold tracking-wide',
                s.mode === 'live' ? 'bg-critical text-white' : 'bg-series-1/25 text-ink',
              )}
            >
              {s.mode === 'live' ? 'LIVE TRADING' : 'PAPER TRADING'}
            </span>
          )}
          {s && (
            <span className="text-xs text-ink-2">
              Engine: <span className="text-ink">{s.engineRunning ? 'running' : 'stopped'}</span> · auto-trade:{' '}
              <span className="text-ink">{s.autoTrade ? 'on' : 'off'}</span> · queue {s.queue.pending}/{s.queue.inFlight}
            </span>
          )}
          <span className="ml-auto">
            <ConnectionDot />
          </span>
        </header>
        {s?.halted && (
          <div className="flex items-center gap-2 border-b border-critical/40 bg-critical/15 px-4 py-2 text-sm text-ink lg:px-6" role="alert">
            <ShieldAlert size={16} className="text-critical" aria-hidden />
            Trading halted: {s.haltReason ?? 'risk limit reached'}. New entries are blocked; open positions are still protected.
          </div>
        )}
        {status.isError && (
          <div className="border-b border-critical/40 bg-critical/15 px-4 py-2 text-sm text-ink lg:px-6" role="alert">
            Backend unreachable — is the API running?
          </div>
        )}
        <main className="mx-auto w-full max-w-[1600px] flex-1 px-4 py-5 lg:px-6">{children}</main>
      </div>
      <Toasts />
    </div>
  );
}
