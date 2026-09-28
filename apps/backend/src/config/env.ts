import { z } from 'zod';
import type { Chain, RiskLimits, StrategyParams, TradingMode } from '@memeguard/shared';

/** Exact phrase that must be present in LIVE_TRADING_CONFIRMATION before live trading can start. */
export const LIVE_TRADING_CONFIRMATION_PHRASE = 'I_UNDERSTAND_LIVE_TRADING_CAN_LOSE_REAL_MONEY';

export const SUPPORTED_CHAINS = ['solana', 'ethereum', 'bsc', 'base', 'arbitrum'] as const satisfies readonly Chain[];

/** Chains for which a live execution venue is implemented. */
export const LIVE_EXECUTION_CHAINS: readonly Chain[] = ['solana'];

export class ConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ConfigError';
  }
}

const bool = (def: boolean) =>
  z
    .string()
    .optional()
    .transform((v, ctx) => {
      if (v === undefined || v.trim() === '') return def;
      const s = v.trim().toLowerCase();
      if (['1', 'true', 'yes', 'on'].includes(s)) return true;
      if (['0', 'false', 'no', 'off'].includes(s)) return false;
      ctx.addIssue({ code: 'custom', message: `expected a boolean, got "${v}"` });
      return z.NEVER;
    });

const num = (def: number, opts: { min?: number; max?: number; int?: boolean } = {}) =>
  z
    .string()
    .optional()
    .transform((v, ctx) => {
      if (v === undefined || v.trim() === '') return def;
      const n = Number(v);
      if (!Number.isFinite(n)) {
        ctx.addIssue({ code: 'custom', message: `expected a number, got "${v}"` });
        return z.NEVER;
      }
      if (opts.int && !Number.isInteger(n)) {
        ctx.addIssue({ code: 'custom', message: `expected an integer, got "${v}"` });
        return z.NEVER;
      }
      if (opts.min !== undefined && n < opts.min) {
        ctx.addIssue({ code: 'custom', message: `must be >= ${opts.min}` });
        return z.NEVER;
      }
      if (opts.max !== undefined && n > opts.max) {
        ctx.addIssue({ code: 'custom', message: `must be <= ${opts.max}` });
        return z.NEVER;
      }
      return n;
    });

const optStr = z
  .string()
  .optional()
  .transform((v) => (v === undefined || v.trim() === '' ? null : v.trim()));

const optUrl = optStr.refine((v) => v === null || /^https?:\/\//.test(v) || /^wss?:\/\//.test(v), {
  message: 'must be an http(s) URL',
});

