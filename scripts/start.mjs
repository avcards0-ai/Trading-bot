/**
 * One-step launcher, for running MemeGuard without typing commands. It:
 *   1. installs dependencies on the first run,
 *   2. creates .env (paper trading) with a random dashboard password (API_KEY) if there is none,
 *   3. offers to save a Solana RPC link, which turns on the launch sniper (paper) and the deeper
 *      Solana checks,
 *   4. starts the bot and the dashboard, and opens the dashboard in the browser.
 * Started by start.bat (Windows), start.command (macOS) or `npm run launch`.
 * It never prints the password or the RPC link (which usually contains an API key).
 */
import { exec, spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { chmodSync, copyFileSync, existsSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { createInterface } from 'node:readline/promises';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const envPath = path.join(root, '.env');
const isWindows = process.platform === 'win32';
const DASHBOARD_URL = 'http://localhost:5173';
const DASHBOARD_CHECK = 'http://127.0.0.1:5173/';

const say = (msg = '') => console.log(msg);
function fail(msg) {
  console.error(`\n${msg}\n`);
  process.exit(1);
}

const major = Number(process.versions.node.split('.')[0]);
if (major < 22) {
  fail(
    `MemeGuard needs Node.js 22 or newer (this computer has ${process.versions.node}).\n` +
      'Install the LTS version from https://nodejs.org, then start MemeGuard again.',
  );
}

/** npm is a .cmd script on Windows, which Node only runs through a shell. */
const npm = (args, opts = {}) =>
  spawn('npm', args, { cwd: root, stdio: 'inherit', shell: isWindows, ...opts });

const exitCode = (child) =>
  new Promise((resolve) => {
    child.on('error', () => resolve(1));
    child.on('exit', (code) => resolve(code ?? 1));
  });

/** KEY=value lines, as dotenv reads them (comments and surrounding quotes removed). */
function parseEnv(text) {
  const out = {};
  for (const line of text.split(/\r?\n/)) {
    const m = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/.exec(line);
    if (!m) continue;
    const raw = m[2];
    out[m[1]] = /^(["']).*\1$/.test(raw) ? raw.slice(1, -1) : raw.replace(/\s+#.*$/, '');
  }
  return out;
}

/** Sets KEY=value in .env text: rewrites every line for the key (the last one wins), or adds one. */
function setEnvValues(text, updates) {
  const eol = text.includes('\r\n') ? '\r\n' : '\n';
  const lines = text.split(/\r?\n/);
  for (const [key, value] of Object.entries(updates)) {
    const re = new RegExp(`^\\s*${key}\\s*=`);
    let found = false;
    for (let i = 0; i < lines.length; i++) {
      if (re.test(lines[i])) {
        lines[i] = `${key}=${value}`;
        found = true;
      }
    }
    if (found) continue;
    if (lines.at(-1) === '') lines.splice(lines.length - 1, 0, `${key}=${value}`);
    else lines.push(`${key}=${value}`);
  }
  return lines.join(eol);
}

/** One question in this window. No keyboard, or no answer within `ms`, counts as skipping. */
async function ask(question, ms) {
  if (!process.stdin.isTTY) return '';
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  rl.on('SIGINT', () => {
    rl.close();
    process.exit(130);
  });
  try {
    return (await rl.question(question, { signal: AbortSignal.timeout(ms) })).trim();
  } catch {
    say('\n(No answer: skipped for now.)');
    return '';
  } finally {
    rl.close();
  }
}

/** True when the link answers a Solana JSON-RPC call. */
async function isSolanaRpc(url) {
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'getSlot' }),
      signal: AbortSignal.timeout(10_000),
    });
    const body = await res.json();
    return typeof body?.result === 'number';
  } catch {
    return false;
  }
}

async function isUp(url) {
  try {
    return (await fetch(url, { signal: AbortSignal.timeout(2000) })).ok;
  } catch {
    return false;
  }
}

async function waitFor(url, ms) {
  const until = Date.now() + ms;
  while (Date.now() < until) {
    if (await isUp(url)) return true;
    await new Promise((r) => setTimeout(r, 1000));
  }
  return false;
}

function openBrowser(url) {
  const cmd = isWindows
    ? `start "" "${url}"`
    : process.platform === 'darwin'
      ? `open "${url}"`
      : `xdg-open "${url}"`;
  exec(cmd, () => undefined);
}

function copyToClipboard(text) {
  const cmd = isWindows ? 'clip' : process.platform === 'darwin' ? 'pbcopy' : null;
  if (!cmd) return Promise.resolve(false);
  return new Promise((resolve) => {
    const p = spawn(cmd, [], { stdio: ['pipe', 'ignore', 'ignore'], shell: isWindows });
    p.on('error', () => resolve(false));
    p.on('exit', (code) => resolve(code === 0));
    p.stdin.on('error', () => undefined);
    p.stdin.end(text);
  });
}

function stop(child) {
  if (child.exitCode !== null || child.signalCode !== null || !child.pid) return;
  // Windows has no SIGINT for other processes: end the whole tree so nothing keeps running.
  if (isWindows) exec(`taskkill /pid ${child.pid} /T /F`, () => undefined);
  else child.kill('SIGINT');
}

// 1. Dependencies (npm writes node_modules/.package-lock.json last, so a broken install retries).
if (!existsSync(path.join(root, 'node_modules', '.package-lock.json'))) {
  say('First start: installing MemeGuard. This takes a few minutes...\n');
  if ((await exitCode(npm(['ci', '--no-audit', '--no-fund']))) !== 0) {
    fail(
      'Installing failed. Check your internet connection and start MemeGuard again.\n' +
        'If it keeps failing, copy the messages above and ask for help.',
    );
  }
}

