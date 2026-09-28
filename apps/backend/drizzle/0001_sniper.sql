ALTER TABLE "positions" ADD COLUMN "strategy" text DEFAULT 'main' NOT NULL;--> statement-breakpoint
ALTER TABLE "positions" ADD COLUMN "max_hold_minutes" integer;--> statement-breakpoint
ALTER TABLE "positions" ADD COLUMN "meta" jsonb;