const chainList = z
  .string()
  .optional()
  .transform((v, ctx) => {
    const raw = v && v.trim() !== '' ? v : 'solana,base,ethereum,bsc';
    const items = raw
      .split(',')
      .map((s) => s.trim().toLowerCase())
      .filter(Boolean);
    for (const item of items) {
      if (!(SUPPORTED_CHAINS as readonly string[]).includes(item)) {
        ctx.addIssue({ code: 'custom', message: `unsupported chain "${item}"` });
        return z.NEVER;
      }
    }
    return [...new Set(items)] as Chain[];
  });

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']).optional().default('development'),
  LOG_LEVEL: z.enum(['trace', 'debug', 'info', 'warn', 'error', 'fatal']).optional().default('info'),
  LOG_FILE: optStr,
  LOG_PRETTY: bool(false),

  HOST: z.string().optional().default('127.0.0.1'),
  PORT: num(8080, { min: 1, max: 65535, int: true }),
  CORS_ORIGINS: z.string().optional().default('http://localhost:5173,http://127.0.0.1:5173'),
  /** Admin API key. Administrative endpoints are DISABLED when unset (fail closed). */
  API_KEY: optStr,
  REQUIRE_AUTH_FOR_READS: bool(false),

  DATABASE_URL: z.string().optional().default('pglite://./data/pglite'),
  DB_AUTO_MIGRATE: bool(true),
  MIGRATIONS_DIR: optStr,

  TRADING_MODE: z.enum(['paper', 'live']).optional().default('paper'),
  LIVE_TRADING_CONFIRMATION: optStr,
  LIVE_MAX_POSITION_USD: num(50, { min: 0 }),
  AUTO_TRADE: bool(true),
  ENGINE_AUTOSTART: bool(true),

  PAPER_STARTING_BALANCE_USD: num(10_000, { min: 1 }),
  PAPER_DEX_FEE_PERCENT: num(0.25, { min: 0, max: 10 }),
  PAPER_FAILURE_RATE: num(0.02, { min: 0, max: 1 }),
  PAPER_RANDOM_SEED: optStr,

  MAX_POSITION_PERCENT: num(2, { min: 0.01, max: 100 }),
  MAX_DAILY_LOSS: num(5, { min: 0.1, max: 100 }),
  MAX_DRAWDOWN: num(20, { min: 0.5, max: 100 }),
  MAX_OPEN_POSITIONS: num(5, { min: 0, max: 100, int: true }),
  MIN_LIQUIDITY: num(25_000, { min: 0 }),
  MAX_RUG_SCORE: num(35, { min: 0, max: 100 }),
  MAX_SLIPPAGE: num(3, { min: 0.01, max: 50 }),
  EXIT_MAX_SLIPPAGE: num(15, { min: 0.01, max: 99 }),
  MIN_TOKEN_AGE: num(30, { min: 0 }),
  MAX_LIQUIDITY_SHARE_PERCENT: num(1, { min: 0.01, max: 100 }),
  MIN_POSITION_USD: num(10, { min: 0 }),
  REQUIRE_HONEYPOT_CHECK: bool(true),
  MAX_DATA_AGE_SECONDS: num(120, { min: 5 }),
  CATASTROPHIC_LOSS_PERCENT: num(50, { min: 1, max: 100 }),

  CHAINS: chainList,
  DISCOVERY_SOURCES: z.string().optional().default('geckoterminal,dexscreener'),
  DISCOVERY_INTERVAL_SECONDS: num(60, { min: 5 }),
  MONITOR_INTERVAL_SECONDS: num(20, { min: 2 }),
  WATCHLIST_INTERVAL_SECONDS: num(180, { min: 10 }),
  WATCHLIST_BATCH_SIZE: num(10, { min: 1, int: true }),
  WATCHLIST_MAX_AGE_HOURS: num(24, { min: 1 }),
  METRICS_INTERVAL_SECONDS: num(60, { min: 5 }),
  SECURITY_REFRESH_SECONDS: num(300, { min: 30 }),
  ANALYSIS_CONCURRENCY: num(2, { min: 1, max: 16, int: true }),
  MAX_QUEUE_SIZE: num(200, { min: 1, int: true }),
  WALLET_ANALYSIS_TOP_N: num(10, { min: 0, max: 50, int: true }),
  FRESH_WALLET_AGE_HOURS: num(72, { min: 1 }),
  SOURCE_TIMEOUT_MS: num(15_000, { min: 1000 }),

  RPC_URL: optUrl,
  ETHEREUM_RPC_URL: optUrl,
  BASE_RPC_URL: optUrl,
  BSC_RPC_URL: optUrl,
  ARBITRUM_RPC_URL: optUrl,

  WALLET_PRIVATE_KEY: optStr,
  WALLET_KEYPAIR_PATH: optStr,

  GOPLUS_APP_KEY: optStr,
  GOPLUS_APP_SECRET: optStr,
  ETHERSCAN_API_KEY: optStr,
  HONEYPOT_IS_API_KEY: optStr,
  RUGCHECK_API_KEY: optStr,
  JUPITER_API_URL: z.string().optional().default('https://lite-api.jup.ag'),
  JUPITER_API_KEY: optStr,

  DEXSCREENER_RPM: num(240, { min: 1 }),
  GECKOTERMINAL_RPM: num(25, { min: 1 }),
  GOPLUS_RPM: num(25, { min: 1 }),
  RUGCHECK_RPM: num(30, { min: 1 }),
  HONEYPOT_IS_RPM: num(30, { min: 1 }),
  ETHERSCAN_RPM: num(240, { min: 1 }),
  SOLANA_RPC_RPM: num(300, { min: 1 }),
  EVM_RPC_RPM: num(300, { min: 1 }),
  JUPITER_RPM: num(50, { min: 1 }),

  TELEGRAM_BOT_TOKEN: optStr,
  TELEGRAM_CHAT_ID: optStr,
  DISCORD_WEBHOOK_URL: optUrl,
  ALERT_MIN_SEVERITY: z.enum(['info', 'warning', 'critical']).optional().default('warning'),
  ALERT_COOLDOWN_SECONDS: num(900, { min: 0 }),
  ALERT_MAX_PER_TYPE_PER_HOUR: num(30, { min: 1, int: true }),

  ANTHROPIC_API_KEY: optStr,
  LLM_REVIEW_ENABLED: bool(false),
  LLM_REVIEW_MODEL: z.string().optional().default('claude-opus-5'),
  LLM_REVIEW_REQUIRED: bool(false),
  LLM_REVIEW_TIMEOUT_MS: num(30_000, { min: 1000 }),

  STRATEGY_STOP_LOSS_PERCENT: num(15, { min: 0.5, max: 95 }),
  STRATEGY_TAKE_PROFIT_PERCENT: num(40, { min: 0.5, max: 10_000 }),
  STRATEGY_TRAILING_STOP_PERCENT: num(0, { min: 0, max: 95 }),
  STRATEGY_MAX_HOLD_MINUTES: num(240, { min: 1 }),
  STRATEGY_RISK_PER_TRADE_PERCENT: num(0.5, { min: 0.01, max: 100 }),
  STRATEGY_MIN_SCORE: num(60, { min: 0, max: 100 }),
  STRATEGY_MIN_BUY_SELL_RATIO: num(1.2, { min: 0 }),
  STRATEGY_MIN_VOLUME_1H_USD: num(20_000, { min: 0 }),
  STRATEGY_MAX_PRICE_CHANGE_5M_PERCENT: num(25, { min: 0 }),
  STRATEGY_MIN_PRICE_CHANGE_1H_PERCENT: num(0),
  STRATEGY_MAX_TOKEN_AGE_MINUTES: num(1440, { min: 1 }),
  STRATEGY_EXIT_RUG_SCORE: num(50, { min: 0, max: 100 }),
  STRATEGY_EXIT_LIQUIDITY_DROP_PERCENT: num(30, { min: 1, max: 100 }),
});

