import type {
  Chain,
  ContractData,
  DeployerProfile,
  DeveloperActivity,
  HolderInfo,
  HoneypotSimulation,
  LiquidityData,
  MarketData,
  ProviderWarning,
  TradeActivity,
  WalletAnalysis,
} from '@memeguard/shared';

/**
 * Adapter contracts. Every external dependency (market data, security scanners, chain RPC,
 * execution venues) sits behind one of these interfaces so it can be swapped or mocked.
 */

export interface DiscoveredPair {
  chain: Chain;
  tokenAddress: string;
  name: string | null;
  symbol: string | null;
  pairAddress: string | null;
  dexId: string | null;
  pairCreatedAt: Date | null;
  liquidityUsd: number | null;
  source: string;
}

export interface DiscoveryProvider {
  readonly name: string;
  supports(chain: Chain): boolean;
  discover(chain: Chain): Promise<DiscoveredPair[]>;
}

export interface MarketQuote {
  market: MarketData;
  /** Summed over every pool where the token is the base asset. */
  totalLiquidityUsd: number | null;
  poolCount: number;
  name: string | null;
  symbol: string | null;
  /** Liquidity is controlled by a launchpad bonding-curve program rather than withdrawable LP. */
  programControlledLiquidity: boolean;
  /** The token's own X (Twitter) account, when the listing names one. */
  xHandle?: string | null;
}

export interface MarketDataProvider {
  readonly name: string;
  getMarket(chain: Chain, address: string): Promise<MarketQuote | null>;
  /** Batch lookup; returns entries keyed by the (normalised) token address. */
  getMarkets(chain: Chain, addresses: string[]): Promise<Map<string, MarketQuote>>;
}

/** Fallback market lookup (deepest pool for a token) when the primary provider has no data. */
export interface MarketFallbackProvider {
  readonly name: string;
  getTokenPools(chain: Chain, address: string): Promise<MarketData | null>;
}

export interface RawTrade {
  txHash: string;
  wallet: string;
  kind: 'buy' | 'sell';
  volumeUsd: number;
  timestamp: Date;
}

export interface TradeFeedProvider {
  readonly name: string;
  getRecentTrades(chain: Chain, pairAddress: string): Promise<RawTrade[]>;
}

export interface OhlcvBar {
  ts: Date;
  open: number;
  high: number;
  low: number;
  close: number;
  volumeUsd: number;
}

export interface OhlcvProvider {
  readonly name: string;
  getOhlcv(
    chain: Chain,
    pairAddress: string,
    opts: { timeframe: 'minute' | 'hour' | 'day'; aggregate: number; limit: number; before?: Date },
  ): Promise<OhlcvBar[]>;
}

/** Partial data contributed by one security/chain source, merged by the SnapshotCollector. */
export interface SnapshotContribution {
  source: string;
  name?: string | null;
  symbol?: string | null;
  decimals?: number | null;
  contract?: Partial<ContractData>;
  holders?: { holderCount?: number | null; topHolders?: HolderInfo[]; totalSupply?: number | null };
  liquidity?: Partial<LiquidityData>;
  honeypot?: HoneypotSimulation;
  deployer?: Partial<DeployerProfile>;
  warnings?: ProviderWarning[];
  reportedRugged?: boolean | null;
}

export interface TokenContext {
  chain: Chain;
  address: string;
  pairAddress: string | null;
  dexId: string | null;
  priceUsd: number | null;
  liquidityUsd: number | null;
}

export interface SecuritySource {
  readonly name: string;
  supports(chain: Chain): boolean;
  inspect(ctx: TokenContext): Promise<SnapshotContribution | null>;
}

export interface WalletProfile {
  address: string;
  createdAt: Date | null;
  ageIsLowerBound: boolean;
  fundedBy: string | null;
}

export interface WalletProfiler {
  readonly name: string;
  supports(chain: Chain): boolean;
  profile(chain: Chain, addresses: string[]): Promise<Map<string, WalletProfile>>;
}

export interface DeveloperActivitySource {
  readonly name: string;
  supports(chain: Chain): boolean;
  activity(
    chain: Chain,
    token: {
      address: string;
      totalSupply: number | null;
      decimals: number | null;
      pairAddress: string | null;
    },
    devAddress: string,
    lookbackMinutes: number,
  ): Promise<DeveloperActivity>;
}

export interface DeployerHistorySource {
  readonly name: string;
  supports(chain: Chain): boolean;
  history(
    chain: Chain,
    deployer: string,
  ): Promise<{ tokensCreated: number | null; walletCreatedAt: Date | null }>;
}

export type { TradeActivity, WalletAnalysis };
