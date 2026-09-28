import type {
  Chain,
  DeveloperActivity,
  HolderInfo,
  SourceStatus,
  TokenSnapshot,
  TradeActivity,
  WalletAnalysis,
} from '@memeguard/shared';
import type { Providers } from '../adapters';
import type { MarketQuote, SnapshotContribution, TokenContext, WalletProfile } from '../adapters/types';
import { withTimeout } from '../lib/async';
import { errorMessage } from '../lib/errors';
import type { Logger } from '../lib/logger';
import { computeTradeActivity, circulatingHolders, computeWalletAnalysis } from './activity';
import {
  mergeContract,
  mergeDeployer,
  mergeHolders,
  mergeHoneypot,
  mergeLiquidity,
  mergeWarnings,
} from './merge';

/** Cache for wallet age/funder lookups (they never change, so they're persisted). */
export interface WalletCache {
  get(chain: Chain, addresses: string[]): Promise<Map<string, WalletProfile>>;
  put(chain: Chain, profiles: WalletProfile[]): Promise<void>;
}

export class MemoryWalletCache implements WalletCache {
  private readonly m = new Map<string, WalletProfile>();
  async get(chain: Chain, addresses: string[]) {
    const out = new Map<string, WalletProfile>();
    for (const a of addresses) {
      const p = this.m.get(`${chain}:${a}`);
      if (p) out.set(a, p);
    }
    return out;
  }
  async put(chain: Chain, profiles: WalletProfile[]) {
    for (const p of profiles) this.m.set(`${chain}:${p.address}`, p);
  }
}

export interface CollectOptions {
  chain: Chain;
  address: string;
  /** Hints from discovery (used when market data is unavailable). */
  hint?: {
    name?: string | null;
    symbol?: string | null;
    pairAddress?: string | null;
    dexId?: string | null;
    pairCreatedAt?: Date | null;
  };
  /** Previous snapshot: when security data is still fresh it is reused instead of re-fetched. */
  previous?: TokenSnapshot | null;
  refreshSecurity: boolean;
  /** Skip the expensive wallet/dev lookups (e.g. fast monitoring refresh). */
  lightweight?: boolean;
}

export interface CollectorDeps {
  providers: Providers;
  logger: Logger;
  walletCache: WalletCache;
  timeoutMs: number;
  walletAnalysisTopN: number;
  freshWalletAgeHours: number;
  now?: () => Date;
}

/**
 * Orchestrates every adapter for one token and merges the results into a TokenSnapshot.
 * Sources run in parallel with individual timeouts; failures are recorded (never thrown) so
 * missing data is visible to the rug model, which treats it as risk.
 */
export class SnapshotCollector {
  constructor(private readonly deps: CollectorDeps) {}

  private now(): Date {
    return this.deps.now?.() ?? new Date();
  }

  private async timed<T>(name: string, statuses: SourceStatus[], fn: () => Promise<T>): Promise<T | null> {
    const start = Date.now();
    try {
      const r = await withTimeout(fn(), this.deps.timeoutMs, name);
      statuses.push({ name, ok: true, durationMs: Date.now() - start, error: null });
      return r;
    } catch (err) {
      const msg = errorMessage(err).slice(0, 300);
      statuses.push({ name, ok: false, durationMs: Date.now() - start, error: msg });
      this.deps.logger.debug({ source: name, err: msg }, 'data source failed');
      return null;
    }
  }

