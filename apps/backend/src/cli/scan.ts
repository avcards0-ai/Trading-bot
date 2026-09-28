import { parseArgs } from 'node:util';
import type { Chain, RiskReport } from '@memeguard/shared';
import { isValidAddress } from '../api/server';
import { createApp } from '../app';
import { SUPPORTED_CHAINS, loadConfig } from '../config/env';
import { loadEnvFile } from '../config/loadEnv';
import { normalizeAddress } from '../db/repositories';
import { errorMessage } from '../lib/errors';
import { createLogger } from '../lib/logger';
import { SecretRedactor } from '../lib/redact';

const USAGE = `Usage: npm run scan -- --chain <${SUPPORTED_CHAINS.join('|')}> --address <token> [--json] [--trade]

Runs the full decision pipeline on one token and prints the rug-risk report.
  --json    print the raw decision + report JSON
  --trade   allow the pipeline to place an order if EVERY risk check passes
            (paper mode by default; live only if live trading is armed in .env)`;

function printReport(r: RiskReport) {
  const line = (k: string, v: string) => console.log(`  ${k.padEnd(28)} ${v}`);
  console.log(`\nRUG-RISK REPORT  ${r.chain}:${r.address}  (${r.modelVersion})`);
  line('RUG_SCORE', `${r.rugScore}/100`);
  line('HONEYPOT_RISK', r.honeypotRisk);
  line('LIQUIDITY_RISK', r.liquidityRisk);
  line('CONTRACT_RISK', r.contractRisk);
  line('WALLET_CONCENTRATION_RISK', r.walletConcentrationRisk);
  line('DEVELOPER_RISK', r.developerRisk);
  line('MARKET_INTEGRITY_RISK', r.marketIntegrityRisk);
  line('OVERALL_RISK', `${r.overallRisk}${r.isLikelyScam ? '  (LIKELY SCAM)' : ''}`);
  line('Data completeness', `${Math.round(r.dataCompleteness * 100)}%${r.missingData.length ? ` (missing: ${r.missingData.join(', ')})` : ''}`);
  console.log('\nWHY:');
  for (const [k, v] of Object.entries(r.explanations)) console.log(`  - ${k}: ${v}`);
  if (r.factors.length > 0) {
    console.log('\nFACTORS (points into category score):');
    for (const f of [...r.factors].sort((a, b) => b.points - a.points)) {
      console.log(`  [${f.severity.padEnd(8)}] ${f.category.padEnd(13)} +${String(Math.round(f.points)).padStart(3)}  ${f.label}${f.critical ? ' (CRITICAL)' : ''}`);
    }
  }
}

async function main() {
  const { values } = parseArgs({
    options: {
      chain: { type: 'string' },
      address: { type: 'string' },
      json: { type: 'boolean', default: false },
      trade: { type: 'boolean', default: false },
      help: { type: 'boolean', default: false },
    },
  });
  if (values.help || !values.chain || !values.address) {
    console.log(USAGE);
    process.exit(values.help ? 0 : 1);
  }
  const chain = values.chain as Chain;
  if (!SUPPORTED_CHAINS.includes(chain as (typeof SUPPORTED_CHAINS)[number])) throw new Error(`unsupported chain ${chain}`);
  if (!isValidAddress(chain, values.address)) throw new Error(`invalid ${chain} address`);

  loadEnvFile();
  const config = loadConfig({ ...process.env, ENGINE_AUTOSTART: 'false' });
  const redactor = new SecretRedactor();
  const logger = createLogger({ level: values.json ? 'error' : 'warn', pretty: false, redactor });
  const app = await createApp(config, { logger });
  try {
    const { row } = await app.repos.tokens.upsertDiscovered({ chain, address: normalizeAddress(chain, values.address), discoveredVia: 'cli' });
    const res = await app.pipeline.analyze({ tokenId: row.id, trigger: 'manual', allowTrade: values.trade, manual: true, forceSecurityRefresh: true });
    if (values.json) {
      console.log(JSON.stringify({ decision: res.decision, risk: res.report }, null, 2));
    } else {
      printReport(res.report);
      const d = res.decision;
      console.log(`\nDECISION: ${d.label}   (action ${d.action}, confidence ${d.confidence}, mode ${d.mode})`);
      for (const r of d.reasons) console.log(`  - ${r}`);
      console.log('\nPIPELINE:');
      for (const s of d.stages) console.log(`  ${s.stage.padEnd(11)} ${s.status.padEnd(7)} ${s.summary}`);
      if (d.riskChecks.length > 0) {
        console.log('\nRISK CHECKS:');
        for (const c of d.riskChecks) console.log(`  ${c.passed ? 'PASS' : 'FAIL'} ${c.check.padEnd(22)} ${c.message}`);
      }
      const failed = res.snapshot.sources.filter((s) => !s.ok);
      if (failed.length > 0) {
        console.log('\nDATA SOURCES THAT FAILED (treated as risk):');
        for (const s of failed) console.log(`  - ${s.name}: ${s.error}`);
      }
    }
  } finally {
    await app.close();
  }
}

main().catch((err) => {
  console.error(`[memeguard] scan failed: ${errorMessage(err)}`);
  process.exit(1);
});
