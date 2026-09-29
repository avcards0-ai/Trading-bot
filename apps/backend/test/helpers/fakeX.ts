/**
 * A scriptable X API v2 (api.x.com/2) in its documented response shapes: user lookup, user
 * timelines and recent search, enough to exercise the real adapter and tracker end to end.
 */
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });

interface FakeUser {
  id: string;
  username: string;
  name: string;
  created_at: string;
  verified: boolean;
  public_metrics: { followers_count: number; following_count: number; tweet_count: number };
}

interface FakePost {
  id: string;
  text: string;
  author_id: string;
  created_at: string;
  entities?: { urls: { url: string; expanded_url: string }[] };
  public_metrics: { like_count: number; retweet_count: number; reply_count: number; quote_count: number };
}

let nextId = 1_800_000_000_000_000_000n;

export class FakeX {
  private readonly users = new Map<string, FakeUser>();
  private readonly timelines = new Map<string, FakePost[]>();
  private readonly mentions = new Map<string, FakePost[]>();
  readonly calls: string[] = [];

  addUser(
    username: string,
    opts: { followers?: number; ageDays?: number; verified?: boolean } = {},
  ): FakeUser {
    const existing = this.users.get(username.toLowerCase());
    if (existing) return existing;
    nextId += 1n;
    const u: FakeUser = {
      id: nextId.toString(),
      username,
      name: username,
      created_at: new Date(Date.now() - (opts.ageDays ?? 900) * 86_400_000).toISOString(),
      verified: opts.verified ?? false,
      public_metrics: { followers_count: opts.followers ?? 1000, following_count: 100, tweet_count: 500 },
    };
    this.users.set(username.toLowerCase(), u);
    return u;
  }

  /** A post on an account's timeline (newest first). */
  post(username: string, text: string, opts: { urls?: string[]; minutesAgo?: number } = {}): string {
    const u = this.addUser(username);
    nextId += 1n;
    const p: FakePost = {
      id: nextId.toString(),
      text,
      author_id: u.id,
      created_at: new Date(Date.now() - (opts.minutesAgo ?? 1) * 60_000).toISOString(),
      ...(opts.urls
        ? { entities: { urls: opts.urls.map((e, i) => ({ url: `https://t.co/x${i}`, expanded_url: e })) } }
        : {}),
      public_metrics: { like_count: 10, retweet_count: 2, reply_count: 1, quote_count: 0 },
    };
    this.timelines.set(u.id, [p, ...(this.timelines.get(u.id) ?? [])]);
    return p.id;
  }

  /** Posts by other accounts that mention an address (returned by recent search). */
  addMentions(
    address: string,
    posts: { username: string; text: string; followers?: number; ageDays?: number; minutesAgo?: number }[],
  ): void {
    const list = this.mentions.get(address) ?? [];
    for (const m of posts) {
      const u = this.addUser(m.username, { followers: m.followers, ageDays: m.ageDays });
      nextId += 1n;
      list.unshift({
        id: nextId.toString(),
        text: m.text,
        author_id: u.id,
        created_at: new Date(Date.now() - (m.minutesAgo ?? 10) * 60_000).toISOString(),
        public_metrics: { like_count: 1, retweet_count: 0, reply_count: 0, quote_count: 0 },
      });
    }
    this.mentions.set(address, list);
  }

  handle(url: URL): Response {
    this.calls.push(url.pathname);
    const path = url.pathname.replace(/^\/2/, '');
    if (path === '/users/by') {
      const names = (url.searchParams.get('usernames') ?? '').split(',').filter(Boolean);
      const found = names
        .map((n) => this.users.get(n.toLowerCase()))
        .filter((u): u is FakeUser => Boolean(u));
      const missing = names.filter((n) => !this.users.has(n.toLowerCase()));
      return json({
        ...(found.length ? { data: found } : {}),
        ...(missing.length
          ? {
              errors: missing.map((m) => ({
                value: m,
                detail: `Could not find user with usernames: [${m}].`,
                title: 'Not Found Error',
                resource_type: 'user',
                parameter: 'usernames',
                type: 'https://api.twitter.com/2/problems/resource-not-found',
              })),
            }
          : {}),
      });
    }
    const timeline = /^\/users\/(\d+)\/tweets$/.exec(path);
    if (timeline) {
      const since = url.searchParams.get('since_id');
      const max = Number(url.searchParams.get('max_results') ?? 10);
      const posts = (this.timelines.get(timeline[1] as string) ?? [])
        .filter((p) => !since || BigInt(p.id) > BigInt(since))
        .slice(0, max);
      return json(
        posts.length
          ? { data: posts, meta: { result_count: posts.length, newest_id: posts[0]?.id } }
          : { meta: { result_count: 0 } },
      );
    }
    if (path === '/tweets/search/recent') {
      const q = url.searchParams.get('query') ?? '';
      const address = /"([^"]+)"/.exec(q)?.[1] ?? '';
      const max = Number(url.searchParams.get('max_results') ?? 10);
      const all = this.mentions.get(address) ?? [];
      const posts = all.slice(0, max);
      const authors = [...new Set(posts.map((p) => p.author_id))];
      const users = [...this.users.values()].filter((u) => authors.includes(u.id));
      return json(
        posts.length
          ? {
              data: posts,
              includes: { users },
              meta: { result_count: posts.length, ...(all.length > max ? { next_token: 'next' } : {}) },
            }
          : { meta: { result_count: 0 } },
      );
    }
    return json({ title: 'Not Found', detail: `unhandled ${path}` }, 404);
  }
}