  async collect(opts: CollectOptions): Promise<TokenSnapshot> {
    const { providers } = this.deps;
    const statuses: SourceStatus[] = [];
    const { chain, address } = opts;

    // 1. Market data (primary + fallback)
    let quote: MarketQuote | null = await this.timed(`market:${providers.market.name}`, statuses, () =>
      providers.market.getMarket(chain, address),
    );
    if (!quote) {
      const fb = await this.timed(`market:${providers.marketFallback.name}`, statuses, () =>
        providers.marketFallback.getTokenPools(chain, address),
      );
      if (fb) {
        quote = {
          market: fb,
          totalLiquidityUsd: fb.liquidityUsd,
          poolCount: 1,
          name: null,
          symbol: null,
          programControlledLiquidity: false,
        };
      }
    }
    const market = quote?.market ?? null;
    const ctx: TokenContext = {
      chain,
      address,
      pairAddress: market?.pairAddress ?? opts.hint?.pairAddress ?? null,
      dexId: market?.dexId ?? opts.hint?.dexId ?? null,
      priceUsd: market?.priceUsd ?? null,
      liquidityUsd: market?.liquidityUsd ?? null,
    };

    // 2. Security sources (or reuse cached security data)
    const prev = opts.previous ?? null;
    const reuse = !opts.refreshSecurity && prev !== null && prev.contract !== null;
    let contributions: SnapshotContribution[] = [];
    if (!reuse) {
      const sources = providers.security.filter((s) => s.supports(chain));
      const results = await Promise.all(
        sources.map((s) => this.timed(`security:${s.name}`, statuses, () => s.inspect(ctx))),
      );
      contributions = results.filter((r): r is SnapshotContribution => r !== null);
    }

    const contract = reuse ? prev.contract : mergeContract(contributions);
    const holders = reuse ? prev.holders : mergeHolders(chain, contributions);
    const liquidity = reuse
      ? prev.liquidity
        ? {
            ...prev.liquidity,
            totalLiquidityUsd:
              quote?.totalLiquidityUsd ?? market?.liquidityUsd ?? prev.liquidity.totalLiquidityUsd,
          }
        : null
      : mergeLiquidity(contributions, quote);
    const honeypot = reuse ? prev.honeypot : mergeHoneypot(contributions);
    const warnings = reuse ? prev.warnings : mergeWarnings(contributions);
    const reportedRugged = reuse
      ? prev.reportedRugged
      : contributions.some((c) => c.reportedRugged === true)
        ? true
        : contributions.some((c) => c.reportedRugged === false)
          ? false
          : null;
    let deployer = reuse ? prev.deployer : mergeDeployer(chain, contributions);

    // 3. Trade flow (wash trading / abnormal activity)
    let trades: TradeActivity | null = prev?.trades ?? null;
    if (ctx.pairAddress && !opts.lightweight) {
      const raw = await this.timed(`trades:${providers.trades.name}`, statuses, () =>
        providers.trades.getRecentTrades(chain, ctx.pairAddress as string),
      );
      trades = raw ? computeTradeActivity(raw, providers.trades.name) : trades;
    }

    // 4. Wallet analysis + deployer history + developer activity
    let wallets: WalletAnalysis | null = reuse ? prev.wallets : null;
    let developer: DeveloperActivity | null = prev?.developer ?? null;
    if (!opts.lightweight) {
      if (!reuse && holders && this.deps.walletAnalysisTopN > 0) {
        wallets = await this.walletAnalysis(chain, holders.topHolders, statuses);
      }
      if (deployer?.address && !reuse) {
        deployer = await this.enrichDeployer(chain, deployer, statuses);
      }
      if (deployer?.address) {
        const ageMin = market?.pairCreatedAt
          ? (this.now().getTime() - Date.parse(market.pairCreatedAt)) / 60_000
          : 1440;
        const lookback = Math.max(30, Math.min(1440, ageMin));
        const devSource = providers.developerSources.find((d) => d.supports(chain));
        if (devSource) {
          const act = await this.timed(`developer:${devSource.name}`, statuses, () =>
            devSource.activity(
              chain,
              {
                address,
                totalSupply: holders?.totalSupply ?? null,
                decimals:
                  contributions.find((c) => typeof c.decimals === 'number')?.decimals ??
                  prev?.decimals ??
                  null,
                pairAddress: ctx.pairAddress,
              },
              deployer?.address as string,
              lookback,
            ),
          );
          if (act) developer = act;
        }
      }
    }

    const nameSrc = contributions.find((c) => c.name);
    const symSrc = contributions.find((c) => c.symbol);
    const decSrc = contributions.find((c) => typeof c.decimals === 'number');
    return {
      chain,
      address,
      name: quote?.name ?? nameSrc?.name ?? opts.hint?.name ?? prev?.name ?? null,
      symbol: quote?.symbol ?? symSrc?.symbol ?? opts.hint?.symbol ?? prev?.symbol ?? null,
      decimals: decSrc?.decimals ?? prev?.decimals ?? null,
      collectedAt: this.now().toISOString(),
      market,
      contract,
      holders,
      liquidity,
      honeypot,
      deployer,
      trades,
      wallets,
      developer,
      warnings,
      reportedRugged,
      sources: statuses,
    };
  }

  private async walletAnalysis(
    chain: Chain,
    holders: HolderInfo[],
    statuses: SourceStatus[],
  ): Promise<WalletAnalysis | null> {
    const profiler = this.deps.providers.walletProfilers.find((p) => p.supports(chain));
    if (!profiler) return null;
    const targets = circulatingHolders(holders, chain).slice(0, this.deps.walletAnalysisTopN);
    if (targets.length === 0) return null;
    const addresses = targets.map((t) => t.address);
    const cached = await this.deps.walletCache.get(chain, addresses);
    const missing = addresses.filter((a) => !cached.has(a));
    if (missing.length > 0) {
      const fresh = await this.timed(`wallets:${profiler.name}`, statuses, () =>
        profiler.profile(chain, missing),
      );
      if (fresh) {
        for (const [k, v] of fresh) cached.set(k, v);
        await this.deps.walletCache.put(chain, [...fresh.values()]).catch(() => undefined);
      }
    }
    return computeWalletAnalysis(targets, cached, {
      freshWalletAgeHours: this.deps.freshWalletAgeHours,
      now: this.now(),
      sources: [profiler.name],
    });
  }

  private async enrichDeployer(
    chain: Chain,
    deployer: NonNullable<TokenSnapshot['deployer']>,
    statuses: SourceStatus[],
  ): Promise<NonNullable<TokenSnapshot['deployer']>> {
    const address = deployer.address as string;
    const out = { ...deployer, sources: [...deployer.sources] };
    const hist = this.deps.providers.deployerHistory.find((d) => d.supports(chain));
    if (hist) {
      const h = await this.timed(`deployer:${hist.name}`, statuses, () => hist.history(chain, address));
      if (h) {
        out.tokensCreated = Math.max(out.tokensCreated ?? 0, h.tokensCreated ?? 0);
        if (h.walletCreatedAt)
          out.walletAgeDays = (this.now().getTime() - h.walletCreatedAt.getTime()) / 86_400_000;
        out.sources.push(hist.name);
      }
    }
    if (out.walletAgeDays === null) {
      const cached = await this.deps.walletCache.get(chain, [address]);
      let profile = cached.get(address);
      const profiler = this.deps.providers.walletProfilers.find((p) => p.supports(chain));
      if (!profile && profiler) {
        const r = await this.timed(`deployer-age:${profiler.name}`, statuses, () =>
          profiler.profile(chain, [address]),
        );
        profile = r?.get(address);
        if (profile) await this.deps.walletCache.put(chain, [profile]).catch(() => undefined);
      }
      if (profile?.createdAt && !profile.ageIsLowerBound) {
        out.walletAgeDays = (this.now().getTime() - profile.createdAt.getTime()) / 86_400_000;
      }
    }
    return out;
  }
}
