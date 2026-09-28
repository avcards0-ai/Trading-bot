/**
 * Core domain contracts. This package is TYPE-ONLY: it must never contain runtime code,
 * so both the backend (Node) and the dashboard (browser) can import it with `import type`.
 */

export type Chain = 'solana' | 'ethereum' | 'bsc' | 'base' | 'arbitrum';

export type RiskLevel = 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL';

export type DecisionAction = 'BUY' | 'SELL' | 'HOLD' | 'SKIP';

export type TradingMode = 'paper' | 'live';

/** Internal risk categories. The first four map 1:1 to the required public risk outputs. */
export type RiskCategory =
  | 'honeypot'
  | 'liquidity'
  | 'contract'
  | 'concentration'
  | 'developer'
  | 'market'
  | 'data';

export type Scalar = string | number | boolean | null;

// ---------------------------------------------------------------------------
// Normalised on-chain / market data (produced by adapters, consumed by analysis)
// ---------------------------------------------------------------------------

export interface WindowedNumbers {
  m5: number | null;
  h1: number | null;
  h6: number | null;
  h24: number | null;
}

export interface TxnCounts {
  buys: number;
  sells: number;
}

export interface MarketData {
  source: string;
  pairAddress: string | null;
  dexId: string | null;
  quoteSymbol: string | null;
  priceUsd: number | null;
  priceNative: number | null;
  marketCapUsd: number | null;
  fdvUsd: number | null;
  liquidityUsd: number | null;
  volumeUsd: WindowedNumbers;
  priceChangePct: WindowedNumbers;
  txns: { m5: TxnCounts | null; h1: TxnCounts | null; h6: TxnCounts | null; h24: TxnCounts | null };
  pairCreatedAt: string | null;
  fetchedAt: string;
}

export interface HolderInfo {
  /** Wallet (owner) address when known; otherwise the token account / holder address. */
  address: string;
  /** Percent of total supply, 0-100. */
  percent: number;
  amount?: number | null;
  isContract?: boolean | null;
  isLocked?: boolean | null;
  tag?: string | null;
  /** Liquidity pools, burn addresses and lockers are excluded from concentration metrics. */
  isLiquidityPool?: boolean;
  isBurn?: boolean;
  isInsider?: boolean | null;
}

export interface HolderData {
  sources: string[];
  holderCount: number | null;
  /** Sorted by percent, descending. */
  topHolders: HolderInfo[];
  totalSupply: number | null;
}

export interface LiquidityData {
  sources: string[];
  totalLiquidityUsd: number | null;
  /** Percent (0-100) of LP tokens locked in a locker contract. */
  lpLockedPercent: number | null;
  /** Percent (0-100) of LP tokens sent to a burn address. */
  lpBurnedPercent: number | null;
  /** True when liquidity is held by a program (e.g. pump.fun bonding curve) rather than withdrawable LP. */
  programControlled: boolean;
  /** Percent (0-100) of LP tokens held by the creator/owner wallet. */
  creatorLpPercent: number | null;
  lpHolderCount: number | null;
  poolCount: number | null;
}

export type TokenProgram = 'spl-token' | 'spl-token-2022' | 'evm' | 'unknown';

export interface ContractData {
  sources: string[];
  tokenProgram: TokenProgram;
  isVerified: boolean | null;
  isProxy: boolean | null;
  proxyImplementation: string | null;
  ownerAddress: string | null;
  ownershipRenounced: boolean | null;
  hiddenOwner: boolean | null;
  canTakeBackOwnership: boolean | null;
  ownerCanChangeBalance: boolean | null;
  mintable: boolean | null;
  mintAuthority: string | null;
  freezable: boolean | null;
  freezeAuthority: string | null;
  transferPausable: boolean | null;
  hasBlacklist: boolean | null;
  hasWhitelist: boolean | null;
  tradingCooldown: boolean | null;
  antiWhaleModifiable: boolean | null;
  /** Owner can modify buy/sell taxes (GoPlus: slippage_modifiable). */
  taxModifiable: boolean | null;
  /** Owner can set a tax for specific addresses (GoPlus: personal_slippage_modifiable). */
  personalTaxModifiable: boolean | null;
  selfDestruct: boolean | null;
  externalCall: boolean | null;
  /** Declared / reported taxes, percent 0-100. */
  buyTaxPct: number | null;
  sellTaxPct: number | null;
  transferTaxPct: number | null;
  cannotBuy: boolean | null;
  cannotSellAll: boolean | null;
  /** Security provider's own honeypot flag (not a simulation). */
  flaggedHoneypot: boolean | null;
  /** Solana Token-2022 extensions present on the mint. */
  tokenExtensions: string[];
  permanentDelegate: string | null;
  transferHook: boolean | null;
  nonTransferable: boolean | null;
  defaultAccountStateFrozen: boolean | null;
  transferFeeAuthority: string | null;
  metadataMutable: boolean | null;
  /** Human readable names of suspicious functions detected in bytecode / by providers. */
  suspiciousFunctions: string[];
  /** Hash of runtime bytecode (EVM) or mint account data (Solana) for change detection. */
  codeHash: string | null;
}

