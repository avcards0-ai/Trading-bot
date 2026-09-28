import type { Chain } from '@memeguard/shared';
import { createProviders, type Providers } from './adapters';
import { signerFromFile, signerFromSecret } from './adapters/solana/keys';
import type { WalletProfile } from './adapters/types';
import { AlertService } from './alerts/alertService';
import { DiscordNotifier, TelegramNotifier, type Notifier } from './alerts/notifiers';
import { SnapshotCollector, type WalletCache } from './analysis/collector';
import { LlmReviewer } from './analysis/llmReviewer';
import { RugDetector } from './analysis/rug/detector';
import { collectSecrets, safeConfigView, type AppConfig } from './config/env';
import { StrategyStore } from './config/strategyStore';
import { createDatabase, type DatabaseHandle } from './db/client';
import { createRepositories, type Repositories } from './db/repositories';
import { TradingEngine } from './engine/engine';
import { DecisionPipeline } from './engine/pipeline';
import { LiveSolanaExecutor } from './execution/liveSolanaExecutor';
import { PaperExecutor } from './execution/paperExecutor';
import type { TradeExecutor } from './execution/types';
import { EventBus } from './lib/events';
import { HttpClient, type FetchLike } from './lib/http';
import { createLogger, type Logger } from './lib/logger';
import { SecretRedactor } from './lib/redact';
import { RiskManager } from './risk/riskManager';
import type { WebSocketFactory } from './sniper/listener';
import { SniperService } from './sniper/sniperService';
import { Portfolio } from './trading/portfolio';
import { TradeService } from './trading/tradeService';

export interface App {
  config: AppConfig;
  logger: Logger;
  redactor: SecretRedactor;
  db: DatabaseHandle;
  repos: Repositories;
  providers: Providers;
  bus: EventBus;
  alerts: AlertService;
  notifierConfig: { name: string; configured: boolean }[];
  strategyStore: StrategyStore;
  executor: TradeExecutor;
  portfolio: Portfolio;
  tradeService: TradeService;
  pipeline: DecisionPipeline;
  engine: TradingEngine;
  sniper: SniperService;
  llm: LlmReviewer | null;
  startedAt: Date;
  close(): Promise<void>;
}

export interface AppOverrides {
  logger?: Logger;
  db?: DatabaseHandle;
  providers?: Providers;
  executor?: TradeExecutor;
  notifiers?: Notifier[];
  fetchImpl?: FetchLike;
  llm?: LlmReviewer | null;
  wsFactory?: WebSocketFactory;
}

/** Persistent wallet-profile cache (wallet age and funder never change). */
function dbWalletCache(repos: Repositories): WalletCache {
  return {
    async get(chain: Chain, addresses: string[]) {
      const rows = await repos.wallets.getMany(chain, addresses);
      const out = new Map<string, WalletProfile>();
      for (const [addr, row] of rows) {
        if (row.metadata?.profiled !== true) continue;
        out.set(addr, {
          address: addr,
          createdAt: row.walletCreatedAt,
          ageIsLowerBound: row.ageIsLowerBound,
          fundedBy: row.fundedBy,
        });
      }
      return out;
    },
    async put(chain: Chain, profiles: WalletProfile[]) {
      for (const p of profiles) {
        await repos.wallets.upsert({
          chain,
          address: p.address,
          walletCreatedAt: p.createdAt,
          ageIsLowerBound: p.ageIsLowerBound,
          fundedBy: p.fundedBy,
          metadata: { profiled: true },
        });
      }
    },
  };
}

