import { describe, expect, it } from 'vitest';
import type { SocialData } from '@memeguard/shared';
import type { XPost, XUser } from '../../src/adapters/x';
import { socialFactors } from '../../src/analysis/rug/factors';
import { ConfigError, collectSecrets, loadConfig, safeConfigView } from '../../src/config/env';
import {
  extractTokenMentions,
  handleFromUrl,
  normalisePostText,
  summariseMentions,
} from '../../src/social/analysis';
import { cleanSnapshot } from '../helpers/snapshots';
import { walletAddress } from '../helpers/fakeSolana';

const MINT = walletAddress('social-mint');
const OTHER = walletAddress('social-other');
const EVM = '0x6982508145454Ce325dDbE47a25d4ec3d2311933';
const SOL = 'So11111111111111111111111111111111111111112';

describe('token mentions in posts', () => {
  it('finds Solana contract addresses in the text and ignores SOL/USDC mints', () => {
    const r = extractTokenMentions(`new gem 👀 CA: ${MINT} paired with ${SOL}`);
    expect(r).toEqual([{ chain: 'solana', address: MINT, fromLink: false }]);
  });

  it('leaves the chain of a bare EVM address open, but takes it from a link', () => {
    expect(extractTokenMentions(`ape ${EVM}`)).toEqual([{ chain: null, address: EVM, fromLink: false }]);
    expect(extractTokenMentions('chart', [`https://dexscreener.com/base/${EVM}`])).toEqual([
      { chain: 'base', address: EVM, fromLink: true },
    ]);
  });

  it('marks link-only addresses (which may be pools) and prefers text over links', () => {
    const r = extractTokenMentions(`${MINT}`, [
      `https://pump.fun/coin/${MINT}`,
      `https://dexscreener.com/solana/${OTHER}`,
    ]);
    expect(r).toEqual([
      { chain: 'solana', address: MINT, fromLink: false },
      { chain: 'solana', address: OTHER, fromLink: true },
    ]);
  });

  it('rejects strings that look like base58 but are not 32-byte addresses', () => {
    expect(extractTokenMentions('1111111111111111111111111111111111111111111')).toEqual([]);
  });

  it('normalises posts so copy-paste shilling is recognisable', () => {
    expect(normalisePostText(`🚀 $PEPE to 100x!!! ${MINT} https://t.co/abc @someone`)).toBe(
      normalisePostText(`🚀 $PEPE to 1000x ${OTHER} https://t.co/zzz @other`),
    );
  });

  it('reads X handles from profile links only', () => {
    expect(handleFromUrl('https://x.com/TokenTeam')).toBe('TokenTeam');
    expect(handleFromUrl('https://twitter.com/token_team?s=21')).toBe('token_team');
    expect(handleFromUrl('https://x.com/i/communities/1234')).toBeNull();
    expect(handleFromUrl('https://example.com/x')).toBeNull();
  });
});

const now = new Date('2026-06-01T12:00:00Z');
const user = (id: string, followers: number, ageDays: number): XUser => ({
  id,
  username: `u${id}`,
  createdAt: new Date(now.getTime() - ageDays * 86_400_000),
  followers,
  verified: false,
});
const post = (id: string, author: string, text: string, minutesAgo: number): XPost => ({
  id,
  text,
  authorId: author,
  createdAt: new Date(now.getTime() - minutesAgo * 60_000),
  urls: [],
  likes: 0,
  reposts: 0,
});

