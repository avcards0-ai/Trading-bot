import fs from 'node:fs';
import { parseArgs } from 'node:util';
import type { BacktestResult } from '@memeguard/shared';
import { runBacktest } from '../backtest/engine';
import { loadDatasetFromDatabase, loadDatasetFromFile } from '../backtest/sources';
import { generateSyntheticDataset } from '../backtest/synthetic';
import type { BacktestDataset } from '../backtest/types';
import { loadConfig } from '../config/env';
import { loadEnvFile } from '../config/loadEnv';
import { StrategyStore } from '../config/strategyStore';
import { createDatabase } from '../db/client';
import { createRepositories } from '../db/repositories';
import { errorMessage } from '../lib/errors';

const USAGE = `Usage: npm run backtest -- [options]

  --source synthetic|file|db   data source (default: synthetic)
  --file <path>                dataset JSON (with --source file)
  --tokens <n>                 synthetic token count / max db tokens (default 200)
  --seed <seed>                PRNG seed (default 42)
  --balance <usd>              starting balance (default PAPER_STARTING_BALANCE_USD)
  --assume-clean-security      treat tokens WITHOUT security data as clean (optimistic!)
  --save                       store the result in the database (visible in the dashboard)
  --out <path>                 write the full JSON result to a file`;

function fmt(n: number | null, suffix = ''): string {
  return n === null ? 'n/a' : `${n.toLocaleString('en-US', { maximumFractionDigits: 2 })}${suffix}`;
}

function print(r: BacktestResult) {
  const m = r.metrics;
  const row = (k: string, v: string) => console.log(`  ${k.padEnd(30)} ${v}`);
  console.log(`\nBACKTEST: ${r.name} (${r.source}${r.syntheticData ? ', SYNTHETIC' : ''})`);
  row('Starting balance', `$${fmt(m.startingBalanceUsd)}`);
  row('Ending balance', `$${fmt(m.endingBalanceUsd)}`);
  row('Total return', fmt(m.totalReturnPct, '%'));
  row('Maximum drawdown', `${fmt(m.maxDrawdownPct, '%')} ($${fmt(m.maxDrawdownUsd)})`);
  row('Number of trades', fmt(m.numberOfTrades));
  row('Winning / losing trades', `${m.winningTrades} / ${m.losingTrades}`);
  row('Win rate', m.winRate === null ? 'n/a' : fmt(m.winRate * 100, '%'));
  row('Average win / loss', `$${fmt(m.averageWinUsd)} / $${fmt(m.averageLossUsd)}`);
  row('Profit factor', fmt(m.profitFactor));
  row('Largest gain / loss', `$${fmt(m.largestGainUsd)} / $${fmt(m.largestLossUsd)}`);
  console.log('\n  Risk-adjusted');
  row('Expectancy per trade', `$${fmt(m.expectancyUsd)}`);
  row('Sharpe (per trade)', fmt(m.sharpeRatio));
  row('Sortino (per trade)', fmt(m.sortinoRatio));
  row('Calmar', fmt(m.calmarRatio));
  row('CVaR 95% (worst 5% trades)', fmt(m.cvar95Pct, '%'));
  row('Exposure', fmt(m.exposurePct, '%'));
  row('Fees paid', `$${fmt(m.totalFeesUsd)}`);
  console.log('\n  Rug protection');
  row('Tokens evaluated', fmt(m.tokensEvaluated));
  row('Skipped for rug risk', fmt(m.tokensSkippedForRugRisk));
  row('Scams avoided / hit', `${m.rugsAvoided} / ${m.rugsHit}`);
  row('Catastrophic losses', fmt(m.catastrophicLosses));
  if (r.catastrophicEvents.length > 0) {
    console.log('\nCATASTROPHIC EVENTS:');
    for (const e of r.catastrophicEvents.slice(0, 25)) console.log(`  ! ${e.ts} ${e.kind.padEnd(24)} ${e.symbol ?? ''} ${e.description}`);
    if (r.catastrophicEvents.length > 25) console.log(`  … ${r.catastrophicEvents.length - 25} more`);
  }
  console.log('\nWARNINGS:');
  for (const w of r.warnings) console.log(`  - ${w}`);
}

async function main() {
  const { values } = parseArgs({
    options: {
      source: { type: 'string', default: 'synthetic' },
      file: { type: 'string' },
      tokens: { type: 'string', default: '200' },
      seed: { type: 'string', default: '42' },
      balance: { type: 'string' },
      'assume-clean-security': { type: 'boolean', default: false },
      save: { type: 'boolean', default: false },
      out: { type: 'string' },
      help: { type: 'boolean', default: false },
    },
  });
  if (values.help) {
    console.log(USAGE);
    return;
  }
  loadEnvFile();
  const config = loadConfig(process.env);
  const needsDb = values.save || values.source === 'db';
  const db = needsDb ? await createDatabase(config.database.url) : null;
  if (db && config.database.autoMigrate) await db.migrate(config.database.migrationsDir);
  const repos = db ? createRepositories(db.db) : null;
  try {
    let limits = config.hardLimits;
    let strategy = config.defaultStrategy;
    if (repos) {
      const eff = await new StrategyStore(repos.strategy, config.trading.mode, config.hardLimits, config.defaultStrategy).load();
      limits = eff.limits;
      strategy = eff.strategy;
    }
    let dataset: BacktestDataset;
    if (values.source === 'file') {
      if (!values.file) throw new Error('--file is required with --source file');
      dataset = loadDatasetFromFile(values.file);
    } else if (values.source === 'db') {
      dataset = await loadDatasetFromDatabase(repos as NonNullable<typeof repos>, { limit: Number(values.tokens), minPoints: 10 });
      if (dataset.tokens.length === 0) throw new Error('no recorded tokens with enough history; run the engine first');
    } else {
      dataset = generateSyntheticDataset({ tokens: Number(values.tokens), seed: values.seed as string });
    }
    const result = runBacktest(dataset, {
      startingBalanceUsd: values.balance ? Number(values.balance) : config.paper.startingBalanceUsd,
      limits,
      strategy,
      dexFeePct: config.paper.dexFeePercent,
      failureRate: config.paper.failureRate,
      seed: values.seed as string,
      catastrophicLossPct: config.trading.catastrophicLossPercent,
      evaluateEveryMinutes: 5,
      exitMaxSlippagePct: config.trading.exitMaxSlippagePercent,
      assumeCleanSecurity: values['assume-clean-security'] as boolean,
    });
    if (repos && values.save) result.id = await repos.backtests.insert(result);
    print(result);
    if (values.out) {
      fs.writeFileSync(values.out, JSON.stringify(result, null, 2));
      console.log(`\nFull result written to ${values.out}`);
    }
  } finally {
    await db?.close();
  }
}

main().catch((err) => {
  console.error(`[memeguard] backtest failed: ${errorMessage(err)}`);
  process.exit(1);
});
