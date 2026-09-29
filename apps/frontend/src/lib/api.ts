import type {
  Alert,
  BacktestResult,
  Decision,
  EffectiveConfig,
  Paginated,
  PaperTradeRequest,
  PaperTradeResponse,
  PerformanceSummary,
  Position,
  RiskReport,
  ScanRequest,
  ScanResponse,
  SniperStatus,
  SocialStatus,
  StrategyUpdateRequest,
  SystemStatus,
  TokenDetail,
  TokenListItem,
  Trade,
  Chain,
  HolderData,
  WalletAnalysis,
  DeployerProfile,
  DeveloperActivity,
  TradeActivity,
} from '@memeguard/shared';

export const API_BASE = (import.meta.env.VITE_API_BASE as string | undefined) ?? '/api';

const KEY_STORAGE = 'memeguard.adminKey';

/** The admin key lives only in this browser's storage (never in URLs or logs). */
export const adminKey = {
  get(): string | null {
    try {
      return window.sessionStorage.getItem(KEY_STORAGE) ?? window.localStorage.getItem(KEY_STORAGE);
    } catch {
      return null;
    }
  },
  set(key: string, remember: boolean): void {
    try {
      window.sessionStorage.setItem(KEY_STORAGE, key);
      if (remember) window.localStorage.setItem(KEY_STORAGE, key);
      else window.localStorage.removeItem(KEY_STORAGE);
    } catch {
      /* storage unavailable: key lasts for this page only */
    }
    memoryKey = key;
  },
  clear(): void {
    try {
      window.sessionStorage.removeItem(KEY_STORAGE);
      window.localStorage.removeItem(KEY_STORAGE);
    } catch {
      /* ignore */
    }
    memoryKey = null;
  },
};
let memoryKey: string | null = null;
const currentKey = () => adminKey.get() ?? memoryKey;

export class ApiError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message: string,
    public readonly issues?: string[],
  ) {
    super(message);
  }
}

export function authHeaders(): Record<string, string> {
  const k = currentKey();
  return k ? { authorization: `Bearer ${k}` } : {};
}

