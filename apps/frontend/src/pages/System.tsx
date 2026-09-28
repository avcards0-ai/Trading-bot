import { useQuery } from '@tanstack/react-query';
import { clsx } from 'clsx';
import { CheckCircle2, CircleSlash, XCircle } from 'lucide-react';
import { useState } from 'react';
import { Card, ErrorBox, Spinner, Td, Th } from '../components/ui';
import { api } from '../lib/api';
import { dateTime, timeAgo } from '../lib/format';

function Health({ ok, configured = true }: { ok: boolean; configured?: boolean }) {
  if (!configured)
    return (
      <span className="inline-flex items-center gap-1 text-xs text-muted">
        <CircleSlash size={13} aria-hidden /> not configured
      </span>
    );
  return ok ? (
    <span className="inline-flex items-center gap-1 text-xs text-ink">
      <CheckCircle2 size={13} className="text-good" aria-hidden /> healthy
    </span>
  ) : (
    <span className="inline-flex items-center gap-1 text-xs text-ink">
      <XCircle size={13} className="text-critical" aria-hidden /> failing
    </span>
  );
}

export function SystemPage() {
  const status = useQuery({ queryKey: ['status'], queryFn: api.status, refetchInterval: 10_000 });
  const [category, setCategory] = useState('');
  const logs = useQuery({
    queryKey: ['logs', category],
    queryFn: () => api.logs({ limit: 150, category: category || undefined }),
    refetchInterval: 20_000,
  });
  if (status.isLoading) return <Spinner />;
  if (status.error) return <ErrorBox error={status.error} />;
  const s = status.data;
  if (!s) return null;

  return (
    <div className="space-y-5">
      <h1 className="text-lg font-semibold">System status</h1>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <Card title="Mode">
          <div className="text-sm">
            {s.mode === 'live' ? 'LIVE' : 'Paper'} {s.liveTradingArmed && '(armed)'}
          </div>
          <div className="text-xs text-muted">
            v{s.version} · up {Math.round(s.uptimeSeconds / 60)} min
          </div>
        </Card>
        <Card title="Engine">
          <div className="text-sm">{s.engineRunning ? 'Running' : 'Stopped (positions still protected)'}</div>
          <div className="text-xs text-muted">
            auto-trade {s.autoTrade ? 'on' : 'off'} · queue {s.queue.pending} pending, {s.queue.inFlight} in
            flight
          </div>
        </Card>
        <Card title="Database">
          <Health ok={s.database.ok} />
          <div className="text-xs text-muted">
            {s.database.driver}
            {s.database.error ? ` · ${s.database.error}` : ''}
          </div>
        </Card>
        <Card title="Risk state">
          <div className="text-sm">{s.halted ? 'HALTED' : 'Normal'}</div>
          <div className="text-xs text-muted">{s.haltReason ?? 'no active halt'}</div>
        </Card>
      </div>

      <Card title="Engine loops" padded={false}>
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead>
              <tr>
                <Th>Loop</Th>
                <Th>State</Th>
                <Th align="right">Interval</Th>
                <Th align="right">Runs</Th>
                <Th align="right">Last run</Th>
                <Th align="right">Duration</Th>
                <Th>Last error</Th>
              </tr>
            </thead>
            <tbody>
              {s.loops.map((l) => (
                <tr key={l.name}>
                  <Td>{l.name}</Td>
                  <Td>{l.running ? 'running' : 'stopped'}</Td>
                  <Td align="right">{Math.round(l.intervalMs / 1000)}s</Td>
                  <Td align="right">{l.runs}</Td>
                  <Td align="right">{timeAgo(l.lastRunAt)}</Td>
                  <Td align="right">{l.lastDurationMs ?? '—'}ms</Td>
                  <Td className="max-w-[24rem] truncate text-xs text-ink-2">{l.lastError ?? '—'}</Td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Card>

      <Card
        title="Data providers"
        subtitle="Client-side rate limits, retries and circuit breakers per provider"
        padded={false}
      >
        <div className="overflow-x-auto">
          <table className="w-full min-w-[900px]">
            <thead>
              <tr>
                <Th>Provider</Th>
                <Th>Health</Th>
                <Th align="right">Requests</Th>
                <Th align="right">Failures</Th>
                <Th align="right">Rate-limited</Th>
                <Th>Circuit</Th>
                <Th align="right">Last success</Th>
                <Th>Last error</Th>
              </tr>
            </thead>
            <tbody>
              {s.providers.map((p) => (
                <tr key={p.name}>
                  <Td>{p.name}</Td>
                  <Td>
                    <Health
                      ok={
                        p.lastError === null ||
                        (p.lastSuccessAt !== null &&
                          p.lastErrorAt !== null &&
                          p.lastSuccessAt > p.lastErrorAt)
                      }
                      configured={p.configured}
                    />
                  </Td>
                  <Td align="right">{p.requests}</Td>
                  <Td align="right">{p.failures}</Td>
                  <Td align="right">{p.rateLimited}</Td>
                  <Td>{p.circuitOpen ? 'open (paused)' : 'closed'}</Td>
                  <Td align="right">{timeAgo(p.lastSuccessAt)}</Td>
                  <Td className="max-w-[28rem] truncate text-xs text-ink-2">{p.lastError ?? '—'}</Td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Card>

      <div className="grid gap-5 lg:grid-cols-2">
        <Card title="Notifications" padded={false}>
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr>
                  <Th>Channel</Th>
                  <Th>Status</Th>
                  <Th align="right">Sent</Th>
                  <Th align="right">Failed</Th>
                </tr>
              </thead>
              <tbody>
                {s.notifiers.map((n) => (
                  <tr key={n.name}>
                    <Td>{n.name}</Td>
                    <Td>
                      <Health ok={n.failed === 0 || n.sent > 0} configured={n.configured} />
                    </Td>
                    <Td align="right">{n.sent}</Td>
                    <Td align="right">{n.failed}</Td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
        <Card title="LLM second opinion">
          <div className="text-sm">
            {s.llmReviewer.enabled ? `Enabled (${s.llmReviewer.model})` : 'Disabled'}
          </div>
          <p className="mt-1 text-xs text-muted">
            The deterministic rug model always runs. When enabled, the LLM reviews each report and may only
            escalate risk — it can never lower a score or unlock a trade.
          </p>
        </Card>
      </div>

      <Card
        title="Event log"
        subtitle="Errors, skipped opportunities and engine events"
        padded={false}
        actions={
          <select
            aria-label="Category"
            value={category}
            onChange={(e) => setCategory(e.target.value)}
            className="rounded-md border border-border bg-surface-2 px-2 py-1 text-xs text-ink"
          >
            <option value="">All categories</option>
            {['skipped', 'execution', 'pipeline', 'discovery', 'engine', 'risk', 'config'].map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        }
      >
        {logs.isLoading ? (
          <Spinner />
        ) : (
          <div className="max-h-[28rem] overflow-auto">
            <div className="overflow-x-auto">
              <table className="w-full">
                <thead>
                  <tr>
                    <Th>Time</Th>
                    <Th>Level</Th>
                    <Th>Category</Th>
                    <Th>Message</Th>
                  </tr>
                </thead>
                <tbody>
                  {logs.data?.items.map((l) => (
                    <tr key={l.id}>
                      <Td className="text-xs text-ink-2">{dateTime(l.createdAt)}</Td>
                      <Td>
                        <span
                          className={clsx(
                            'text-xs',
                            l.level === 'error' ? 'font-semibold text-ink' : 'text-ink-2',
                          )}
                        >
                          {l.level === 'error' ? '✗ ' : ''}
                          {l.level}
                        </span>
                      </Td>
                      <Td className="text-xs">{l.category}</Td>
                      <Td className="whitespace-normal text-xs text-ink-2">{l.message}</Td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}
      </Card>
    </div>
  );
}
