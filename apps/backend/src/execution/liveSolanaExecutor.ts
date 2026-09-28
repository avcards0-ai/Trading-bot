import type { Chain } from '@memeguard/shared';
import { SOL_MINT } from '../adapters/chains';
import type { JupiterAdapter } from '../adapters/jupiter';
import type { Signer } from '../adapters/solana/keys';
import type { SolanaRpc } from '../adapters/solana/rpc';
import { signSerializedTransaction } from '../adapters/solana/transaction';
import { lamportDelta, tokenDelta } from '../adapters/solana/walletProfiler';
import { sleep } from '../lib/async';
import { errorMessage } from '../lib/errors';
import type { Logger } from '../lib/logger';
import { toNum } from '../lib/math';
import type { ExecutionRequest, ExecutionResult, TradeExecutor } from './types';

const LAMPORTS = 1_000_000_000;
/** SOL kept aside for fees/rent; never spent on trades. */
const SOL_RESERVE = 0.02;

/**
 * LIVE Solana execution through the Jupiter aggregator. Only constructed when live trading is
 * armed (see config). Safety measures:
 *  - quotes whose price impact exceeds the limit are rejected before any transaction is built
 *  - the swap carries slippageBps so the chain reverts if the price moves past tolerance
 *  - the transaction is signed only if our wallet is its fee payer and sole missing signer
 *  - confirmation is polled until confirmed or the blockhash expires; unknown outcomes are
 *    reported as failures with the signature so they can be reconciled manually
 */
export class LiveSolanaExecutor implements TradeExecutor {
  readonly mode = 'live' as const;
  private solPrice: { value: number; at: number } | null = null;

  constructor(
    private readonly deps: { rpc: SolanaRpc; jupiter: JupiterAdapter; signer: Signer; logger: Logger },
  ) {}

  get walletAddress(): string {
    return this.deps.signer.publicKey;
  }

  supports(chain: Chain): boolean {
    return chain === 'solana';
  }

  networkFeeUsd(): number {
    return this.solPrice ? 0.00005 * this.solPrice.value + 0.002 * this.solPrice.value : 0.3;
  }

  private async solUsd(): Promise<number> {
    if (this.solPrice && Date.now() - this.solPrice.at < 30_000) return this.solPrice.value;
    const p = await this.deps.jupiter.priceUsd(SOL_MINT);
    if (!p || p <= 0) throw new Error('SOL price unavailable');
    this.solPrice = { value: p, at: Date.now() };
    return p;
  }

  async walletCashUsd(): Promise<number> {
    const [lamports, price] = await Promise.all([
      this.deps.rpc.getBalance(this.walletAddress),
      this.solUsd(),
    ]);
    return Math.max(0, lamports / LAMPORTS - SOL_RESERVE) * price;
  }

  async execute(req: ExecutionRequest): Promise<ExecutionResult> {
    if (req.chain !== 'solana') return this.failed(`live execution not supported on ${req.chain}`, 0);
    try {
      return req.side === 'buy' ? await this.buy(req) : await this.sell(req);
    } catch (err) {
      this.deps.logger.error(
        { err: errorMessage(err), side: req.side, token: req.address },
        'live execution error',
      );
      return this.failed(errorMessage(err), 0);
    }
  }

  private failed(error: string, feeUsd: number, txHash: string | null = null): ExecutionResult {
    return {
      status: 'failed',
      filledUsd: 0,
      quantity: 0,
      rawQuantity: null,
      avgPriceUsd: null,
      slippagePct: null,
      feeUsd,
      txHash,
      error,
    };
  }

  private async buy(req: ExecutionRequest): Promise<ExecutionResult> {
    const usd = req.amountUsd ?? 0;
    const solPrice = await this.solUsd();
    const lamports = BigInt(Math.floor((usd / solPrice) * LAMPORTS));
    if (lamports <= 0n) return this.failed('buy amount too small', 0);
    const quote = await this.deps.jupiter.quote(
      SOL_MINT,
      req.address,
      lamports,
      Math.round(req.maxSlippagePct * 100),
    );
    if (!quote) return this.failed('no swap route available', 0);
    const impact = (toNum(quote.priceImpactPct) ?? 0) * 100;
    if (impact > req.maxSlippagePct) {
      return this.failed(
        `quoted price impact ${impact.toFixed(2)}% exceeds ${req.maxSlippagePct}% (no transaction sent)`,
        0,
      );
    }
    const outcome = await this.swapAndConfirm(quote);
    if (!outcome.ok) return this.failed(outcome.error, outcome.feeUsd, outcome.signature);
    const tx = await this.deps.rpc.getParsedTransaction(outcome.signature);
    const received = tx ? tokenDelta(tx, this.walletAddress, req.address) : 0;
    const decimals = req.decimals ?? 0;
    const solDelta = tx ? lamportDelta(tx, this.walletAddress) : null;
    // Actual SOL spent (swap + fees + token-account rent) when the tx is readable, else the quote.
    const spentUsd =
      solDelta !== null
        ? (-solDelta / LAMPORTS) * solPrice
        : (Number(lamports) / LAMPORTS) * solPrice + outcome.feeUsd;
    if (received <= 0) {
      return this.failed(
        'transaction confirmed but no tokens received — reconcile manually',
        outcome.feeUsd,
        outcome.signature,
      );
    }
    const mid = req.market.priceUsd ?? spentUsd / received;
    return {
      status: 'filled',
      filledUsd: spentUsd,
      quantity: received,
      rawQuantity: BigInt(Math.round(received * 10 ** decimals)).toString(),
      avgPriceUsd: spentUsd / received,
      slippagePct: ((spentUsd / received - mid) / mid) * 100,
      feeUsd: outcome.feeUsd,
      txHash: outcome.signature,
      error: null,
      raw: { quotedPriceImpactPct: impact, inAmountLamports: quote.inAmount, outAmount: quote.outAmount },
    };
  }

