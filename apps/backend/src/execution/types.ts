import type { Chain, MarketData, TradingMode } from '@memeguard/shared';

export interface ExecutionRequest {
  side: 'buy' | 'sell';
  chain: Chain;
  address: string;
  decimals: number | null;
  market: MarketData;
  /** Buy: USD to spend (fees included). */
  amountUsd?: number;
  /** Sell: tokens to sell (UI units). */
  quantity?: number;
  /** Sell (live): exact raw base-unit amount when known. */
  rawQuantity?: string | null;
  maxSlippagePct: number;
  taxes: { buyPct: number; sellPct: number };
}

export interface ExecutionResult {
  status: 'filled' | 'failed';
  /** Buy: total USD debited. Sell: net USD credited. */
  filledUsd: number;
  quantity: number;
  rawQuantity: string | null;
  avgPriceUsd: number | null;
  /** Execution price vs mid price, percent (positive = worse for us). */
  slippagePct: number | null;
  /** DEX + network fees in USD (charged even when a transaction fails). */
  feeUsd: number;
  txHash: string | null;
  error: string | null;
  raw?: Record<string, unknown>;
}

export interface TradeExecutor {
  readonly mode: TradingMode;
  supports(chain: Chain): boolean;
  networkFeeUsd(chain: Chain): number;
  execute(req: ExecutionRequest): Promise<ExecutionResult>;
  /** Live executors report the wallet's spendable balance in USD. */
  walletCashUsd?(): Promise<number>;
}
