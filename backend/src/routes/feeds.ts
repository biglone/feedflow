import { Hono } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import { eq, and, desc } from "drizzle-orm";
import { db } from "../db";
import { feeds, articles, articleReadStatus, articleStarStatus } from "../db/schema";
import { getUserIdFromContext } from "../lib/auth";
import { fetchAndParseFeed } from "../services/rss";

const feedsRouter = new Hono();

const addFeedSchema = z.object({
  url: z.string().url(),
  folderId: z.string().uuid().optional(),
});

const updateFeedSchema = z.object({
  title: z.string().optional(),
  folderId: z.string().uuid().nullable().optional(),
});

feedsRouter.get("/", async (c) => {
  const userId = await getUserIdFromContext(c);

  const userFeeds = await db.query.feeds.findMany({
    where: eq(feeds.userId, userId),
    with: {
      folder: true,
    },
    orderBy: [desc(feeds.createdAt)],
  });

  return c.json({ feeds: userFeeds });
});

feedsRouter.post("/", zValidator("json", addFeedSchema), async (c) => {
  const userId = await getUserIdFromContext(c);
  const { url, folderId } = c.req.valid("json");

  const existingFeed = await db.query.feeds.findFirst({
    where: and(eq(feeds.userId, userId), eq(feeds.feedUrl, url)),
  });

  if (existingFeed) {
    return c.json({ error: "Feed already exists" }, 400);
  }

  const parsedFeed = await fetchAndParseFeed(url);

  const [feed] = await db
    .insert(feeds)
    .values({
      userId,
      folderId,
      title: parsedFeed.title,
      feedUrl: url,
      siteUrl: parsedFeed.siteUrl,
      iconUrl: parsedFeed.iconUrl,
      description: parsedFeed.description,
      lastFetchedAt: new Date(),
    })
    .returning();

  if (parsedFeed.articles.length > 0) {
    await db.insert(articles).values(
      parsedFeed.articles.map((article) => ({
        feedId: feed.id,
        guid: article.guid,
        title: article.title,
        content: article.content,
        summary: article.summary,
        url: article.url,
        author: article.author,
        imageUrl: article.imageUrl,
        publishedAt: article.publishedAt,
      }))
    );
  }

  return c.json({ feed });
});

feedsRouter.get("/:id", async (c) => {
  const userId = await getUserIdFromContext(c);
  const feedId = c.req.param("id");

  const feed = await db.query.feeds.findFirst({
    where: and(eq(feeds.id, feedId), eq(feeds.userId, userId)),
    with: {
      folder: true,
    },
  });

  if (!feed) {
    return c.json({ error: "Feed not found" }, 404);
  }

  return c.json({ feed });
});

feedsRouter.patch("/:id", zValidator("json", updateFeedSchema), async (c) => {
  const userId = await getUserIdFromContext(c);
  const feedId = c.req.param("id");
  const updates = c.req.valid("json");

  const feed = await db.query.feeds.findFirst({
    where: and(eq(feeds.id, feedId), eq(feeds.userId, userId)),
  });

  if (!feed) {
    return c.json({ error: "Feed not found" }, 404);
  }

  const [updatedFeed] = await db
    .update(feeds)
    .set({
      ...updates,
      updatedAt: new Date(),
    })
    .where(eq(feeds.id, feedId))
    .returning();

  return c.json({ feed: updatedFeed });
});

feedsRouter.delete("/:id", async (c) => {
  const userId = await getUserIdFromContext(c);
  const feedId = c.req.param("id");

  const feed = await db.query.feeds.findFirst({
    where: and(eq(feeds.id, feedId), eq(feeds.userId, userId)),
  });

  if (!feed) {
    return c.json({ error: "Feed not found" }, 404);
  }

  await db.delete(feeds).where(eq(feeds.id, feedId));

  return c.json({ success: true });
});

feedsRouter.post("/:id/refresh", async (c) => {
  const userId = await getUserIdFromContext(c);
  const feedId = c.req.param("id");

  const feed = await db.query.feeds.findFirst({
    where: and(eq(feeds.id, feedId), eq(feeds.userId, userId)),
  });

  if (!feed) {
    return c.json({ error: "Feed not found" }, 404);
  }

  const parsedFeed = await fetchAndParseFeed(feed.feedUrl);

  const existingArticles = await db.query.articles.findMany({
    where: eq(articles.feedId, feedId),
    columns: { guid: true },
  });

  const existingGuids = new Set(existingArticles.map((a) => a.guid));
  const newArticles = parsedFeed.articles.filter(
    (a) => !existingGuids.has(a.guid)
  );

  if (newArticles.length > 0) {
    await db.insert(articles).values(
      newArticles.map((article) => ({
        feedId: feed.id,
        guid: article.guid,
        title: article.title,
        content: article.content,
        summary: article.summary,
        url: article.url,
        author: article.author,
        imageUrl: article.imageUrl,
        publishedAt: article.publishedAt,
      }))
    );
  }

  await db
    .update(feeds)
    .set({ lastFetchedAt: new Date() })
    .where(eq(feeds.id, feedId));

  return c.json({ newArticlesCount: newArticles.length });
});

feedsRouter.get("/:id/articles", async (c) => {
  const userId = await getUserIdFromContext(c);
  const feedId = c.req.param("id");
  const limit = parseInt(c.req.query("limit") || "50");
  const offset = parseInt(c.req.query("offset") || "0");

  const feed = await db.query.feeds.findFirst({
    where: and(eq(feeds.id, feedId), eq(feeds.userId, userId)),
  });

  if (!feed) {
    return c.json({ error: "Feed not found" }, 404);
  }

  const feedArticles = await db.query.articles.findMany({
    where: eq(articles.feedId, feedId),
    orderBy: [desc(articles.publishedAt)],
    limit,
    offset,
  });

  const readStatuses = await db.query.articleReadStatus.findMany({
    where: and(
      eq(articleReadStatus.userId, userId),
    ),
  });

  const starStatuses = await db.query.articleStarStatus.findMany({
    where: and(
      eq(articleStarStatus.userId, userId),
    ),
  });

  const readMap = new Map(readStatuses.map((s) => [s.articleId, s.isRead]));
  const starMap = new Map(starStatuses.map((s) => [s.articleId, s.isStarred]));

  const articlesWithStatus = feedArticles.map((article) => ({
    ...article,
    isRead: readMap.get(article.id) || false,
    isStarred: starMap.get(article.id) || false,
  }));

  return c.json({ articles: articlesWithStatus });
});

export { feedsRouter };