export type RawEnv = z.infer<typeof envSchema>;

export interface AppConfig {
  env: RawEnv['NODE_ENV'];
  version: string;
  log: { level: RawEnv['LOG_LEVEL']; file: string | null; pretty: boolean };
  server: {
    host: string;
    port: number;
    corsOrigins: string[];
    apiKey: string | null;
    requireAuthForReads: boolean;
  };
  database: { url: string; autoMigrate: boolean; migrationsDir: string | null };
  trading: {
    mode: TradingMode;
    liveArmed: boolean;
    liveMaxPositionUsd: number;
    autoTrade: boolean;
    engineAutostart: boolean;
    exitMaxSlippagePercent: number;
    catastrophicLossPercent: number;
  };
  paper: {
    startingBalanceUsd: number;
    dexFeePercent: number;
    failureRate: number;
    randomSeed: string | null;
  };
  hardLimits: RiskLimits;
  defaultStrategy: StrategyParams;
  engine: {
    chains: Chain[];
    discoverySources: string[];
    discoveryIntervalMs: number;
    monitorIntervalMs: number;
    watchlistIntervalMs: number;
    watchlistBatchSize: number;
    watchlistMaxAgeHours: number;
    metricsIntervalMs: number;
    securityRefreshMs: number;
    analysisConcurrency: number;
    maxQueueSize: number;
    walletAnalysisTopN: number;
    freshWalletAgeHours: number;
    sourceTimeoutMs: number;
  };
  rpc: {
    solana: string | null;
    evm: Partial<Record<Chain, string>>;
  };
  wallet: {
    privateKey: string | null;
    keypairPath: string | null;
  };
  providers: {
    goplusAppKey: string | null;
    goplusAppSecret: string | null;
    etherscanApiKey: string | null;
    honeypotIsApiKey: string | null;
    rugcheckApiKey: string | null;
    jupiterApiUrl: string;
    jupiterApiKey: string | null;
    rpm: {
      dexscreener: number;
      geckoterminal: number;
      goplus: number;
      rugcheck: number;
      honeypotIs: number;
      etherscan: number;
      solanaRpc: number;
      evmRpc: number;
      jupiter: number;
    };
  };
  alerts: {
    telegramBotToken: string | null;
    telegramChatId: string | null;
    discordWebhookUrl: string | null;
    minSeverity: 'info' | 'warning' | 'critical';
    cooldownSeconds: number;
    maxPerTypePerHour: number;
  };
  llm: {
    apiKey: string | null;
    enabled: boolean;
    model: string;
    required: boolean;
    timeoutMs: number;
  };
}

