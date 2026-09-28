import { sql } from 'drizzle-orm';
import {
  bigserial,
  boolean,
  doublePrecision,
  index,
  integer,
  jsonb,
  pgTable,
  serial,
  text,
  timestamp,
  uniqueIndex,
} from 'drizzle-orm/pg-core';
import type {
  Decision,
  PositionSizing,
  RiskCheckResult,
  RiskLimits,
  RiskReport,
  StageResult,
  StrategyParams,
  TokenSnapshot,
  BacktestResult,
} from '@memeguard/shared';

const ts = (name: string) => timestamp(name, { withTimezone: true, mode: 'date' });

/** Tokens discovered or scanned, with denormalised latest metrics for fast listing/sorting. */
export const tokens = pgTable(
  'tokens',
  {
    id: serial('id').primaryKey(),
    chain: text('chain').notNull(),
    address: text('address').notNull(),
    name: text('name'),
    symbol: text('symbol'),
    decimals: integer('decimals'),
    pairAddress: text('pair_address'),
    dexId: text('dex_id'),
    pairCreatedAt: ts('pair_created_at'),
    discoveredVia: text('discovered_via').notNull().default('manual'),
    status: text('status').notNull().default('watching'),
    firstSeenAt: ts('first_seen_at').notNull().defaultNow(),
    lastAnalyzedAt: ts('last_analyzed_at'),
    lastSecurityAt: ts('last_security_at'),
    latestSnapshot: jsonb('latest_snapshot').$type<TokenSnapshot>(),
    priceUsd: doublePrecision('price_usd'),
    marketCapUsd: doublePrecision('market_cap_usd'),
    liquidityUsd: doublePrecision('liquidity_usd'),
    volume24hUsd: doublePrecision('volume_24h_usd'),
    priceChange1hPct: doublePrecision('price_change_1h_pct'),
    holderCount: integer('holder_count'),
    topHolderPercent: doublePrecision('top_holder_percent'),
    top10HolderPercent: doublePrecision('top10_holder_percent'),
    buySellRatio1h: doublePrecision('buy_sell_ratio_1h'),
    rugScore: doublePrecision('rug_score'),
    overallRisk: text('overall_risk'),
    honeypotRisk: text('honeypot_risk'),
    contractRisk: text('contract_risk'),
    liquidityRisk: text('liquidity_risk'),
    concentrationRisk: text('concentration_risk'),
    lastDecision: text('last_decision'),
    lastDecisionLabel: text('last_decision_label'),
    createdAt: ts('created_at').notNull().defaultNow(),
    updatedAt: ts('updated_at').notNull().defaultNow(),
  },
  (t) => [
    uniqueIndex('tokens_chain_address_uq').on(t.chain, t.address),
    index('tokens_rug_score_idx').on(t.rugScore),
    index('tokens_last_analyzed_idx').on(t.lastAnalyzedAt),
    index('tokens_status_idx').on(t.status),
  ],
);

/** Wallets of interest (deployers, top holders, funders) with cached age/funding lookups. */
export const wallets = pgTable(
  'wallets',
  {
    id: serial('id').primaryKey(),
    chain: text('chain').notNull(),
    address: text('address').notNull(),
    label: text('label'),
    walletCreatedAt: ts('wallet_created_at'),
    /** True when the wallet has more history than we paged through (age is a lower bound). */
    ageIsLowerBound: boolean('age_is_lower_bound').notNull().default(false),
    fundedBy: text('funded_by'),
    riskFlags: jsonb('risk_flags').$type<string[]>().notNull().default(sql`'[]'::jsonb`),
    metadata: jsonb('metadata').$type<Record<string, unknown>>().notNull().default(sql`'{}'::jsonb`),
    firstSeenAt: ts('first_seen_at').notNull().defaultNow(),
    updatedAt: ts('updated_at').notNull().defaultNow(),
  },
  (t) => [uniqueIndex('wallets_chain_address_uq').on(t.chain, t.address)],
);

/** Link table: which wallets matter for which token, and in what role. */
export const tokenWallets = pgTable(
  'token_wallets',
  {
    id: serial('id').primaryKey(),
    tokenId: integer('token_id')
      .notNull()
      .references(() => tokens.id, { onDelete: 'cascade' }),
    walletId: integer('wallet_id')
      .notNull()
      .references(() => wallets.id, { onDelete: 'cascade' }),
    role: text('role').notNull(),
    percent: doublePrecision('percent'),
    clusterFunder: text('cluster_funder'),
    updatedAt: ts('updated_at').notNull().defaultNow(),
  },
  (t) => [uniqueIndex('token_wallets_uq').on(t.tokenId, t.walletId, t.role)],
);

