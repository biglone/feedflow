import {
  pgTable,
  uuid,
  varchar,
  text,
  timestamp,
  boolean,
  integer,
  index,
} from "drizzle-orm/pg-core";
import { relations } from "drizzle-orm";

export const users = pgTable("users", {
  id: uuid("id").primaryKey().defaultRandom(),
  email: varchar("email", { length: 255 }).unique().notNull(),
  passwordHash: varchar("password_hash", { length: 255 }).notNull(),
  createdAt: timestamp("created_at").defaultNow().notNull(),
  updatedAt: timestamp("updated_at").defaultNow().notNull(),
});

export const usersRelations = relations(users, ({ many }) => ({
  feeds: many(feeds),
  folders: many(folders),
}));

export const folders = pgTable("folders", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .references(() => users.id, { onDelete: "cascade" })
    .notNull(),
  name: varchar("name", { length: 255 }).notNull(),
  order: integer("order").default(0).notNull(),
  createdAt: timestamp("created_at").defaultNow().notNull(),
});

export const foldersRelations = relations(folders, ({ one, many }) => ({
  user: one(users, {
    fields: [folders.userId],
    references: [users.id],
  }),
  feeds: many(feeds),
}));

export const feeds = pgTable(
  "feeds",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    userId: uuid("user_id")
      .references(() => users.id, { onDelete: "cascade" })
      .notNull(),
    folderId: uuid("folder_id").references(() => folders.id, {
      onDelete: "set null",
    }),
    title: varchar("title", { length: 500 }).notNull(),
    feedUrl: varchar("feed_url", { length: 2000 }).notNull(),
    siteUrl: varchar("site_url", { length: 2000 }),
    iconUrl: varchar("icon_url", { length: 2000 }),
    description: text("description"),
    lastFetchedAt: timestamp("last_fetched_at"),
    createdAt: timestamp("created_at").defaultNow().notNull(),
    updatedAt: timestamp("updated_at").defaultNow().notNull(),
  },
  (table) => ({
    userIdIdx: index("feeds_user_id_idx").on(table.userId),
    folderIdIdx: index("feeds_folder_id_idx").on(table.folderId),
  })
);

export const feedsRelations = relations(feeds, ({ one, many }) => ({
  user: one(users, {
    fields: [feeds.userId],
    references: [users.id],
  }),
  folder: one(folders, {
    fields: [feeds.folderId],
    references: [folders.id],
  }),
  articles: many(articles),
}));

export const articles = pgTable(
  "articles",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    feedId: uuid("feed_id")
      .references(() => feeds.id, { onDelete: "cascade" })
      .notNull(),
    guid: varchar("guid", { length: 2000 }).notNull(),
    title: varchar("title", { length: 1000 }).notNull(),
    content: text("content"),
    summary: text("summary"),
    url: varchar("url", { length: 2000 }),
    author: varchar("author", { length: 500 }),
    imageUrl: varchar("image_url", { length: 2000 }),
    publishedAt: timestamp("published_at"),
    createdAt: timestamp("created_at").defaultNow().notNull(),
  },
  (table) => ({
    feedIdIdx: index("articles_feed_id_idx").on(table.feedId),
    guidIdx: index("articles_guid_idx").on(table.guid),
    publishedAtIdx: index("articles_published_at_idx").on(table.publishedAt),
  })
);

export const articlesRelations = relations(articles, ({ one, many }) => ({
  feed: one(feeds, {
    fields: [articles.feedId],
    references: [feeds.id],
  }),
  readStatuses: many(articleReadStatus),
  starStatuses: many(articleStarStatus),
}));

export const articleReadStatus = pgTable(
  "article_read_status",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    userId: uuid("user_id")
      .references(() => users.id, { onDelete: "cascade" })
      .notNull(),
    articleId: uuid("article_id")
      .references(() => articles.id, { onDelete: "cascade" })
      .notNull(),
    isRead: boolean("is_read").default(false).notNull(),
    readAt: timestamp("read_at"),
  },
  (table) => ({
    userArticleIdx: index("article_read_user_article_idx").on(
      table.userId,
      table.articleId
    ),
  })
);

export const articleReadStatusRelations = relations(
  articleReadStatus,
  ({ one }) => ({
    user: one(users, {
      fields: [articleReadStatus.userId],
      references: [users.id],
    }),
    article: one(articles, {
      fields: [articleReadStatus.articleId],
      references: [articles.id],
    }),
  })
);

export const articleStarStatus = pgTable(
  "article_star_status",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    userId: uuid("user_id")
      .references(() => users.id, { onDelete: "cascade" })
      .notNull(),
    articleId: uuid("article_id")
      .references(() => articles.id, { onDelete: "cascade" })
      .notNull(),
    isStarred: boolean("is_starred").default(false).notNull(),
    starredAt: timestamp("starred_at"),
  },
  (table) => ({
    userArticleIdx: index("article_star_user_article_idx").on(
      table.userId,
      table.articleId
    ),
  })
);

export const articleStarStatusRelations = relations(
  articleStarStatus,
  ({ one }) => ({
    user: one(users, {
      fields: [articleStarStatus.userId],
      references: [users.id],
    }),
    article: one(articles, {
      fields: [articleStarStatus.articleId],
      references: [articles.id],
    }),
  })
);