/** Every configured value that must never appear in logs. */
export function collectSecrets(config: AppConfig): string[] {
  const values = [
    config.server.apiKey,
    config.wallet.privateKey,
    config.providers.goplusAppKey,
    config.providers.goplusAppSecret,
    config.providers.etherscanApiKey,
    config.providers.honeypotIsApiKey,
    config.providers.rugcheckApiKey,
    config.providers.jupiterApiKey,
    config.alerts.telegramBotToken,
    config.alerts.discordWebhookUrl,
    config.llm.apiKey,
    // RPC URLs frequently embed provider API keys.
    config.rpc.solana,
    ...Object.values(config.rpc.evm),
    passwordFromUrl(config.database.url),
  ];
  return values.filter((v): v is string => typeof v === 'string' && v.length >= 6);
}

function passwordFromUrl(url: string): string | null {
  try {
    const u = new URL(url);
    return u.password ? decodeURIComponent(u.password) : null;
  } catch {
    return null;
  }
}

function formatIssues(error: z.ZodError): string {
  return error.issues.map((i) => `  - ${i.path.join('.') || '(root)'}: ${i.message}`).join('\n');
}

/**
 * Parse and validate configuration. Throws ConfigError on any invalid value.
 * Live trading is only armed when every explicit safety requirement is met; a request for
 * live mode that does not meet them is a hard startup error (never a silent fallback).
 */
