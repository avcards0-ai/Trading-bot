import { createHash, timingSafeEqual } from 'node:crypto';
import type { FastifyReply, FastifyRequest } from 'fastify';

const digest = (s: string) => createHash('sha256').update(s).digest();

/** Extracts the API key from `Authorization: Bearer <key>` or `X-API-Key: <key>`. */
export function extractApiKey(req: FastifyRequest): string | null {
  const auth = req.headers.authorization;
  if (typeof auth === 'string' && auth.toLowerCase().startsWith('bearer ')) return auth.slice(7).trim();
  const x = req.headers['x-api-key'];
  if (typeof x === 'string' && x.length > 0) return x.trim();
  return null;
}

/** Constant-time comparison (hashing first equalises lengths). */
export function keysMatch(provided: string, expected: string): boolean {
  return timingSafeEqual(digest(provided), digest(expected));
}

export function makeAuthGuards(apiKey: string | null, requireAuthForReads: boolean) {
  const check = async (req: FastifyRequest, reply: FastifyReply, kind: 'admin' | 'read') => {
    if (!apiKey) {
      if (kind === 'read') return;
      // Fail closed: no key configured means administrative actions are unavailable.
      return reply.code(503).send({
        error: 'admin_api_disabled',
        message: 'Administrative endpoints are disabled because API_KEY is not configured.',
      });
    }
    const provided = extractApiKey(req);
    if (!provided || !keysMatch(provided, apiKey)) {
      req.log.warn({ route: req.routeOptions.url, ip: req.ip }, 'unauthorized request');
      return reply.code(401).send({ error: 'unauthorized', message: 'Valid API key required.' });
    }
  };
  return {
    requireAdmin: (req: FastifyRequest, reply: FastifyReply) => check(req, reply, 'admin'),
    requireRead: async (req: FastifyRequest, reply: FastifyReply) => {
      if (requireAuthForReads) return check(req, reply, 'admin');
    },
  };
}
