import { TimeoutError } from './errors';

export const sleep = (ms: number, signal?: AbortSignal): Promise<void> =>
  new Promise((resolve, reject) => {
    if (signal?.aborted) return reject(signal.reason ?? new Error('aborted'));
    const t = setTimeout(() => {
      signal?.removeEventListener('abort', onAbort);
      resolve();
    }, ms);
    const onAbort = () => {
      clearTimeout(t);
      reject(signal?.reason ?? new Error('aborted'));
    };
    signal?.addEventListener('abort', onAbort, { once: true });
  });

export async function withTimeout<T>(promise: Promise<T>, ms: number, what: string): Promise<T> {
  let timer: NodeJS.Timeout | undefined;
  try {
    return await Promise.race([
      promise,
      new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(new TimeoutError(what, ms)), ms);
      }),
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

export interface RetryOptions {
  retries: number;
  baseDelayMs: number;
  maxDelayMs: number;
  /** Return false to stop retrying. */
  shouldRetry: (err: unknown, attempt: number) => boolean;
  /** Optional explicit delay (e.g. from Retry-After). */
  delayFor?: (err: unknown, attempt: number) => number | null;
  onRetry?: (err: unknown, attempt: number, delayMs: number) => void;
  random?: () => number;
}

/** Exponential backoff with full jitter. */
export async function retry<T>(fn: (attempt: number) => Promise<T>, opts: RetryOptions): Promise<T> {
  const random = opts.random ?? Math.random;
  let attempt = 0;
  for (;;) {
    try {
      return await fn(attempt);
    } catch (err) {
      if (attempt >= opts.retries || !opts.shouldRetry(err, attempt)) throw err;
      const explicit = opts.delayFor?.(err, attempt) ?? null;
      const cap = Math.min(opts.maxDelayMs, opts.baseDelayMs * 2 ** attempt);
      const delay = explicit !== null ? Math.min(explicit, opts.maxDelayMs * 6) : Math.round(random() * cap);
      opts.onRetry?.(err, attempt, delay);
      await sleep(delay);
      attempt += 1;
    }
  }
}

/** Minimal promise concurrency limiter. */
export function createLimiter(concurrency: number) {
  let active = 0;
  const queue: (() => void)[] = [];
  const next = () => {
    if (active >= concurrency) return;
    const run = queue.shift();
    if (run) run();
  };
  return async function limit<T>(fn: () => Promise<T>): Promise<T> {
    await new Promise<void>((resolve) => {
      queue.push(resolve);
      next();
    });
    active += 1;
    try {
      return await fn();
    } finally {
      active -= 1;
      next();
    }
  };
}

/** Run tasks with a concurrency cap and collect settled results in order. */
export async function mapSettled<T, R>(
  items: readonly T[],
  concurrency: number,
  fn: (item: T, index: number) => Promise<R>,
): Promise<PromiseSettledResult<R>[]> {
  const limit = createLimiter(concurrency);
  return Promise.allSettled(items.map((item, i) => limit(() => fn(item, i))));
}
