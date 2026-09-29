import { describe, expect, it } from 'vitest';
import { z } from 'zod';
import { CircuitOpenError, ProviderError, ProviderResponseError } from '../../src/lib/errors';
import { HttpClient, parseRateLimitReset, parseRetryAfter, type FetchLike } from '../../src/lib/http';
import { TokenBucket } from '../../src/lib/rateLimiter';

const respond = (status: number, body: unknown, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json', ...headers } });

function client(fetchImpl: FetchLike, extra: Partial<ConstructorParameters<typeof HttpClient>[0]> = {}) {
  return new HttpClient({
    name: 'test',
    baseUrl: 'https://api.test',
    ratePerMinute: 6000,
    burst: 100,
    baseDelayMs: 1,
    maxDelayMs: 5,
    fetchImpl,
    ...extra,
  });
}

describe('HttpClient', () => {
  it('retries transient 5xx failures and then succeeds', async () => {
    let n = 0;
    const c = client(async () => (++n < 3 ? respond(502, {}) : respond(200, { ok: true })));
    await expect(c.get('/x')).resolves.toEqual({ ok: true });
    expect(n).toBe(3);
    expect(c.health().failures).toBe(0);
  });

  it('honours 429 Retry-After and retries', async () => {
    let n = 0;
    const c = client(async () => (++n === 1 ? respond(429, {}, { 'retry-after': '0' }) : respond(200, [1])));
    await expect(c.get('/x')).resolves.toEqual([1]);
    expect(c.health().rateLimited).toBe(1);
  });

  it('does not retry client errors', async () => {
    let n = 0;
    const c = client(async () => {
      n += 1;
      return respond(400, { error: 'bad' });
    });
    await expect(c.get('/x')).rejects.toBeInstanceOf(ProviderError);
    expect(n).toBe(1);
  });

  it('validates responses against a schema without tripping the circuit breaker', async () => {
    const c = client(async () => respond(200, { price: 'nope' }), { circuitThreshold: 1 });
    await expect(c.get('/x', { schema: z.object({ price: z.number() }) })).rejects.toBeInstanceOf(
      ProviderResponseError,
    );
    expect(c.health().circuitOpen).toBe(false);
  });

  it('opens the circuit after repeated failures and fails fast', async () => {
    let n = 0;
    const c = client(
      async () => {
        n += 1;
        return respond(503, {});
      },
      { retries: 0, circuitThreshold: 2, circuitCooldownMs: 60_000 },
    );
    await expect(c.get('/a')).rejects.toBeInstanceOf(ProviderError);
    await expect(c.get('/a')).rejects.toBeInstanceOf(ProviderError);
    await expect(c.get('/a')).rejects.toBeInstanceOf(CircuitOpenError);
    expect(n).toBe(2);
    expect(c.health().circuitOpen).toBe(true);
  });

  it('times out slow requests', async () => {
    const c = client(
      (_u, init) =>
        new Promise((_r, reject) => {
          init?.signal?.addEventListener('abort', () => reject(new Error('aborted')));
        }),
      { timeoutMs: 20, retries: 0 },
    );
    await expect(c.get('/slow')).rejects.toThrow(/timeout/);
  });

  it('keeps API keys out of error messages', async () => {
    const c = client(async () => respond(500, {}), { retries: 0 });
    await expect(c.get('/x', { query: { apikey: 'TOPSECRET' } })).rejects.toSatisfy(
      (e: Error) => !e.message.includes('TOPSECRET'),
    );
  });

  it('does not count an expected "answer" error against provider health', async () => {
    const c = client(async () => respond(400, { errorCode: 'COULD_NOT_FIND_ANY_ROUTE' }));
    await expect(
      c.get('/quote', { isAnswer: (e) => e.status === 400 && /NO_ROUTE|ANY_ROUTE/.test(e.message) }),
    ).rejects.toBeInstanceOf(ProviderError);
    expect(c.health().failures).toBe(0);
    await expect(c.get('/quote')).rejects.toBeInstanceOf(ProviderError);
    expect(c.health().failures).toBe(1);
  });

  it('waits for an x-rate-limit-reset time on 429 (X API style)', async () => {
    let n = 0;
    const reset = String(Math.floor(Date.now() / 1000));
    const c = client(async () =>
      ++n === 1 ? respond(429, {}, { 'x-rate-limit-reset': reset }) : respond(200, { ok: 1 }),
    );
    await expect(c.get('/x')).resolves.toEqual({ ok: 1 });
    expect(parseRateLimitReset(String(Math.floor(Date.now() / 1000) + 60))).toBeGreaterThan(55_000);
    expect(parseRateLimitReset(String(Math.floor(Date.now() / 1000) + 3600))).toBe(15 * 60_000);
    expect(parseRateLimitReset(null)).toBeNull();
  });

  it('parses Retry-After in seconds and HTTP-date form', () => {
    expect(parseRetryAfter('2')).toBe(2000);
    expect(parseRetryAfter(null)).toBeNull();
    expect(parseRetryAfter(new Date(Date.now() + 5000).toUTCString())).toBeGreaterThan(3000);
  });
});

describe('TokenBucket', () => {
  it('allows a burst then smooths to the configured rate', async () => {
    let t = 0;
    const b = new TokenBucket(60, 2, () => t);
    expect(b.tryAcquire()).toBe(true);
    expect(b.tryAcquire()).toBe(true);
    expect(b.tryAcquire()).toBe(false);
    expect(b.msUntilAvailable()).toBe(1000);
    t = 1000;
    expect(b.tryAcquire()).toBe(true);
  });

  it('pauses after a penalty (Retry-After)', () => {
    let t = 0;
    const b = new TokenBucket(600, 5, () => t);
    b.penalize(3000);
    expect(b.msUntilAvailable()).toBe(3000);
    t = 3000;
    expect(b.tryAcquire()).toBe(true);
  });
});
