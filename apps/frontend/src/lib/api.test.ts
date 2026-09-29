import { afterEach, describe, expect, it, vi } from 'vitest';
import { ApiError, BOT_DOWN_MESSAGE, UNREACHABLE_MESSAGE, api } from './api';

const respond = (body: string, status: number, contentType = 'application/json') =>
  vi.fn(async () => new Response(body, { status, headers: { 'content-type': contentType } }));

async function errorOf(p: Promise<unknown>): Promise<ApiError> {
  try {
    await p;
  } catch (err) {
    if (err instanceof ApiError) return err;
    throw err;
  }
  throw new Error('expected the request to fail');
}

describe('api errors', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('explains a network failure instead of "Failed to fetch"', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => {
        throw new TypeError('Failed to fetch');
      }),
    );
    const err = await errorOf(api.status());
    expect(err.code).toBe('unreachable');
    expect(err.message).toBe(UNREACHABLE_MESSAGE);
  });

  it('reports a bot that is down behind the dashboard proxy', async () => {
    vi.stubGlobal('fetch', respond('', 502, 'text/plain'));
    const err = await errorOf(api.status());
    expect(err.code).toBe('bot_unreachable');
    expect(err.message).toBe(BOT_DOWN_MESSAGE);
  });

  it("keeps the bot's own error messages", async () => {
    vi.stubGlobal('fetch', respond(JSON.stringify({ error: 'admin_disabled', message: 'Set API_KEY' }), 503));
    const err = await errorOf(api.status());
    expect(err.code).toBe('admin_disabled');
    expect(err.message).toBe('Set API_KEY');
  });

  it('returns parsed JSON on success', async () => {
    vi.stubGlobal('fetch', respond(JSON.stringify({ ok: true }), 200));
    await expect(api.status()).resolves.toEqual({ ok: true });
  });
});
