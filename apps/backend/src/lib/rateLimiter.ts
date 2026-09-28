/**
 * Token-bucket rate limiter with a FIFO wait queue. `acquire()` resolves when a token is available,
 * so callers are smoothed to the configured rate instead of being rejected.
 * `penalize(ms)` pauses the bucket (used when a provider answers 429 with Retry-After).
 */
export class TokenBucket {
  private tokens: number;
  private lastRefill: number;
  private pausedUntil = 0;
  private readonly waiters: (() => void)[] = [];
  private timer: NodeJS.Timeout | null = null;

  constructor(
    private readonly ratePerMinute: number,
    private readonly burst: number = Math.max(1, Math.ceil(ratePerMinute / 10)),
    private readonly now: () => number = Date.now,
  ) {
    if (ratePerMinute <= 0) throw new Error('ratePerMinute must be > 0');
    this.tokens = this.burst;
    this.lastRefill = this.now();
  }

  private refill(): void {
    const t = this.now();
    const elapsed = t - this.lastRefill;
    if (elapsed <= 0) return;
    this.tokens = Math.min(this.burst, this.tokens + (elapsed * this.ratePerMinute) / 60_000);
    this.lastRefill = t;
  }

  /** Milliseconds until the next token is available (0 if one is available now). */
  msUntilAvailable(): number {
    this.refill();
    const pause = Math.max(0, this.pausedUntil - this.now());
    if (this.tokens >= 1) return pause;
    const needed = 1 - this.tokens;
    return Math.max(pause, Math.ceil((needed * 60_000) / this.ratePerMinute));
  }

  tryAcquire(): boolean {
    if (this.waiters.length > 0) return false;
    if (this.msUntilAvailable() > 0) return false;
    this.tokens -= 1;
    return true;
  }

  acquire(): Promise<void> {
    if (this.tryAcquire()) return Promise.resolve();
    return new Promise((resolve) => {
      this.waiters.push(resolve);
      this.schedule();
    });
  }

  penalize(ms: number): void {
    this.pausedUntil = Math.max(this.pausedUntil, this.now() + ms);
  }

  get pending(): number {
    return this.waiters.length;
  }

  private schedule(): void {
    if (this.timer || this.waiters.length === 0) return;
    const wait = Math.max(5, this.msUntilAvailable());
    this.timer = setTimeout(() => {
      this.timer = null;
      while (this.waiters.length > 0 && this.msUntilAvailable() === 0) {
        this.tokens -= 1;
        this.waiters.shift()?.();
      }
      this.schedule();
    }, wait);
    this.timer.unref?.();
  }
}
