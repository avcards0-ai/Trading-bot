import { keccak_256 } from '@noble/hashes/sha3.js';
import { bytesToHex, utf8ToBytes } from '@noble/hashes/utils.js';

/** 4-byte function selector for a canonical signature, e.g. "blacklist(address)". */
export const selector = (signature: string): string =>
  bytesToHex(keccak_256(utf8ToBytes(signature)).slice(0, 4));

export const keccakHex = (bytes: Uint8Array): string => `0x${bytesToHex(keccak_256(bytes))}`;

export type SuspiciousCategory =
  'blacklist' | 'fee_control' | 'mint' | 'pause' | 'tx_limits' | 'balance_control' | 'upgrade' | 'cooldown';

/** Function signatures commonly used to restrict sells, change taxes, or alter balances. */
export const SUSPICIOUS_SIGNATURES: Record<SuspiciousCategory, string[]> = {
  blacklist: [
    'blacklist(address)',
    'addBlacklist(address)',
    'addToBlacklist(address)',
    'setBlacklist(address,bool)',
    'blacklistAddress(address,bool)',
    'setBlacklisted(address,bool)',
    'updateBlacklist(address,bool)',
    'addBot(address)',
    'addBots(address[])',
    'setBot(address,bool)',
    'setBots(address[])',
    'blockBots(address[])',
    'setSniper(address,bool)',
  ],
  fee_control: [
    'setFee(uint256)',
    'setFees(uint256,uint256)',
    'setTaxFeePercent(uint256)',
    'setBuyFee(uint256)',
    'setSellFee(uint256)',
    'setBuyTax(uint256)',
    'setSellTax(uint256)',
    'setTax(uint256,uint256)',
    'setTaxes(uint256,uint256)',
    'updateFees(uint256,uint256)',
    'updateBuyFees(uint256,uint256,uint256)',
    'updateSellFees(uint256,uint256,uint256)',
    'setFeePercent(uint256)',
  ],
  mint: ['mint(address,uint256)', 'mint(uint256)', 'mintTo(address,uint256)'],
  pause: ['pause()', 'setPaused(bool)', 'setTradingEnabled(bool)', 'setTrading(bool)', 'enableTrading(bool)'],
  tx_limits: [
    'setMaxTxAmount(uint256)',
    'setMaxWalletSize(uint256)',
    'setMaxTxPercent(uint256)',
    'setMaxWallet(uint256)',
  ],
  balance_control: ['setBalance(address,uint256)', 'burn(address,uint256)', 'rebase(uint256,int256)'],
  upgrade: ['upgradeTo(address)', 'upgradeToAndCall(address,bytes)'],
  cooldown: ['setCooldownEnabled(bool)', 'setCooldown(uint256)'],
};

const SELECTOR_INDEX: Map<string, { signature: string; category: SuspiciousCategory }> = (() => {
  const m = new Map<string, { signature: string; category: SuspiciousCategory }>();
  for (const [category, sigs] of Object.entries(SUSPICIOUS_SIGNATURES) as [SuspiciousCategory, string[]][]) {
    for (const signature of sigs) m.set(selector(signature), { signature, category });
  }
  return m;
})();

export interface BytecodeAnalysis {
  size: number;
  codeHash: string;
  selectors: Set<string>;
  hasSelfDestruct: boolean;
  hasDelegateCall: boolean;
  minimalProxyTarget: string | null;
  suspicious: { signature: string; category: SuspiciousCategory }[];
}

export function hexToBytes(hex: string): Uint8Array {
  const h = hex.startsWith('0x') ? hex.slice(2) : hex;
  if (h.length % 2 !== 0) throw new Error('odd-length hex');
  const out = new Uint8Array(h.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(h.slice(i * 2, i * 2 + 2), 16);
  return out;
}

/** Strip the trailing CBOR metadata blob (solc appends its length as the last 2 bytes). */
function executableLength(code: Uint8Array): number {
  if (code.length < 2) return code.length;
  const metaLen = ((code[code.length - 2] as number) << 8) | (code[code.length - 1] as number);
  if (metaLen > 0 && metaLen + 2 < code.length && metaLen < 256) {
    const marker = code[code.length - 2 - metaLen];
    // CBOR maps start with 0xa1..0xa5
    if (marker !== undefined && marker >= 0xa1 && marker <= 0xa5) return code.length - 2 - metaLen;
  }
  return code.length;
}

/**
 * Linear-sweep disassembly: collects PUSH4 immediates (dispatcher selectors) and notes opcodes,
 * skipping PUSH data so immediates are not misread as instructions. Heuristic by nature: data
 * sections can still produce false positives, so findings are weighted accordingly.
 */
export function analyzeBytecode(hex: string): BytecodeAnalysis {
  const code = hexToBytes(hex);
  const end = executableLength(code);
  const selectors = new Set<string>();
  let hasSelfDestruct = false;
  let hasDelegateCall = false;
  for (let pc = 0; pc < end; pc++) {
    const op = code[pc] as number;
    if (op >= 0x60 && op <= 0x7f) {
      const n = op - 0x5f;
      if (op === 0x63 && pc + 4 < code.length) selectors.add(bytesToHex(code.slice(pc + 1, pc + 5)));
      pc += n;
      continue;
    }
    if (op === 0xff) hasSelfDestruct = true;
    if (op === 0xf4) hasDelegateCall = true;
  }
  const hexStr = bytesToHex(code);
  // EIP-1167 minimal proxy: 363d3d373d3d3d363d73 <20-byte impl> 5af43d82803e903d91602b57fd5bf3
  const m = /^363d3d373d3d3d363d73([0-9a-f]{40})5af43d82803e903d91602b57fd5bf3/.exec(hexStr);
  const suspicious: BytecodeAnalysis['suspicious'] = [];
  for (const s of selectors) {
    const hit = SELECTOR_INDEX.get(s);
    if (hit) suspicious.push(hit);
  }
  return {
    size: code.length,
    codeHash: keccakHex(code),
    selectors,
    hasSelfDestruct,
    hasDelegateCall,
    minimalProxyTarget: m ? `0x${m[1]}` : null,
    suspicious,
  };
}
