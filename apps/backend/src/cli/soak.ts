import fs from 'node:fs';
import { parseArgs } from 'node:util';
import { createApp } from '../app';
import { loadConfig } from '../config/env';
import { loadEnvFile } from '../config/loadEnv';
import { errorMessage } from '../lib/errors';
import { createLogger } from '../lib/logger';
import { SecretRedactor } from '../lib/redact';
import { buildSoakReport, formatSoakReport } from '../soak/report';

const USAGE = `Usage: npm run soak -- [--minutes 30] [--out soak-report.json] [--db pglite://memory]

Runs the whole engine in PAPER mode against live market data for a fixed time, then prints a
report: tokens found and analysed, risk verdicts, decisions, paper trades and P/L, and the health
of every data source (including responses that no longer match the expected format).
Always paper trading, whatever TRADING_MODE says. Uses a fresh in-memory database by default.
Stop early with Ctrl+C; the report is still written.`;

async function main() {
  const { values } = parseArgs({
    options: {
      minutes: { type: 'string', default: '30' },
      out: { type: 'string', default: 'soak-report.json' },
      db: { type: 'string', default: 'pglite://memory' },
      help: { type: 'boolean', default: false },
    },
  });
  if (values.help) {
    console.log(USAGE);
    return;
  }
  const minutes = Number(values.minutes);
  if (!(minutes > 0 && minutes <= 24 * 60)) throw new Error('--minutes must be between 0 and 1440');

  loadEnvFile();
  // Forced paper mode: a soak test never touches a wallet.
  const config = loadConfig({
    ...process.env,
    TRADING_MODE: 'paper',
    LIVE_TRADING_CONFIRMATION: '',
    WALLET_PRIVATE_KEY: '',
    WALLET_KEYPAIR_PATH: '',
    ENGINE_AUTOSTART: 'false',
    DATABASE_URL: values.db,
  });
  const redactor = new SecretRedactor();
  // Provider errors are summarised in the report; per-request warnings would drown it out.
  const logger = createLogger({ level: 'error', pretty: false, redactor });
  const app = await createApp(config, { logger });

  const startedAt = new Date();
  const until = startedAt.getTime() + minutes * 60_000;
  let stop = false;
  process.once('SIGINT', () => {
    console.log('\nStopping early; writing the report…');
    stop = true;
  });

  console.log(`Soak test: ${minutes} min, PAPER mode, chains ${config.engine.chains.join(', ')}.`);
  await app.engine.start();
  try {
    let nextProgress = Date.now() + 60_000;
    while (!stop && Date.now() < until) {
      await new Promise((r) => setTimeout(r, 1000));
      if (Date.now() >= nextProgress) {
        nextProgress += 60_000;
        const r = await buildSoakReport(app, startedAt);
        const failing = r.providers.filter((p) => p.configured && p.calls > 0 && p.failures / p.calls >= 0.2);
        console.log(
          `  ${r.minutes.toFixed(0).padStart(3)} min · ${r.discovery.tokensSeen} tokens found, ${r.discovery.tokensAnalysed} analysed · ` +
            `${r.trading.buys} buys, ${r.trading.sells} sells · equity $${r.trading.equityUsd.toFixed(2)}` +
            (failing.length > 0 ? ` · failing: ${failing.map((p) => p.name).join(', ')}` : ''),
        );
      }
    }
  } finally {
    await app.engine.stop();
    // Let queued analyses finish so the report reflects everything that was started.
    await app.engine.drain(30_000);
    const report = await buildSoakReport(app, startedAt);
    fs.writeFileSync(values.out, `${JSON.stringify(report, null, 2)}\n`);
    console.log(formatSoakReport(report));
    console.log(`\nFull report written to ${values.out}`);
    await app.close();
  }
}

main().catch((err) => {
  console.error(`[memeguard] soak test failed: ${errorMessage(err)}`);
  process.exit(1);
});
