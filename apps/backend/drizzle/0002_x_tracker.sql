CREATE TABLE "social_mentions" (
	"id" serial PRIMARY KEY NOT NULL,
	"token_id" integer,
	"chain" text NOT NULL,
	"address" text NOT NULL,
	"tweet_id" text NOT NULL,
	"author_handle" text NOT NULL,
	"author_followers" integer,
	"text" text NOT NULL,
	"tweeted_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "social_mentions" ADD CONSTRAINT "social_mentions_token_id_tokens_id_fk" FOREIGN KEY ("token_id") REFERENCES "public"."tokens"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "social_mentions_tweet_address_idx" ON "social_mentions" USING btree ("tweet_id","address");--> statement-breakpoint
CREATE INDEX "social_mentions_tweeted_idx" ON "social_mentions" USING btree ("tweeted_at");