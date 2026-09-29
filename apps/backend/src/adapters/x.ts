import { z } from 'zod';
import type { HttpClient } from '../lib/http';

/**
 * Official X (Twitter) API v2, app-only bearer token. https://docs.x.com/x-api
 *   GET /users/by?usernames=…                 user lookup (batch)
 *   GET /users/:id/tweets                     an account's recent posts
 *   GET /tweets/search/recent?query=…         posts from the last 7 days matching a query
 * Read-only: this project never posts, likes, follows or messages.
 */

const metrics = z
  .object({
    followers_count: z.number().nullish(),
    following_count: z.number().nullish(),
    tweet_count: z.number().nullish(),
  })
  .passthrough();

const userSchema = z
  .object({
    id: z.string(),
    username: z.string(),
    name: z.string().nullish(),
    created_at: z.string().nullish(),
    verified: z.boolean().nullish(),
    public_metrics: metrics.nullish(),
  })
  .passthrough();

const tweetSchema = z
  .object({
    id: z.string(),
    text: z.string(),
    author_id: z.string().nullish(),
    created_at: z.string().nullish(),
    entities: z
      .object({
        urls: z
          .array(z.object({ url: z.string().nullish(), expanded_url: z.string().nullish() }).passthrough())
          .nullish(),
      })
      .passthrough()
      .nullish(),
    public_metrics: z
      .object({ like_count: z.number().nullish(), retweet_count: z.number().nullish() })
      .passthrough()
      .nullish(),
  })
  .passthrough();

const apiError = z
  .object({ title: z.string().nullish(), detail: z.string().nullish(), value: z.string().nullish() })
  .passthrough();

const usersResponse = z
  .object({ data: z.array(userSchema).nullish(), errors: z.array(apiError).nullish() })
  .passthrough();

const tweetsResponse = z
  .object({
    data: z.array(tweetSchema).nullish(),
    includes: z
      .object({ users: z.array(userSchema).nullish() })
      .passthrough()
      .nullish(),
    meta: z
      .object({
        result_count: z.number().nullish(),
        newest_id: z.string().nullish(),
        next_token: z.string().nullish(),
      })
      .passthrough()
      .nullish(),
  })
  .passthrough();

export interface XUser {
  id: string;
  username: string;
  createdAt: Date | null;
  followers: number | null;
  verified: boolean | null;
}

export interface XPost {
  id: string;
  text: string;
  authorId: string | null;
  createdAt: Date | null;
  /** Expanded link targets (DexScreener, pump.fun, … pages often carry the contract address). */
  urls: string[];
  likes: number;
  reposts: number;
}

const toUser = (u: z.infer<typeof userSchema>): XUser => ({
  id: u.id,
  username: u.username,
  createdAt: u.created_at ? new Date(u.created_at) : null,
  followers: u.public_metrics?.followers_count ?? null,
  verified: u.verified ?? null,
});

const toPost = (t: z.infer<typeof tweetSchema>): XPost => ({
  id: t.id,
  text: t.text,
  authorId: t.author_id ?? null,
  createdAt: t.created_at ? new Date(t.created_at) : null,
  urls: (t.entities?.urls ?? []).map((u) => u.expanded_url ?? u.url ?? '').filter(Boolean),
  likes: t.public_metrics?.like_count ?? 0,
  reposts: t.public_metrics?.retweet_count ?? 0,
});

const USER_FIELDS = 'created_at,public_metrics,verified';
const TWEET_FIELDS = 'created_at,author_id,entities,public_metrics';

export class XAdapter {
  readonly name = 'x';

  constructor(private readonly http: HttpClient) {}

  /** Looks up handles (up to 100 per request). Missing or suspended accounts come back in `missing`. */
  async usersByUsername(handles: string[]): Promise<{ found: XUser[]; missing: string[] }> {
    const found: XUser[] = [];
    for (let i = 0; i < handles.length; i += 100) {
      const batch = handles.slice(i, i + 100);
      const r = await this.http.get('/users/by', {
        query: { usernames: batch.join(','), 'user.fields': USER_FIELDS },
        schema: usersResponse,
      });
      found.push(...(r.data ?? []).map(toUser));
    }
    const have = new Set(found.map((u) => u.username.toLowerCase()));
    return { found, missing: handles.filter((h) => !have.has(h.toLowerCase())) };
  }

  /** An account's recent original posts (reposts excluded), newest first. */
  async userPosts(userId: string, opts: { sinceId?: string | null; max?: number } = {}): Promise<XPost[]> {
    const r = await this.http.get(`/users/${encodeURIComponent(userId)}/tweets`, {
      query: {
        max_results: Math.max(5, Math.min(100, opts.max ?? 10)),
        exclude: 'retweets',
        'tweet.fields': TWEET_FIELDS,
        since_id: opts.sinceId ?? undefined,
      },
      schema: tweetsResponse,
    });
    return (r.data ?? []).map(toPost);
  }

  /** Recent posts (last 7 days) matching a query, with their authors. One page, newest first. */
  async searchRecent(
    query: string,
    max = 100,
  ): Promise<{ posts: XPost[]; users: Map<string, XUser>; truncated: boolean }> {
    const r = await this.http.get('/tweets/search/recent', {
      query: {
        query,
        max_results: Math.max(10, Math.min(100, max)),
        'tweet.fields': TWEET_FIELDS,
        expansions: 'author_id',
        'user.fields': USER_FIELDS,
      },
      schema: tweetsResponse,
    });
    const users = new Map((r.includes?.users ?? []).map((u) => [u.id, toUser(u)] as const));
    return { posts: (r.data ?? []).map(toPost), users, truncated: Boolean(r.meta?.next_token) };
  }
}
