import { errorMessage } from '../lib/errors';
import type { Logger } from '../lib/logger';

export interface QueueItem<T> {
  key: number;
  priority: number;
  payload: T;
  enqueuedAt: number;
}

/**
 * Bounded, de-duplicating priority queue with a concurrency limit.
 * Higher priority first, FIFO within a priority. When full, the lowest-priority oldest item is
 * dropped (and reported) rather than blocking discovery.
 */
export class WorkQueue<T> {
  private items: QueueItem<T>[] = [];
  private readonly active = new Set<number>();
  private stopped = false;

  constructor(
    private readonly worker: (item: QueueItem<T>) => Promise<void>,
    private readonly opts: {
      concurrency: number;
      maxSize: number;
      logger: Logger;
      onDrop?: (item: QueueItem<T>) => void;
    },
  ) {}

  get pending(): number {
    return this.items.length;
  }

  get inFlight(): number {
    return this.active.size;
  }

  has(key: number): boolean {
    return this.active.has(key) || this.items.some((i) => i.key === key);
  }

  keys(): number[] {
    return [...this.active, ...this.items.map((i) => i.key)];
  }

  enqueue(key: number, payload: T, priority = 0): boolean {
    if (this.stopped) return false;
    if (this.active.has(key)) return false;
    const existing = this.items.find((i) => i.key === key);
    if (existing) {
      if (priority > existing.priority) {
        existing.priority = priority;
        existing.payload = payload;
        this.sort();
      }
      return false;
    }
    if (this.items.length >= this.opts.maxSize) {
      const victim = this.items[this.items.length - 1] as QueueItem<T>;
      if (victim.priority > priority) return false;
      this.items.pop();
      this.opts.onDrop?.(victim);
    }
    this.items.push({ key, priority, payload, enqueuedAt: Date.now() });
    this.sort();
    this.pump();
    return true;
  }

  private sort(): void {
    this.items.sort((a, b) => b.priority - a.priority || a.enqueuedAt - b.enqueuedAt);
  }

  private pump(): void {
    while (!this.stopped && this.active.size < this.opts.concurrency && this.items.length > 0) {
      const item = this.items.shift() as QueueItem<T>;
      this.active.add(item.key);
      void this.worker(item)
        .catch((err) =>
          this.opts.logger.error({ key: item.key, err: errorMessage(err) }, 'queue worker failed'),
        )
        .finally(() => {
          this.active.delete(item.key);
          this.pump();
        });
    }
  }

  stop(): void {
    this.stopped = true;
    this.items = [];
  }

  resume(): void {
    this.stopped = false;
    this.pump();
  }

  /** Resolves when no work is pending or in flight (tests / graceful shutdown). */
  async drain(timeoutMs = 30_000): Promise<void> {
    const until = Date.now() + timeoutMs;
    while ((this.items.length > 0 || this.active.size > 0) && Date.now() < until) {
      await new Promise((r) => setTimeout(r, 25));
    }
  }
}