/** On-chain transactions observed (developer activity, large transfers) and our own swaps. */
export const transactions = pgTable(
  'transactions',
  {
    id: serial('id').primaryKey(),
    chain: text('chain').notNull(),
    tokenId: integer('token_id').references(() => tokens.id, { onDelete: 'cascade' }),
    txHash: text('tx_hash').notNull(),
    wallet: text('wallet'),
    kind: text('kind').notNull(),
    percentOfSupply: doublePrecision('percent_of_supply'),
    usdValue: doublePrecision('usd_value'),
    counterparty: text('counterparty'),
    source: text('source').notNull(),
    blockTime: ts('block_time'),
    raw: jsonb('raw').$type<Record<string, unknown>>(),
    createdAt: ts('created_at').notNull().defaultNow(),
  },
  (t) => [
    uniqueIndex('transactions_uq').on(t.chain, t.txHash, t.kind),
    index('transactions_token_idx').on(t.tokenId, t.blockTime),
  ],
);

export const riskScores = pgTable(
  'risk_scores',
  {
    id: serial('id').primaryKey(),
    tokenId: integer('token_id')
      .notNull()
      .references(() => tokens.id, { onDelete: 'cascade' }),
    rugScore: doublePrecision('rug_score').notNull(),
    honeypotRisk: text('honeypot_risk').notNull(),
    liquidityRisk: text('liquidity_risk').notNull(),
    contractRisk: text('contract_risk').notNull(),
    walletConcentrationRisk: text('wallet_concentration_risk').notNull(),
    developerRisk: text('developer_risk').notNull(),
    marketIntegrityRisk: text('market_integrity_risk').notNull(),
    overallRisk: text('overall_risk').notNull(),
    isLikelyScam: boolean('is_likely_scam').notNull(),
    criticalFlags: jsonb('critical_flags').$type<string[]>().notNull(),
    dataCompleteness: doublePrecision('data_completeness').notNull(),
    modelVersion: text('model_version').notNull(),
    report: jsonb('report').$type<RiskReport>().notNull(),
    createdAt: ts('created_at').notNull().defaultNow(),
  },
  (t) => [index('risk_scores_token_idx').on(t.tokenId, t.createdAt)],
);

export const priceHistory = pgTable(
  'price_history',
  {
    id: bigserial('id', { mode: 'number' }).primaryKey(),
    tokenId: integer('token_id')
      .notNull()
      .references(() => tokens.id, { onDelete: 'cascade' }),
    ts: ts('ts').notNull(),
    priceUsd: doublePrecision('price_usd'),
    marketCapUsd: doublePrecision('market_cap_usd'),
    fdvUsd: doublePrecision('fdv_usd'),
    volume5mUsd: doublePrecision('volume_5m_usd'),
    volume1hUsd: doublePrecision('volume_1h_usd'),
    volume24hUsd: doublePrecision('volume_24h_usd'),
    buys5m: integer('buys_5m'),
    sells5m: integer('sells_5m'),
    buys1h: integer('buys_1h'),
    sells1h: integer('sells_1h'),
    priceChange5mPct: doublePrecision('price_change_5m_pct'),
    priceChange1hPct: doublePrecision('price_change_1h_pct'),
    source: text('source'),
  },
  (t) => [index('price_history_token_ts_idx').on(t.tokenId, t.ts)],
);

export const liquidityHistory = pgTable(
  'liquidity_history',
  {
    id: bigserial('id', { mode: 'number' }).primaryKey(),
    tokenId: integer('token_id')
      .notNull()
      .references(() => tokens.id, { onDelete: 'cascade' }),
    ts: ts('ts').notNull(),
    liquidityUsd: doublePrecision('liquidity_usd'),
    lpLockedPercent: doublePrecision('lp_locked_percent'),
    lpBurnedPercent: doublePrecision('lp_burned_percent'),
    source: text('source'),
  },
  (t) => [index('liquidity_history_token_ts_idx').on(t.tokenId, t.ts)],
);