export interface HoneypotSimulation {
  source: string;
  /** True when an actual buy/sell simulation (or sell-route quote) was performed. */
  simulated: boolean;
  isHoneypot: boolean | null;
  buyTaxPct: number | null;
  sellTaxPct: number | null;
  transferTaxPct: number | null;
  sellRouteFound: boolean | null;
  reason: string | null;
}

export interface DeployerProfile {
  sources: string[];
  address: string | null;
  walletAgeDays: number | null;
  tokensCreated: number | null;
  knownRugs: number | null;
  /** Security provider reports a honeypot created by the same deployer. */
  honeypotWithSameCreator: boolean | null;
  /** Percent (0-100) of supply currently held by the deployer. */
  holdsPercent: number | null;
  flaggedMalicious: boolean | null;
}

export interface TradeActivity {
  source: string;
  windowMinutes: number;
  tradeCount: number;
  uniqueTraders: number;
  buyers: number;
  sellers: number;
  buyVolumeUsd: number;
  sellVolumeUsd: number;
  /** Wallets that both bought and sold inside the window. */
  roundTripWallets: number;
  /** Share (0-1) of window volume produced by round-trip wallets. */
  roundTripVolumeShare: number;
  /** Share (0-1) of window volume produced by the single most active wallet. */
  topTraderVolumeShare: number;
  /** Coefficient of variation of trade sizes; very low values indicate scripted trades. */
  tradeSizeCv: number | null;
  /** Share (0-1) of trades whose USD size exactly repeats another trade's size. */
  repeatedSizeShare: number;
}

export interface WalletCluster {
  funder: string;
  wallets: string[];
  /** Combined percent of supply held by the cluster. */
  combinedPercent: number;
}

export interface WalletAnalysis {
  sources: string[];
  analyzedWallets: number;
  /** Wallets younger than the configured "fresh wallet" threshold. */
  newWallets: number;
  /** Share (0-1) of analysed top holders that are newly created wallets. */
  newWalletShare: number | null;
  clusters: WalletCluster[];
  largestClusterPercent: number | null;
}

export interface DeveloperEvent {
  kind: 'sell' | 'transfer_out' | 'transfer_in' | 'lp_remove' | 'mint' | 'other';
  signature: string | null;
  timestamp: string | null;
  /** Percent of total supply moved. */
  percentOfSupply: number | null;
  counterparty: string | null;
}

export interface DeveloperActivity {
  sources: string[];
  devAddress: string | null;
  lookbackMinutes: number;
  transfersOut: number;
  sells: number;
  /** Percent of total supply the dev moved out (sold or transferred) inside the lookback. */
  percentOfSupplyMoved: number | null;
  transfersToFreshWallets: number;
  events: DeveloperEvent[];
}

/** A red flag reported verbatim by an external security provider. */
export interface ProviderWarning {
  source: string;
  code: string;
  level: 'info' | 'warn' | 'danger';
  message: string;
}

export interface SourceStatus {
  name: string;
  ok: boolean;
  durationMs: number;
  error: string | null;
}

export interface TokenSnapshot {
  chain: Chain;
  address: string;
  name: string | null;
  symbol: string | null;
  decimals: number | null;
  collectedAt: string;
  market: MarketData | null;
  contract: ContractData | null;
  holders: HolderData | null;
  liquidity: LiquidityData | null;
  honeypot: HoneypotSimulation | null;
  deployer: DeployerProfile | null;
  trades: TradeActivity | null;
  wallets: WalletAnalysis | null;
  developer: DeveloperActivity | null;
  warnings: ProviderWarning[];
  /** Provider explicitly reports that the token has already been rugged. */
  reportedRugged: boolean | null;
  sources: SourceStatus[];
}

// ---------------------------------------------------------------------------
// Risk report
// ---------------------------------------------------------------------------

export interface RiskFactor {
  id: string;
  category: RiskCategory;
  label: string;
  /** Contribution to the category score, 0-100 (combined with noisy-OR). */
  points: number;
  severity: RiskLevel;
  /** A critical factor forces the category to CRITICAL and marks the token as a likely scam. */
  critical: boolean;
  observed: Scalar;
  threshold: Scalar;
  explanation: string;
  sources: string[];
}

export interface CategoryAssessment {
  category: RiskCategory;
  score: number;
  level: RiskLevel;
  explanation: string;
  factorIds: string[];
}

export interface LlmReview {
  model: string;
  escalate: boolean;
  concerns: string[];
  summary: string;
  error: string | null;
}