export function loadConfig(source: NodeJS.ProcessEnv = process.env, version = '1.0.0'): AppConfig {
  const parsed = envSchema.safeParse(source);
  if (!parsed.success) {
    throw new ConfigError(`Invalid configuration:\n${formatIssues(parsed.error)}`);
  }
  const e = parsed.data;

  if (e.API_KEY !== null && e.API_KEY.length < 24) {
    throw new ConfigError('API_KEY must be at least 24 characters (use a long random value).');
  }
  if (e.REQUIRE_AUTH_FOR_READS && e.API_KEY === null) {
    throw new ConfigError('REQUIRE_AUTH_FOR_READS=true requires API_KEY to be set.');
  }
  if (e.HOST !== '127.0.0.1' && e.HOST !== 'localhost' && e.HOST !== '::1' && !e.REQUIRE_AUTH_FOR_READS && e.NODE_ENV === 'production') {
    // Not fatal (docker binds 0.0.0.0 behind a localhost port mapping), but worth knowing.
    process.emitWarning('HOST is not loopback and REQUIRE_AUTH_FOR_READS=false: read endpoints are unauthenticated.');
  }
  if (e.EXIT_MAX_SLIPPAGE < e.MAX_SLIPPAGE) {
    throw new ConfigError('EXIT_MAX_SLIPPAGE must be >= MAX_SLIPPAGE.');
  }

  const evm: Partial<Record<Chain, string>> = {};
  if (e.ETHEREUM_RPC_URL) evm.ethereum = e.ETHEREUM_RPC_URL;
  if (e.BASE_RPC_URL) evm.base = e.BASE_RPC_URL;
  if (e.BSC_RPC_URL) evm.bsc = e.BSC_RPC_URL;
  if (e.ARBITRUM_RPC_URL) evm.arbitrum = e.ARBITRUM_RPC_URL;

  const mode: TradingMode = e.TRADING_MODE;
  let liveArmed = false;
  if (mode === 'live') {
    const problems: string[] = [];
    if (e.LIVE_TRADING_CONFIRMATION !== LIVE_TRADING_CONFIRMATION_PHRASE) {
      problems.push(`LIVE_TRADING_CONFIRMATION must be exactly "${LIVE_TRADING_CONFIRMATION_PHRASE}"`);
    }
    if (!e.WALLET_PRIVATE_KEY && !e.WALLET_KEYPAIR_PATH) {
      problems.push('WALLET_PRIVATE_KEY or WALLET_KEYPAIR_PATH is required');
    }
    if (e.WALLET_PRIVATE_KEY && e.WALLET_KEYPAIR_PATH) {
      problems.push('set only one of WALLET_PRIVATE_KEY or WALLET_KEYPAIR_PATH');
    }
    if (!e.RPC_URL) problems.push('RPC_URL (Solana RPC endpoint) is required');
    if (!e.API_KEY) problems.push('API_KEY is required so the engine can be stopped via the admin API');
    if (!e.REQUIRE_HONEYPOT_CHECK) problems.push('REQUIRE_HONEYPOT_CHECK cannot be disabled in live mode');
    if (e.LIVE_MAX_POSITION_USD <= 0) problems.push('LIVE_MAX_POSITION_USD must be > 0');
    if (!e.CHAINS.some((c) => LIVE_EXECUTION_CHAINS.includes(c))) {
      problems.push(`CHAINS must include a live-executable chain (${LIVE_EXECUTION_CHAINS.join(', ')})`);
    }
    if (problems.length > 0) {
      throw new ConfigError(
        `TRADING_MODE=live was requested but live trading is NOT armed:\n${problems
          .map((p) => `  - ${p}`)
          .join('\n')}\nRefusing to start. Use TRADING_MODE=paper (the default) or fix the items above.`,
      );
    }
    liveArmed = true;
  }

  const hardLimits: RiskLimits = {
    maxPositionPercent: e.MAX_POSITION_PERCENT,
    maxDailyLossPercent: e.MAX_DAILY_LOSS,
    maxDrawdownPercent: e.MAX_DRAWDOWN,
    maxOpenPositions: e.MAX_OPEN_POSITIONS,
    minLiquidityUsd: e.MIN_LIQUIDITY,
    maxRugScore: e.MAX_RUG_SCORE,
    maxSlippagePercent: e.MAX_SLIPPAGE,
    minTokenAgeMinutes: e.MIN_TOKEN_AGE,
    maxLiquiditySharePercent: e.MAX_LIQUIDITY_SHARE_PERCENT,
    minPositionUsd: e.MIN_POSITION_USD,
    requireHoneypotCheck: e.REQUIRE_HONEYPOT_CHECK,
    maxDataAgeSeconds: e.MAX_DATA_AGE_SECONDS,
  };

  const defaultStrategy: StrategyParams = {
    name: 'momentum-safety-v1',
    autoTrade: e.AUTO_TRADE,
    chains: e.CHAINS,
    stopLossPercent: e.STRATEGY_STOP_LOSS_PERCENT,
    takeProfitPercent: e.STRATEGY_TAKE_PROFIT_PERCENT,
    trailingStopPercent: e.STRATEGY_TRAILING_STOP_PERCENT > 0 ? e.STRATEGY_TRAILING_STOP_PERCENT : null,
    maxHoldMinutes: e.STRATEGY_MAX_HOLD_MINUTES,
    riskPerTradePercent: e.STRATEGY_RISK_PER_TRADE_PERCENT,
    minStrategyScore: e.STRATEGY_MIN_SCORE,
    minBuySellRatio: e.STRATEGY_MIN_BUY_SELL_RATIO,
    minVolume1hUsd: e.STRATEGY_MIN_VOLUME_1H_USD,
    maxPriceChange5mPercent: e.STRATEGY_MAX_PRICE_CHANGE_5M_PERCENT,
    minPriceChange1hPercent: e.STRATEGY_MIN_PRICE_CHANGE_1H_PERCENT,
    maxTokenAgeMinutes: e.STRATEGY_MAX_TOKEN_AGE_MINUTES,
    exitOnRugScoreAbove: e.STRATEGY_EXIT_RUG_SCORE,
    exitOnLiquidityDropPercent: e.STRATEGY_EXIT_LIQUIDITY_DROP_PERCENT,
  };

  return {
    env: e.NODE_ENV,
    version,
    log: { level: e.LOG_LEVEL, file: e.LOG_FILE, pretty: e.LOG_PRETTY },
    server: {
      host: e.HOST,
      port: e.PORT,
      corsOrigins: e.CORS_ORIGINS.split(',')
        .map((s) => s.trim())
        .filter(Boolean),
      apiKey: e.API_KEY,
      requireAuthForReads: e.REQUIRE_AUTH_FOR_READS,
    },
    database: { url: e.DATABASE_URL, autoMigrate: e.DB_AUTO_MIGRATE, migrationsDir: e.MIGRATIONS_DIR },
    trading: {
      mode,
      liveArmed,
      liveMaxPositionUsd: e.LIVE_MAX_POSITION_USD,
      autoTrade: e.AUTO_TRADE,
      engineAutostart: e.ENGINE_AUTOSTART,
      exitMaxSlippagePercent: e.EXIT_MAX_SLIPPAGE,
      catastrophicLossPercent: e.CATASTROPHIC_LOSS_PERCENT,
    },
    paper: {
      startingBalanceUsd: e.PAPER_STARTING_BALANCE_USD,
      dexFeePercent: e.PAPER_DEX_FEE_PERCENT,
      failureRate: e.PAPER_FAILURE_RATE,
      randomSeed: e.PAPER_RANDOM_SEED,
    },
    hardLimits,
    defaultStrategy,
    engine: {
      chains: e.CHAINS,
      discoverySources: e.DISCOVERY_SOURCES.split(',')
        .map((s) => s.trim().toLowerCase())
        .filter(Boolean),
      discoveryIntervalMs: e.DISCOVERY_INTERVAL_SECONDS * 1000,
      monitorIntervalMs: e.MONITOR_INTERVAL_SECONDS * 1000,
      watchlistIntervalMs: e.WATCHLIST_INTERVAL_SECONDS * 1000,
      watchlistBatchSize: e.WATCHLIST_BATCH_SIZE,
      watchlistMaxAgeHours: e.WATCHLIST_MAX_AGE_HOURS,
      metricsIntervalMs: e.METRICS_INTERVAL_SECONDS * 1000,
      securityRefreshMs: e.SECURITY_REFRESH_SECONDS * 1000,
      analysisConcurrency: e.ANALYSIS_CONCURRENCY,
      maxQueueSize: e.MAX_QUEUE_SIZE,
      walletAnalysisTopN: e.WALLET_ANALYSIS_TOP_N,
      freshWalletAgeHours: e.FRESH_WALLET_AGE_HOURS,
      sourceTimeoutMs: e.SOURCE_TIMEOUT_MS,
    },
    rpc: { solana: e.RPC_URL, evm },
    wallet: { privateKey: e.WALLET_PRIVATE_KEY, keypairPath: e.WALLET_KEYPAIR_PATH },
    providers: {
      goplusAppKey: e.GOPLUS_APP_KEY,
      goplusAppSecret: e.GOPLUS_APP_SECRET,
      etherscanApiKey: e.ETHERSCAN_API_KEY,
      honeypotIsApiKey: e.HONEYPOT_IS_API_KEY,
      rugcheckApiKey: e.RUGCHECK_API_KEY,
      jupiterApiUrl: e.JUPITER_API_URL.replace(/\/+$/, ''),
      jupiterApiKey: e.JUPITER_API_KEY,
      rpm: {
        dexscreener: e.DEXSCREENER_RPM,
        geckoterminal: e.GECKOTERMINAL_RPM,
        goplus: e.GOPLUS_RPM,
        rugcheck: e.RUGCHECK_RPM,
        honeypotIs: e.HONEYPOT_IS_RPM,
        etherscan: e.ETHERSCAN_RPM,
        solanaRpc: e.SOLANA_RPC_RPM,
        evmRpc: e.EVM_RPC_RPM,
        jupiter: e.JUPITER_RPM,
      },
    },
    alerts: {
      telegramBotToken: e.TELEGRAM_BOT_TOKEN,
      telegramChatId: e.TELEGRAM_CHAT_ID,
      discordWebhookUrl: e.DISCORD_WEBHOOK_URL,
      minSeverity: e.ALERT_MIN_SEVERITY,
      cooldownSeconds: e.ALERT_COOLDOWN_SECONDS,
      maxPerTypePerHour: e.ALERT_MAX_PER_TYPE_PER_HOUR,
    },
    llm: {
      apiKey: e.ANTHROPIC_API_KEY,
      enabled: e.LLM_REVIEW_ENABLED && e.ANTHROPIC_API_KEY !== null,
      model: e.LLM_REVIEW_MODEL,
      required: e.LLM_REVIEW_REQUIRED,
      timeoutMs: e.LLM_REVIEW_TIMEOUT_MS,
    },
  };
}

