import { Hono, type Context } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import { ProxyAgent, fetch as undiciFetch, type HeadersInit } from "undici";
import { HTTPException } from "hono/http-exception";
import {
  searchChannels,
  getChannelInfo,
  getChannelVideos,
  resolveChannelUrl,
  getChannelRssUrl,
  formatDuration,
  getSubscriptions,
  resolveReplayVideoIdForUpcomingVideo,
} from "../services/youtube.js";
import { getStreamUrls, getVideoInfo } from "../services/ytdlp.js";
import {
  createStreamProxySignature,
  verifyStreamProxySignature,
  type StreamType,
} from "../lib/streamToken.js";
import { getUserIdFromContext } from "../lib/auth.js";

function extractYtdlpErrorMessage(error: unknown): string | undefined {
  const anyError = error as any;
  const candidates = [
    anyError?.stderr,
    anyError?.stdout,
    anyError?.message,
  ].filter(Boolean);

  if (candidates.length === 0) return undefined;

  const raw = candidates
    .map((v) => (typeof v === "string" ? v : JSON.stringify(v)))
    .join("\n");

  const line =
    raw
      .split("\n")
      .map((l) => l.trim())
      .find((l) => l.startsWith("ERROR:")) || raw.trim();

  const cleaned = line.replace(
    /^ERROR:\s*(?:\[[^\]]+\]\s*)?(?:[A-Za-z0-9_-]{11}:)?\s*/i,
    ""
  );

  return cleaned.slice(0, 2000);
}

function extractYtdlpErrorText(error: unknown): string | undefined {
  const anyError = error as any;
  const candidates = [
    anyError?.stderr,
    anyError?.stdout,
    anyError?.message,
  ].filter(Boolean);

  if (candidates.length === 0) return undefined;

  return candidates
    .map((v) => (typeof v === "string" ? v : JSON.stringify(v)))
    .join("\n");
}

function normalizeErrorMessage(value: string): string {
  return value.toLowerCase().replaceAll("\u2019", "'");
}

function isYtdlpCookiesInvalidMessage(message: string): boolean {
  const normalized = normalizeErrorMessage(message);
  return (
    normalized.includes("cookies are no longer valid") ||
    normalized.includes("likely been rotated in the browser")
  );
}

function isYouTubeAuthOrBotCheckMessage(message: string): boolean {
  const normalized = normalizeErrorMessage(message);
  return (
    normalized.includes("confirm you're not a bot") ||
    normalized.includes("please sign in to continue") ||
    normalized.includes("cookies-from-browser") ||
    normalized.includes("use --cookies")
  );
}

// Proxy configuration
const proxyUrl = process.env.https_proxy || process.env.HTTPS_PROXY;
const proxyAgent = proxyUrl ? new ProxyAgent(proxyUrl) : undefined;

const youtubeRouter = new Hono();

const streamProxySecret = process.env.STREAM_PROXY_SECRET;
const streamProxyAccessToken = process.env.STREAM_PROXY_ACCESS_TOKEN;
const streamProxyTtlSeconds = parseInt(
  process.env.STREAM_PROXY_TTL_SECONDS || "21600",
  10
);
const streamProxyClockSkewSeconds = parseInt(
  process.env.STREAM_PROXY_CLOCK_SKEW_SECONDS || "30",
  10
);

const youtubeStreamUrlMode = (
  (process.env.YOUTUBE_STREAM_URL_MODE || "").trim() ||
  (process.env.VERCEL || process.env.VERCEL_ENV ? "direct" : "proxy")
)
  .trim()
  .toLowerCase();
const youtubeStreamUseDirectUrls = youtubeStreamUrlMode === "direct";

async function authorizeStreamRequest(c: Context): Promise<void> {
  if (!streamProxySecret && !streamProxyAccessToken) return;

  if (streamProxyAccessToken) {
    const provided = c.req.header("x-feedflow-stream-token");
    if (provided && provided === streamProxyAccessToken) return;
  }

  await getUserIdFromContext(c);
}

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

const googleTokenResponseSchema = z
  .object({
    access_token: z.string().optional(),
    refresh_token: z.string().optional(),
    expires_in: z.number().optional(),
    error: z.string().optional(),
    error_description: z.string().optional(),
  })
  .passthrough();

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

    const parsed = googleTokenResponseSchema.safeParse(await response.json());
    if (!parsed.success) {
      console.error("OAuth token response parse error:", parsed.error);
      return c.json({ error: "Invalid token response from Google" }, 502);
    }
    const data = parsed.data;

    if (!response.ok) {
      console.error("OAuth token error:", data);
      return c.json({ error: data.error_description || "Failed to exchange code" }, 400);
    }

    if (!data.access_token) {
      return c.json({ error: "Missing access token in Google response" }, 502);
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
  limit: z.string().optional().transform((v) => {
    const parsed = v ? parseInt(v, 10) : 10;
    if (!Number.isFinite(parsed)) return 10;
    return Math.min(Math.max(parsed, 1), 50);
  }),
  pageToken: z.string().optional(),
});

