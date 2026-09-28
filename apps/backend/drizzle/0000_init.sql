CREATE TABLE "accounts" (
	"id" serial PRIMARY KEY NOT NULL,
	"mode" text NOT NULL,
	"starting_balance_usd" double precision NOT NULL,
	"cash_usd" double precision NOT NULL,
	"realized_pnl_usd" double precision DEFAULT 0 NOT NULL,
	"peak_equity_usd" double precision NOT NULL,
	"max_drawdown_pct" double precision DEFAULT 0 NOT NULL,
	"day" text NOT NULL,
	"day_start_equity_usd" double precision NOT NULL,
	"halted" boolean DEFAULT false NOT NULL,
	"halt_reason" text,
	"halted_at" timestamp with time zone,
	"halt_clears_on_new_day" boolean DEFAULT false NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "accounts_mode_unique" UNIQUE("mode")
);
--> statement-breakpoint
CREATE TABLE "ai_decisions" (
	"id" serial PRIMARY KEY NOT NULL,
	"token_id" integer NOT NULL,
	"action" text NOT NULL,
	"label" text NOT NULL,
	"reason_code" text NOT NULL,
	"confidence" double precision NOT NULL,
	"rug_score" double precision,
	"strategy_score" double precision,
	"mode" text NOT NULL,
	"executed" boolean DEFAULT false NOT NULL,
	"trade_id" integer,
	"reasons" jsonb NOT NULL,
	"factors" jsonb NOT NULL,
	"stages" jsonb NOT NULL,
	"risk_checks" jsonb NOT NULL,
	"sizing" jsonb,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "alerts" (
	"id" serial PRIMARY KEY NOT NULL,
	"token_id" integer,
	"type" text NOT NULL,
	"severity" text NOT NULL,
	"title" text NOT NULL,
	"message" text NOT NULL,
	"data" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"dedupe_key" text,
	"acknowledged" boolean DEFAULT false NOT NULL,
	"delivered_to" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "backtest_runs" (
	"id" serial PRIMARY KEY NOT NULL,
	"name" text NOT NULL,
	"source" text NOT NULL,
	"synthetic" boolean NOT NULL,
	"config" jsonb NOT NULL,
	"result" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "event_log" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"level" text NOT NULL,
	"category" text NOT NULL,
	"message" text NOT NULL,
	"token_id" integer,
	"data" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "liquidity_history" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"token_id" integer NOT NULL,
	"ts" timestamp with time zone NOT NULL,
	"liquidity_usd" double precision,
	"lp_locked_percent" double precision,
	"lp_burned_percent" double precision,
	"source" text
);
--> statement-breakpoint
CREATE TABLE "performance_metrics" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"mode" text NOT NULL,
	"ts" timestamp with time zone DEFAULT now() NOT NULL,
	"equity_usd" double precision NOT NULL,
	"conservative_equity_usd" double precision NOT NULL,
	"cash_usd" double precision NOT NULL,
	"unrealized_pnl_usd" double precision NOT NULL,
	"realized_pnl_usd" double precision NOT NULL,
	"daily_pnl_usd" double precision NOT NULL,
	"drawdown_pct" double precision NOT NULL,
	"open_positions" integer NOT NULL,
	"win_rate" double precision
);
--> statement-breakpoint
CREATE TABLE "positions" (
	"id" serial PRIMARY KEY NOT NULL,
	"token_id" integer NOT NULL,
	"mode" text NOT NULL,
	"status" text DEFAULT 'open' NOT NULL,
	"quantity" double precision NOT NULL,
	"raw_quantity" text,
	"token_decimals" integer,
	"entry_price_usd" double precision NOT NULL,
	"cost_basis_usd" double precision NOT NULL,
	"stop_loss_price_usd" double precision NOT NULL,
	"take_profit_price_usd" double precision NOT NULL,
	"trailing_stop_percent" double precision,
	"highest_price_usd" double precision NOT NULL,
	"last_price_usd" double precision,
	"entry_liquidity_usd" double precision,
	"entry_rug_score" double precision,
	"exit_price_usd" double precision,
	"proceeds_usd" double precision,
	"realized_pnl_usd" double precision,
	"close_reason" text,
	"opened_at" timestamp with time zone DEFAULT now() NOT NULL,
	"closed_at" timestamp with time zone,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "price_history" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"token_id" integer NOT NULL,
	"ts" timestamp with time zone NOT NULL,
	"price_usd" double precision,
	"market_cap_usd" double precision,
	"fdv_usd" double precision,
	"volume_5m_usd" double precision,
	"volume_1h_usd" double precision,
	"volume_24h_usd" double precision,
	"buys_5m" integer,
	"sells_5m" integer,
	"buys_1h" integer,
	"sells_1h" integer,
	"price_change_5m_pct" double precision,
	"price_change_1h_pct" double precision,
	"source" text
);
--> statement-breakpoint
CREATE TABLE "risk_scores" (
	"id" serial PRIMARY KEY NOT NULL,
	"token_id" integer NOT NULL,
	"rug_score" double precision NOT NULL,
	"honeypot_risk" text NOT NULL,
	"liquidity_risk" text NOT NULL,
	"contract_risk" text NOT NULL,
	"wallet_concentration_risk" text NOT NULL,
	"developer_risk" text NOT NULL,
	"market_integrity_risk" text NOT NULL,
	"overall_risk" text NOT NULL,
	"is_likely_scam" boolean NOT NULL,
	"critical_flags" jsonb NOT NULL,
	"data_completeness" double precision NOT NULL,
	"model_version" text NOT NULL,
	"report" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "strategy_configs" (
	"id" serial PRIMARY KEY NOT NULL,
	"version" integer NOT NULL,
	"limits" jsonb NOT NULL,
	"strategy" jsonb NOT NULL,
	"active" boolean DEFAULT true NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "token_wallets" (
	"id" serial PRIMARY KEY NOT NULL,
	"token_id" integer NOT NULL,
	"wallet_id" integer NOT NULL,
	"role" text NOT NULL,
	"percent" double precision,
	"cluster_funder" text,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "tokens" (
	"id" serial PRIMARY KEY NOT NULL,
	"chain" text NOT NULL,
	"address" text NOT NULL,
	"name" text,
	"symbol" text,
	"decimals" integer,
	"pair_address" text,
	"dex_id" text,
	"pair_created_at" timestamp with time zone,
	"discovered_via" text DEFAULT 'manual' NOT NULL,
	"status" text DEFAULT 'watching' NOT NULL,
	"first_seen_at" timestamp with time zone DEFAULT now() NOT NULL,
	"last_analyzed_at" timestamp with time zone,
	"last_security_at" timestamp with time zone,
	"latest_snapshot" jsonb,
	"price_usd" double precision,
	"market_cap_usd" double precision,
	"liquidity_usd" double precision,
	"volume_24h_usd" double precision,
	"price_change_1h_pct" double precision,
	"holder_count" integer,
	"top_holder_percent" double precision,
	"top10_holder_percent" double precision,
	"buy_sell_ratio_1h" double precision,
	"rug_score" double precision,
	"overall_risk" text,
	"honeypot_risk" text,
	"contract_risk" text,
	"liquidity_risk" text,
	"concentration_risk" text,
	"last_decision" text,
	"last_decision_label" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "trades" (
	"id" serial PRIMARY KEY NOT NULL,
	"token_id" integer NOT NULL,
	"position_id" integer,
	"decision_id" integer,
	"mode" text NOT NULL,
	"side" text NOT NULL,
	"status" text NOT NULL,
	"requested_usd" double precision NOT NULL,
	"filled_usd" double precision,
	"quantity" double precision,
	"price_usd" double precision,
	"slippage_pct" double precision,
	"fee_usd" double precision,
	"tx_hash" text,
	"error" text,
	"reason" text NOT NULL,
	"raw" jsonb,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "transactions" (
	"id" serial PRIMARY KEY NOT NULL,
	"chain" text NOT NULL,
	"token_id" integer,
	"tx_hash" text NOT NULL,
	"wallet" text,
	"kind" text NOT NULL,
	"percent_of_supply" double precision,
	"usd_value" double precision,
	"counterparty" text,
	"source" text NOT NULL,
	"block_time" timestamp with time zone,
	"raw" jsonb,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "wallets" (
	"id" serial PRIMARY KEY NOT NULL,
	"chain" text NOT NULL,
	"address" text NOT NULL,
	"label" text,
	"wallet_created_at" timestamp with time zone,
	"age_is_lower_bound" boolean DEFAULT false NOT NULL,
	"funded_by" text,
	"risk_flags" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"metadata" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"first_seen_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "ai_decisions" ADD CONSTRAINT "ai_decisions_token_id_tokens_id_fk" FOREIGN KEY ("token_id") REFERENCES "public"."tokens"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "alerts" ADD CONSTRAINT "alerts_token_id_tokens_id_fk" FOREIGN KEY ("token_id") REFERENCES "public"."tokens"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "event_log" ADD CONSTRAINT "event_log_token_id_tokens_id_fk" FOREIGN KEY ("token_id") REFERENCES "public"."tokens"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "liquidity_history" ADD CONSTRAINT "liquidity_history_token_id_tokens_id_fk" FOREIGN KEY ("token_id") REFERENCES "public"."tokens"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "positions" ADD CONSTRAINT "positions_token_id_tokens_id_fk" FOREIGN KEY ("token_id") REFERENCES "public"."tokens"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "price_history" ADD CONSTRAINT "price_history_token_id_tokens_id_fk" FOREIGN KEY ("token_id") REFERENCES "public"."tokens"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "risk_scores" ADD CONSTRAINT "risk_scores_token_id_tokens_id_fk" FOREIGN KEY ("token_id") REFERENCES "public"."tokens"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "token_wallets" ADD CONSTRAINT "token_wallets_token_id_tokens_id_fk" FOREIGN KEY ("token_id") REFERENCES "public"."tokens"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "token_wallets" ADD CONSTRAINT "token_wallets_wallet_id_wallets_id_fk" FOREIGN KEY ("wallet_id") REFERENCES "public"."wallets"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "trades" ADD CONSTRAINT "trades_token_id_tokens_id_fk" FOREIGN KEY ("token_id") REFERENCES "public"."tokens"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "trades" ADD CONSTRAINT "trades_position_id_positions_id_fk" FOREIGN KEY ("position_id") REFERENCES "public"."positions"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "trades" ADD CONSTRAINT "trades_decision_id_ai_decisions_id_fk" FOREIGN KEY ("decision_id") REFERENCES "public"."ai_decisions"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "transactions" ADD CONSTRAINT "transactions_token_id_tokens_id_fk" FOREIGN KEY ("token_id") REFERENCES "public"."tokens"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "ai_decisions_token_idx" ON "ai_decisions" USING btree ("token_id","created_at");--> statement-breakpoint
CREATE INDEX "ai_decisions_action_idx" ON "ai_decisions" USING btree ("action","created_at");--> statement-breakpoint
CREATE INDEX "alerts_created_idx" ON "alerts" USING btree ("created_at");--> statement-breakpoint
CREATE INDEX "alerts_dedupe_idx" ON "alerts" USING btree ("dedupe_key","created_at");--> statement-breakpoint
CREATE INDEX "alerts_token_idx" ON "alerts" USING btree ("token_id");--> statement-breakpoint
CREATE INDEX "event_log_created_idx" ON "event_log" USING btree ("created_at");--> statement-breakpoint
CREATE INDEX "event_log_category_idx" ON "event_log" USING btree ("category");--> statement-breakpoint
CREATE INDEX "liquidity_history_token_ts_idx" ON "liquidity_history" USING btree ("token_id","ts");--> statement-breakpoint
CREATE INDEX "performance_metrics_mode_ts_idx" ON "performance_metrics" USING btree ("mode","ts");--> statement-breakpoint
CREATE INDEX "positions_status_idx" ON "positions" USING btree ("mode","status");--> statement-breakpoint
CREATE INDEX "positions_token_idx" ON "positions" USING btree ("token_id");--> statement-breakpoint
CREATE INDEX "price_history_token_ts_idx" ON "price_history" USING btree ("token_id","ts");--> statement-breakpoint
CREATE INDEX "risk_scores_token_idx" ON "risk_scores" USING btree ("token_id","created_at");--> statement-breakpoint
CREATE UNIQUE INDEX "token_wallets_uq" ON "token_wallets" USING btree ("token_id","wallet_id","role");--> statement-breakpoint
CREATE UNIQUE INDEX "tokens_chain_address_uq" ON "tokens" USING btree ("chain","address");--> statement-breakpoint
CREATE INDEX "tokens_rug_score_idx" ON "tokens" USING btree ("rug_score");--> statement-breakpoint
CREATE INDEX "tokens_last_analyzed_idx" ON "tokens" USING btree ("last_analyzed_at");--> statement-breakpoint
CREATE INDEX "tokens_status_idx" ON "tokens" USING btree ("status");--> statement-breakpoint
CREATE INDEX "trades_created_idx" ON "trades" USING btree ("created_at");--> statement-breakpoint
CREATE INDEX "trades_token_idx" ON "trades" USING btree ("token_id");--> statement-breakpoint
CREATE UNIQUE INDEX "transactions_uq" ON "transactions" USING btree ("chain","tx_hash","kind");--> statement-breakpoint
CREATE INDEX "transactions_token_idx" ON "transactions" USING btree ("token_id","block_time");--> statement-breakpoint
CREATE UNIQUE INDEX "wallets_chain_address_uq" ON "wallets" USING btree ("chain","address");