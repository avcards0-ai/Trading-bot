/**
 * Solana programs whose pool-creation transactions the launch sniper listens for.
 *
 * The program ids and log markers follow each program's public deployment and on-chain logs.
 * They could not be exercised against mainnet from the development environment, so they are
 * configurable: SNIPER_SOURCES accepts a known name or `name=programId` for anything else.
 */
export interface LaunchProgram {
  name: string;
  programId: string;
  /** A pool-creation transaction's logs match this; other instructions of the program do not. */
  marker: RegExp;
}

export const KNOWN_LAUNCH_PROGRAMS: Record<string, LaunchProgram> = {
  'raydium-amm-v4': {
    name: 'raydium-amm-v4',
    programId: '675kPX9MHTjS2zt1qfr1NYHuzeLXfQM9H24wFSUt1Mp8',
    marker: /\binitialize2\b/i,
  },
  'raydium-cpmm': {
    name: 'raydium-cpmm',
    programId: 'CPMMoo8L3F4NbTegBCKVNunggL7H1ZpdTHKxQB5qKP1C',
    marker: /Instruction: Initialize\b/,
  },
  pumpswap: {
    name: 'pumpswap',
    programId: 'pAMMBay6oceH9fJKBRHGP5D4bD4sWpmSwMn52FMfXEA',
    marker: /Instruction: CreatePool\b/,
  },
};

export const DEFAULT_LAUNCH_SOURCES = 'raydium-amm-v4,raydium-cpmm,pumpswap';

const GENERIC_MARKER = /initiali[sz]e|create_?pool/i;

/** Parses SNIPER_SOURCES. Throws with a readable message on unknown names or bad program ids. */
export function parseLaunchSources(raw: string): LaunchProgram[] {
  const out: LaunchProgram[] = [];
  for (const item of raw
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean)) {
    const [name, programId] = item.split('=').map((s) => s.trim());
    if (programId !== undefined) {
      if (!name || !/^[1-9A-HJ-NP-Za-km-z]{32,44}$/.test(programId)) {
        throw new Error(`invalid launch source "${item}" (expected name=<base58 program id>)`);
      }
      out.push({ name, programId, marker: KNOWN_LAUNCH_PROGRAMS[name]?.marker ?? GENERIC_MARKER });
      continue;
    }
    const known = name ? KNOWN_LAUNCH_PROGRAMS[name.toLowerCase()] : undefined;
    if (!known) {
      throw new Error(
        `unknown launch source "${item}" (known: ${Object.keys(KNOWN_LAUNCH_PROGRAMS).join(', ')}; or use name=programId)`,
      );
    }
    out.push(known);
  }
  return out;
}
