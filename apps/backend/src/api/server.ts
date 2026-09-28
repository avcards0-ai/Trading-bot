import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import Fastify, { type FastifyBaseLogger, type FastifyInstance, type FastifyReply } from 'fastify';
import { z } from 'zod';
import type { Chain, PaperTradeResponse, ScanResponse, ServerEvent } from '@memeguard/shared';
import { isValidSolanaAddress } from '../adapters/solana/keys';
import type { App } from '../app';
import { runBacktest } from '../backtest/engine';
import { loadDatasetFromDatabase } from '../backtest/sources';
import { generateSyntheticDataset } from '../backtest/synthetic';
import { SUPPORTED_CHAINS, safeConfigView } from '../config/env';
import { StrategyValidationError } from '../config/strategyStore';
import { normalizeAddress, toPosition, toTrade } from '../db/repositories';
import { errorMessage } from '../lib/errors';
import { closeWithDecision } from '../trading/exitDecision';
import { makeAuthGuards } from './auth';
import { findToken, listPositions, systemStatus, tokenDetail, tokenItems } from './queries';

const chainEnum = z.enum(SUPPORTED_CHAINS);
const riskEnum = z.enum(['LOW', 'MEDIUM', 'HIGH', 'CRITICAL']);
/** Query-string boolean. (z.coerce.boolean() would turn the string "false" into true.) */
const boolQuery = z.enum(['true', 'false', '1', '0']).transform((v) => v === 'true' || v === '1');
const pageQuery = {
  limit: z.coerce.number().int().min(1).max(500).default(50),
  offset: z.coerce.number().int().min(0).default(0),
};

export function isValidAddress(chain: Chain, address: string): boolean {
  return chain === 'solana' ? isValidSolanaAddress(address) : /^0x[0-9a-fA-F]{40}$/.test(address);
}