export async function createApp(config: AppConfig, o: AppOverrides = {}): Promise<App> {
  const redactor = new SecretRedactor(collectSecrets(config));
  const logger =
    o.logger ??
    createLogger({ level: config.log.level, file: config.log.file, pretty: config.log.pretty, redactor });
  logger.info({ config: safeConfigView(config) }, 'starting MemeGuard');

  const db = o.db ?? (await createDatabase(config.database.url, logger));
  if (config.database.autoMigrate) {
    await db.migrate(config.database.migrationsDir);
    logger.info('database migrations applied');
  }
  const repos = createRepositories(db.db);
  const providers =
    o.providers ??
    createProviders({ config, logger, registerSecret: (s) => redactor.add(s), fetchImpl: o.fetchImpl });
  const bus = new EventBus();

  const notifierConfig = [
    {
      name: 'telegram',
      configured: config.alerts.telegramBotToken !== null && config.alerts.telegramChatId !== null,
    },
    { name: 'discord', configured: config.alerts.discordWebhookUrl !== null },
  ];
  let notifiers = o.notifiers;
  if (!notifiers) {
    notifiers = [];
    if (config.alerts.telegramBotToken && config.alerts.telegramChatId) {
      notifiers.push(
        new TelegramNotifier(
          new HttpClient({
            name: 'telegram',
            baseUrl: 'https://api.telegram.org',
            ratePerMinute: 20,
            burst: 3,
            logger,
            fetchImpl: o.fetchImpl,
          }),
          config.alerts.telegramBotToken,
          config.alerts.telegramChatId,
        ),
      );
    }
    if (config.alerts.discordWebhookUrl) {
      notifiers.push(
        new DiscordNotifier(
          new HttpClient({
            name: 'discord',
            baseUrl: config.alerts.discordWebhookUrl,
            ratePerMinute: 25,
            burst: 3,
            logger,
            fetchImpl: o.fetchImpl,
          }),
        ),
      );
    }
  }
  const alerts = new AlertService(repos.alerts, bus, notifiers, config.alerts, logger);

  const strategyStore = new StrategyStore(
    repos.strategy,
    config.trading.mode,
    config.hardLimits,
    config.defaultStrategy,
  );
  await strategyStore.load();

  let executor: TradeExecutor;
  if (o.executor) {
    executor = o.executor;
  } else if (config.trading.mode === 'live') {
    if (!config.trading.liveArmed) throw new Error('live mode requested but not armed');
    if (!providers.solanaRpc) throw new Error('live mode requires RPC_URL');
    const signer = config.wallet.keypairPath
      ? signerFromFile(config.wallet.keypairPath, (s) => redactor.add(s))
      : signerFromSecret(config.wallet.privateKey as string, (s) => redactor.add(s));
    executor = new LiveSolanaExecutor({
      rpc: providers.solanaRpc,
      jupiter: providers.jupiter,
      signer,
      logger,
    });
    logger.warn({ wallet: signer.publicKey }, 'LIVE TRADING ARMED — real funds will be used');
  } else {
    executor = new PaperExecutor({
      dexFeePct: config.paper.dexFeePercent,
      failureRate: config.paper.failureRate,
      seed: config.paper.randomSeed,
    });
  }

  const portfolio = new Portfolio({
    repos,
    mode: config.trading.mode,
    startingBalanceUsd: config.paper.startingBalanceUsd,
    executor,
    dexFeePct: config.paper.dexFeePercent,
    bus,
    alerts,
    logger,
  });
  await portfolio.init();

  const collector = new SnapshotCollector({
    providers,
    logger,
    walletCache: dbWalletCache(repos),
    timeoutMs: config.engine.sourceTimeoutMs,
    walletAnalysisTopN: config.engine.walletAnalysisTopN,
    freshWalletAgeHours: config.engine.freshWalletAgeHours,
  });
  const detector = new RugDetector({ freshWalletAgeHours: config.engine.freshWalletAgeHours });
  const llm =
    o.llm !== undefined
      ? o.llm
      : config.llm.enabled && config.llm.apiKey
        ? new LlmReviewer({
            apiKey: config.llm.apiKey,
            model: config.llm.model,
            timeoutMs: config.llm.timeoutMs,
            logger,
          })
        : null;

  const tradeService = new TradeService({
    repos,
    executor,
    portfolio,
    alerts,
    bus,
    logger,
    market: providers.market,
    mode: config.trading.mode,
    exitMaxSlippagePct: config.trading.exitMaxSlippagePercent,
  });
  const pipeline = new DecisionPipeline({
    repos,
    collector,
    detector,
    llm,
    llmRequired: config.llm.required,
    strategyStore,
    riskManager: new RiskManager(),
    portfolio,
    tradeService,
    executor,
    alerts,
    bus,
    logger,
    settings: {
      mode: config.trading.mode,
      liveMaxPositionUsd: config.trading.liveMaxPositionUsd,
      dexFeePct: config.paper.dexFeePercent,
      securityRefreshMs: config.engine.securityRefreshMs,
    },
  });
  const sniper = new SniperService({
    config: config.sniper,
    mode: config.trading.mode,
    dexFeePct: config.paper.dexFeePercent,
    repos,
    rpc: providers.solanaRpc,
    jupiter: providers.jupiter,
    walletProfiler: providers.walletProfilers.find((p) => p.supports('solana')) ?? null,
    tradeService,
    portfolio,
    strategyStore,
    bus,
    logger,
    wsFactory: o.wsFactory,
  });
  const engine = new TradingEngine({
    repos,
    providers,
    pipeline,
    portfolio,
    tradeService,
    strategyStore,
    alerts,
    bus,
    logger,
    settings: config.engine,
    sniper,
  });

  return {
    config,
    logger,
    redactor,
    db,
    repos,
    providers,
    bus,
    alerts,
    notifierConfig,
    strategyStore,
    executor,
    portfolio,
    tradeService,
    pipeline,
    engine,
    sniper,
    llm,
    startedAt: new Date(),
    async close() {
      await engine.shutdown();
      logger.info('engine shut down');
      await alerts.flush();
      await db.close();
      logger.info('database closed');
    },
  };
}