async function request<T>(
  method: 'GET' | 'POST',
  path: string,
  body?: unknown,
  query?: Record<string, unknown>,
): Promise<T> {
  // Relative URL built without window.location.origin, which is "null" in sandboxed frames.
  const params = new URLSearchParams();
  for (const [k, v] of Object.entries(query ?? {})) {
    if (v !== undefined && v !== null && v !== '') params.set(k, String(v));
  }
  const qs = params.toString();
  const res = await fetch(`${API_BASE}${path}${qs ? `?${qs}` : ''}`, {
    method,
    headers: { ...(body !== undefined ? { 'content-type': 'application/json' } : {}), ...authHeaders() },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  const data = text ? (JSON.parse(text) as unknown) : null;
  if (!res.ok) {
    const d = (data ?? {}) as { error?: string; message?: string; issues?: string[] };
    throw new ApiError(res.status, d.error ?? 'error', d.message ?? res.statusText, d.issues);
  }
  return data as T;
}

export interface TokenQuery {
  limit?: number;
  offset?: number;
  sort?:
    | 'rugScore'
    | 'lastAnalyzedAt'
    | 'firstSeenAt'
    | 'liquidityUsd'
    | 'volume24hUsd'
    | 'marketCapUsd'
    | 'pairCreatedAt';
  order?: 'asc' | 'desc';
  chain?: Chain;
  risk?: 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL';
  search?: string;
  analyzedOnly?: boolean;
}

export interface WalletView {
  holders: HolderData | null;
  walletAnalysis: WalletAnalysis | null;
  deployer: DeployerProfile | null;
  developer: DeveloperActivity | null;
  trades: TradeActivity | null;
  wallets: {
    address: string;
    role: string;
    percent: number | null;
    clusterFunder: string | null;
    label: string | null;
    walletCreatedAt: string | null;
    ageIsLowerBound: boolean;
    fundedBy: string | null;
  }[];
  transactions: {
    id: number;
    txHash: string;
    kind: string;
    percentOfSupply: number | null;
    counterparty: string | null;
    blockTime: string | null;
  }[];
}

export interface LogEntry {
  id: number;
  level: string;
  category: string;
  message: string;
  tokenId: number | null;
  data: Record<string, unknown>;
  createdAt: string;
}

export const api = {
  status: () => request<SystemStatus>('GET', '/status'),
  config: () => request<{ effective: EffectiveConfig; system: Record<string, unknown> }>('GET', '/config'),
  tokens: (q: TokenQuery) =>
    request<Paginated<TokenListItem>>('GET', '/tokens', undefined, q as Record<string, unknown>),
  token: (address: string, chain?: Chain) =>
    request<TokenDetail>('GET', `/tokens/${encodeURIComponent(address)}`, undefined, { chain }),
  wallets: (address: string, chain?: Chain) =>
    request<WalletView>('GET', `/tokens/${encodeURIComponent(address)}/wallets`, undefined, { chain }),
  risk: (address: string, chain?: Chain) =>
    request<RiskReport>('GET', `/risk/${encodeURIComponent(address)}`, undefined, { chain }),
  positions: (status: 'open' | 'closed' | 'all' = 'all') =>
    request<{ items: Position[] }>('GET', '/positions', undefined, { status }),
  trades: (limit = 100, offset = 0) =>
    request<Paginated<Trade>>('GET', '/trades', undefined, { limit, offset }),
  performance: () => request<PerformanceSummary>('GET', '/performance'),
  sniper: () => request<SniperStatus>('GET', '/sniper'),
  social: () => request<SocialStatus>('GET', '/social'),
  decisions: (limit = 50, action?: Decision['action']) =>
    request<{ items: Decision[] }>('GET', '/decisions', undefined, { limit, action }),
  alerts: (q: {
    limit?: number;
    offset?: number;
    severity?: string;
    type?: string;
    unacknowledged?: boolean;
  }) => request<Paginated<Alert> & { unacknowledged: number }>('GET', '/alerts', undefined, q),
  logs: (q: { limit?: number; category?: string; level?: string }) =>
    request<{ items: LogEntry[] }>('GET', '/logs', undefined, q),
  backtests: () =>
    request<{
      items: {
        id: number;
        name: string;
        source: string;
        synthetic: boolean;
        createdAt: string;
        metrics: BacktestResult['metrics'];
      }[];
    }>('GET', '/backtests'),
  backtest: (id: number) => request<BacktestResult>('GET', `/backtests/${id}`),

  // admin
  scan: (body: ScanRequest) => request<ScanResponse>('POST', '/scan', body),
  discover: () => request<{ queued: boolean }>('POST', '/scan', { discover: true }),
  paperTrade: (body: PaperTradeRequest) => request<PaperTradeResponse>('POST', '/paper-trade', body),
  closePosition: (id: number) =>
    request<{ closed: boolean; trade: Trade | null; position: Position }>(
      'POST',
      `/positions/${id}/close`,
      {},
    ),
  updateStrategy: (body: StrategyUpdateRequest) => request<EffectiveConfig>('POST', '/strategy', body),
  engineStart: () => request<{ engineRunning: boolean }>('POST', '/engine/start', {}),
  engineStop: () => request<{ engineRunning: boolean; note: string }>('POST', '/engine/stop', {}),
  resume: () => request<{ halted: boolean }>('POST', '/risk/resume', {}),
  ackAlert: (id: number) => request<{ acknowledged: boolean }>('POST', `/alerts/${id}/ack`, {}),
  ackAll: () => request<{ acknowledged: number }>('POST', '/alerts/ack-all', {}),
  runBacktest: (body: {
    source: 'synthetic' | 'database';
    tokens?: number;
    seed?: string | number;
    assumeCleanSecurity?: boolean;
    startingBalanceUsd?: number;
  }) => request<BacktestResult>('POST', '/backtest', body),
};
