import type { Database } from '../client';
import { DecisionsRepository, HistoryRepository, RiskScoresRepository } from './analysis';
import {
  AlertsRepository,
  BacktestRepository,
  EventLogRepository,
  StrategyConfigRepository,
  TransactionsRepository,
  WalletsRepository,
} from './misc';
import { SocialRepository } from './social';
import { TokensRepository } from './tokens';
import { AccountsRepository, PerformanceRepository, PositionsRepository, TradesRepository } from './trading';

export interface Repositories {
  tokens: TokensRepository;
  risk: RiskScoresRepository;
  decisions: DecisionsRepository;
  history: HistoryRepository;
  positions: PositionsRepository;
  trades: TradesRepository;
  accounts: AccountsRepository;
  performance: PerformanceRepository;
  alerts: AlertsRepository;
  strategy: StrategyConfigRepository;
  events: EventLogRepository;
  backtests: BacktestRepository;
  wallets: WalletsRepository;
  transactions: TransactionsRepository;
  social: SocialRepository;
}

export function createRepositories(db: Database): Repositories {
  return {
    tokens: new TokensRepository(db),
    risk: new RiskScoresRepository(db),
    decisions: new DecisionsRepository(db),
    history: new HistoryRepository(db),
    positions: new PositionsRepository(db),
    trades: new TradesRepository(db),
    accounts: new AccountsRepository(db),
    performance: new PerformanceRepository(db),
    alerts: new AlertsRepository(db),
    strategy: new StrategyConfigRepository(db),
    events: new EventLogRepository(db),
    backtests: new BacktestRepository(db),
    wallets: new WalletsRepository(db),
    transactions: new TransactionsRepository(db),
    social: new SocialRepository(db),
  };
}

export * from './analysis';
export * from './misc';
export * from './social';
export * from './tokens';
export * from './trading';
