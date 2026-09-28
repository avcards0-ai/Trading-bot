/**
 * Value-based secret scrubbing. Every configured secret (and derived encodings registered at
 * runtime, e.g. a keypair converted to base58) is replaced with a placeholder in any string that
 * is about to be written to a log sink. This is a second line of defence behind key-path redaction.
 */
export class SecretRedactor {
  private secrets: string[] = [];

  constructor(initial: Iterable<string> = []) {
    for (const s of initial) this.add(s);
  }

  add(secret: string | null | undefined): void {
    if (!secret || secret.length < 6) return;
    const variants = new Set<string>([secret, JSON.stringify(secret).slice(1, -1), encodeURIComponent(secret)]);
    for (const v of variants) {
      if (v.length >= 6 && !this.secrets.includes(v)) this.secrets.push(v);
    }
    // Longest first so a secret containing another secret is fully replaced.
    this.secrets.sort((a, b) => b.length - a.length);
  }

  get size(): number {
    return this.secrets.length;
  }

  scrub(text: string): string {
    let out = text;
    for (const s of this.secrets) {
      if (out.includes(s)) out = out.split(s).join('[REDACTED]');
    }
    return scrubUrlCredentials(out);
  }
}

const QUERY_SECRET_RE = /([?&](?:api[-_]?key|apikey|key|token|access[-_]?token|secret|auth)=)[^&\s"']+/gi;
const TELEGRAM_PATH_RE = /(\/bot)\d{5,}:[A-Za-z0-9_-]{20,}/g;
const DISCORD_WEBHOOK_RE = /(discord(?:app)?\.com\/api\/webhooks\/\d+\/)[A-Za-z0-9_-]+/g;
const URL_PASSWORD_RE = /(\b[a-z][a-z0-9+.-]*:\/\/[^:/\s"']+:)[^@/\s"']+@/gi;

/** Removes credentials that commonly appear inside URLs even when the exact value is unknown. */
export function scrubUrlCredentials(text: string): string {
  return text
    .replace(QUERY_SECRET_RE, '$1[REDACTED]')
    .replace(TELEGRAM_PATH_RE, '$1[REDACTED]')
    .replace(DISCORD_WEBHOOK_RE, '$1[REDACTED]')
    .replace(URL_PASSWORD_RE, '$1[REDACTED]@');
}

/** Returns origin + path only, with credential-bearing path segments masked. Safe for logs/errors. */
export function sanitizeUrl(raw: string): string {
  try {
    const u = new URL(raw);
    return scrubUrlCredentials(`${u.origin}${u.pathname}`);
  } catch {
    return '[unparseable-url]';
  }
}

/** Object keys whose values are always redacted by the logger. */
export const REDACT_PATHS = [
  'privateKey',
  'secretKey',
  'seed',
  'mnemonic',
  'password',
  'apiKey',
  'token',
  'authorization',
  '*.privateKey',
  '*.secretKey',
  '*.seed',
  '*.mnemonic',
  '*.password',
  '*.apiKey',
  '*.token',
  '*.authorization',
  'req.headers.authorization',
  'req.headers["x-api-key"]',
  'headers.authorization',
  'headers["x-api-key"]',
  'config.wallet',
];
