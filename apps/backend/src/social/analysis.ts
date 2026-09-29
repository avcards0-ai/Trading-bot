import type { Chain, SocialData } from '@memeguard/shared';
import { SOL_MINT } from '../adapters/chains';
import { isValidSolanaAddress } from '../adapters/solana/keys';
import type { XPost, XUser } from '../adapters/x';

/** Quote and infrastructure mints that appear in posts but are never "the token". */
const IGNORED_SOLANA = new Set([
  SOL_MINT,
  'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v', // USDC
  'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB', // USDT
  'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA',
  'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb',
  '11111111111111111111111111111111',
]);

/** Chain names used in DexScreener / GeckoTerminal / Birdeye style links. */
const LINK_CHAINS: Record<string, Chain> = {
  solana: 'solana',
  sol: 'solana',
  ethereum: 'ethereum',
  eth: 'ethereum',
  base: 'base',
  bsc: 'bsc',
  arbitrum: 'arbitrum',
};

export interface MentionedToken {
  /** `null` for an EVM address whose chain must be looked up. */
  chain: Chain | null;
  address: string;
  /** Only seen inside a link: may be a pool/pair address rather than the token; confirm first. */
  fromLink: boolean;
}

const SOLANA_RE = /\b[1-9A-HJ-NP-Za-km-z]{32,44}\b/g;
const EVM_RE = /\b0x[a-fA-F0-9]{40}\b/g;

/**
 * Contract addresses in a post's text and links. Solana addresses must decode to 32 bytes; EVM
 * addresses have no chain in them, so the chain comes from a link (e.g. dexscreener.com/base/0x…)
 * or is left for the caller to resolve.
 */
export function extractTokenMentions(text: string, urls: string[] = []): MentionedToken[] {
  const out = new Map<string, MentionedToken>();
  const add = (chain: Chain | null, address: string, fromLink: boolean) => {
    const key = address.startsWith('0x') ? address.toLowerCase() : address;
    const e = out.get(key);
    out.set(key, {
      chain: e?.chain ?? chain,
      address: e?.address ?? address,
      fromLink: (e?.fromLink ?? true) && fromLink,
    });
  };
  const scan = (s: string, linkChain: Chain | null, fromLink: boolean) => {
    for (const m of s.match(EVM_RE) ?? [])
      add(linkChain && linkChain !== 'solana' ? linkChain : null, m, fromLink);
    for (const m of s.match(SOLANA_RE) ?? []) {
      if (IGNORED_SOLANA.has(m) || !isValidSolanaAddress(m)) continue;
      add('solana', m, fromLink);
    }
  };
  scan(text, null, false);
  for (const raw of urls) {
    try {
      const u = new URL(raw);
      const parts = u.pathname
        .split('/')
        .filter(Boolean)
        .map((p) => p.toLowerCase());
      const chain = /pump\.fun$/i.test(u.hostname)
        ? 'solana'
        : (parts.map((p) => LINK_CHAINS[p]).find((c): c is Chain => Boolean(c)) ?? null);
      scan(`${u.pathname} ${u.search}`, chain, true);
    } catch {
      scan(raw, null, true);
    }
  }
  return [...out.values()];
}

/** Text with links, handles, numbers and punctuation removed, for spotting copy-pasted posts. */
export function normalisePostText(text: string): string {
  // Addresses first: base58 is case-sensitive, so they must go before lowercasing.
  return text
    .replace(/https?:\/\/\S+/g, ' ')
    .replace(/@\w+/g, ' ')
    .replace(/\b[1-9A-HJ-NP-Za-km-z]{32,44}\b/g, ' ')
    .replace(/0x[a-fA-F0-9]{40}/g, ' ')
    .toLowerCase()
    .replace(/[\d$#.,!?:;'"()[\]{}*_~-]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

const days = (from: Date | null, now: Date) =>
  from ? Math.max(0, (now.getTime() - from.getTime()) / 86_400_000) : null;

/** Summarises posts that mention a token: volume, breadth, and how organic the authors look. */
export function summariseMentions(args: {
  posts: XPost[];
  users: Map<string, XUser>;
  truncated: boolean;
  official: { username: string; user: XUser | null } | null;
  now: Date;
}): SocialData {
  const { posts, users, now } = args;
  const hourAgo = now.getTime() - 3_600_000;
  const dayAgo = now.getTime() - 86_400_000;
  const authorIds = [...new Set(posts.map((p) => p.authorId).filter((a): a is string => Boolean(a)))];
  const authors = authorIds.map((id) => users.get(id)).filter((u): u is XUser => Boolean(u));
  const share = (n: number, d: number) => (d > 0 ? Math.round((n / d) * 1000) / 1000 : null);

  const texts = posts.map((p) => normalisePostText(p.text)).filter((t) => t.length >= 12);
  const counts = new Map<string, number>();
  for (const t of texts) counts.set(t, (counts.get(t) ?? 0) + 1);
  const duplicated = texts.filter((t) => (counts.get(t) ?? 0) > 1).length;

  const official = args.official;
  return {
    source: 'x',
    fetchedAt: now.toISOString(),
    mentions: {
      lastHour: posts.filter((p) => (p.createdAt?.getTime() ?? 0) >= hourAgo).length,
      last24h: posts.filter((p) => (p.createdAt?.getTime() ?? 0) >= dayAgo).length,
      sampleSize: posts.length,
      sampleTruncated: args.truncated,
    },
    uniqueAuthors: authorIds.length,
    freshAuthorShare: share(
      authors.filter((u) => (days(u.createdAt, now) ?? Infinity) < 30).length,
      authors.length,
    ),
    lowFollowerAuthorShare: share(authors.filter((u) => (u.followers ?? 0) < 50).length, authors.length),
    duplicateTextShare: share(duplicated, texts.length),
    topAuthors: [...authors]
      .sort((a, b) => (b.followers ?? 0) - (a.followers ?? 0))
      .slice(0, 5)
      .map((u) => ({
        username: u.username,
        followers: u.followers ?? 0,
        verified: u.verified ?? false,
        accountAgeDays: days(u.createdAt, now) === null ? null : Math.round(days(u.createdAt, now) as number),
      })),
    officialAccount: official
      ? official.user
        ? {
            username: official.user.username,
            status: 'ok',
            followers: official.user.followers,
            accountAgeDays:
              days(official.user.createdAt, now) === null
                ? null
                : Math.round((days(official.user.createdAt, now) as number) * 10) / 10,
            verified: official.user.verified,
          }
        : {
            username: official.username,
            status: 'not_found',
            followers: null,
            accountAgeDays: null,
            verified: null,
          }
      : null,
  };
}

/** The X handle in a social link, ignoring non-profile pages (communities, intents, posts' ids…). */
export function handleFromUrl(url: string | null | undefined): string | null {
  if (!url) return null;
  const m = /^https?:\/\/(?:www\.|mobile\.)?(?:twitter|x)\.com\/([A-Za-z0-9_]{1,15})(?:[/?#]|$)/i.exec(
    url.trim(),
  );
  if (!m) return null;
  const h = m[1] as string;
  return ['i', 'intent', 'home', 'search', 'share', 'hashtag', 'explore', 'communities'].includes(
    h.toLowerCase(),
  )
    ? null
    : h;
}
