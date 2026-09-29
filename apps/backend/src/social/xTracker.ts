import type { Chain, LoopStatus, RiskLevel, SocialData, SocialStatus } from '@memeguard/shared';
import type { MarketDataProvider } from '../adapters/types';
import type { XAdapter, XPost, XUser } from '../adapters/x';
import type { AlertService } from '../alerts/alertService';
import type { XConfig } from '../config/env';
import type { Repositories } from '../db/repositories';
import { Loop } from '../engine/loop';
import { errorMessage } from '../lib/errors';
import type { EventBus } from '../lib/events';
import type { Logger } from '../lib/logger';
import { extractTokenMentions, summariseMentions, type MentionedToken } from './analysis';

export interface XTrackerDeps {
  config: XConfig;
  chains: Chain[];
  x: XAdapter | null;
  repos: Repositories;
  market: MarketDataProvider;
  alerts: AlertService;
  bus: EventBus;
  logger: Logger;
  /** Queues a token for the normal analysis pipeline (every risk check still applies). */
  onToken: (tokenId: number) => void;
}

interface TrackedAccount {
  handle: string;
  user: XUser | null;
  found: boolean | null;
  sinceId: string | null;
  lastPolledAt: Date | null;
  lastError: string | null;
}

const EVM_CHAINS: Chain[] = ['ethereum', 'base', 'bsc', 'arbitrum'];
const SEARCH_CACHE_MS = 15 * 60_000;
const OFFICIAL_CACHE_MS = 24 * 3_600_000;

/** Snowflake ids are numeric strings; compare them as numbers. */
const newer = (a: string, b: string | null) => b === null || BigInt(a) > BigInt(b);

/**
 * X (Twitter) tracker, read-only:
 *  - watches the posts of configured accounts for token contract addresses; each new one is
 *    recorded, alerted and queued for the full analysis (a post never bypasses a risk check);
 *  - for tokens being analysed, looks up recent posts mentioning the contract address and the
 *    token's own X account, within an hourly search budget. The result feeds the rug model as
 *    evidence of manipulation (bot or copy-paste promotion, brand-new or missing accounts); it can
 *    only raise risk.
 */
export class XTracker {
  private readonly loop: Loop;
  private readonly accounts = new Map<string, TrackedAccount>();
  private readonly searches: number[] = [];
  private readonly cache = new Map<string, { at: number; data: SocialData }>();
  private readonly official = new Map<string, { at: number; user: XUser | null }>();

  constructor(private readonly d: XTrackerDeps) {
    for (const handle of d.config.trackedAccounts) {
      this.accounts.set(handle, {
        handle,
        user: null,
        found: null,
        sinceId: null,
        lastPolledAt: null,
        lastError: null,
      });
    }
    this.loop = new Loop('x-tracker', d.config.pollIntervalMs, () => this.poll(), d.logger);
  }

  get enabled(): boolean {
    return this.d.x !== null;
  }

  loopStatus(): LoopStatus[] {
    return this.enabled && this.accounts.size > 0 ? [this.loop.snapshot()] : [];
  }

  /** Watching accounts is a discovery source: it follows the engine's start/stop. */
  start(): void {
    if (this.enabled && this.accounts.size > 0) this.loop.start(true);
  }

  stop(): void {
    this.loop.stop();
  }

  async shutdown(): Promise<void> {
    this.loop.stop();
    await this.loop.idle(10_000);
  }

  // ------------------------------------------------------------------ tracked accounts

  /** One polling round over every tracked account. */
  async poll(): Promise<void> {
    const x = this.d.x;
    if (!x) return;
    const unresolved = [...this.accounts.values()].filter((a) => a.found === null);
    if (unresolved.length > 0) {
      const { found, missing } = await x.usersByUsername(unresolved.map((a) => a.handle));
      for (const u of found) {
        const a = this.accounts.get(u.username.toLowerCase());
        if (a) Object.assign(a, { user: u, found: true, lastError: null });
      }
      for (const h of missing) {
        const a = this.accounts.get(h.toLowerCase());
        if (a) Object.assign(a, { found: false, lastError: 'Account not found or suspended' });
      }
    }
    for (const a of this.accounts.values()) {
      if (!a.user) continue;
      try {
        const first = a.sinceId === null;
        const posts = await x.userPosts(a.user.id, { sinceId: a.sinceId, max: first ? 5 : 20 });
        for (const p of posts) if (newer(p.id, a.sinceId)) a.sinceId = p.id;
        // On the first poll only look at the last day, so old calls are not replayed.
        const dayAgo = Date.now() - 86_400_000;
        const fresh = first ? posts.filter((p) => (p.createdAt?.getTime() ?? 0) >= dayAgo) : posts;
        for (const p of [...fresh].reverse()) await this.handlePost(a, p);
        a.lastPolledAt = new Date();
        a.lastError = null;
      } catch (err) {
        a.lastError = errorMessage(err).slice(0, 200);
        this.d.logger.warn({ account: a.handle, err: a.lastError }, 'x tracker poll failed');
      }
    }
  }

