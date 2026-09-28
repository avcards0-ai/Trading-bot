export class ProviderError extends Error {
  constructor(
    public readonly provider: string,
    message: string,
    public readonly status: number | null = null,
    public readonly retryable = false,
  ) {
    super(`[${provider}] ${message}`);
    this.name = 'ProviderError';
  }
}

export class RateLimitedError extends ProviderError {
  constructor(
    provider: string,
    public readonly retryAfterMs: number | null,
  ) {
    super(provider, `rate limited${retryAfterMs ? ` (retry after ${retryAfterMs}ms)` : ''}`, 429, true);
    this.name = 'RateLimitedError';
  }
}

export class CircuitOpenError extends ProviderError {
  constructor(provider: string, until: Date) {
    super(provider, `circuit open until ${until.toISOString()} after repeated failures`, null, false);
    this.name = 'CircuitOpenError';
  }
}

export class ProviderResponseError extends ProviderError {
  constructor(provider: string, message: string) {
    super(provider, `unexpected response: ${message}`, null, false);
    this.name = 'ProviderResponseError';
  }
}

export class NotConfiguredError extends ProviderError {
  constructor(provider: string, what: string) {
    super(provider, `not configured: ${what}`, null, false);
    this.name = 'NotConfiguredError';
  }
}

export class TimeoutError extends Error {
  constructor(what: string, ms: number) {
    super(`${what} timed out after ${ms}ms`);
    this.name = 'TimeoutError';
  }
}

export function errorMessage(err: unknown): string {
  if (err instanceof Error) return err.message;
  if (typeof err === 'string') return err;
  try {
    return JSON.stringify(err);
  } catch {
    return String(err);
  }
}
