import bs58 from 'bs58';
import type { Signer } from './keys';

/**
 * Minimal Solana transaction wire-format handling, enough to sign a transaction that was
 * built by a trusted aggregator (Jupiter) for our fee-payer key.
 *
 * Wire format: compact-u16 signature count | 64-byte signatures | message
 * Message:     [0x80|version]? | header(3) | compact-u16 key count | 32-byte keys | ...
 */

export function decodeCompactU16(bytes: Uint8Array, offset: number): { value: number; size: number } {
  let value = 0;
  let size = 0;
  for (;;) {
    if (size >= 3) throw new Error('compact-u16 too long');
    const byte = bytes[offset + size];
    if (byte === undefined) throw new Error('compact-u16 truncated');
    value |= (byte & 0x7f) << (7 * size);
    size += 1;
    if ((byte & 0x80) === 0) break;
  }
  return { value, size };
}

export interface ParsedWireTransaction {
  signatureCount: number;
  signaturesOffset: number;
  messageOffset: number;
  requiredSignatures: number;
  staticKeys: string[];
}

export function parseWireTransaction(tx: Uint8Array): ParsedWireTransaction {
  const sigCount = decodeCompactU16(tx, 0);
  const signaturesOffset = sigCount.size;
  const messageOffset = signaturesOffset + sigCount.value * 64;
  if (messageOffset > tx.length) throw new Error('transaction truncated (signatures)');
  let p = messageOffset;
  const first = tx[p];
  if (first === undefined) throw new Error('transaction truncated (message)');
  if ((first & 0x80) !== 0) {
    const version = first & 0x7f;
    if (version !== 0) throw new Error(`unsupported message version ${version}`);
    p += 1;
  }
  const requiredSignatures = tx[p];
  if (requiredSignatures === undefined) throw new Error('transaction truncated (header)');
  p += 3;
  const keyCount = decodeCompactU16(tx, p);
  p += keyCount.size;
  const staticKeys: string[] = [];
  for (let i = 0; i < keyCount.value; i++) {
    const key = tx.slice(p, p + 32);
    if (key.length !== 32) throw new Error('transaction truncated (keys)');
    staticKeys.push(bs58.encode(key));
    p += 32;
  }
  if (sigCount.value !== requiredSignatures) {
    throw new Error(`signature slots (${sigCount.value}) != required signatures (${requiredSignatures})`);
  }
  return { signatureCount: sigCount.value, signaturesOffset, messageOffset, requiredSignatures, staticKeys };
}

/**
 * Signs `txBase64` with `signer` and returns the signed transaction (base64) and its signature
 * (base58, which is also the transaction id). Refuses to sign if our key is not a required signer
 * or if other signatures would still be missing.
 */
export function signSerializedTransaction(txBase64: string, signer: Signer): { signedBase64: string; signature: string } {
  const tx = Uint8Array.from(Buffer.from(txBase64, 'base64'));
  const parsed = parseWireTransaction(tx);
  const index = parsed.staticKeys.slice(0, parsed.requiredSignatures).indexOf(signer.publicKey);
  if (index < 0) throw new Error('wallet is not a required signer of the provided transaction');
  if (index !== 0) throw new Error('wallet must be the fee payer (first signer) of the transaction');
  for (let i = 0; i < parsed.signatureCount; i++) {
    if (i === index) continue;
    const slot = tx.slice(parsed.signaturesOffset + i * 64, parsed.signaturesOffset + (i + 1) * 64);
    if (slot.every((b) => b === 0)) throw new Error('transaction requires additional signers; refusing to send');
  }
  const message = tx.slice(parsed.messageOffset);
  const sig = signer.sign(message);
  tx.set(sig, parsed.signaturesOffset + index * 64);
  return { signedBase64: Buffer.from(tx).toString('base64'), signature: bs58.encode(sig) };
}