  private async sell(req: ExecutionRequest): Promise<ExecutionResult> {
    const onChain = await this.deps.rpc.getTokenBalanceForOwner(this.walletAddress, req.address);
    let raw = req.rawQuantity
      ? BigInt(req.rawQuantity)
      : BigInt(Math.floor((req.quantity ?? 0) * 10 ** onChain.decimals));
    if (raw > onChain.raw) raw = onChain.raw; // never try to sell more than we hold
    if (raw <= 0n) return this.failed('no token balance to sell', 0);
    const quote = await this.deps.jupiter.quote(
      req.address,
      SOL_MINT,
      raw,
      Math.round(req.maxSlippagePct * 100),
    );
    if (!quote) return this.failed('no route to sell token', 0);
    const impact = (toNum(quote.priceImpactPct) ?? 0) * 100;
    if (impact > req.maxSlippagePct) {
      return this.failed(
        `quoted price impact ${impact.toFixed(2)}% exceeds exit limit ${req.maxSlippagePct}%`,
        0,
      );
    }
    const solPrice = await this.solUsd();
    const outcome = await this.swapAndConfirm(quote);
    if (!outcome.ok) return this.failed(outcome.error, outcome.feeUsd, outcome.signature);
    const tx = await this.deps.rpc.getParsedTransaction(outcome.signature);
    const sold = tx ? -tokenDelta(tx, this.walletAddress, req.address) : Number(raw) / 10 ** onChain.decimals;
    const solDelta = tx ? lamportDelta(tx, this.walletAddress) : null;
    const proceedsUsd =
      solDelta !== null
        ? (solDelta / LAMPORTS) * solPrice
        : (Number(BigInt(quote.outAmount)) / LAMPORTS) * solPrice - outcome.feeUsd;
    const mid = req.market.priceUsd ?? proceedsUsd / Math.max(sold, 1e-18);
    return {
      status: 'filled',
      filledUsd: proceedsUsd,
      quantity: sold,
      rawQuantity: raw.toString(),
      avgPriceUsd: proceedsUsd / Math.max(sold, 1e-18),
      slippagePct: ((mid - proceedsUsd / Math.max(sold, 1e-18)) / mid) * 100,
      feeUsd: outcome.feeUsd,
      txHash: outcome.signature,
      error: null,
      raw: { quotedPriceImpactPct: impact, outAmountLamports: quote.outAmount },
    };
  }

  private async swapAndConfirm(
    quote: Awaited<ReturnType<JupiterAdapter['quote']>> & object,
  ): Promise<
    | { ok: true; signature: string; feeUsd: number }
    | { ok: false; signature: string | null; error: string; feeUsd: number }
  > {
    const swap = await this.deps.jupiter.buildSwap(quote, this.walletAddress);
    const { signedBase64, signature } = signSerializedTransaction(swap.swapTransaction, this.deps.signer);
    const feeUsd = this.networkFeeUsd();
    await this.deps.rpc.sendRawTransaction(signedBase64);
    this.deps.logger.info({ signature }, 'live swap submitted');
    const deadline = Date.now() + 120_000;
    while (Date.now() < deadline) {
      await sleep(2_000);
      const status = await this.deps.rpc.getSignatureStatus(signature).catch(() => null);
      if (status?.err)
        return {
          ok: false,
          signature,
          error: `transaction failed on-chain: ${JSON.stringify(status.err)}`,
          feeUsd,
        };
      if (status?.confirmationStatus === 'confirmed' || status?.confirmationStatus === 'finalized') {
        return { ok: true, signature, feeUsd };
      }
      const height = await this.deps.rpc.getBlockHeight().catch(() => null);
      if (height !== null && height > swap.lastValidBlockHeight) {
        return { ok: false, signature, error: 'transaction expired (blockhash no longer valid)', feeUsd: 0 };
      }
    }
    return {
      ok: false,
      signature,
      error: 'confirmation status unknown after 120s — reconcile manually',
      feeUsd,
    };
  }
}
