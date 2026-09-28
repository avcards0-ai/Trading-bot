import fs from 'node:fs';
import path from 'node:path';
import dotenv from 'dotenv';

/**
 * Loads `.env` from the current directory or the repository root (whichever exists first).
 * Existing process environment variables always win over file values.
 */
export function loadEnvFile(): string | null {
  const candidates = [path.resolve(process.cwd(), '.env'), path.resolve(process.cwd(), '../../.env')];
  for (const file of candidates) {
    if (fs.existsSync(file)) {
      dotenv.config({ path: file, quiet: true, override: false });
      return file;
    }
  }
  return null;
}
