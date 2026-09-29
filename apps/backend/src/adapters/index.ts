import type { Chain } from '@memeguard/shared';
import type { AppConfig } from '../config/env';
import { HttpClient, ProviderRegistry, type FetchLike } from '../lib/http';
import { JsonRpcClient } from '../lib/jsonRpc';
import type { Logger } from '../lib/logger';
import { DEXSCREENER_BASE_URL, DexScreenerAdapter } from './dexscreener';
import { ETHERSCAN_BASE_URL, EtherscanAdapter } from './etherscan';
import { EvmInspector } from './evm/inspector';
import { GECKOTERMINAL_BASE_URL, GECKOTERMINAL_HEADERS, GeckoTerminalAdapter } from './geckoterminal';
import { GOPLUS_BASE_URL, GoPlusAdapter } from './goplus';
import { HONEYPOT_IS_BASE_URL, HoneypotIsAdapter } from './honeypotis';
import { JupiterAdapter } from './jupiter';
import { RUGCHECK_BASE_URL, RugCheckAdapter } from './rugcheck';
import { XAdapter } from './x';
import { SolanaInspector } from './solana/inspector';
import { SolanaRpc } from './solana/rpc';
import { SolanaWalletProfiler } from './solana/walletProfiler';
import type {
  DeployerHistorySource,
  DeveloperActivitySource,
  DiscoveryProvider,
  MarketDataProvider,
  MarketFallbackProvider,
  OhlcvProvider,
  SecuritySource,
  TradeFeedProvider,
  WalletProfiler,
} from './types';

export interface Providers {
  registry: ProviderRegistry;
  discovery: DiscoveryProvider[];
  market: MarketDataProvider;
  marketFallback: MarketFallbackProvider;
  trades: TradeFeedProvider;
  ohlcv: OhlcvProvider;
  security: SecuritySource[];
  walletProfilers: WalletProfiler[];
  developerSources: DeveloperActivitySource[];
  deployerHistory: DeployerHistorySource[];
  solanaRpc: SolanaRpc | null;
  jupiter: JupiterAdapter;
  /** Official X API (read-only); null when X_BEARER_TOKEN is not set. */
  x: XAdapter | null;
}

export interface ProviderDeps {
  config: AppConfig;
  logger: Logger;
  registerSecret: (s: string) => void;
  fetchImpl?: FetchLike;
}

export function createProviders({ config, logger, registerSecret, fetchImpl }: ProviderDeps): Providers {
  const registry = new ProviderRegistry();
  const rpm = config.providers.rpm;
  const common = { logger, fetchImpl, timeoutMs: config.engine.sourceTimeoutMs };

  const http = (
    name: string,
    baseUrl: string,
    ratePerMinute: number,
    extra: Partial<ConstructorParameters<typeof HttpClient>[0]> = {},
  ) => registry.register(new HttpClient({ name, baseUrl, ratePerMinute, ...common, ...extra }));

  const dexscreener = new DexScreenerAdapter(http('dexscreener', DEXSCREENER_BASE_URL, rpm.dexscreener));
  const gecko = new GeckoTerminalAdapter(
    http('geckoterminal', GECKOTERMINAL_BASE_URL, rpm.geckoterminal, {
      headers: GECKOTERMINAL_HEADERS,
      burst: 2,
    }),
  );
  const goplus = new GoPlusAdapter(
    http('goplus', GOPLUS_BASE_URL, rpm.goplus, { burst: 2 }),
    { appKey: config.providers.goplusAppKey, appSecret: config.providers.goplusAppSecret },
    registerSecret,
  );
  const honeypot = new HoneypotIsAdapter(
    http('honeypot.is', HONEYPOT_IS_BASE_URL, rpm.honeypotIs, {
      headers: config.providers.honeypotIsApiKey ? { 'X-API-KEY': config.providers.honeypotIsApiKey } : {},
    }),
  );
  const rugcheck = new RugCheckAdapter(
    http('rugcheck', RUGCHECK_BASE_URL, rpm.rugcheck, {
      headers: config.providers.rugcheckApiKey
        ? { authorization: `Bearer ${config.providers.rugcheckApiKey}` }
        : {},
    }),
  );
  const jupiter = new JupiterAdapter(
    http('jupiter', config.providers.jupiterApiUrl, rpm.jupiter, {
      headers: config.providers.jupiterApiKey ? { 'x-api-key': config.providers.jupiterApiKey } : {},
      retries: 2,
    }),
  );

  const security: SecuritySource[] = [goplus, honeypot, rugcheck];
  const walletProfilers: WalletProfiler[] = [];
  const developerSources: DeveloperActivitySource[] = [];
  const deployerHistory: DeployerHistorySource[] = [];

  let solanaRpc: SolanaRpc | null = null;
  if (config.rpc.solana) {
    solanaRpc = new SolanaRpc(
      new JsonRpcClient(http('solana-rpc', config.rpc.solana, rpm.solanaRpc, { burst: 10 })),
    );
    security.push(new SolanaInspector(solanaRpc));
    const profiler = new SolanaWalletProfiler(solanaRpc, {
      freshWalletAgeHours: config.engine.freshWalletAgeHours,
    });
    walletProfilers.push(profiler);
    developerSources.push(profiler);
  } else {
    registry.register({ name: 'solana-rpc', health: () => notConfigured('solana-rpc') });
  }
  // Jupiter round-trip quotes are the Solana sellability check.
  security.push(jupiter);

  for (const [chain, url] of Object.entries(config.rpc.evm) as [Chain, string][]) {
    const client = new JsonRpcClient(http(`evm-rpc:${chain}`, url, rpm.evmRpc, { burst: 10 }));
    security.push(new EvmInspector(chain, client));
  }

  if (config.providers.etherscanApiKey) {
    const etherscan = new EtherscanAdapter(
      http('etherscan', ETHERSCAN_BASE_URL, rpm.etherscan, { burst: 3 }),
      config.providers.etherscanApiKey,
      { freshWalletAgeHours: config.engine.freshWalletAgeHours },
    );
    security.push(etherscan);
    walletProfilers.push(etherscan);
    developerSources.push(etherscan);
    deployerHistory.push(etherscan);
  } else {
    registry.register({ name: 'etherscan', health: () => notConfigured('etherscan') });
  }

  let x: XAdapter | null = null;
  if (config.x.bearerToken) {
    x = new XAdapter(
      http('x', config.x.apiUrl, config.x.rpm, {
        headers: { authorization: `Bearer ${config.x.bearerToken}` },
        burst: 3,
        retries: 2,
      }),
    );
  } else {
    registry.register({ name: 'x', health: () => notConfigured('x') });
  }

  const discovery: DiscoveryProvider[] = [];
  for (const src of config.engine.discoverySources) {
    if (src === 'geckoterminal') discovery.push(gecko);
    else if (src === 'dexscreener') discovery.push(dexscreener);
    else logger.warn({ source: src }, 'unknown discovery source ignored');
  }

  return {
    registry,
    discovery,
    market: dexscreener,
    marketFallback: gecko,
    trades: gecko,
    ohlcv: gecko,
    security,
    walletProfilers,
    developerSources,
    deployerHistory,
    solanaRpc,
    jupiter,
    x,
  };
}

function notConfigured(name: string) {
  return {
    name,
    configured: false,
    calls: 0,
    requests: 0,
    failures: 0,
    rateLimited: 0,
    consecutiveFailures: 0,
    circuitOpen: false,
    lastSuccessAt: null,
    lastError: null,
    lastErrorAt: null,
  };
}
