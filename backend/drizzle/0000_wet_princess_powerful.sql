CREATE EXTENSION IF NOT EXISTS "pgcrypto";
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "article_read_status" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"article_id" uuid NOT NULL,
	"is_read" boolean DEFAULT false NOT NULL,
	"read_at" timestamp
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "article_star_status" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"article_id" uuid NOT NULL,
	"is_starred" boolean DEFAULT false NOT NULL,
	"starred_at" timestamp
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "articles" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"feed_id" uuid NOT NULL,
	"guid" varchar(2000) NOT NULL,
	"title" varchar(1000) NOT NULL,
	"content" text,
	"summary" text,
	"url" varchar(2000),
	"author" varchar(500),
	"image_url" varchar(2000),
	"published_at" timestamp,
	"created_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "feeds" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"folder_id" uuid,
	"title" varchar(500) NOT NULL,
	"feed_url" varchar(2000) NOT NULL,
	"site_url" varchar(2000),
	"icon_url" varchar(2000),
	"description" text,
	"last_fetched_at" timestamp,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "folders" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"name" varchar(255) NOT NULL,
	"order" integer DEFAULT 0 NOT NULL,
	"created_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "users" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"email" varchar(255) NOT NULL,
	"password_hash" varchar(255) NOT NULL,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL,
	CONSTRAINT "users_email_unique" UNIQUE("email")
);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "article_read_user_article_idx" ON "article_read_status" ("user_id","article_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "article_star_user_article_idx" ON "article_star_status" ("user_id","article_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "articles_feed_id_idx" ON "articles" ("feed_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "articles_guid_idx" ON "articles" ("guid");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "articles_published_at_idx" ON "articles" ("published_at");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "feeds_user_id_idx" ON "feeds" ("user_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "feeds_folder_id_idx" ON "feeds" ("folder_id");--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "article_read_status" ADD CONSTRAINT "article_read_status_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE cascade ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "article_read_status" ADD CONSTRAINT "article_read_status_article_id_articles_id_fk" FOREIGN KEY ("article_id") REFERENCES "articles"("id") ON DELETE cascade ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "article_star_status" ADD CONSTRAINT "article_star_status_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE cascade ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "article_star_status" ADD CONSTRAINT "article_star_status_article_id_articles_id_fk" FOREIGN KEY ("article_id") REFERENCES "articles"("id") ON DELETE cascade ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "articles" ADD CONSTRAINT "articles_feed_id_feeds_id_fk" FOREIGN KEY ("feed_id") REFERENCES "feeds"("id") ON DELETE cascade ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "feeds" ADD CONSTRAINT "feeds_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE cascade ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "feeds" ADD CONSTRAINT "feeds_folder_id_folders_id_fk" FOREIGN KEY ("folder_id") REFERENCES "folders"("id") ON DELETE set null ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
--> statement-breakpoint
DO $$ BEGIN
 ALTER TABLE "folders" ADD CONSTRAINT "folders_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE cascade ON UPDATE no action;
EXCEPTION
 WHEN duplicate_object THEN null;
END $$;
