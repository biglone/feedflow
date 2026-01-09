import { Hono } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import {
  searchChannels,
  getChannelInfo,
  getChannelVideos,
  resolveChannelUrl,
  getChannelRssUrl,
  formatDuration,
  getSubscriptions,
} from "../services/youtube";
import { getStreamUrls, getVideoInfo } from "../services/ytdlp";

const youtubeRouter = new Hono();

// Google OAuth2 configuration
const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID;
const GOOGLE_CLIENT_SECRET = process.env.GOOGLE_CLIENT_SECRET;
const GOOGLE_REDIRECT_URI = process.env.GOOGLE_REDIRECT_URI || "feedflow://oauth/google/callback";

// Generate Google OAuth URL
youtubeRouter.get("/oauth/url", (c) => {
  if (!GOOGLE_CLIENT_ID) {
    return c.json({ error: "Google OAuth not configured" }, 500);
  }

  const scopes = [
    "https://www.googleapis.com/auth/youtube.readonly",
  ];

  const params = new URLSearchParams({
    client_id: GOOGLE_CLIENT_ID,
    redirect_uri: GOOGLE_REDIRECT_URI,
    response_type: "code",
    scope: scopes.join(" "),
    access_type: "offline",
    prompt: "consent",
  });

  const oauthUrl = `https://accounts.google.com/o/oauth2/v2/auth?${params.toString()}`;

  return c.json({ url: oauthUrl });
});

// Exchange authorization code for tokens
const tokenSchema = z.object({
  code: z.string(),
  redirectUri: z.string().optional(),
});

youtubeRouter.post("/oauth/token", zValidator("json", tokenSchema), async (c) => {
  const { code, redirectUri } = c.req.valid("json");

  if (!GOOGLE_CLIENT_ID || !GOOGLE_CLIENT_SECRET) {
    return c.json({ error: "Google OAuth not configured" }, 500);
  }

  try {
    const response = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({
        code,
        client_id: GOOGLE_CLIENT_ID,
        client_secret: GOOGLE_CLIENT_SECRET,
        redirect_uri: redirectUri || GOOGLE_REDIRECT_URI,
        grant_type: "authorization_code",
      }),
    });

    const data = await response.json();

    if (!response.ok) {
      console.error("OAuth token error:", data);
      return c.json({ error: data.error_description || "Failed to exchange code" }, 400);
    }

    return c.json({
      accessToken: data.access_token,
      refreshToken: data.refresh_token,
      expiresIn: data.expires_in,
    });
  } catch (error) {
    console.error("OAuth token exchange error:", error);
    return c.json({ error: "Failed to exchange authorization code" }, 500);
  }
});

// Get user's YouTube subscriptions
youtubeRouter.get("/subscriptions", async (c) => {
  const authHeader = c.req.header("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return c.json({ error: "Access token required" }, 401);
  }

  const accessToken = authHeader.substring(7);

  try {
    const subscriptions = await getSubscriptions(accessToken);
    return c.json({ subscriptions });
  } catch (error: any) {
    console.error("Get subscriptions error:", error);
    if (error.message?.includes("401") || error.message?.includes("Invalid")) {
      return c.json({ error: "Invalid or expired access token" }, 401);
    }
    return c.json({ error: "Failed to get subscriptions" }, 500);
  }
});

// Search YouTube channels
const searchSchema = z.object({
  q: z.string().min(1),
  limit: z.string().optional().transform((v) => (v ? parseInt(v) : 10)),
});

youtubeRouter.get("/search", zValidator("query", searchSchema), async (c) => {
  const { q, limit } = c.req.valid("query");

  try {
    const channels = await searchChannels(q, limit);
    return c.json({ channels });
  } catch (error: any) {
    console.error("YouTube search error:", error);
    const message = error.message || "Failed to search YouTube channels";
    const statusCode = error.message?.includes("quota exceeded") ? 503 :
                       error.message?.includes("not configured") ? 500 : 500;
    return c.json({ error: message }, statusCode);
  }
});

// Get channel info by ID
youtubeRouter.get("/channel/:id", async (c) => {
  const channelId = c.req.param("id");

  try {
    const channel = await getChannelInfo(channelId);
    if (!channel) {
      return c.json({ error: "Channel not found" }, 404);
    }
    return c.json({ channel });
  } catch (error) {
    console.error("Get channel error:", error);
    return c.json({ error: "Failed to get channel info" }, 500);
  }
});

// Get channel videos
const videosSchema = z.object({
  limit: z.string().optional().transform((v) => (v ? parseInt(v) : 20)),
});

youtubeRouter.get(
  "/channel/:id/videos",
  zValidator("query", videosSchema),
  async (c) => {
    const channelId = c.req.param("id");
    const { limit } = c.req.valid("query");

    try {
      const videos = await getChannelVideos(channelId, limit);

      // Format duration for each video
      const formattedVideos = videos.map((video) => ({
        ...video,
        formattedDuration: video.duration
          ? formatDuration(video.duration)
          : "0:00",
      }));

      return c.json({ videos: formattedVideos });
    } catch (error) {
      console.error("Get channel videos error:", error);
      return c.json({ error: "Failed to get channel videos" }, 500);
    }
  }
);

// Resolve YouTube URL to channel info and RSS feed URL
const resolveSchema = z.object({
  url: z.string().url(),
});

youtubeRouter.post("/resolve", zValidator("json", resolveSchema), async (c) => {
  const { url } = c.req.valid("json");

  try {
    const result = await resolveChannelUrl(url);
    if (!result) {
      return c.json({ error: "Could not resolve YouTube channel URL" }, 400);
    }

    // Get channel info
    const channel = await getChannelInfo(result.channelId);

    return c.json({
      channelId: result.channelId,
      rssUrl: result.rssUrl,
      channel,
    });
  } catch (error) {
    console.error("Resolve URL error:", error);
    return c.json({ error: "Failed to resolve YouTube URL" }, 500);
  }
});

// Get RSS feed URL for a channel
youtubeRouter.get("/channel/:id/rss", async (c) => {
  const channelId = c.req.param("id");

  return c.json({
    rssUrl: getChannelRssUrl(channelId),
  });
});

// Get video info
youtubeRouter.get("/video/:id", async (c) => {
  const videoId = c.req.param("id");

  try {
    const video = await getVideoInfo(videoId);
    return c.json({ video });
  } catch (error) {
    console.error("Get video info error:", error);
    return c.json({ error: "Failed to get video info" }, 500);
  }
});

// Get stream URLs for a video
const streamSchema = z.object({
  type: z.enum(["video", "audio", "both"]).optional().default("both"),
});

youtubeRouter.get(
  "/stream/:id",
  zValidator("query", streamSchema),
  async (c) => {
    const videoId = c.req.param("id");
    const { type } = c.req.valid("query");

    try {
      const streams = await getStreamUrls(videoId);

      const response: any = {
        title: streams.title,
        duration: streams.duration,
        thumbnailUrl: streams.thumbnailUrl,
      };

      if (type === "video" || type === "both") {
        response.videoUrl = streams.videoUrl;
      }
      if (type === "audio" || type === "both") {
        response.audioUrl = streams.audioUrl;
      }

      if (!response.videoUrl && !response.audioUrl) {
        return c.json({ error: "No playable streams found" }, 404);
      }

      return c.json(response);
    } catch (error) {
      console.error("Get stream error:", error);
      return c.json({ error: "Failed to get stream URLs" }, 500);
    }
  }
);

export { youtubeRouter };