// 2. Settings: .env from the example (paper trading), plus a dashboard password if it has none.
if (!existsSync(envPath)) {
  copyFileSync(path.join(root, '.env.example'), envPath);
  say('Created the settings file (.env) with the default settings: paper trading, fake money.');
}
let envText = readFileSync(envPath, 'utf8');
let env = parseEnv(envText);
const saveEnv = (updates) => {
  envText = setEnvValues(envText, updates);
  writeFileSync(envPath, envText);
  env = parseEnv(envText);
};
if (!env.API_KEY) {
  saveEnv({ API_KEY: randomBytes(24).toString('hex') });
  say('Created a dashboard password (the API_KEY line in .env).');
}
try {
  chmodSync(envPath, 0o600); // it holds the password (and any keys you add later)
} catch {
  /* not supported on this system */
}

const port = Number(env.PORT) || 8080;
const backendUrl = `http://127.0.0.1:${port}`;
const live = (env.TRADING_MODE ?? 'paper').trim().toLowerCase() === 'live';

if (await isUp(`${backendUrl}/health`)) {
  say(`\nMemeGuard is already running. Opening the dashboard: ${DASHBOARD_URL}`);
  openBrowser(DASHBOARD_URL);
  process.exit(0);
}

// 3. Optional Solana RPC link: turns on the launch sniper (paper only) and the deeper Solana
//    checks (wallet ages, developer activity). Asked on each start until one is saved.
if (!env.RPC_URL && !live) {
  const link = await ask(
    '\nOptional: paste a Solana RPC link to turn on the launch sniper and the full Solana checks.\n' +
      'Get one free at https://www.helius.dev (sign up, then copy your Mainnet RPC URL).\n' +
      'Paste it and press Enter, or just press Enter to skip: ',
    120_000,
  );
  if (link) {
    const localRpc = /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?(\/|$)/.test(link);
    if (!/^https:\/\/\S+$/.test(link) && !localRpc) {
      say("That doesn't look like a link starting with https://, so it was not saved.");
    } else if (!(await isSolanaRpc(link))) {
      say("That link didn't answer like a Solana RPC, so it was not saved. Check it and start again.");
    } else {
      saveEnv({ RPC_URL: link, SNIPER_ENABLED: 'true' });
      say('Saved. The launch sniper is on (paper trading: fake money).');
    }
  }
}

// 4. Start the bot and the dashboard as plain Node processes (no npm or shell in between, and no
//    watch mode), so a crash ends the launcher with a message and stopping reaches them directly.
//    Warnings and errors only, so this window stays readable; the dashboard shows the full log.
say('\nStarting MemeGuard...');
const bin = (p) => path.join(root, 'node_modules', p);
const bot = spawn(process.execPath, [bin('tsx/dist/cli.mjs'), 'src/index.ts'], {
  cwd: path.join(root, 'apps', 'backend'),
  env: { ...process.env, LOG_LEVEL: 'warn' },
  stdio: 'inherit',
});
const dashboard = spawn(process.execPath, [bin('vite/bin/vite.js'), '--strictPort'], {
  cwd: path.join(root, 'apps', 'frontend'),
  env: { ...process.env, VITE_BACKEND_URL: backendUrl },
  stdio: ['ignore', 'ignore', 'inherit'],
});
const children = [bot, dashboard];
// Listen from the start: a child that has already exited emits no further 'exit' event.
const exited = children.map(exitCode);

let stopping = false;
const shutdown = (code = 0) => {
  if (stopping) return;
  stopping = true;
  for (const c of children) stop(c);
  setTimeout(() => process.exit(code), 10_000).unref();
};
// Ctrl+C reaches the children directly; wait for them to finish saving before exiting.
process.on('SIGINT', () => {
  stopping = true;
});
// Closing the window or being told to stop: stop the children ourselves.
for (const sig of ['SIGTERM', 'SIGHUP']) process.on(sig, () => shutdown());

Promise.race(exited).then(async (code) => {
  if (!stopping) {
    console.error(
      `\nMemeGuard stopped${code ? ' with an error (see the messages above)' : ''}. ` +
        'Start it again, or copy the messages above and ask for help.',
    );
  }
  const failed = !stopping;
  shutdown(failed ? 1 : 0);
  await Promise.all(exited);
  process.exit(failed ? 1 : 0);
});

const ready = (await waitFor(`${backendUrl}/health`, 180_000)) && (await waitFor(DASHBOARD_CHECK, 60_000));
if (stopping) await new Promise(() => undefined); // exiting: the handler above finishes up
if (!ready) {
  say(`\nMemeGuard is taking longer than usual to start. Try opening ${DASHBOARD_URL} in a minute.`);
} else {
  openBrowser(DASHBOARD_URL);
}
const copied = await copyToClipboard(env.API_KEY);
const line = '-'.repeat(72);
say(`\n${line}`);
say(
  live
    ? '  MemeGuard is running in LIVE mode: it trades REAL MONEY from your wallet.'
    : '  MemeGuard is running in PAPER mode: it trades fake money only.',
);
say(`  Dashboard: ${DASHBOARD_URL}${ready ? ' (opened in your browser)' : ''}`);
say(
  copied
    ? '  Dashboard password: copied to your clipboard. Paste it on the Configuration page\n' +
        '  to use the buttons (scan, trade, start/stop). It is the API_KEY line in .env.'
    : '  Dashboard password: the API_KEY line in the .env file in the MemeGuard folder.\n' +
        '  Paste it on the Configuration page to use the buttons (scan, trade, start/stop).',
);
say('  Keep this window open. To stop MemeGuard, press Ctrl+C or close this window.');
say(line);
