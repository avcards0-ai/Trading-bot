import type { ProviderHealth } from '@memeguard/shared';
import type { z } from 'zod';
import { retry } from './async';
import {
  CircuitOpenError,
  ProviderError,
  ProviderResponseError,
  RateLimitedError,
  errorMessage,
} from './errors';
import type { Logger } from './logger';
import { TokenBucket } from './rateLimiter';
import { sanitizeUrl } from './redact';

export type FetchLike = (input: string, init?: RequestInit) => Promise<Response>;

export interface HttpClientOptions {
  name: string;
  baseUrl: string;
  ratePerMinute: number;
  burst?: number;
  timeoutMs?: number;
  retries?: number;
  baseDelayMs?: number;
  maxDelayMs?: number;
  circuitThreshold?: number;
  circuitCooldownMs?: number;
  headers?: Record<string, string>;
  fetchImpl?: FetchLike;
  logger?: Logger;
  configured?: boolean;
}

export interface RequestOptions<T> {
  query?: Record<string, string | number | boolean | undefined | null>;
  headers?: Record<string, string>;
  schema?: z.ZodType<T>;
  /** Treat these statuses as a valid (non-error) empty response and return null. */
  nullOnStatus?: number[];
  timeoutMs?: number;
  retries?: number;
}

/**
 * JSON HTTP client used by every external adapter.
 * - token-bucket rate limiting per provider
 * - timeouts via AbortController
 * - retries with exponential backoff + jitter on network errors, 5xx and 429 (honours Retry-After)
 * - circuit breaker: after N consecutive failed calls the provider is short-circuited for a cooldown
 * - response validation with zod
 * - URLs are sanitised before they appear in errors or logs (API keys live in query strings)
 */
export class HttpClient {
  readonly name: string;
  private readonly bucket: TokenBucket;
  private readonly fetchImpl: FetchLike;
  private readonly stats = {
    requests: 0,
    failures: 0,
    rateLimited: 0,
    consecutiveFailures: 0,
    lastSuccessAt: null as Date | null,
    lastError: null as string | null,
    lastErrorAt: null as Date | null,
  };
  private circuitOpenUntil = 0;

  constructor(private readonly opts: HttpClientOptions) {
    this.name = opts.name;
    this.bucket = new TokenBucket(opts.ratePerMinute, opts.burst);
    this.fetchImpl = opts.fetchImpl ?? ((input, init) => fetch(input, init));
  }

  health(): ProviderHealth {
    return {
      name: this.name,
      configured: this.opts.configured ?? true,
      requests: this.stats.requests,
      failures: this.stats.failures,
      rateLimited: this.stats.rateLimited,
      consecutiveFailures: this.stats.consecutiveFailures,
      circuitOpen: Date.now() < this.circuitOpenUntil,
      lastSuccessAt: this.stats.lastSuccessAt?.toISOString() ?? null,
      lastError: this.stats.lastError,
      lastErrorAt: this.stats.lastErrorAt?.toISOString() ?? null,
    };
  }

  async get<T>(path: string, options: RequestOptions<T> = {}): Promise<T> {
    return this.request<T>('GET', path, undefined, options);
  }

  async post<T>(path: string, body: unknown, options: RequestOptions<T> = {}): Promise<T> {
    return this.request<T>('POST', path, body, options);
  }

  buildUrl(path: string, query?: RequestOptions<unknown>['query']): string {
    const base = this.opts.baseUrl.replace(/\/+$/, '');
    const url = new URL(path.startsWith('http') ? path : `${base}${path.startsWith('/') ? '' : '/'}${path}`);
    if (query) {
      for (const [k, v] of Object.entries(query)) {
        if (v !== undefined && v !== null) url.searchParams.set(k, String(v));
      }
    }
    return url.toString();
  }

