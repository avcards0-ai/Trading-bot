import { loadConfig } from '../config/env';
import { loadEnvFile } from '../config/loadEnv';
import { createDatabase } from '../db/client';
import { errorMessage } from '../lib/errors';

/** Applies pending database migrations: `npm run db:migrate`. */
async function main() {
  loadEnvFile();
  const config = loadConfig(process.env);
  const db = await createDatabase(config.database.url);
  await db.migrate(config.database.migrationsDir);
  await db.close();
  console.log(`[memeguard] migrations applied (${db.driver})`);
}

main().catch((err) => {
  console.error(`[memeguard] migration failed: ${errorMessage(err)}`);
  process.exit(1);
});
