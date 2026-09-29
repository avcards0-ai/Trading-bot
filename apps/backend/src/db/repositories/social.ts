import { desc, eq, gte, sql } from 'drizzle-orm';
import type { Chain, RiskLevel, SocialMention, SocialStatus } from '@memeguard/shared';
import type { Database } from '../client';
import { socialMentions, tokens } from '../schema';

export type SocialMentionRow = typeof socialMentions.$inferSelect;

const tokenCols = {
  symbol: tokens.symbol,
  rugScore: tokens.rugScore,
  overallRisk: tokens.overallRisk,
  lastDecisionLabel: tokens.lastDecisionLabel,
};

export class SocialRepository {
  constructor(private readonly db: Database) {}

  /** Stores a mention once per (post, token). Returns null when it was already recorded. */
  async insert(v: typeof socialMentions.$inferInsert): Promise<SocialMentionRow | null> {
    const [row] = await this.db
      .insert(socialMentions)
      .values(v)
      .onConflictDoNothing({ target: [socialMentions.tweetId, socialMentions.address] })
      .returning();
    return row ?? null;
  }

  async listRecent(limit: number): Promise<SocialMention[]> {
    const rows = await this.db
      .select({ m: socialMentions, t: tokenCols })
      .from(socialMentions)
      .leftJoin(tokens, eq(tokens.id, socialMentions.tokenId))
      .orderBy(desc(socialMentions.tweetedAt), desc(socialMentions.id))
      .limit(limit);
    return rows.map(({ m, t }) => ({
      id: m.id,
      tweetId: m.tweetId,
      url: `https://x.com/${m.authorHandle}/status/${m.tweetId}`,
      authorHandle: m.authorHandle,
      authorFollowers: m.authorFollowers,
      text: m.text,
      tweetedAt: m.tweetedAt.toISOString(),
      chain: m.chain as Chain,
      address: m.address,
      tokenId: m.tokenId,
      symbol: t?.symbol ?? null,
      rugScore: t?.rugScore ?? null,
      overallRisk: (t?.overallRisk as RiskLevel | null) ?? null,
      lastDecisionLabel: t?.lastDecisionLabel ?? null,
    }));
  }

  /** Tokens posted by the most distinct tracked accounts since `since`. */
  async mostMentioned(since: Date, limit: number): Promise<SocialStatus['mostMentioned']> {
    const rows = await this.db
      .select({
        chain: socialMentions.chain,
        address: socialMentions.address,
        tokenId: sql<number | null>`max(${socialMentions.tokenId})`,
        mentions: sql<number>`count(*)`,
        accounts: sql<string[]>`array_agg(distinct ${socialMentions.authorHandle})`,
      })
      .from(socialMentions)
      .where(gte(socialMentions.tweetedAt, since))
      .groupBy(socialMentions.chain, socialMentions.address)
      .orderBy(sql`count(distinct ${socialMentions.authorHandle}) desc`, sql`count(*) desc`)
      .limit(limit);
    const out: SocialStatus['mostMentioned'] = [];
    for (const r of rows) {
      const tokenId = r.tokenId === null ? null : Number(r.tokenId);
      const [t] = tokenId
        ? await this.db.select(tokenCols).from(tokens).where(eq(tokens.id, tokenId)).limit(1)
        : [];
      out.push({
        chain: r.chain as Chain,
        address: r.address,
        tokenId,
        symbol: t?.symbol ?? null,
        mentions: Number(r.mentions),
        accounts: r.accounts ?? [],
        rugScore: t?.rugScore ?? null,
        overallRisk: (t?.overallRisk as RiskLevel | null) ?? null,
        lastDecisionLabel: t?.lastDecisionLabel ?? null,
      });
    }
    return out;
  }
}