export interface RiskReport {
  chain: Chain;
  address: string;
  modelVersion: string;
  generatedAt: string;
  rugScore: number;
  honeypotRisk: RiskLevel;
  liquidityRisk: RiskLevel;
  contractRisk: RiskLevel;
  walletConcentrationRisk: RiskLevel;
  developerRisk: RiskLevel;
  marketIntegrityRisk: RiskLevel;
  overallRisk: RiskLevel;
  isLikelyScam: boolean;
  criticalFlags: string[];
  categories: Record<RiskCategory, CategoryAssessment>;
  factors: RiskFactor[];
  /** Plain-language explanation of every score. */
  explanations: {
    rugScore: string;
    honeypotRisk: string;
    liquidityRisk: string;
    contractRisk: string;
    walletConcentrationRisk: string;
    overallRisk: string;
  };
  dataCompleteness: number;
  missingData: string[];
  sources: string[];
  llmReview: LlmReview | null;
}

// ---------------------------------------------------------------------------
// Decisions
// ---------------------------------------------------------------------------

export type PipelineStage =
  | 'DISCOVERY'
  | 'ON_CHAIN'
  | 'CONTRACT'
  | 'WALLET'
  | 'LIQUIDITY'
  | 'MARKET'
  | 'RUG_RISK'
  | 'STRATEGY'
  | 'RISK_CHECK'
  | 'EXECUTION';

export type StageStatus = 'pass' | 'warn' | 'fail' | 'error' | 'skipped';

export interface StageResult {
  stage: PipelineStage;
  status: StageStatus;
  summary: string;
  metrics: Record<string, Scalar>;
  durationMs: number;
}

export type RiskCheckName =
  | 'TRADING_ENABLED'
  | 'NOT_HALTED'
  | 'MAX_POSITION_PERCENT'
  | 'MAX_DAILY_LOSS'
  | 'MAX_DRAWDOWN'
  | 'MAX_OPEN_POSITIONS'
  | 'MIN_LIQUIDITY'
  | 'MAX_RUG_SCORE'
  | 'MAX_SLIPPAGE'
  | 'MIN_TOKEN_AGE'
  | 'HONEYPOT_VERIFIED'
  | 'NO_CRITICAL_FLAGS'
  | 'DATA_FRESHNESS'
  | 'SUFFICIENT_CASH'
  | 'MIN_POSITION_SIZE'
  | 'NO_DUPLICATE_POSITION'
  | 'LIQUIDITY_SHARE'
  | 'LIVE_EXECUTION_SUPPORTED'
  | 'LLM_REVIEW';

export interface RiskCheckResult {
  check: RiskCheckName;
  passed: boolean;
  value: Scalar;
  limit: Scalar;
  message: string;
}

export interface PositionSizing {
  equityUsd: number;
  sizeUsd: number;
  byMaxPositionPercent: number;
  byRiskPerTrade: number;
  byLiquidityShare: number;
  byAvailableCash: number;
  confidenceMultiplier: number;
  limitingFactor: string;
  stopLossPrice: number;
  takeProfitPrice: number;
  expectedSlippagePct: number;
}

export interface Decision {
  id: number | null;
  chain: Chain;
  address: string;
  symbol: string | null;
  action: DecisionAction;
  /** Display label, e.g. "SKIP — HIGH RUG RISK". */
  label: string;
  reasonCode: string;
  confidence: number;
  reasons: string[];
  factors: Record<string, number | null>;
  stages: StageResult[];
  riskChecks: RiskCheckResult[];
  sizing: PositionSizing | null;
  rugScore: number | null;
  strategyScore: number | null;
  mode: TradingMode;
  executed: boolean;
  tradeId: number | null;
  createdAt: string;
}

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

export interface RiskLimits {
  /** Max size of one position as a percent of equity. */
  maxPositionPercent: number;
  /** Max loss for the UTC day as a percent of day-start equity. Halts new entries when breached. */
  maxDailyLossPercent: number;
  /** Max drawdown from peak equity, percent. Halts trading until manually reset. */
  maxDrawdownPercent: number;
  maxOpenPositions: number;
  minLiquidityUsd: number;
  maxRugScore: number;
  maxSlippagePercent: number;
  minTokenAgeMinutes: number;
  /** Position may not exceed this percent of pool liquidity. */
  maxLiquiditySharePercent: number;
  minPositionUsd: number;
  requireHoneypotCheck: boolean;
  maxDataAgeSeconds: number;
}

export interface StrategyParams {
  name: string;
  autoTrade: boolean;
  chains: Chain[];
  stopLossPercent: number;
  takeProfitPercent: number;
  trailingStopPercent: number | null;
  maxHoldMinutes: number;
  riskPerTradePercent: number;
  minStrategyScore: number;
  minBuySellRatio: number;
  minVolume1hUsd: number;
  maxPriceChange5mPercent: number;
  minPriceChange1hPercent: number;
  maxTokenAgeMinutes: number;
  exitOnRugScoreAbove: number;
  exitOnLiquidityDropPercent: number;
}

export interface EffectiveConfig {
  mode: TradingMode;
  hardLimits: RiskLimits;
  limits: RiskLimits;
  strategy: StrategyParams;
  version: number;
  updatedAt: string;
}
