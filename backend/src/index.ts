import "dotenv/config";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { logger } from "hono/logger";
import { serve } from "@hono/node-server";
import { authRouter } from "./routes/auth";
import { feedsRouter } from "./routes/feeds";
import { articlesRouter } from "./routes/articles";
import { youtubeRouter } from "./routes/youtube";

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

app.get("/health", (c) => {
  return c.json({ status: "ok" });
});

app.route("/api/auth", authRouter);
app.route("/api/feeds", feedsRouter);
app.route("/api/articles", articlesRouter);
app.route("/api/youtube", youtubeRouter);

app.onError((err, c) => {
  console.error(`Error: ${err.message}`);
  return c.json(
    {
      error: err.message || "Internal Server Error",
    },
    500
  );
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
