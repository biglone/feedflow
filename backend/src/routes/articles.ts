import { Hono } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import { eq, and, desc, inArray } from "drizzle-orm";
import { db } from "../db/index.js";
import {
  articles,
  feeds,
  articleReadStatus,
  articleStarStatus,
} from "../db/schema.js";
import { getUserIdFromContext } from "../lib/auth.js";

const articlesRouter = new Hono();

const updateStatusSchema = z.object({
  isRead: z.boolean().optional(),
  isStarred: z.boolean().optional(),
});

const batchUpdateSchema = z.object({
  articleIds: z.array(z.string().uuid()),
  isRead: z.boolean().optional(),
  isStarred: z.boolean().optional(),
});

articlesRouter.get("/", async (c) => {
  const userId = await getUserIdFromContext(c);
  const limit = parseInt(c.req.query("limit") || "50");
  const offset = parseInt(c.req.query("offset") || "0");
  const unreadOnly = c.req.query("unread") === "true";
  const starredOnly = c.req.query("starred") === "true";

  const userFeeds = await db.query.feeds.findMany({
    where: eq(feeds.userId, userId),
    columns: { id: true },
  });

  const feedIds = userFeeds.map((f) => f.id);

  if (feedIds.length === 0) {
    return c.json({ articles: [] });
  }

  const allArticles = await db.query.articles.findMany({
    where: inArray(articles.feedId, feedIds),
    with: {
      feed: {
        columns: {
          id: true,
          title: true,
          iconUrl: true,
        },
      },
    },
    orderBy: [desc(articles.publishedAt)],
    limit: limit + offset,
  });

  const readStatuses = await db.query.articleReadStatus.findMany({
    where: eq(articleReadStatus.userId, userId),
  });

  const starStatuses = await db.query.articleStarStatus.findMany({
    where: eq(articleStarStatus.userId, userId),
  });

  const readMap = new Map(readStatuses.map((s) => [s.articleId, s.isRead]));
  const starMap = new Map(starStatuses.map((s) => [s.articleId, s.isStarred]));

  let articlesWithStatus = allArticles.map((article) => ({
    ...article,
    isRead: readMap.get(article.id) || false,
    isStarred: starMap.get(article.id) || false,
  }));

  if (unreadOnly) {
    articlesWithStatus = articlesWithStatus.filter((a) => !a.isRead);
  }

  if (starredOnly) {
    articlesWithStatus = articlesWithStatus.filter((a) => a.isStarred);
  }

  return c.json({
    articles: articlesWithStatus.slice(offset, offset + limit),
  });
});

articlesRouter.get("/starred", async (c) => {
  const userId = await getUserIdFromContext(c);
  const limit = parseInt(c.req.query("limit") || "50");
  const offset = parseInt(c.req.query("offset") || "0");

  const starredStatuses = await db.query.articleStarStatus.findMany({
    where: and(
      eq(articleStarStatus.userId, userId),
      eq(articleStarStatus.isStarred, true)
    ),
    orderBy: [desc(articleStarStatus.starredAt)],
    limit,
    offset,
  });

  const articleIds = starredStatuses.map((s) => s.articleId);

  if (articleIds.length === 0) {
    return c.json({ articles: [] });
  }

  const starredArticles = await db.query.articles.findMany({
    where: inArray(articles.id, articleIds),
    with: {
      feed: {
        columns: {
          id: true,
          title: true,
          iconUrl: true,
        },
      },
    },
  });

  const readStatuses = await db.query.articleReadStatus.findMany({
    where: and(
      eq(articleReadStatus.userId, userId),
      inArray(articleReadStatus.articleId, articleIds)
    ),
  });

  const readMap = new Map(readStatuses.map((s) => [s.articleId, s.isRead]));

  const articlesWithStatus = starredArticles.map((article) => ({
    ...article,
    isRead: readMap.get(article.id) || false,
    isStarred: true,
  }));

  return c.json({ articles: articlesWithStatus });
});