export const aiDecisions = pgTable(
  'ai_decisions',
  {
    id: serial('id').primaryKey(),
    tokenId: integer('token_id')
      .notNull()
      .references(() => tokens.id, { onDelete: 'cascade' }),
    action: text('action').$type<Decision['action']>().notNull(),
    label: text('label').notNull(),
    reasonCode: text('reason_code').notNull(),
    confidence: doublePrecision('confidence').notNull(),
    rugScore: doublePrecision('rug_score'),
    strategyScore: doublePrecision('strategy_score'),
    mode: text('mode').$type<Decision['mode']>().notNull(),
    executed: boolean('executed').notNull().default(false),
    tradeId: integer('trade_id'),
    reasons: jsonb('reasons').$type<string[]>().notNull(),
    factors: jsonb('factors').$type<Record<string, number | null>>().notNull(),
    stages: jsonb('stages').$type<StageResult[]>().notNull(),
    riskChecks: jsonb('risk_checks').$type<RiskCheckResult[]>().notNull(),
    sizing: jsonb('sizing').$type<PositionSizing | null>(),
    createdAt: ts('created_at').notNull().defaultNow(),
  },
  (t) => [
    index('ai_decisions_token_idx').on(t.tokenId, t.createdAt),
    index('ai_decisions_action_idx').on(t.action, t.createdAt),
  ],
);

export const positions = pgTable(
  'positions',
  {
    id: serial('id').primaryKey(),
    tokenId: integer('token_id')
      .notNull()
      .references(() => tokens.id, { onDelete: 'restrict' }),
    mode: text('mode').notNull(),
    status: text('status').notNull().default('open'),
    quantity: doublePrecision('quantity').notNull(),
    /** Raw on-chain amount (base units) for live positions. */
    rawQuantity: text('raw_quantity'),
    tokenDecimals: integer('token_decimals'),
    entryPriceUsd: doublePrecision('entry_price_usd').notNull(),
    costBasisUsd: doublePrecision('cost_basis_usd').notNull(),
    stopLossPriceUsd: doublePrecision('stop_loss_price_usd').notNull(),
    takeProfitPriceUsd: doublePrecision('take_profit_price_usd').notNull(),
    trailingStopPercent: doublePrecision('trailing_stop_percent'),
    highestPriceUsd: doublePrecision('highest_price_usd').notNull(),
    lastPriceUsd: doublePrecision('last_price_usd'),
    entryLiquidityUsd: doublePrecision('entry_liquidity_usd'),
    entryRugScore: doublePrecision('entry_rug_score'),
    exitPriceUsd: doublePrecision('exit_price_usd'),
    proceedsUsd: doublePrecision('proceeds_usd'),
    realizedPnlUsd: doublePrecision('realized_pnl_usd'),
    closeReason: text('close_reason'),
    openedAt: ts('opened_at').notNull().defaultNow(),
    closedAt: ts('closed_at'),
    updatedAt: ts('updated_at').notNull().defaultNow(),
  },
  (t) => [
    index('positions_status_idx').on(t.mode, t.status),
    index('positions_token_idx').on(t.tokenId),
  ],
);

export const trades = pgTable(
  'trades',
  {
    id: serial('id').primaryKey(),
    tokenId: integer('token_id')
      .notNull()
      .references(() => tokens.id, { onDelete: 'restrict' }),
    positionId: integer('position_id').references(() => positions.id, { onDelete: 'set null' }),
    decisionId: integer('decision_id').references(() => aiDecisions.id, { onDelete: 'set null' }),
    mode: text('mode').notNull(),
    side: text('side').notNull(),
    status: text('status').notNull(),
    requestedUsd: doublePrecision('requested_usd').notNull(),
    filledUsd: doublePrecision('filled_usd'),
    quantity: doublePrecision('quantity'),
    priceUsd: doublePrecision('price_usd'),
    slippagePct: doublePrecision('slippage_pct'),
    feeUsd: doublePrecision('fee_usd'),
    txHash: text('tx_hash'),
    error: text('error'),
    reason: text('reason').notNull(),
    raw: jsonb('raw').$type<Record<string, unknown>>(),
    createdAt: ts('created_at').notNull().defaultNow(),
  },
  (t) => [index('trades_created_idx').on(t.createdAt), index('trades_token_idx').on(t.tokenId)],
);

export const alerts = pgTable(
  'alerts',
  {
    id: serial('id').primaryKey(),
    tokenId: integer('token_id').references(() => tokens.id, { onDelete: 'cascade' }),
    type: text('type').notNull(),
    severity: text('severity').notNull(),
    title: text('title').notNull(),
    message: text('message').notNull(),
    data: jsonb('data').$type<Record<string, unknown>>().notNull().default(sql`'{}'::jsonb`),
    dedupeKey: text('dedupe_key'),
    acknowledged: boolean('acknowledged').notNull().default(false),
    deliveredTo: jsonb('delivered_to').$type<string[]>().notNull().default(sql`'[]'::jsonb`),
    createdAt: ts('created_at').notNull().defaultNow(),
  },
  (t) => [
    index('alerts_created_idx').on(t.createdAt),
    index('alerts_dedupe_idx').on(t.dedupeKey, t.createdAt),
    index('alerts_token_idx').on(t.tokenId),
  ],
);

