import type { Chain } from '@memeguard/shared';
import { createRng } from '../lib/math';
import { NETWORK_FEE_USD, simulateBuy, simulateSell } from './amm';
import type { ExecutionRequest, ExecutionResult, TradeExecutor } from './types';

export interface PaperExecutorOptions {
  dexFeePct: number;
  failureRate: number;
  seed?: string | number | null;
  /** Max random adverse price move between decision and inclusion, percent. */
  maxLatencyDriftPct?: number;
  /** A single order may not consume more than this share of the quote reserve. */
  maxReserveShare?: number;
}

const FAILURE_REASONS = [
  'simulated failure: transaction expired before inclusion (blockhash not found)',
  'simulated failure: RPC node timed out while sending transaction',
  'simulated failure: transaction dropped due to network congestion',
];

/**
 * Paper-trading venue. Simulates what a real swap would do:
 *  - constant-product price impact against the pool's liquidity
 *  - DEX fee and chain network fee (the network fee is charged even when a tx fails)
 *  - token buy/sell taxes reported by the security analysis
 *  - adverse latency drift, and slippage-tolerance reverts when impact + drift > max slippage
 *  - random transaction failures at a configurable rate
 *  - liquidity limits: orders larger than a share of the pool are rejected
 * No funds move; results are deterministic when a seed is configured.
 */
export class PaperExecutor implements TradeExecutor {
  readonly mode = 'paper' as const;
  private readonly rng: () => number;

  constructor(private readonly opts: PaperExecutorOptions) {
    this.rng = createRng(opts.seed ?? null);
  }

  supports(): boolean {
    return true;
  }

  networkFeeUsd(chain: Chain): number {
    return NETWORK_FEE_USD[chain];
  }

  async execute(req: ExecutionRequest): Promise<ExecutionResult> {
    const fee = this.networkFeeUsd(req.chain);
    const mid = req.market.priceUsd;
    const liq = req.market.liquidityUsd;
    const fail = (error: string, extra: Partial<ExecutionResult> = {}): ExecutionResult => ({
      status: 'failed',
      filledUsd: 0,
      quantity: 0,
      rawQuantity: null,
      avgPriceUsd: null,
      slippagePct: null,
      feeUsd: fee,
      txHash: null,
      error,
      ...extra,
    });

    if (mid === null || mid <= 0) return fail('no valid price');
    if (liq === null || liq <= 0) return fail('no liquidity in pool');
    if (this.rng() < this.opts.failureRate) {
      return fail(FAILURE_REASONS[Math.floor(this.rng() * FAILURE_REASONS.length)] as string);
    }
    // Price may move against us while the transaction is in flight.
    const drift = this.rng() * (this.opts.maxLatencyDriftPct ?? 0.5);
    const maxShare = this.opts.maxReserveShare ?? 0.3;
    const quoteReserve = liq / 2;
    const txHash = `paper-${Date.now().toString(36)}-${Math.floor(this.rng() * 1e9).toString(36)}`;

    if (req.side === 'buy') {
      const usd = req.amountUsd ?? 0;
      if (!(usd > 0)) return fail('invalid buy amount');
      if (usd > quoteReserve * maxShare) return fail('insufficient liquidity for order size (would exceed pool reserve share)');
      const execMid = mid * (1 + drift / 100);
      const sim = simulateBuy(usd, execMid, liq, this.opts.dexFeePct, req.taxes.buyPct);
      const slippagePct = ((sim.avgPriceUsd - mid) / mid) * 100;
      const slippageExTax = sim.priceImpactPct + drift;
      if (slippageExTax > req.maxSlippagePct) {
        return fail(`slippage tolerance exceeded: ${slippageExTax.toFixed(2)}% > ${req.maxSlippagePct}% (transaction reverted)`);
      }
      return {
        status: 'filled',
        filledUsd: usd + fee,
        quantity: sim.tokensOut,
        rawQuantity: null,
        avgPriceUsd: (usd + fee) / sim.tokensOut,
        slippagePct,
        feeUsd: sim.dexFeeUsd + fee,
        txHash,
        error: null,
        raw: { priceImpactPct: sim.priceImpactPct, driftPct: drift, midPriceUsd: mid, buyTaxPct: req.taxes.buyPct },
      };
    }

    const qty = req.quantity ?? 0;
    if (!(qty > 0)) return fail('invalid sell quantity');
    const execMid = mid * (1 - drift / 100);
    const sim = simulateSell(qty, execMid, liq, this.opts.dexFeePct, req.taxes.sellPct);
    const slippageExTax = sim.priceImpactPct + drift;
    if (slippageExTax > req.maxSlippagePct) {
      return fail(`slippage tolerance exceeded: ${slippageExTax.toFixed(2)}% > ${req.maxSlippagePct}% (transaction reverted)`);
    }
    const net = sim.usdOut - fee;
    return {
      status: 'filled',
      filledUsd: net,
      quantity: qty,
      rawQuantity: null,
      avgPriceUsd: net / qty,
      slippagePct: ((mid - net / qty) / mid) * 100,
      feeUsd: sim.dexFeeUsd + fee,
      txHash,
      error: null,
      raw: { priceImpactPct: sim.priceImpactPct, driftPct: drift, midPriceUsd: mid, sellTaxUsd: sim.taxUsd },
    };
  }
}