class HttpError extends Error {
  constructor(
    public readonly statusCode: number,
    public readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

function parse<T>(schema: z.ZodType<T>, data: unknown): T {
  const r = schema.safeParse(data);
  if (!r.success) {
    throw new HttpError(
      400,
      'invalid_request',
      r.error.issues.map((i) => `${i.path.join('.') || '(root)'}: ${i.message}`).join('; '),
    );
  }
  return r.data;
}

export async function buildServer(app: App): Promise<FastifyInstance> {
  const { config } = app;
  const server = Fastify({
    loggerInstance: app.logger as unknown as FastifyBaseLogger,
    trustProxy: true,
    bodyLimit: 1_000_000,
  });
  const { requireAdmin, requireRead } = makeAuthGuards(
    config.server.apiKey,
    config.server.requireAuthForReads,
  );
  const exitDeps = {
    repos: app.repos,
    tradeService: app.tradeService,
    bus: app.bus,
    mode: config.trading.mode,
  };

  await server.register(helmet, { contentSecurityPolicy: false });
  await server.register(cors, {
    origin: config.server.corsOrigins,
    methods: ['GET', 'POST', 'OPTIONS'],
    allowedHeaders: ['content-type', 'authorization', 'x-api-key'],
  });
  await server.register(rateLimit, { global: true, max: 600, timeWindow: '1 minute' });

  server.setErrorHandler((err, req, reply) => {
    if (err instanceof HttpError)
      return reply.code(err.statusCode).send({ error: err.code, message: err.message });
    if (err instanceof StrategyValidationError)
      return reply.code(400).send({ error: 'invalid_strategy', message: err.message, issues: err.issues });
    const status = (err as { statusCode?: number }).statusCode;
    if (status && status >= 400 && status < 500)
      return reply.code(status).send({ error: 'bad_request', message: errorMessage(err) });
    req.log.error({ err: errorMessage(err) }, 'request failed');
    return reply.code(500).send({ error: 'internal_error', message: 'Internal server error' });
  });

  const adminLimit = { config: { rateLimit: { max: 60, timeWindow: '1 minute' } } };
  const read = { preHandler: requireRead };
  const admin = { preHandler: requireAdmin, ...adminLimit };

  // ---------------------------------------------------------------- health / status
  server.get('/health', async () => ({ status: 'ok', mode: config.trading.mode }));
  server.get('/status', read, async () => systemStatus(app));
  server.get('/config', read, async () => ({
    effective: app.strategyStore.get(),
    system: safeConfigView(config),
  }));

  // ---------------------------------------------------------------- tokens
  server.get('/tokens', read, async (req) => {
    const q = parse(
      z.object({
        ...pageQuery,
        sort: z
          .enum([
            'rugScore',
            'lastAnalyzedAt',
            'firstSeenAt',
            'liquidityUsd',
            'volume24hUsd',
            'marketCapUsd',
            'pairCreatedAt',
          ])
          .default('lastAnalyzedAt'),
        order: z.enum(['asc', 'desc']).default('desc'),
        chain: chainEnum.optional(),
        risk: riskEnum.optional(),
        search: z.string().max(80).optional(),
        analyzedOnly: boolQuery.optional(),
      }),
      req.query,
    );
    const { rows, total } = await app.repos.tokens.list(q);
    return { items: await tokenItems(app, rows), total, limit: q.limit, offset: q.offset };
  });

  server.get('/tokens/:address', read, async (req) => {
    const { address } = parse(z.object({ address: z.string().min(20).max(64) }), req.params);
    const { chain } = parse(z.object({ chain: chainEnum.optional() }), req.query);
    const row = await findToken(app, address, chain);
    if (!row) throw new HttpError(404, 'not_found', 'Token not found. POST /scan to analyse it.');
    return tokenDetail(app, row);
  });

  server.get('/tokens/:address/wallets', read, async (req) => {
    const { address } = parse(z.object({ address: z.string().min(20).max(64) }), req.params);
    const { chain } = parse(z.object({ chain: chainEnum.optional() }), req.query);
    const row = await findToken(app, address, chain);
    if (!row) throw new HttpError(404, 'not_found', 'Token not found.');
    const [wallets, transactions] = await Promise.all([
      app.repos.wallets.listForToken(row.id),
      app.repos.transactions.listForToken(row.id, 100),
    ]);
    const s = row.latestSnapshot;
    return {
      holders: s?.holders ?? null,
      walletAnalysis: s?.wallets ?? null,
      deployer: s?.deployer ?? null,
      developer: s?.developer ?? null,
      trades: s?.trades ?? null,
      wallets,
      transactions,
    };
  });

  server.get('/risk/:address', read, async (req) => {
    const { address } = parse(z.object({ address: z.string().min(20).max(64) }), req.params);
    const { chain } = parse(z.object({ chain: chainEnum.optional() }), req.query);
    const row = await findToken(app, address, chain);
    if (!row) throw new HttpError(404, 'not_found', 'Token not found. POST /scan to analyse it.');
    const report = await app.repos.risk.latest(row.id);
    if (!report) throw new HttpError(404, 'not_analyzed', 'Token has not been analysed yet.');
    return report;
  });

  // ---------------------------------------------------------------- trading read models
  server.get('/positions', read, async (req) => {
    const q = parse(
      z.object({
        status: z.enum(['open', 'closed', 'all']).default('all'),
        limit: z.coerce.number().int().min(1).max(500).default(100),
      }),
      req.query,
    );
    return { items: await listPositions(app, q.status, q.limit) };
  });

  server.get('/trades', read, async (req) => {
    const q = parse(z.object(pageQuery), req.query);
    const { rows, total } = await app.repos.trades.list({
      mode: config.trading.mode,
      limit: q.limit,
      offset: q.offset,
    });
    return { items: rows.map((r) => toTrade(r.trade, r.token)), total, limit: q.limit, offset: q.offset };
  });

  server.get('/performance', read, async () => app.portfolio.summary());

  server.get('/decisions', read, async (req) => {
    const q = parse(
      z.object({ ...pageQuery, action: z.enum(['BUY', 'SELL', 'HOLD', 'SKIP']).optional() }),
      req.query,
    );
    return { items: await app.repos.decisions.list(q) };
  });

  server.get('/alerts', read, async (req) => {
    const q = parse(
      z.object({
        ...pageQuery,
        severity: z.enum(['info', 'warning', 'critical']).optional(),
        type: z.string().max(40).optional(),
        unacknowledged: boolQuery.optional(),
      }),
      req.query,
    );
    const res = await app.repos.alerts.list({ ...q, type: q.type as never });
    return {
      ...res,
      unacknowledged: await app.repos.alerts.countUnacknowledged(),
      limit: q.limit,
      offset: q.offset,
    };
  });

  server.get('/logs', read, async (req) => {
    const q = parse(
      z.object({
        limit: z.coerce.number().int().min(1).max(500).default(100),
        category: z.string().max(40).optional(),
        level: z.enum(['debug', 'info', 'warn', 'error']).optional(),
      }),
      req.query,
    );
    return { items: await app.repos.events.list(q) };
  });

  server.get('/backtests', read, async () => ({ items: await app.repos.backtests.list(50) }));
  server.get('/backtests/:id', read, async (req) => {
    const { id } = parse(z.object({ id: z.coerce.number().int().positive() }), req.params);
    const r = await app.repos.backtests.get(id);
    if (!r) throw new HttpError(404, 'not_found', 'Backtest not found.');
    return r;
  });

  // ---------------------------------------------------------------- realtime (SSE)
  server.get('/events', read, async (req, reply: FastifyReply) => {
    reply.hijack();
    const res = reply.raw;
    const origin = req.headers.origin;
    res.writeHead(200, {
      'content-type': 'text/event-stream',
      'cache-control': 'no-cache, no-transform',
      connection: 'keep-alive',
      'x-accel-buffering': 'no',
      // The response is hijacked, so the CORS plugin cannot add this header for us.
      ...(origin && config.server.corsOrigins.includes(origin)
        ? { 'access-control-allow-origin': origin, vary: 'Origin' }
        : {}),
    });
    const send = (e: ServerEvent) => res.write(`event: ${e.type}\ndata: ${JSON.stringify(e.data)}\n\n`);
    res.write(`retry: 3000\n\n`);
    const unsubscribe = app.bus.subscribe(send);
    const heartbeat = setInterval(() => res.write(`: ping ${Date.now()}\n\n`), 15_000);
    req.raw.on('close', () => {
      clearInterval(heartbeat);
      unsubscribe();
    });
  });

  // ---------------------------------------------------------------- admin
  server.post('/scan', admin, async (req): Promise<ScanResponse | { queued: boolean }> => {
    const body = parse(
      z.union([
        z.object({ discover: z.literal(true) }),
        z.object({
          chain: chainEnum,
          address: z.string().min(20).max(64),
          allowTrade: z.boolean().optional(),
        }),
      ]),
      req.body,
    );
    if ('discover' in body) {
      void app.engine.runOnce('discovery');
      return { queued: true };
    }
    if (!isValidAddress(body.chain, body.address))
      throw new HttpError(400, 'invalid_address', `Not a valid ${body.chain} token address.`);
    const { row } = await app.repos.tokens.upsertDiscovered({
      chain: body.chain,
      address: normalizeAddress(body.chain, body.address),
      discoveredVia: 'manual',
    });
    const result = await app.pipeline.analyze({
      tokenId: row.id,
      trigger: 'manual',
      allowTrade: body.allowTrade === true,
      manual: true,
      forceSecurityRefresh: true,
    });
    return { decision: result.decision, risk: result.report };
  });

  server.post('/paper-trade', admin, async (req): Promise<PaperTradeResponse> => {
    if (config.trading.mode !== 'paper') {
      throw new HttpError(403, 'not_paper_mode', 'POST /paper-trade is only available in paper mode.');
    }
    const body = parse(
      z.object({
        chain: chainEnum,
        address: z.string().min(20).max(64),
        side: z.enum(['buy', 'sell']),
        amountUsd: z.number().positive().max(1_000_000).optional(),
        positionId: z.number().int().positive().optional(),
      }),
      req.body,
    );
    if (!isValidAddress(body.chain, body.address))
      throw new HttpError(400, 'invalid_address', `Not a valid ${body.chain} token address.`);
    const { row } = await app.repos.tokens.upsertDiscovered({
      chain: body.chain,
      address: normalizeAddress(body.chain, body.address),
      discoveredVia: 'manual',
    });

    if (body.side === 'buy') {
      const r = await app.pipeline.analyze({
        tokenId: row.id,
        trigger: 'manual',
        allowTrade: true,
        manual: true,
        bypassStrategy: true,
        requestedUsd: body.amountUsd ?? null,
        forceSecurityRefresh: false,
      });
      return { accepted: r.decision.executed, decision: r.decision, trade: r.trade, position: r.position };
    }

    const open = body.positionId
      ? (await app.repos.positions.get(body.positionId))?.position
      : await app.repos.positions.openForToken('paper', row.id);
    if (!open || open.status !== 'open' || open.tokenId !== row.id)
      throw new HttpError(404, 'no_open_position', 'No open paper position for this token.');
    const { decision, result } = await closeWithDecision(exitDeps, {
      positionId: open.id,
      tokenId: row.id,
      token: { chain: body.chain, address: row.address, symbol: row.symbol },
      reason: 'manual',
      reasonCode: 'MANUAL_SELL',
      reasons: ['Manual paper sell requested via API.'],
      trigger: 'manual',
      rugScore: row.rugScore,
    });
    return {
      accepted: decision.executed,
      decision,
      trade: result?.trade ?? null,
      position: result?.position ?? null,
    };
  });

  server.post('/positions/:id/close', admin, async (req) => {
    const { id } = parse(z.object({ id: z.coerce.number().int().positive() }), req.params);
    const found = await app.repos.positions.get(id);
    if (!found || found.position.status !== 'open')
      throw new HttpError(404, 'no_open_position', 'Position not found or already closed.');
    const { decision, result } = await closeWithDecision(exitDeps, {
      positionId: id,
      tokenId: found.token.id,
      token: { chain: found.token.chain as Chain, address: found.token.address, symbol: found.token.symbol },
      reason: 'manual',
      reasonCode: 'MANUAL_CLOSE',
      reasons: ['Manual close requested via API.'],
      trigger: 'manual',
      rugScore: (await app.repos.risk.latest(found.token.id))?.rugScore ?? null,
    });
    return {
      closed: decision.executed,
      decision,
      trade: result?.trade ?? null,
      position: result?.position ?? toPosition(found.position, found.token),
    };
  });

  server.post('/strategy', admin, async (req) => {
    const updated = await app.strategyStore.update(req.body);
    await app.repos.events.log('info', 'config', `strategy updated to version ${updated.version}`, {
      body: req.body as Record<string, unknown>,
    });
    return updated;
  });

  server.post('/engine/start', admin, async () => {
    await app.engine.start();
    return { engineRunning: true };
  });
  server.post('/engine/stop', admin, async () => {
    await app.engine.stop();
    return {
      engineRunning: false,
      note: 'Discovery and new entries stopped; open positions remain protected by the monitor.',
    };
  });
  server.post('/risk/resume', admin, async () => {
    await app.portfolio.resume();
    return { halted: false };
  });

  server.post('/alerts/:id/ack', admin, async (req) => {
    const { id } = parse(z.object({ id: z.coerce.number().int().positive() }), req.params);
    return { acknowledged: await app.repos.alerts.acknowledge(id) };
  });
  server.post('/alerts/ack-all', admin, async () => ({
    acknowledged: await app.repos.alerts.acknowledgeAll(),
  }));

  server.post(
    '/backtest',
    { ...admin, config: { rateLimit: { max: 6, timeWindow: '1 minute' } } },
    async (req) => {
      const body = parse(
        z.object({
          source: z.enum(['synthetic', 'database']).default('synthetic'),
          tokens: z.number().int().min(1).max(1000).default(150),
          seed: z.union([z.string(), z.number()]).default(42),
          startingBalanceUsd: z.number().positive().max(1e9).optional(),
          assumeCleanSecurity: z.boolean().default(false),
          failureRate: z.number().min(0).max(1).optional(),
          evaluateEveryMinutes: z.number().min(1).max(1440).default(5),
        }),
        req.body ?? {},
      );
      const cfg = app.strategyStore.get();
      const dataset =
        body.source === 'synthetic'
          ? generateSyntheticDataset({ tokens: body.tokens, seed: body.seed })
          : await loadDatasetFromDatabase(app.repos, { limit: body.tokens, minPoints: 10 });
      if (dataset.tokens.length === 0)
        throw new HttpError(400, 'no_data', 'No tokens with enough recorded history to backtest.');
      const result = runBacktest(dataset, {
        startingBalanceUsd: body.startingBalanceUsd ?? config.paper.startingBalanceUsd,
        limits: cfg.limits,
        strategy: cfg.strategy,
        dexFeePct: config.paper.dexFeePercent,
        failureRate: body.failureRate ?? config.paper.failureRate,
        seed: body.seed,
        catastrophicLossPct: config.trading.catastrophicLossPercent,
        evaluateEveryMinutes: body.evaluateEveryMinutes,
        exitMaxSlippagePct: config.trading.exitMaxSlippagePercent,
        assumeCleanSecurity: body.assumeCleanSecurity,
      });
      result.id = await app.repos.backtests.insert(result);
      return result;
    },
  );

  return server;
}
