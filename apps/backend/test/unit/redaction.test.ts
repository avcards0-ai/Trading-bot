import { describe, expect, it } from 'vitest';
import { signerFromSecret } from '../../src/adapters/solana/keys';
import { createLogger } from '../../src/lib/logger';
import { SecretRedactor, sanitizeUrl, scrubUrlCredentials } from '../../src/lib/redact';
import bs58 from 'bs58';

function capture(secrets: string[]) {
  const lines: string[] = [];
  const redactor = new SecretRedactor(secrets);
  const logger = createLogger({ level: 'debug', redactor, sink: (l) => lines.push(l) });
  return { lines, logger, redactor };
}

describe('secret redaction', () => {
  it('scrubs configured secret values anywhere in a log line', () => {
    const { lines, logger } = capture(['super-secret-api-key-123']);
    logger.info({ note: 'key is super-secret-api-key-123' }, 'using super-secret-api-key-123 now');
    const out = lines.join('');
    expect(out).not.toContain('super-secret-api-key-123');
    expect(out).toContain('[REDACTED]');
  });

  it('redacts sensitive keys by path even when the value is unknown', () => {
    const { lines, logger } = capture([]);
    logger.info(
      {
        privateKey: 'abcdef',
        wallet: { secretKey: 'zzz' },
        req: { headers: { authorization: 'Bearer tok' } },
      },
      'x',
    );
    const out = lines.join('');
    expect(out).not.toContain('abcdef');
    expect(out).not.toContain('Bearer tok');
    expect(out).not.toContain('"zzz"');
  });

  it('scrubs credentials embedded in URLs', () => {
    expect(scrubUrlCredentials('https://rpc.io/?api-key=SECRET&x=1')).toBe(
      'https://rpc.io/?api-key=[REDACTED]&x=1',
    );
    expect(
      scrubUrlCredentials('https://api.telegram.org/bot123456:ABCdefGHIjklMNOpqrSTUvwxYZ12345/sendMessage'),
    ).not.toContain('ABCdef');
    expect(scrubUrlCredentials('https://discord.com/api/webhooks/123/tokenpart')).toContain('[REDACTED]');
    expect(scrubUrlCredentials('postgres://user:pw123@db:5432/x')).toBe(
      'postgres://user:[REDACTED]@db:5432/x',
    );
    expect(sanitizeUrl('https://x.io/path?apikey=abc')).toBe('https://x.io/path');
  });

  it('also scrubs alternate encodings of a wallet key registered at load time', () => {
    const secret = new Uint8Array(64);
    for (let i = 0; i < 32; i++) secret[i] = i + 1;
    // Derive the matching public half so the key is valid.
    const seedOnly = bs58.encode(secret.slice(0, 32));
    const { lines, logger, redactor } = capture([]);
    const signer = signerFromSecret(seedOnly, (s) => redactor.add(s));
    logger.info(`leak attempt ${seedOnly}`);
    expect(lines.join('')).not.toContain(seedOnly);
    expect(signer.publicKey.length).toBeGreaterThan(30);
  });
});
