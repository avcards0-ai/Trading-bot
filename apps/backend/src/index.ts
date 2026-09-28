import { buildServer } from './api/server';
import { createApp } from './app';
import { ConfigError, loadConfig } from './config/env';
import { loadEnvFile } from './config/loadEnv';
import { errorMessage } from './lib/errors';

async function main(): Promise<void> {
  loadEnvFile();
  let config;
  try {
    config = loadConfig(process.env, process.env.npm_package_version ?? '1.0.0');
  } catch (err) {
    if (err instanceof ConfigError) {
      // Config errors never contain secret values (only variable names and rules).
      console.error(`\n[memeguard] ${err.message}\n`);
      process.exit(1);
    }
    throw err;
  }

  const app = await createApp(config);
  const server = await buildServer(app);
  await server.listen({ host: config.server.host, port: config.server.port });

  // Position protection always runs; discovery/entries only when autostart is enabled.
  app.engine.startProtection();
  if (config.trading.engineAutostart) await app.engine.start();
  else app.logger.info('ENGINE_AUTOSTART=false: discovery idle until POST /engine/start');

  let stopping = false;
  const shutdown = async (signal: string) => {
    if (stopping) return;
    stopping = true;
    app.logger.info({ signal }, 'shutting down');
    const force = setTimeout(() => process.exit(1), 20_000);
    force.unref();
    try {
      await server.close();
      app.logger.info('http server closed');
      await app.close();
    } catch (err) {
      app.logger.error({ err: errorMessage(err) }, 'error during shutdown');
    }
    process.exit(0);
  };
  process.on('SIGINT', () => void shutdown('SIGINT'));
  process.on('SIGTERM', () => void shutdown('SIGTERM'));
  process.on('unhandledRejection', (reason) =>
    app.logger.error({ err: errorMessage(reason) }, 'unhandled rejection'),
  );
}

main().catch((err) => {
  console.error(`[memeguard] fatal: ${errorMessage(err)}`);
  process.exit(1);
});