/** Account state per trading mode (paper wallet balance, peaks, halts). */
export const accounts = pgTable('accounts', {
  id: serial('id').primaryKey(),
  mode: text('mode').notNull().unique(),
  startingBalanceUsd: doublePrecision('starting_balance_usd').notNull(),
  cashUsd: doublePrecision('cash_usd').notNull(),
  realizedPnlUsd: doublePrecision('realized_pnl_usd').notNull().default(0),
  peakEquityUsd: doublePrecision('peak_equity_usd').notNull(),
  maxDrawdownPct: doublePrecision('max_drawdown_pct').notNull().default(0),
  day: text('day').notNull(),
  dayStartEquityUsd: doublePrecision('day_start_equity_usd').notNull(),
  halted: boolean('halted').notNull().default(false),
  haltReason: text('halt_reason'),
  haltedAt: ts('halted_at'),
  /** Daily-loss halts auto-clear on the next UTC day; drawdown halts need a manual resume. */
  haltClearsOnNewDay: boolean('halt_clears_on_new_day').notNull().default(false),
  updatedAt: ts('updated_at').notNull().defaultNow(),
});

export const performanceMetrics = pgTable(
  'performance_metrics',
  {
    id: bigserial('id', { mode: 'number' }).primaryKey(),
    mode: text('mode').notNull(),
    ts: ts('ts').notNull().defaultNow(),
    equityUsd: doublePrecision('equity_usd').notNull(),
    conservativeEquityUsd: doublePrecision('conservative_equity_usd').notNull(),
    cashUsd: doublePrecision('cash_usd').notNull(),
    unrealizedPnlUsd: doublePrecision('unrealized_pnl_usd').notNull(),
    realizedPnlUsd: doublePrecision('realized_pnl_usd').notNull(),
    dailyPnlUsd: doublePrecision('daily_pnl_usd').notNull(),
    drawdownPct: doublePrecision('drawdown_pct').notNull(),
    openPositions: integer('open_positions').notNull(),
    winRate: doublePrecision('win_rate'),
  },
  (t) => [index('performance_metrics_mode_ts_idx').on(t.mode, t.ts)],
);

/** Versioned runtime strategy/limit configuration (POST /strategy). */
export const strategyConfigs = pgTable('strategy_configs', {
  id: serial('id').primaryKey(),
  version: integer('version').notNull(),
  limits: jsonb('limits').$type<RiskLimits>().notNull(),
  strategy: jsonb('strategy').$type<StrategyParams>().notNull(),
  active: boolean('active').notNull().default(true),
  createdAt: ts('created_at').notNull().defaultNow(),
});

/** Engine event log: errors, skipped opportunities, lifecycle events. */
export const eventLog = pgTable(
  'event_log',
  {
    id: bigserial('id', { mode: 'number' }).primaryKey(),
    level: text('level').notNull(),
    category: text('category').notNull(),
    message: text('message').notNull(),
    tokenId: integer('token_id').references(() => tokens.id, { onDelete: 'set null' }),
    data: jsonb('data').$type<Record<string, unknown>>().notNull().default(sql`'{}'::jsonb`),
    createdAt: ts('created_at').notNull().defaultNow(),
  },
  (t) => [index('event_log_created_idx').on(t.createdAt), index('event_log_category_idx').on(t.category)],
);

export const backtestRuns = pgTable('backtest_runs', {
  id: serial('id').primaryKey(),
  name: text('name').notNull(),
  source: text('source').notNull(),
  synthetic: boolean('synthetic').notNull(),
  config: jsonb('config').$type<Record<string, unknown>>().notNull(),
  result: jsonb('result').$type<BacktestResult>().notNull(),
  createdAt: ts('created_at').notNull().defaultNow(),
});

export const schema = {
  tokens,
  wallets,
  tokenWallets,
  transactions,
  riskScores,
  priceHistory,
  liquidityHistory,
  aiDecisions,
  positions,
  trades,
  alerts,
  accounts,
  performanceMetrics,
  strategyConfigs,
  eventLog,
  backtestRuns,
};
