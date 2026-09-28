import type {
  Chain,
  Decision,
  DecisionAction,
  RiskLevel,
  RiskReport,
  TokenSnapshot,
  TradingMode,
  EffectiveConfig,
} from './domain';

export interface Paginated<T> {
  items: T[];
  total: number;
  limit: number;
  offset: number;
}

export interface TokenListItem {
  id: number;
  chain: Chain;
  address: string;
  name: string | null;
  symbol: string | null;
  priceUsd: number | null;
  marketCapUsd: number | null;
  liquidityUsd: number | null;
  volume24hUsd: number | null;
  priceChange1hPct: number | null;
  holderCount: number | null;
  topHolderPercent: number | null;
  top10HolderPercent: number | null;
  buySellRatio1h: number | null;
  rugScore: number | null;
  honeypotRisk: RiskLevel | null;
  contractRisk: RiskLevel | null;
  liquidityRisk: RiskLevel | null;
  walletConcentrationRisk: RiskLevel | null;
  overallRisk: RiskLevel | null;
  lastDecision: DecisionAction | null;
  lastDecisionLabel: string | null;
  pairCreatedAt: string | null;
  firstSeenAt: string;
  lastAnalyzedAt: string | null;
  openPosition: PositionSummary | null;
}

export interface PositionSummary {
  id: number;
  quantity: number;
  entryPriceUsd: number;
  costBasisUsd: number;
  unrealizedPnlUsd: number | null;
  unrealizedPnlPct: number | null;
}

export interface PricePoint {
  ts: string;
  priceUsd: number | null;
  marketCapUsd: number | null;
  volume5mUsd: number | null;
  volume1hUsd: number | null;
  buys5m: number | null;
  sells5m: number | null;
}

export interface LiquidityPoint {
  ts: string;
  liquidityUsd: number | null;
  lpLockedPercent: number | null;
}

export interface RiskScorePoint {
  ts: string;
  rugScore: number;
  overallRisk: RiskLevel;
}

export interface TokenDetail {
  token: TokenListItem;
  snapshot: TokenSnapshot | null;
  risk: RiskReport | null;
  priceHistory: PricePoint[];
  liquidityHistory: LiquidityPoint[];
  riskHistory: RiskScorePoint[];
  decisions: Decision[];
  positions: Position[];
  alerts: Alert[];
}

export type PositionStatus = 'open' | 'closed';

export type CloseReason =
  | 'stop_loss'
  | 'take_profit'
  | 'trailing_stop'
  | 'max_hold_time'
  | 'rug_risk_escalation'
  | 'liquidity_drop'
  | 'manual'
  | 'strategy_exit'
  | 'daily_loss_limit';

export interface Position {
  id: number;
  tokenId: number;
  chain: Chain;
  address: string;
  symbol: string | null;
  mode: TradingMode;
  status: PositionStatus;
  quantity: number;
  entryPriceUsd: number;
  costBasisUsd: number;
  currentPriceUsd: number | null;
  stopLossPriceUsd: number;
  takeProfitPriceUsd: number;
  trailingStopPercent: number | null;
  highestPriceUsd: number;
  unrealizedPnlUsd: number | null;
  unrealizedPnlPct: number | null;
  realizedPnlUsd: number | null;
  exitPriceUsd: number | null;
  closeReason: CloseReason | null;
  openedAt: string;
  closedAt: string | null;
}

export type TradeSide = 'buy' | 'sell';
export type TradeStatus = 'filled' | 'failed' | 'rejected';

export interface Trade {
  id: number;
  tokenId: number;
  positionId: number | null;
  decisionId: number | null;
  chain: Chain;
  address: string;
  symbol: string | null;
  mode: TradingMode;
  side: TradeSide;
  status: TradeStatus;
  requestedUsd: number;
  filledUsd: number | null;
  quantity: number | null;
  priceUsd: number | null;
  slippagePct: number | null;
  feeUsd: number | null;
  txHash: string | null;
  error: string | null;
  reason: string;
  createdAt: string;
}

export interface EquityPoint {
  ts: string;
  equityUsd: number;
  cashUsd: number;
  unrealizedPnlUsd: number;
  realizedPnlUsd: number;
  drawdownPct: number;
}

export interface DailyPnl {
  day: string;
  pnlUsd: number;
  trades: number;
}

export interface PerformanceSummary {
  mode: TradingMode;
  startingBalanceUsd: number;
  cashUsd: number;
  equityUsd: number;
  /** Equity after subtracting estimated exit slippage/fees on open positions. */
  conservativeEquityUsd: number;
  peakEquityUsd: number;
  realizedPnlUsd: number;
  unrealizedPnlUsd: number;
  dailyPnlUsd: number;
  dailyPnlPct: number;
  drawdownPct: number;
  maxDrawdownPct: number;
  totalTrades: number;
  closedPositions: number;
  winningTrades: number;
  losingTrades: number;
  winRate: number | null;
  averageWinUsd: number | null;
  averageLossUsd: number | null;
  profitFactor: number | null;
  openPositions: number;
  halted: boolean;
  haltReason: string | null;
  equityCurve: EquityPoint[];
  dailyPnl: DailyPnl[];
}

