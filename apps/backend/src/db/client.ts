import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { sql } from 'drizzle-orm';
import type { PgDatabase, PgQueryResultHKT } from 'drizzle-orm/pg-core';
import type { Logger } from '../lib/logger';
import { schema } from './schema';

export type Database = PgDatabase<PgQueryResultHKT, typeof schema>;

export interface DatabaseHandle {
  db: Database;
  driver: 'postgres' | 'pglite';
  migrate(migrationsDir?: string | null): Promise<void>;
  ping(): Promise<void>;
  close(): Promise<void>;
}

/** Locate the drizzle migrations folder both from source (tsx) and from the built bundle. */
export function resolveMigrationsDir(explicit?: string | null): string {
  const candidates = [
    explicit,
    process.env.MIGRATIONS_DIR,
    path.resolve(process.cwd(), 'drizzle'),
    path.resolve(process.cwd(), 'apps/backend/drizzle'),
    path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../drizzle'),
    path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../drizzle'),
  ].filter((c): c is string => typeof c === 'string' && c.length > 0);
  for (const c of candidates) {
    if (fs.existsSync(path.join(c, 'meta', '_journal.json'))) return c;
  }
  throw new Error(`Could not find drizzle migrations folder (tried: ${candidates.join(', ')})`);
}

/**
 * DATABASE_URL formats:
 *   postgres://user:pass@host:5432/db   -> node-postgres pool
 *   pglite://memory                      -> in-memory embedded Postgres (tests/dev)
 *   pglite://./data/pglite               -> persistent embedded Postgres directory
 */
export async function createDatabase(url: string, logger?: Logger): Promise<DatabaseHandle> {
  if (url.startsWith('pglite://')) {
    const target = url.slice('pglite://'.length);
    const { PGlite } = await import('@electric-sql/pglite');
    const { drizzle } = await import('drizzle-orm/pglite');
    const { migrate } = await import('drizzle-orm/pglite/migrator');
    let client: InstanceType<typeof PGlite>;
    if (target === '' || target === 'memory') {
      client = new PGlite();
    } else {
      const dir = path.resolve(target);
      fs.mkdirSync(dir, { recursive: true });
      client = new PGlite(dir);
    }
    await client.waitReady;
    const db = drizzle(client, { schema });
    logger?.info({ driver: 'pglite', target: target || 'memory' }, 'database connected');
    return {
      db: db as unknown as Database,
      driver: 'pglite',
      migrate: async (dir) => {
        await migrate(db, { migrationsFolder: resolveMigrationsDir(dir) });
      },
      ping: async () => {
        await db.execute(sql`select 1`);
      },
      close: async () => {
        await client.close();
      },
    };
  }

  if (url.startsWith('postgres://') || url.startsWith('postgresql://')) {
    const pg = await import('pg');
    const { drizzle } = await import('drizzle-orm/node-postgres');
    const { migrate } = await import('drizzle-orm/node-postgres/migrator');
    const pool = new pg.default.Pool({ connectionString: url, max: 10, idleTimeoutMillis: 30_000 });
    pool.on('error', (err) => logger?.error({ err }, 'postgres pool error'));
    const db = drizzle(pool, { schema });
    await pool.query('select 1');
    logger?.info({ driver: 'postgres' }, 'database connected');
    return {
      db: db as unknown as Database,
      driver: 'postgres',
      migrate: async (dir) => {
        await migrate(db, { migrationsFolder: resolveMigrationsDir(dir) });
      },
      ping: async () => {
        await pool.query('select 1');
      },
      close: async () => {
        await pool.end();
      },
    };
  }

  throw new Error('DATABASE_URL must start with postgres://, postgresql:// or pglite://');
}
