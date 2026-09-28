import fs from 'node:fs';
import { ed25519 } from '@noble/curves/ed25519.js';
import bs58 from 'bs58';

/**
 * Solana keypair handling. The secret key is held only in this closure-backed object:
 * it is never returned as a string, serialised, or attached to errors.
 */
export interface Signer {
  readonly publicKey: string;
  sign(message: Uint8Array): Uint8Array;
}

export class KeyLoadError extends Error {
  constructor(reason: string) {
    // Deliberately never include the input value in the message.
    super(`Could not load wallet key: ${reason}`);
    this.name = 'KeyLoadError';
  }
}

function decodeSecret(raw: string): Uint8Array {
  const trimmed = raw.trim();
  if (trimmed.startsWith('[')) {
    let arr: unknown;
    try {
      arr = JSON.parse(trimmed);
    } catch {
      throw new KeyLoadError('JSON key is not valid JSON');
    }
    if (!Array.isArray(arr) || !arr.every((n) => Number.isInteger(n) && n >= 0 && n <= 255)) {
      throw new KeyLoadError('JSON key must be an array of bytes');
    }
    return Uint8Array.from(arr as number[]);
  }
  try {
    return bs58.decode(trimmed);
  } catch {
    throw new KeyLoadError('key is neither a JSON byte array nor valid base58');
  }
}

/** Builds a signer from a 64-byte Solana secret key (seed || pubkey) or a 32-byte seed. */
export function signerFromSecret(raw: string, onDerivedSecret?: (s: string) => void): Signer {
  const bytes = decodeSecret(raw);
  let seed: Uint8Array;
  let expectedPub: Uint8Array | null = null;
  if (bytes.length === 64) {
    seed = bytes.slice(0, 32);
    expectedPub = bytes.slice(32);
  } else if (bytes.length === 32) {
    seed = bytes.slice();
  } else {
    throw new KeyLoadError(`expected 64 (or 32) bytes, got ${bytes.length}`);
  }
  const pub = ed25519.getPublicKey(seed);
  if (expectedPub && !expectedPub.every((b, i) => b === pub[i])) {
    throw new KeyLoadError('public key half does not match the secret seed (corrupted key)');
  }
  // Register alternate encodings so the log scrubber also catches them.
  onDerivedSecret?.(bs58.encode(bytes));
  onDerivedSecret?.(JSON.stringify(Array.from(bytes)));
  onDerivedSecret?.(bs58.encode(seed));
  bytes.fill(0);
  const publicKey = bs58.encode(pub);
  return {
    publicKey,
    sign: (message: Uint8Array) => ed25519.sign(message, seed),
  };
}

export function signerFromFile(path: string, onDerivedSecret?: (s: string) => void): Signer {
  let stat: fs.Stats;
  try {
    stat = fs.statSync(path);
  } catch {
    throw new KeyLoadError(`keypair file not found at WALLET_KEYPAIR_PATH`);
  }
  if (process.platform !== 'win32' && (stat.mode & 0o077) !== 0) {
    throw new KeyLoadError('keypair file permissions are too open; run: chmod 600 <file>');
  }
  const raw = fs.readFileSync(path, 'utf8');
  onDerivedSecret?.(raw.trim());
  return signerFromSecret(raw, onDerivedSecret);
}

/** True if the 32-byte public key is a point on the ed25519 curve (PDAs are off-curve). */
export function isOnCurve(address: string): boolean {
  try {
    const bytes = bs58.decode(address);
    if (bytes.length !== 32) return false;
    ed25519.Point.fromBytes(bytes);
    return true;
  } catch {
    return false;
  }
}

export function isValidSolanaAddress(address: string): boolean {
  try {
    return bs58.decode(address).length === 32;
  } catch {
    return false;
  }
}