export type AlertType =
  | 'LIQUIDITY_REMOVAL'
  | 'LIQUIDITY_CRASH'
  | 'MASSIVE_TRANSFER'
  | 'DEVELOPER_SELLING'
  | 'DEVELOPER_ACTIVITY'
  | 'EXTREME_PRICE_DROP'
  | 'TAX_CHANGE'
  | 'CONTRACT_CHANGE'
  | 'ABNORMAL_VOLUME'
  | 'RUG_RISK_ESCALATION'
  | 'NEW_HIGH_RISK_TOKEN'
  | 'TRADING_OPPORTUNITY'
  | 'POSITION_OPENED'
  | 'POSITION_CLOSED'
  | 'STOP_LOSS'
  | 'TAKE_PROFIT'
  | 'DAILY_LOSS_LIMIT'
  | 'MAX_DRAWDOWN'
  | 'SYSTEM_ERROR';

export type AlertSeverity = 'info' | 'warning' | 'critical';

export interface Alert {
  id: number;
  tokenId: number | null;
  chain: Chain | null;
  address: string | null;
  symbol: string | null;
  type: AlertType;
  severity: AlertSeverity;
  title: string;
  message: string;
  data: Record<string, unknown>;
  acknowledged: boolean;
  deliveredTo: string[];
  createdAt: string;
}

export interface ProviderHealth {
  name: string;
  configured: boolean;
  requests: number;
  failures: number;
  rateLimited: number;
  consecutiveFailures: number;
  circuitOpen: boolean;
  lastSuccessAt: string | null;
  lastError: string | null;
  lastErrorAt: string | null;
}

export interface LoopStatus {
  name: string;
  running: boolean;
  intervalMs: number;
  lastRunAt: string | null;
  lastDurationMs: number | null;
  lastError: string | null;
  runs: number;
}

export interface SystemStatus {
  version: string;
  mode: TradingMode;
  liveTradingArmed: boolean;
  engineRunning: boolean;
  autoTrade: boolean;
  halted: boolean;
  haltReason: string | null;
  uptimeSeconds: number;
  database: { ok: boolean; driver: string; error: string | null };
  loops: LoopStatus[];
  providers: ProviderHealth[];
  notifiers: { name: string; configured: boolean; sent: number; failed: number }[];
  queue: { pending: number; inFlight: number };
  llmReviewer: { enabled: boolean; model: string | null };
  startedAt: string;
}

export interface ScanRequest {
  chain: Chain;
  address: string;
  /** When true the pipeline may trade (paper/live per mode) if every risk check passes. */
  allowTrade?: boolean;
}

export interface ScanResponse {
  decision: Decision;
  risk: RiskReport;
}

export interface PaperTradeRequest {
  chain: Chain;
  address: string;
  side: 'buy' | 'sell';
  /** For buys: USD amount requested (still capped by risk sizing). Omit to let sizing decide. */
  amountUsd?: number;
  /** For sells: position to close. */
  positionId?: number;
}

export interface PaperTradeResponse {
  accepted: boolean;
  decision: Decision;
  trade: Trade | null;
  position: Position | null;
}

export type StrategyUpdateRequest = Partial<{
  limits: Partial<EffectiveConfig['limits']>;
  strategy: Partial<EffectiveConfig['strategy']>;
}>;

export interface BacktestTrade {
  address: string;
  symbol: string | null;
  entryTs: string;
  exitTs: string;
  entryPriceUsd: number;
  exitPriceUsd: number;
  sizeUsd: number;
  pnlUsd: number;
  pnlPct: number;
  feesUsd: number;
  exitReason: string;
  /** Loss larger than the catastrophic threshold, or exit far through the stop (gap / rug). */
  catastrophic: boolean;
  rugEventDuringHold: boolean;
}

export interface CatastrophicEvent {
  address: string;
  symbol: string | null;
  ts: string;
  kind: 'catastrophic_trade_loss' | 'rug_while_holding' | 'stop_gap_through' | 'drawdown_breach';
  lossUsd: number;
  lossPct: number;
  description: string;
}

export interface BacktestMetrics {
  startingBalanceUsd: number;
  endingBalanceUsd: number;
  totalReturnPct: number;
  maxDrawdownPct: number;
  maxDrawdownUsd: number;
  numberOfTrades: number;
  winningTrades: number;
  losingTrades: number;
  winRate: number | null;
  averageWinUsd: number | null;
  averageLossUsd: number | null;
  profitFactor: number | null;
  largestLossUsd: number | null;
  largestGainUsd: number | null;
  expectancyUsd: number | null;
  sharpeRatio: number | null;
  sortinoRatio: number | null;
  calmarRatio: number | null;
  /** Mean of the worst 5% of trade returns (CVaR 95%), percent. */
  cvar95Pct: number | null;
  totalFeesUsd: number;
  exposurePct: number;
  tokensEvaluated: number;
  tokensSkippedForRugRisk: number;
  rugsAvoided: number;
  rugsHit: number;
  catastrophicLosses: number;
}

export interface BacktestResult {
  id: number | null;
  name: string;
  source: string;
  syntheticData: boolean;
  startedAt: string;
  finishedAt: string;
  metrics: BacktestMetrics;
  trades: BacktestTrade[];
  catastrophicEvents: CatastrophicEvent[];
  equityCurve: { ts: string; equityUsd: number; drawdownPct: number }[];
  warnings: string[];
  config: Record<string, unknown>;
}

export type ServerEvent =
  | { type: 'token.analyzed'; data: { token: TokenListItem } }
  | { type: 'decision'; data: Decision }
  | { type: 'trade'; data: Trade }
  | { type: 'position'; data: Position }
  | { type: 'alert'; data: Alert }
  | { type: 'performance'; data: Pick<PerformanceSummary, 'equityUsd' | 'dailyPnlUsd' | 'drawdownPct' | 'halted'> }
  | { type: 'status'; data: Pick<SystemStatus, 'engineRunning' | 'halted' | 'haltReason'> };