/** A copy of the configuration that is safe to log or return from the API (no secrets). */
export function safeConfigView(config: AppConfig): Record<string, unknown> {
  return {
    env: config.env,
    version: config.version,
    mode: config.trading.mode,
    liveArmed: config.trading.liveArmed,
    server: {
      host: config.server.host,
      port: config.server.port,
      corsOrigins: config.server.corsOrigins,
      adminApiEnabled: config.server.apiKey !== null,
      requireAuthForReads: config.server.requireAuthForReads,
    },
    database: { driver: config.database.url.startsWith('pglite') ? 'pglite' : 'postgres' },
    engine: config.engine,
    hardLimits: config.hardLimits,
    providers: {
      solanaRpc: config.rpc.solana !== null,
      evmRpc: Object.keys(config.rpc.evm),
      goplusAuthenticated: config.providers.goplusAppKey !== null,
      etherscan: config.providers.etherscanApiKey !== null,
      honeypotIsKey: config.providers.honeypotIsApiKey !== null,
    },
    wallet: { configured: config.wallet.privateKey !== null || config.wallet.keypairPath !== null },
    alerts: {
      telegram: config.alerts.telegramBotToken !== null && config.alerts.telegramChatId !== null,
      discord: config.alerts.discordWebhookUrl !== null,
      minSeverity: config.alerts.minSeverity,
    },
    llm: { enabled: config.llm.enabled, model: config.llm.enabled ? config.llm.model : null },
  };
}