describe('mention summary', () => {
  it('measures volume, breadth and how organic the authors look', () => {
    const users = new Map(
      [user('1', 20, 3), user('2', 10, 5), user('3', 50_000, 2000), user('4', 5, 1)].map((u) => [u.id, u]),
    );
    const s = summariseMentions({
      posts: [
        post('a', '1', 'buy now this is going to the moon trust me', 5),
        post('b', '2', 'buy now this is going to the moon trust me', 30),
        post('c', '3', 'interesting new launch, checking the contract', 90),
        post('d', '4', 'buy now this is going to the moon trust me', 60 * 30),
      ],
      users,
      truncated: false,
      official: { username: 'TokenTeam', user: null },
      now,
    });
    expect(s.mentions).toEqual({ lastHour: 2, last24h: 3, sampleSize: 4, sampleTruncated: false });
    expect(s.uniqueAuthors).toBe(4);
    expect(s.freshAuthorShare).toBe(0.75);
    expect(s.lowFollowerAuthorShare).toBe(0.75);
    expect(s.duplicateTextShare).toBe(0.75);
    expect(s.topAuthors[0]).toMatchObject({ username: 'u3', followers: 50_000 });
    expect(s.officialAccount).toEqual({
      username: 'TokenTeam',
      status: 'not_found',
      followers: null,
      accountAgeDays: null,
      verified: null,
    });
  });
});

const social = (patch: Partial<SocialData>): SocialData => ({
  source: 'x',
  fetchedAt: now.toISOString(),
  mentions: { lastHour: 1, last24h: 5, sampleSize: 5, sampleTruncated: false },
  uniqueAuthors: 5,
  freshAuthorShare: 0.1,
  lowFollowerAuthorShare: 0.1,
  duplicateTextShare: 0,
  topAuthors: [],
  officialAccount: null,
  ...patch,
});

describe('X risk factors', () => {
  const ids = (s: SocialData | null | undefined) =>
    socialFactors(cleanSnapshot({ social: s })).map((f) => f.id);

  it('adds nothing without X data (optional source, never counted as missing)', () => {
    expect(ids(null)).toEqual([]);
    expect(ids(undefined)).toEqual([]);
    expect(ids(social({}))).toEqual([]);
  });

  it('flags a missing or brand-new official account', () => {
    expect(
      ids(
        social({
          officialAccount: {
            username: 't',
            status: 'not_found',
            followers: null,
            accountAgeDays: null,
            verified: null,
          },
        }),
      ),
    ).toEqual(['x_account_missing']);
    const f = socialFactors(
      cleanSnapshot({
        social: social({
          officialAccount: {
            username: 't',
            status: 'ok',
            followers: 12,
            accountAgeDays: 0.5,
            verified: false,
          },
        }),
      }),
    );
    expect(f[0]).toMatchObject({ id: 'x_account_new', points: 35, category: 'market' });
  });

  it('flags coordinated promotion only with enough distinct authors', () => {
    expect(ids(social({ freshAuthorShare: 0.9 }))).toEqual(['x_coordinated_promotion']);
    expect(ids(social({ duplicateTextShare: 0.55 }))).toEqual(['x_coordinated_promotion']);
    expect(ids(social({ uniqueAuthors: 3, freshAuthorShare: 1 }))).toEqual([]);
  });
});

describe('X configuration', () => {
  const env = (e: Record<string, string>) => e as NodeJS.ProcessEnv;

  it('is off without a bearer token and keeps the token out of the safe view', () => {
    expect(loadConfig(env({})).x.bearerToken).toBeNull();
    const c = loadConfig(
      env({ X_BEARER_TOKEN: 'AAAAxbearer-secret-token', X_TRACKED_ACCOUNTS: '@Caller1, caller1,other_2' }),
    );
    expect(c.x.trackedAccounts).toEqual(['caller1', 'other_2']);
    expect(collectSecrets(c)).toContain('AAAAxbearer-secret-token');
    expect(JSON.stringify(safeConfigView(c))).not.toContain('AAAAxbearer-secret-token');
  });

  it('rejects invalid handles', () => {
    expect(() => loadConfig(env({ X_TRACKED_ACCOUNTS: 'not a handle' }))).toThrow(ConfigError);
    expect(() => loadConfig(env({ X_TRACKED_ACCOUNTS: 'waytoolonghandle_1234' }))).toThrow(ConfigError);
  });
});
