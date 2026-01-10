import "dotenv/config";
import { Hono } from "hono";
import type { Context } from "hono";
import { cors } from "hono/cors";
import { logger } from "hono/logger";
import { serve } from "@hono/node-server";
import { authRouter } from "./routes/auth.js";
import { feedsRouter } from "./routes/feeds.js";
import { articlesRouter } from "./routes/articles.js";
import { youtubeRouter } from "./routes/youtube.js";
import { HTTPException } from "hono/http-exception";

const app = new Hono();

app.use("*", logger());
app.use(
  "*",
  cors({
    origin: "*",
    allowMethods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allowHeaders: ["Content-Type", "Authorization"],
  })
);

app.get("/", (c) => {
  return c.json({
    name: "FeedFlow API",
    version: "1.0.0",
    status: "running",
  });
});

const healthHandler = (c: Context) => c.json({ status: "ok" });

app.get("/health", healthHandler);
app.get("/api/health", healthHandler);

app.route("/api/auth", authRouter);
app.route("/api/feeds", feedsRouter);
app.route("/api/articles", articlesRouter);
app.route("/api/youtube", youtubeRouter);

app.onError((err, c) => {
  console.error(err);

  if (err instanceof HTTPException) {
    return c.json({ error: err.message }, err.status);
  }

  return c.json({ error: err.message || "Internal Server Error" }, 500);
});

app.notFound((c) => {
  return c.json({ error: "Not Found" }, 404);
});

const port = parseInt(process.env.PORT || "3000");

console.log(`🚀 FeedFlow API running on http://localhost:${port}`);

serve({
  fetch: app.fetch,
  port,
});

export default app;