articlesRouter.get("/:id", async (c) => {
  const userId = await getUserIdFromContext(c);
  const articleId = c.req.param("id");

  const article = await db.query.articles.findFirst({
    where: eq(articles.id, articleId),
    with: {
      feed: true,
    },
  });

  if (!article) {
    return c.json({ error: "Article not found" }, 404);
  }

  const feed = await db.query.feeds.findFirst({
    where: and(eq(feeds.id, article.feedId), eq(feeds.userId, userId)),
  });

  if (!feed) {
    return c.json({ error: "Article not found" }, 404);
  }

  const readStatus = await db.query.articleReadStatus.findFirst({
    where: and(
      eq(articleReadStatus.userId, userId),
      eq(articleReadStatus.articleId, articleId)
    ),
  });

  const starStatus = await db.query.articleStarStatus.findFirst({
    where: and(
      eq(articleStarStatus.userId, userId),
      eq(articleStarStatus.articleId, articleId)
    ),
  });

  return c.json({
    article: {
      ...article,
      isRead: readStatus?.isRead || false,
      isStarred: starStatus?.isStarred || false,
    },
  });
});

articlesRouter.patch(
  "/:id",
  zValidator("json", updateStatusSchema),
  async (c) => {
    const userId = await getUserIdFromContext(c);
    const articleId = c.req.param("id");
    const { isRead, isStarred } = c.req.valid("json");

    const article = await db.query.articles.findFirst({
      where: eq(articles.id, articleId),
    });

    if (!article) {
      return c.json({ error: "Article not found" }, 404);
    }

    const feed = await db.query.feeds.findFirst({
      where: and(eq(feeds.id, article.feedId), eq(feeds.userId, userId)),
    });

    if (!feed) {
      return c.json({ error: "Article not found" }, 404);
    }

    if (isRead !== undefined) {
      const existingStatus = await db.query.articleReadStatus.findFirst({
        where: and(
          eq(articleReadStatus.userId, userId),
          eq(articleReadStatus.articleId, articleId)
        ),
      });

      if (existingStatus) {
        await db
          .update(articleReadStatus)
          .set({ isRead, readAt: isRead ? new Date() : null })
          .where(eq(articleReadStatus.id, existingStatus.id));
      } else {
        await db.insert(articleReadStatus).values({
          userId,
          articleId,
          isRead,
          readAt: isRead ? new Date() : null,
        });
      }
    }

    if (isStarred !== undefined) {
      const existingStatus = await db.query.articleStarStatus.findFirst({
        where: and(
          eq(articleStarStatus.userId, userId),
          eq(articleStarStatus.articleId, articleId)
        ),
      });

      if (existingStatus) {
        await db
          .update(articleStarStatus)
          .set({ isStarred, starredAt: isStarred ? new Date() : null })
          .where(eq(articleStarStatus.id, existingStatus.id));
      } else {
        await db.insert(articleStarStatus).values({
          userId,
          articleId,
          isStarred,
          starredAt: isStarred ? new Date() : null,
        });
      }
    }

    return c.json({ success: true });
  }
);

articlesRouter.post(
  "/batch",
  zValidator("json", batchUpdateSchema),
  async (c) => {
    const userId = await getUserIdFromContext(c);
    const { articleIds, isRead, isStarred } = c.req.valid("json");

    for (const articleId of articleIds) {
      if (isRead !== undefined) {
        const existingStatus = await db.query.articleReadStatus.findFirst({
          where: and(
            eq(articleReadStatus.userId, userId),
            eq(articleReadStatus.articleId, articleId)
          ),
        });

        if (existingStatus) {
          await db
            .update(articleReadStatus)
            .set({ isRead, readAt: isRead ? new Date() : null })
            .where(eq(articleReadStatus.id, existingStatus.id));
        } else {
          await db.insert(articleReadStatus).values({
            userId,
            articleId,
            isRead,
            readAt: isRead ? new Date() : null,
          });
        }
      }

      if (isStarred !== undefined) {
        const existingStatus = await db.query.articleStarStatus.findFirst({
          where: and(
            eq(articleStarStatus.userId, userId),
            eq(articleStarStatus.articleId, articleId)
          ),
        });

        if (existingStatus) {
          await db
            .update(articleStarStatus)
            .set({ isStarred, starredAt: isStarred ? new Date() : null })
            .where(eq(articleStarStatus.id, existingStatus.id));
        } else {
          await db.insert(articleStarStatus).values({
            userId,
            articleId,
            isStarred,
            starredAt: isStarred ? new Date() : null,
          });
        }
      }
    }

    return c.json({ success: true });
  }
);

export { articlesRouter };