  private async handlePost(a: TrackedAccount, post: XPost): Promise<void> {
    const tokens = await this.resolve(extractTokenMentions(post.text, post.urls));
    for (const { chain, address } of tokens) {
      const { row: token } = await this.d.repos.tokens.upsertDiscovered({
        chain,
        address,
        discoveredVia: `x:@${a.handle}`,
      });
      const mention = await this.d.repos.social.insert({
        tokenId: token.id,
        chain,
        address,
        tweetId: post.id,
        authorHandle: a.user?.username ?? a.handle,
        authorFollowers: a.user?.followers ?? null,
        text: post.text.slice(0, 1000),
        tweetedAt: post.createdAt ?? new Date(),
      });
      if (!mention) continue; // already seen
      const handle = mention.authorHandle;
      const followers = mention.authorFollowers;
      await this.d.alerts.raise({
        type: 'SOCIAL_MENTION',
        severity: 'info',
        title: `@${handle} posted a token`,
        message: `@${handle}${followers !== null ? ` (${followers.toLocaleString('en-US')} followers)` : ''} posted ${token.symbol ?? address} on ${chain}. It is being analysed now and is only traded if every risk check passes.`,
        tokenId: token.id,
        token: { chain, address, symbol: token.symbol },
        data: { tweetId: post.id, url: `https://x.com/${handle}/status/${post.id}` },
        dedupeKey: `SOCIAL:${post.id}:${address}`,
      });
      this.d.bus.publish({
        type: 'social.mention',
        data: {
          id: mention.id,
          tweetId: post.id,
          url: `https://x.com/${handle}/status/${post.id}`,
          authorHandle: handle,
          authorFollowers: followers,
          text: mention.text,
          tweetedAt: mention.tweetedAt.toISOString(),
          chain,
          address,
          tokenId: token.id,
          symbol: token.symbol,
          rugScore: token.rugScore,
          overallRisk: token.overallRisk as RiskLevel | null,
          lastDecisionLabel: token.lastDecisionLabel,
        },
      });
      this.d.onToken(token.id);
    }
  }

  /**
   * Turns candidate addresses into tokens on configured chains. Addresses typed in a post are
   * taken as given (the analysis will judge them); addresses seen only inside links, or EVM
   * addresses with no chain, are confirmed through market data first.
   */
  private async resolve(cands: MentionedToken[]): Promise<{ chain: Chain; address: string }[]> {
    const out: { chain: Chain; address: string }[] = [];
    const enabled = new Set(this.d.chains);
    const confirm = async (chain: Chain, addresses: string[]) => {
      if (addresses.length === 0 || !enabled.has(chain)) return [];
      try {
        const known = await this.d.market.getMarkets(chain, addresses);
        return addresses.filter((a) => known.has(a) || known.has(a.toLowerCase()));
      } catch (err) {
        this.d.logger.warn({ chain, err: errorMessage(err) }, 'x tracker could not confirm tokens');
        return [];
      }
    };
    const byChain = new Map<Chain, string[]>();
    const unknownEvm: string[] = [];
    for (const c of cands) {
      if (c.chain === 'solana' && !c.fromLink) {
        if (enabled.has('solana')) out.push({ chain: 'solana', address: c.address });
      } else if (c.chain) {
        byChain.set(c.chain, [...(byChain.get(c.chain) ?? []), c.address]);
      } else {
        unknownEvm.push(c.address);
      }
    }
    for (const [chain, addrs] of byChain) {
      for (const a of await confirm(chain, addrs)) out.push({ chain, address: a });
    }
    let pending = unknownEvm;
    for (const chain of EVM_CHAINS) {
      if (pending.length === 0) break;
      const hits = await confirm(chain, pending);
      for (const a of hits) out.push({ chain, address: a });
      pending = pending.filter((a) => !hits.includes(a));
    }
    return out;
  }

  // ------------------------------------------------------------------ mention search

  private searchesLastHour(): number {
    const cutoff = Date.now() - 3_600_000;
    while (this.searches.length > 0 && (this.searches[0] as number) < cutoff) this.searches.shift();
    return this.searches.length;
  }

  /**
   * Recent posts about one token plus its own X account. Returns null when search is off, the
   * hourly budget is used up (callers keep earlier data), or X is not configured.
   */
  async lookup(args: { chain: Chain; address: string; xHandle: string | null }): Promise<SocialData | null> {
    const x = this.d.x;
    if (!x || !this.d.config.mentionSearch) return null;
    const key = `${args.chain}:${args.address}`;
    const cached = this.cache.get(key);
    if (cached && Date.now() - cached.at < SEARCH_CACHE_MS) return cached.data;
    if (this.searchesLastHour() >= this.d.config.maxSearchesPerHour) return null;
    this.searches.push(Date.now());

    const found = await x.searchRecent(`"${args.address}" -is:retweet`, 100);
    let official: { username: string; user: XUser | null } | null = null;
    if (args.xHandle) {
      const h = args.xHandle.toLowerCase();
      let entry = this.official.get(h);
      if (!entry || Date.now() - entry.at > OFFICIAL_CACHE_MS) {
        const r = await x.usersByUsername([args.xHandle]);
        entry = { at: Date.now(), user: r.found[0] ?? null };
        this.official.set(h, entry);
      }
      official = { username: args.xHandle, user: entry.user };
    }
    const data = summariseMentions({ ...found, official, now: new Date() });
    this.cache.set(key, { at: Date.now(), data });
    return data;
  }

  // ------------------------------------------------------------------ status

  async status(): Promise<SocialStatus> {
    return {
      enabled: this.enabled,
      disabledReason: this.enabled
        ? null
        : 'The X tracker is off. Set X_BEARER_TOKEN (and optionally X_TRACKED_ACCOUNTS) in .env.',
      trackedAccounts: [...this.accounts.values()].map((a) => ({
        handle: a.user?.username ?? a.handle,
        found: a.found,
        followers: a.user?.followers ?? null,
        lastPolledAt: a.lastPolledAt?.toISOString() ?? null,
        lastError: a.lastError,
      })),
      mentionSearch: {
        enabled: this.enabled && this.d.config.mentionSearch,
        usedLastHour: this.searchesLastHour(),
        maxPerHour: this.d.config.maxSearchesPerHour,
      },
      mentions: await this.d.repos.social.listRecent(100),
      mostMentioned: await this.d.repos.social.mostMentioned(new Date(Date.now() - 86_400_000), 20),
    };
  }
}
