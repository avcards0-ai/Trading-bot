import { z } from 'zod';
import type { Chain, ContractData, ProviderWarning } from '@memeguard/shared';
import type { JsonRpcClient } from '../../lib/jsonRpc';
import type { SecuritySource, SnapshotContribution, TokenContext } from '../types';
import { analyzeBytecode, type BytecodeAnalysis } from './bytecode';

/** Storage slots used by upgradeable proxy standards. */
export const PROXY_SLOTS = {
  eip1967Implementation: '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc',
  eip1967Beacon: '0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50',
  eip1967Admin: '0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103',
  eip1822Proxiable: '0xc5f16f0fcc639fa48a6947836d9850f504798523bf8c9a3a87d5876cf622bcf7',
  ozLegacyImplementation: '0x7050c9e0f4ca769c69bd3a8ef740bc37934f8e2c036e5a723fd8ee048ed3f8c3',
} as const;

const OWNER_SELECTORS = ['0x8da5cb5b' /* owner() */, '0x893d20e8' /* getOwner() */];

const hex = z.string().regex(/^0x[0-9a-fA-F]*$/);

export const wordToAddress = (word: string): string | null => {
  const h = word.startsWith('0x') ? word.slice(2) : word;
  if (h.length < 40) return null;
  const addr = `0x${h.slice(-40)}`.toLowerCase();
  return /^0x0{40}$/.test(addr) ? null : addr;
};

export class EvmInspector implements SecuritySource {
  readonly name: string;

  constructor(
    private readonly chain: Chain,
    private readonly rpc: JsonRpcClient,
  ) {
    this.name = `evm-rpc:${chain}`;
  }

  supports(chain: Chain): boolean {
    return chain === this.chain;
  }

  private getCode(address: string) {
    return this.rpc.call('eth_getCode', [address, 'latest'], hex);
  }

  private getStorage(address: string, slot: string) {
    return this.rpc.call('eth_getStorageAt', [address, slot, 'latest'], hex);
  }

  private async tryCall(address: string, data: string): Promise<string | null> {
    try {
      const r = await this.rpc.call('eth_call', [{ to: address, data }, 'latest'], hex);
      return r.length >= 66 ? r : null;
    } catch {
      return null; // reverted / not implemented
    }
  }

  async inspect(ctx: TokenContext): Promise<SnapshotContribution | null> {
    const code = await this.getCode(ctx.address);
    const warnings: ProviderWarning[] = [];
    if (code === '0x' || code.length <= 2) {
      return {
        source: this.name,
        contract: { tokenProgram: 'evm', isVerified: false },
        warnings: [
          {
            source: this.name,
            code: 'no_code',
            level: 'danger',
            message: 'No contract code at token address',
          },
        ],
      };
    }
    const own = analyzeBytecode(code);

    // Proxy detection
    let implementation: string | null = own.minimalProxyTarget;
    let proxyKind: string | null = own.minimalProxyTarget ? 'EIP-1167 minimal proxy' : null;
    for (const [kind, slot] of Object.entries(PROXY_SLOTS)) {
      if (implementation) break;
      if (kind === 'eip1967Admin') continue;
      const word = await this.getStorage(ctx.address, slot).catch(() => '0x');
      const addr = wordToAddress(word);
      if (addr) {
        proxyKind = kind;
        if (kind === 'eip1967Beacon') {
          // implementation() on the beacon
          const implWord = await this.tryCall(addr, '0x5c60da1b');
          implementation = implWord ? wordToAddress(implWord) : addr;
        } else {
          implementation = addr;
        }
      }
    }
    let impl: BytecodeAnalysis | null = null;
    if (implementation) {
      const implCode = await this.getCode(implementation).catch(() => '0x');
      if (implCode.length > 2) impl = analyzeBytecode(implCode);
    }
    const effective = impl ?? own;

    // Ownership
    let ownerAddress: string | null = null;
    let ownerKnown = false;
    for (const sel of OWNER_SELECTORS) {
      const r = await this.tryCall(ctx.address, sel);
      if (r !== null) {
        ownerKnown = true;
        ownerAddress = wordToAddress(r);
        break;
      }
    }

    const cats = new Set(effective.suspicious.map((s) => s.category));
    const contract: Partial<ContractData> = {
      tokenProgram: 'evm',
      isProxy: implementation !== null,
      proxyImplementation: implementation,
      ownerAddress: ownerKnown ? ownerAddress : undefined,
      ownershipRenounced: ownerKnown ? ownerAddress === null || ownerAddress.endsWith('dead') : undefined,
      hasBlacklist: cats.has('blacklist') ? true : undefined,
      taxModifiable: cats.has('fee_control') ? true : undefined,
      mintable: cats.has('mint') ? true : undefined,
      transferPausable: cats.has('pause') ? true : undefined,
      ownerCanChangeBalance: cats.has('balance_control') ? true : undefined,
      tradingCooldown: cats.has('cooldown') ? true : undefined,
      selfDestruct: effective.hasSelfDestruct ? true : undefined,
      suspiciousFunctions: effective.suspicious.map((s) => s.signature),
      codeHash: impl ? `${own.codeHash}:${impl.codeHash}` : own.codeHash,
    };
    if (proxyKind) {
      warnings.push({
        source: this.name,
        code: 'upgradeable_proxy',
        level: 'warn',
        message: `Upgradeable proxy (${proxyKind}); logic can be replaced by the admin`,
      });
    }
    return { source: this.name, contract, warnings };
  }
}
