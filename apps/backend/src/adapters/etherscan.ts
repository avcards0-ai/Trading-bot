import { z } from 'zod';
import type { Chain, DeveloperActivity, DeveloperEvent } from '@memeguard/shared';
import { ProviderError, ProviderResponseError } from '../lib/errors';
import type { HttpClient } from '../lib/http';
import { toNum } from '../lib/math';
import { EVM_CHAIN_IDS, isEvm } from './chains';
import type {
  DeployerHistorySource,
  DeveloperActivitySource,
  SecuritySource,
  SnapshotContribution,
  TokenContext,
  WalletProfile,
  WalletProfiler,
} from './types';

/**
 * Etherscan V2 multichain API (one key for Ethereum, BSC, Base, Arbitrum).
 * https://docs.etherscan.io/etherscan-v2
 *   module=contract&action=getsourcecode         -> verification status
 *   module=contract&action=getcontractcreation   -> deployer + creation tx
 *   module=account&action=txlist                 -> wallet age / funder / contracts deployed
 *   module=account&action=tokentx                -> developer token transfers
 */
export const ETHERSCAN_BASE_URL = 'https://api.etherscan.io/v2/api';

const envelope = z.object({
  status: z.string(),
  message: z.string(),
  result: z.unknown(),
});

const txSchema = z
  .object({
    hash: z.string(),
    from: z.string(),
    to: z.string().nullish(),
    timeStamp: z.string(),
    contractAddress: z.string().nullish(),
    isError: z.string().nullish(),
  })
  .passthrough();

const tokenTxSchema = z
  .object({
    hash: z.string(),
    from: z.string(),
    to: z.string(),
    timeStamp: z.string(),
    value: z.string(),
    tokenDecimal: z.string(),
  })
  .passthrough();