youtubeRouter.get("/search", zValidator("query", searchSchema), async (c) => {
  const { q, limit, pageToken } = c.req.valid("query");

  try {
    const { channels, nextPageToken } = await searchChannels(q, limit, pageToken);
    return c.json({ channels, nextPageToken });
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
  limit: z.string().optional().transform((v) => {
    const parsed = v ? parseInt(v, 10) : 20;
    if (!Number.isFinite(parsed)) return 20;
    return Math.min(Math.max(parsed, 1), 50);
  }),
  pageToken: z.string().optional(),
});

youtubeRouter.get(
  "/channel/:id/videos",
  zValidator("query", videosSchema),
  async (c) => {
    const channelId = c.req.param("id");
    const { limit, pageToken } = c.req.valid("query");

    try {
      const { videos, nextPageToken } = await getChannelVideos(
        channelId,
        limit,
        pageToken
      );

      // Format duration for each video
      const formattedVideos = videos.map((video) => ({
        ...video,
        formattedDuration: video.duration
          ? formatDuration(video.duration)
          : "0:00",
      }));

      return c.json({ videos: formattedVideos, nextPageToken });
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
    const requestedVideoId = c.req.param("id");
    const { type } = c.req.valid("query");

    try {
      // Minting signed /proxy URLs should be restricted (JWT or stream access token).
      await authorizeStreamRequest(c);

      let videoId = requestedVideoId;
      let streams: Awaited<ReturnType<typeof getStreamUrls>>;

      try {
        streams = await getStreamUrls(videoId);
      } catch (error) {
        const ytdlpMessage = extractYtdlpErrorMessage(error);

        if (
          ytdlpMessage &&
          /This live event will begin in/i.test(ytdlpMessage)
        ) {
          try {
            const replayVideoId = await resolveReplayVideoIdForUpcomingVideo(videoId);
            if (replayVideoId && replayVideoId !== videoId) {
              videoId = replayVideoId;
              streams = await getStreamUrls(videoId);
            } else {
              return c.json(
                { error: ytdlpMessage, code: "LIVE_NOT_STARTED" },
                409
              );
            }
          } catch (resolveError) {
            console.error("Failed to resolve replay video ID:", resolveError);
            return c.json(
              { error: ytdlpMessage, code: "LIVE_NOT_STARTED" },
              409
            );
          }
        } else {
          throw error;
        }
      }

      const buildProxyUrl = youtubeStreamUseDirectUrls
        ? null
        : ((streamType: StreamType) => {
            const protocol =
              c.req.header("x-forwarded-proto") ||
              new URL(c.req.url).protocol.replace(":", "");
            const host = c.req.header("host") || "localhost:3000";
            const baseUrl = `${protocol}://${host}/api/youtube/proxy/${videoId}`;
            const exp = Math.floor(Date.now() / 1000) + streamProxyTtlSeconds;

            if (!streamProxySecret) return `${baseUrl}?type=${streamType}`;

            const sig = createStreamProxySignature({
              secret: streamProxySecret,
              videoId,
              type: streamType,
              exp,
            });

            const qs = new URLSearchParams({
              type: streamType,
              exp: String(exp),
              sig,
            });

            return `${baseUrl}?${qs.toString()}`;
          });

      const response: any = {
        title: streams.title,
        duration: streams.duration,
        thumbnailUrl: streams.thumbnailUrl,
      };

      if (type === "video" || type === "both") {
        response.videoUrl = streams.videoUrl
          ? youtubeStreamUseDirectUrls
            ? streams.videoUrl
            : buildProxyUrl?.("video")
          : null;
      }
      if (type === "audio" || type === "both") {
        response.audioUrl = streams.audioUrl
          ? youtubeStreamUseDirectUrls
            ? streams.audioUrl
            : buildProxyUrl?.("audio")
          : null;
      }
      if (videoId !== requestedVideoId) {
        response.resolvedVideoId = videoId;
      }

      if (!response.videoUrl && !response.audioUrl) {
        return c.json({ error: "No playable streams found" }, 404);
      }

      return c.json(response);
    } catch (error) {
      if (error instanceof HTTPException) throw error;
      console.error("Get stream error:", error);

      const ytdlpErrorText = extractYtdlpErrorText(error);
      const ytdlpMessage = extractYtdlpErrorMessage(error);
      const debug =
        c.req.header("x-feedflow-debug") === "1" ||
        c.req.query("debug") === "1";

      if (ytdlpErrorText && isYtdlpCookiesInvalidMessage(ytdlpErrorText)) {
        const hint =
          "YouTube cookies are configured but invalid/rotated. Re-export cookies and reinstall (YTDLP_COOKIES_PATH or YTDLP_COOKIES_BASE64), then restart/redeploy.";
        if (debug && ytdlpMessage) {
          return c.json(
            { error: hint, code: "YOUTUBE_COOKIES_INVALID", details: ytdlpMessage },
            503
          );
        }
        return c.json({ error: hint, code: "YOUTUBE_COOKIES_INVALID" }, 503);
      }

      if (ytdlpMessage && isYouTubeAuthOrBotCheckMessage(ytdlpMessage)) {
        const hasCookies =
          Boolean(process.env.YTDLP_COOKIES_PATH?.trim()) ||
          Boolean(process.env.YTDLP_COOKIES_BASE64?.trim()) ||
          Boolean(process.env.YTDLP_COOKIES?.trim());

        const hint = hasCookies
          ? "YouTube blocked this server (bot check). Cookies are configured, but YouTube still requires verification. This is usually caused by the server/proxy exit IP reputation. Try switching to a different proxy/VPN exit (prefer residential) or complete the 'confirm you're not a bot' challenge in a browser using the same exit IP, then re-export cookies and restart/redeploy."
          : "YouTube blocked this server (bot check). Configure yt-dlp cookies (YTDLP_COOKIES_PATH or YTDLP_COOKIES_BASE64) on the backend and restart/redeploy.";
        if (debug) {
          return c.json(
            { error: hint, code: "YOUTUBE_BOT_CHECK", details: ytdlpMessage },
            503
          );
        }
        return c.json({ error: hint, code: "YOUTUBE_BOT_CHECK" }, 503);
      }

      if (
        ytdlpMessage &&
        /This live event will begin in/i.test(ytdlpMessage)
      ) {
        return c.json(
          { error: ytdlpMessage, code: "LIVE_NOT_STARTED" },
          409
        );
      }

      if (
        ytdlpMessage &&
        (/Failed to download yt-dlp/i.test(ytdlpMessage) ||
          /Unsupported platform for yt-dlp binary/i.test(ytdlpMessage))
      ) {
        return c.json({ error: ytdlpMessage, code: "STREAM_BACKEND_UNAVAILABLE" }, 503);
      }

      if (debug && ytdlpMessage) {
        return c.json(
          { error: "Failed to get stream URLs", details: ytdlpMessage },
          500
        );
      }

      return c.json({ error: "Failed to get stream URLs" }, 500);
    }
  }
);

// Proxy video/audio stream to bypass IP restrictions
const proxySchema = z.object({
  type: z.enum(["video", "audio"]).optional().default("video"),
  exp: z.string().optional(),
  sig: z.string().optional(),
});

youtubeRouter.get(
  "/proxy/:id",
  zValidator("query", proxySchema),
  async (c) => {
    const videoId = c.req.param("id");
    const { type, exp: expRaw, sig } = c.req.valid("query");

    try {
      if (streamProxySecret) {
        if (!expRaw || !sig) {
          return c.json({ error: "Missing stream token" }, 401);
        }

        const exp = parseInt(expRaw, 10);
        const now = Math.floor(Date.now() / 1000);
        if (!Number.isFinite(exp) || now - streamProxyClockSkewSeconds > exp) {
          return c.json({ error: "Expired stream token" }, 401);
        }

        const ok = verifyStreamProxySignature({
          secret: streamProxySecret,
          videoId,
          type,
          exp,
          sig,
        });
        if (!ok) {
          return c.json({ error: "Invalid stream token" }, 403);
        }
      }

      const streams = await getStreamUrls(videoId);
      const streamUrl = type === "audio" ? streams.audioUrl : streams.videoUrl;

      if (!streamUrl) {
        return c.json({ error: "No stream URL found" }, 404);
      }

      // Forward range header for seeking support
      const rangeHeader = c.req.header("Range");
      const headers: HeadersInit = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
      };
      if (rangeHeader) {
        headers["Range"] = rangeHeader;
      }

      const response = await undiciFetch(streamUrl, {
        headers,
        dispatcher: proxyAgent,
      });

      // Forward response headers
      const contentType = response.headers.get("Content-Type") || (type === "audio" ? "audio/mp4" : "video/mp4");
      const contentLength = response.headers.get("Content-Length");
      const contentRange = response.headers.get("Content-Range");
      const acceptRanges = response.headers.get("Accept-Ranges");

      const responseHeaders: Record<string, string> = {
        "Content-Type": contentType,
        "Access-Control-Allow-Origin": "*",
        "Cache-Control": "no-cache",
      };

      if (contentLength) responseHeaders["Content-Length"] = contentLength;
      if (contentRange) responseHeaders["Content-Range"] = contentRange;
      if (acceptRanges) responseHeaders["Accept-Ranges"] = acceptRanges;

      return new Response(response.body, {
        status: response.status,
        headers: responseHeaders,
      });
    } catch (error) {
      console.error("Proxy stream error:", error);
      return c.json({ error: "Failed to proxy stream" }, 500);
    }
  }
);

export { youtubeRouter };
