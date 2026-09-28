import type { Alert, AlertSeverity, AlertType, Chain } from '@memeguard/shared';
import type { AlertsRepository } from '../db/repositories';
import { toAlert } from '../db/repositories';
import { errorMessage } from '../lib/errors';
import type { EventBus } from '../lib/events';
import type { Logger } from '../lib/logger';
import type { Notifier } from './notifiers';

export interface AlertInput {
  type: AlertType;
  severity: AlertSeverity;
  title: string;
  message: string;
  tokenId?: number | null;
  token?: { chain: Chain | string; address: string; symbol: string | null } | null;
  data?: Record<string, unknown>;
  dedupeKey?: string;
  cooldownSeconds?: number;
}

const SEVERITY_RANK: Record<AlertSeverity, number> = { info: 0, warning: 1, critical: 2 };

/** Trade-lifecycle and limit events are always pushed (subject to rate caps), whatever their severity. */
const ALWAYS_NOTIFY = new Set<AlertType>([
  'POSITION_OPENED',
  'POSITION_CLOSED',
  'STOP_LOSS',
  'TAKE_PROFIT',
  'TRADING_OPPORTUNITY',
  'DAILY_LOSS_LIMIT',
  'MAX_DRAWDOWN',
]);

export interface AlertServiceOptions {
  minSeverity: AlertSeverity;
  cooldownSeconds: number;
  maxPerTypePerHour: number;
}

/**
 * Persists alerts, streams them to the dashboard, and pushes them to Telegram/Discord.
 *  - dedupe: identical alerts (same type+token, or explicit key) within the cooldown are dropped
 *  - rate caps: at most N external notifications per alert type per hour (the rest stay in-app)
 *  - delivery is asynchronous and never blocks or fails the trading engine
 */
export class AlertService {
  private readonly recent = new Map<string, number>();
  private readonly hourly = new Map<AlertType, number[]>();
  private readonly stats = new Map<string, { sent: number; failed: number }>();
  private pending = new Set<Promise<void>>();

  constructor(
    private readonly repo: AlertsRepository,
    private readonly bus: EventBus,
    private readonly notifiers: Notifier[],
    private readonly opts: AlertServiceOptions,
    private readonly logger: Logger,
    private readonly now: () => Date = () => new Date(),
  ) {
    for (const n of notifiers) this.stats.set(n.name, { sent: 0, failed: 0 });
  }

  notifierStatus(configured: { name: string; configured: boolean }[]) {
    return configured.map((c) => ({ ...c, ...(this.stats.get(c.name) ?? { sent: 0, failed: 0 }) }));
  }

  async raise(input: AlertInput): Promise<Alert | null> {
    const now = this.now();
    const key = input.dedupeKey ?? `${input.type}:${input.tokenId ?? input.token?.address ?? 'global'}`;
    const cooldownMs = (input.cooldownSeconds ?? this.opts.cooldownSeconds) * 1000;
    const last = this.recent.get(key);
    if (last !== undefined && now.getTime() - last < cooldownMs) return null;
    if (cooldownMs > 0 && (await this.repo.existsSince(key, new Date(now.getTime() - cooldownMs)))) {
      this.recent.set(key, now.getTime());
      return null;
    }
    this.recent.set(key, now.getTime());
    this.prune(now.getTime());

    const row = await this.repo.insert({
      tokenId: input.tokenId ?? null,
      type: input.type,
      severity: input.severity,
      title: input.title,
      message: input.message,
      data: input.data ?? {},
      dedupeKey: key,
      createdAt: now,
    });
    const alert = toAlert(
      row,
      input.token
        ? { chain: String(input.token.chain), address: input.token.address, symbol: input.token.symbol }
        : null,
    );
    this.bus.publish({ type: 'alert', data: alert });
    this.logger.info(
      { alert: { type: alert.type, severity: alert.severity, title: alert.title, token: alert.address } },
      'alert raised',
    );

    if (this.shouldNotify(alert, now)) {
      const p = this.deliver(alert).finally(() => this.pending.delete(p));
      this.pending.add(p);
    }
    return alert;
  }

  private shouldNotify(alert: Alert, now: Date): boolean {
    if (this.notifiers.length === 0) return false;
    const eligible =
      ALWAYS_NOTIFY.has(alert.type) || SEVERITY_RANK[alert.severity] >= SEVERITY_RANK[this.opts.minSeverity];
    if (!eligible) return false;
    const hourAgo = now.getTime() - 3_600_000;
    const times = (this.hourly.get(alert.type) ?? []).filter((t) => t > hourAgo);
    if (times.length >= this.opts.maxPerTypePerHour) {
      this.logger.debug({ type: alert.type }, 'notification suppressed by hourly cap');
      this.hourly.set(alert.type, times);
      return false;
    }
    times.push(now.getTime());
    this.hourly.set(alert.type, times);
    return true;
  }

  private async deliver(alert: Alert): Promise<void> {
    const delivered: string[] = [];
    await Promise.all(
      this.notifiers.map(async (n) => {
        const s = this.stats.get(n.name) as { sent: number; failed: number };
        try {
          await n.send(alert);
          s.sent += 1;
          delivered.push(n.name);
        } catch (err) {
          s.failed += 1;
          this.logger.warn({ notifier: n.name, err: errorMessage(err) }, 'alert delivery failed');
        }
      }),
    );
    if (delivered.length > 0) await this.repo.setDelivered(alert.id, delivered).catch(() => undefined);
  }

  /** Wait for in-flight notifications (graceful shutdown / tests). */
  async flush(): Promise<void> {
    await Promise.allSettled([...this.pending]);
  }

  private prune(nowMs: number): void {
    if (this.recent.size < 5000) return;
    for (const [k, t] of this.recent) if (nowMs - t > 86_400_000) this.recent.delete(k);
  }
}