export class EtherscanAdapter
  implements SecuritySource, WalletProfiler, DeveloperActivitySource, DeployerHistorySource
{
  readonly name = 'etherscan';

  constructor(
    private readonly http: HttpClient,
    private readonly apiKey: string,
    private readonly opts: { freshWalletAgeHours: number } = { freshWalletAgeHours: 72 },
  ) {}

  supports(chain: Chain): boolean {
    return isEvm(chain);
  }

  private async call(chain: Chain, params: Record<string, string | number>): Promise<unknown> {
    if (!isEvm(chain)) throw new ProviderError(this.name, `unsupported chain ${chain}`);
    const res = await this.http.get('', {
      query: { chainid: EVM_CHAIN_IDS[chain], ...params, apikey: this.apiKey },
      schema: envelope,
    });
    if (res.status === '1') return res.result;
    const text = typeof res.result === 'string' ? res.result : res.message;
    if (/no (transactions|records) found/i.test(res.message) || /no (transactions|records) found/i.test(text))
      return [];
    if (/rate limit/i.test(text)) throw new ProviderError(this.name, text, 429, true);
    throw new ProviderResponseError(this.name, text);
  }

  async inspect(ctx: TokenContext): Promise<SnapshotContribution | null> {
    const [source, creation] = await Promise.all([
      this.call(ctx.chain, { module: 'contract', action: 'getsourcecode', address: ctx.address }),
      this.call(ctx.chain, {
        module: 'contract',
        action: 'getcontractcreation',
        contractaddresses: ctx.address,
      }).catch(() => []),
    ]);
    const src = z
      .array(
        z
          .object({
            SourceCode: z.string().nullish(),
            Proxy: z.string().nullish(),
            Implementation: z.string().nullish(),
          })
          .passthrough(),
      )
      .safeParse(source);
    const created = z.array(z.object({ contractCreator: z.string() }).passthrough()).safeParse(creation);
    const first = src.success ? src.data[0] : undefined;
    const creator = created.success ? (created.data[0]?.contractCreator.toLowerCase() ?? null) : null;
    return {
      source: this.name,
      contract: {
        isVerified: first ? (first.SourceCode ?? '').length > 0 : undefined,
        isProxy: first?.Proxy === '1' ? true : undefined,
        proxyImplementation: first?.Implementation ? first.Implementation.toLowerCase() : undefined,
      },
      deployer: creator ? { address: creator } : undefined,
    };
  }

  private async firstTransactions(chain: Chain, address: string, count: number) {
    const r = await this.call(chain, {
      module: 'account',
      action: 'txlist',
      address,
      startblock: 0,
      endblock: 99_999_999,
      page: 1,
      offset: count,
      sort: 'asc',
    });
    const parsed = z.array(txSchema).safeParse(r);
    return parsed.success ? parsed.data : [];
  }

  async profile(chain: Chain, addresses: string[]): Promise<Map<string, WalletProfile>> {
    const out = new Map<string, WalletProfile>();
    for (const address of addresses) {
      try {
        const txs = await this.firstTransactions(chain, address, 5);
        const first = txs[0];
        const incoming = txs.find((t) => (t.to ?? '').toLowerCase() === address.toLowerCase());
        out.set(address, {
          address,
          createdAt: first ? new Date(Number(first.timeStamp) * 1000) : null,
          ageIsLowerBound: false,
          fundedBy: incoming ? incoming.from.toLowerCase() : null,
        });
      } catch {
        // tolerate individual failures
      }
    }
    return out;
  }

  async history(
    chain: Chain,
    deployer: string,
  ): Promise<{ tokensCreated: number | null; walletCreatedAt: Date | null }> {
    const txs = await this.firstTransactions(chain, deployer, 1000);
    const created = txs.filter(
      (t) => (!t.to || t.to === '') && t.contractAddress && t.isError !== '1',
    ).length;
    return {
      tokensCreated: created,
      walletCreatedAt: txs[0] ? new Date(Number(txs[0].timeStamp) * 1000) : null,
    };
  }

  async activity(
    chain: Chain,
    token: {
      address: string;
      totalSupply: number | null;
      decimals: number | null;
      pairAddress: string | null;
    },
    devAddress: string,
    lookbackMinutes: number,
  ): Promise<DeveloperActivity> {
    const r = await this.call(chain, {
      module: 'account',
      action: 'tokentx',
      contractaddress: token.address,
      address: devAddress,
      page: 1,
      offset: 50,
      sort: 'desc',
    });
    const parsed = z.array(tokenTxSchema).safeParse(r);
    const since = Date.now() - lookbackMinutes * 60_000;
    const dev = devAddress.toLowerCase();
    const pair = token.pairAddress?.toLowerCase() ?? null;
    const events: DeveloperEvent[] = [];
    let moved = 0;
    for (const t of parsed.success ? parsed.data : []) {
      const ts = Number(t.timeStamp) * 1000;
      if (ts < since) continue;
      const amount = (toNum(t.value) ?? 0) / 10 ** (toNum(t.tokenDecimal) ?? token.decimals ?? 18);
      const pct = token.totalSupply ? (amount / token.totalSupply) * 100 : null;
      if (t.from.toLowerCase() === dev) {
        moved += pct ?? 0;
        const to = t.to.toLowerCase();
        events.push({
          kind: pair && to === pair ? 'sell' : 'transfer_out',
          signature: t.hash,
          timestamp: new Date(ts).toISOString(),
          percentOfSupply: pct,
          counterparty: to,
        });
      } else if (t.to.toLowerCase() === dev) {
        events.push({
          kind: 'transfer_in',
          signature: t.hash,
          timestamp: new Date(ts).toISOString(),
          percentOfSupply: pct,
          counterparty: t.from.toLowerCase(),
        });
      }
    }
    // Transfers into the pair are sells; other outgoing transfers are checked for fresh recipients.
    const recipients = [
      ...new Set(events.filter((e) => e.kind === 'transfer_out').map((e) => e.counterparty as string)),
    ].slice(0, 5);
    const profiles =
      recipients.length > 0 ? await this.profile(chain, recipients) : new Map<string, WalletProfile>();
    const cutoff = Date.now() - this.opts.freshWalletAgeHours * 3_600_000;
    const fresh = [...profiles.values()].filter((p) => p.createdAt && p.createdAt.getTime() >= cutoff).length;
    return {
      sources: [this.name],
      devAddress: dev,
      lookbackMinutes,
      transfersOut: events.filter((e) => e.kind === 'transfer_out').length,
      sells: events.filter((e) => e.kind === 'sell').length,
      percentOfSupplyMoved: token.totalSupply ? moved : null,
      transfersToFreshWallets: fresh,
      events,
    };
  }
}