  private async request<T>(
    method: 'GET' | 'POST',
    path: string,
    body: unknown,
    options: RequestOptions<T>,
  ): Promise<T> {
    const now = Date.now();
    if (now < this.circuitOpenUntil) {
      throw new CircuitOpenError(this.name, new Date(this.circuitOpenUntil));
    }
    const url = this.buildUrl(path, options.query);
    const safeUrl = sanitizeUrl(url);
    const timeoutMs = options.timeoutMs ?? this.opts.timeoutMs ?? 15_000;

    try {
      const result = await retry<T>(
        async () => {
          await this.bucket.acquire();
          this.stats.requests += 1;
          const controller = new AbortController();
          const timer = setTimeout(() => controller.abort(), timeoutMs);
          let res: Response;
          try {
            res = await this.fetchImpl(url, {
              method,
              signal: controller.signal,
              headers: {
                accept: 'application/json',
                'user-agent': 'memeguard/1.0 (+risk-analysis)',
                ...(body !== undefined ? { 'content-type': 'application/json' } : {}),
                ...this.opts.headers,
                ...options.headers,
              },
              body: body !== undefined ? JSON.stringify(body) : undefined,
            });
          } catch (err) {
            const aborted = controller.signal.aborted;
            throw new ProviderError(
              this.name,
              aborted
                ? `timeout after ${timeoutMs}ms (${method} ${safeUrl})`
                : `network error (${method} ${safeUrl}): ${errorMessage(err)}`,
              null,
              true,
            );
          } finally {
            clearTimeout(timer);
          }

          if (options.nullOnStatus?.includes(res.status)) {
            await res.body?.cancel().catch(() => undefined);
            return null as T;
          }
          if (res.status === 429) {
            this.stats.rateLimited += 1;
            const retryAfterMs = parseRetryAfter(res.headers.get('retry-after'));
            this.bucket.penalize(retryAfterMs ?? 2_000);
            await res.body?.cancel().catch(() => undefined);
            throw new RateLimitedError(this.name, retryAfterMs);
          }
          if (!res.ok) {
            const text = await res.text().catch(() => '');
            throw new ProviderError(
              this.name,
              `HTTP ${res.status} (${method} ${safeUrl}) ${text.slice(0, 200)}`,
              res.status,
              res.status >= 500 || res.status === 408,
            );
          }
          const raw = await res.text();
          let json: unknown;
          try {
            json = raw.length === 0 ? null : JSON.parse(raw);
          } catch {
            throw new ProviderResponseError(this.name, `invalid JSON from ${safeUrl}`);
          }
          if (options.schema) {
            const parsed = options.schema.safeParse(json);
            if (!parsed.success) {
              const issue = parsed.error.issues[0];
              throw new ProviderResponseError(
                this.name,
                `schema mismatch at ${issue?.path.join('.') || '(root)'}: ${issue?.message ?? 'invalid'}`,
              );
            }
            return parsed.data;
          }
          return json as T;
        },
        {
          retries: options.retries ?? this.opts.retries ?? 3,
          baseDelayMs: this.opts.baseDelayMs ?? 500,
          maxDelayMs: this.opts.maxDelayMs ?? 10_000,
          shouldRetry: (err) => err instanceof ProviderError && err.retryable,
          delayFor: (err) => (err instanceof RateLimitedError ? err.retryAfterMs : null),
          onRetry: (err, attempt, delayMs) =>
            this.opts.logger?.debug(
              { provider: this.name, attempt: attempt + 1, delayMs, err: errorMessage(err) },
              'retrying provider request',
            ),
        },
      );
      this.onSuccess();
      return result;
    } catch (err) {
      this.onFailure(err);
      throw err;
    }
  }

  private onSuccess(): void {
    this.stats.consecutiveFailures = 0;
    this.stats.lastSuccessAt = new Date();
  }

  private onFailure(err: unknown): void {
    this.stats.failures += 1;
    this.stats.lastError = errorMessage(err).slice(0, 300);
    this.stats.lastErrorAt = new Date();
    // Validation errors are data problems, not availability problems: don't trip the breaker.
    if (err instanceof ProviderResponseError) return;
    if (
      err instanceof ProviderError &&
      err.status !== null &&
      err.status >= 400 &&
      err.status < 500 &&
      err.status !== 429
    ) {
      return;
    }
    this.stats.consecutiveFailures += 1;
    const threshold = this.opts.circuitThreshold ?? 5;
    if (this.stats.consecutiveFailures >= threshold) {
      this.circuitOpenUntil = Date.now() + (this.opts.circuitCooldownMs ?? 60_000);
      this.opts.logger?.warn(
        { provider: this.name, until: new Date(this.circuitOpenUntil).toISOString() },
        'provider circuit opened after consecutive failures',
      );
      this.stats.consecutiveFailures = 0;
    }
  }
}

export function parseRetryAfter(value: string | null): number | null {
  if (!value) return null;
  const seconds = Number(value);
  if (Number.isFinite(seconds)) return Math.max(0, Math.round(seconds * 1000));
  const date = Date.parse(value);
  if (Number.isFinite(date)) return Math.max(0, date - Date.now());
  return null;
}

/** Registry of HTTP clients so the status endpoint can report provider health. */
export class ProviderRegistry {
  private readonly clients = new Map<string, HttpClient | { health(): ProviderHealth }>();

  register<C extends { health(): ProviderHealth; name: string }>(client: C): C {
    this.clients.set(client.name, client);
    return client;
  }

  health(): ProviderHealth[] {
    return [...this.clients.values()].map((c) => c.health());
  }
}
