import type { LoopStatus } from '@memeguard/shared';
import { errorMessage } from '../lib/errors';
import type { Logger } from '../lib/logger';

/** A non-overlapping periodic task with status reporting. */
export class Loop {
  private timer: NodeJS.Timeout | null = null;
  private running = false;
  private busy = false;
  private readonly status: Omit<LoopStatus, 'name' | 'running' | 'intervalMs'> = {
    lastRunAt: null,
    lastDurationMs: null,
    lastError: null,
    runs: 0,
  };

  constructor(
    readonly name: string,
    private readonly intervalMs: number,
    private readonly fn: () => Promise<void>,
    private readonly logger: Logger,
  ) {}

  start(runImmediately = true): void {
    if (this.running) return;
    this.running = true;
    if (runImmediately) void this.tick();
    this.schedule();
  }

  stop(): void {
    this.running = false;
    if (this.timer) clearTimeout(this.timer);
    this.timer = null;
  }

  private schedule(): void {
    if (!this.running) return;
    this.timer = setTimeout(async () => {
      await this.tick();
      this.schedule();
    }, this.intervalMs);
    this.timer.unref?.();
  }

  /** Runs one iteration now (skipped if the previous one is still running). */
  async tick(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    const start = Date.now();
    try {
      await this.fn();
      this.status.lastError = null;
    } catch (err) {
      this.status.lastError = errorMessage(err).slice(0, 300);
      this.logger.error({ loop: this.name, err: this.status.lastError }, 'loop iteration failed');
    } finally {
      this.status.runs += 1;
      this.status.lastRunAt = new Date().toISOString();
      this.status.lastDurationMs = Date.now() - start;
      this.busy = false;
    }
  }

  /** Resolves once no iteration is running (or after the timeout). */
  async idle(timeoutMs: number): Promise<void> {
    const until = Date.now() + timeoutMs;
    while (this.busy && Date.now() < until) await new Promise((r) => setTimeout(r, 25));
  }

  snapshot(): LoopStatus {
    return { name: this.name, running: this.running, intervalMs: this.intervalMs, ...this.status };
  }
}
