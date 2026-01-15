import youtubedl from "youtube-dl-exec";
import { execSync } from "child_process";
import fs from "node:fs";
import { chmod, mkdir, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { ProxyAgent, fetch as undiciFetch, type Response as UndiciResponse } from "undici";

function normalizeEnvValue(value: string | undefined): string | undefined {
  if (!value) return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function normalizeErrorMessage(value: string): string {
  return value.toLowerCase().replaceAll("\u2019", "'");
}

function extractFailureMessage(error: unknown): string {
  const anyError = error as any;
  return [anyError?.stderr, anyError?.stdout, anyError?.message]
    .filter(Boolean)
    .map((part) => (typeof part === "string" ? part : JSON.stringify(part)))
    .join("\n");
}

function isYouTubeAuthOrBotCheckMessage(message: string): boolean {
  return (
    message.includes("confirm you're not a bot") ||
    message.includes("sign in to confirm you're not a bot") ||
    message.includes("please sign in to continue") ||
    message.includes("use --cookies") ||
    message.includes("cookies-from-browser")
  );
}

function isYouTubePlayerClientFallbackMessage(message: string): boolean {
  if (isYouTubeAuthOrBotCheckMessage(message)) return true;

  return (
    message.includes("failed to extract") ||
    message.includes("signature") ||
    message.includes("nsig") ||
    message.includes("player response") ||
    message.includes("unable to download api page") ||
    message.includes("http error 403") ||
    message.includes("http error 429")
  );
}

function shouldAttemptPlayerClientFallback(error: unknown): boolean {
  const message = normalizeErrorMessage(extractFailureMessage(error));
  if (!message) return false;
  return isYouTubePlayerClientFallbackMessage(message);
}

function getYouTubePlayerClientFallbacks(): string[] {
  const raw = normalizeEnvValue(process.env.YTDLP_YOUTUBE_PLAYER_CLIENTS);
  if (!raw) return ["android", "ios"];

  const parsed = raw
    .split(",")
    .map((item) => item.trim().toLowerCase())
    .filter(Boolean);

  const unique = Array.from(new Set(parsed));

  return unique.length > 0 ? unique : ["android", "ios"];
}

// Get system yt-dlp path
const ytdlpPath = (() => {
  try {
    const resolved = execSync("command -v yt-dlp", {
      stdio: ["ignore", "pipe", "ignore"],
    })
      .toString()
      .trim();
    return resolved.length > 0 ? resolved : undefined;
  } catch {
    return undefined;
  }
})();

let ytdlp = ytdlpPath ? youtubedl.create(ytdlpPath) : youtubedl;

// Proxy configuration (for regions where YouTube needs a proxy)
const proxyUrl =
  process.env.https_proxy ||
  process.env.HTTPS_PROXY ||
  process.env.http_proxy ||
  process.env.HTTP_PROXY;
const proxyAgent = proxyUrl ? new ProxyAgent(proxyUrl) : undefined;

const ytdlpCookiesPath = normalizeEnvValue(
  process.env.YTDLP_COOKIES_PATH || process.env.YTDLP_COOKIES
);
const ytdlpCookiesBase64 = normalizeEnvValue(process.env.YTDLP_COOKIES_BASE64);
const ytdlpCookiesTmpPath = ytdlpCookiesBase64
  ? path.join(os.tmpdir(), "feedflow", "yt-dlp-cookies.txt")
  : null;
let ytdlpCookiesPromise: Promise<string> | null = null;

async function ensureYtdlpCookiesFile(): Promise<string> {
  if (!ytdlpCookiesBase64 || !ytdlpCookiesTmpPath) {
    throw new Error("YTDLP_COOKIES_BASE64 is not configured");
  }

  if (ytdlpCookiesPromise) return ytdlpCookiesPromise;

  ytdlpCookiesPromise = (async () => {
    try {
      await mkdir(path.dirname(ytdlpCookiesTmpPath), { recursive: true });
      await writeFile(
        ytdlpCookiesTmpPath,
        Buffer.from(ytdlpCookiesBase64, "base64")
      );
      await chmod(ytdlpCookiesTmpPath, 0o600);
      return ytdlpCookiesTmpPath;
    } catch (error) {
      ytdlpCookiesPromise = null;
      throw error;
    }
  })();

  return ytdlpCookiesPromise;
}

async function resolveYtdlpCookiesPath(): Promise<string | undefined> {
  if (ytdlpCookiesPath) return ytdlpCookiesPath;
  if (ytdlpCookiesBase64) return ensureYtdlpCookiesFile();
  return undefined;
}

const ytdlpFallbackAsset = getYtdlpBinaryAssetName();
const ytdlpFallbackPath = ytdlpFallbackAsset
  ? path.join(os.tmpdir(), "feedflow", ytdlpFallbackAsset)
  : null;
let ytdlpFallbackPromise: Promise<string> | null = null;
let ytdlpFallbackEnabled = false;

const ytdlpUserAgent =
  normalizeEnvValue(process.env.YTDLP_USER_AGENT) ||
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36";

function getYtdlpBinaryAssetName(): string | null {
  if (process.platform === "win32") return "yt-dlp.exe";
  if (process.platform === "darwin") return "yt-dlp_macos";

  if (process.platform === "linux") {
    if (process.arch === "arm64") return "yt-dlp_linux_aarch64";
    return "yt-dlp_linux";
  }

  return null;
}

function getYtdlpDownloadBaseUrl(): string {
  const raw =
    (process.env.YTDLP_DOWNLOAD_BASE_URL ||
      "https://github.com/yt-dlp/yt-dlp/releases/latest/download") ??
    "";
  return raw.trim().replace(/\/+$/, "");
}

async function fetchBinary(url: string): Promise<ArrayBuffer> {
  const attempt = async (useProxy: boolean): Promise<ArrayBuffer> => {
    const response: UndiciResponse = await undiciFetch(url, {
      dispatcher: useProxy ? proxyAgent : undefined,
      redirect: "follow",
      signal: AbortSignal.timeout(60_000),
    });

    if (!response.ok) {
      throw new Error(`Failed to download yt-dlp (${response.status})`);
    }

    return response.arrayBuffer();
  };

  try {
    return await attempt(false);
  } catch (error) {
    if (!proxyAgent) throw error;
    return attempt(true);
  }
}

async function ensureYtdlpFallbackBinary(): Promise<string> {
  if (!ytdlpFallbackPath) {
    throw new Error(`Unsupported platform for yt-dlp binary (${process.platform})`);
  }

  if (ytdlpFallbackPromise) return ytdlpFallbackPromise;

  ytdlpFallbackPromise = (async () => {
    try {
      if (fs.existsSync(ytdlpFallbackPath)) {
        return ytdlpFallbackPath;
      }

      const url = `${getYtdlpDownloadBaseUrl()}/${path.basename(ytdlpFallbackPath)}`;
      const buffer = await fetchBinary(url);

      await mkdir(path.dirname(ytdlpFallbackPath), { recursive: true });
      await writeFile(ytdlpFallbackPath, Buffer.from(buffer));
      await chmod(ytdlpFallbackPath, 0o755);

      return ytdlpFallbackPath;
    } catch (error) {
      ytdlpFallbackPromise = null;
      throw error;
    }
  })();

  return ytdlpFallbackPromise;
}

function isYtdlpRuntimeError(error: unknown): boolean {
  const anyError = error as any;
  const messageParts = [anyError?.stderr, anyError?.stdout, anyError?.message].filter(Boolean);
  const message = messageParts.map((v) => String(v)).join("\n").toLowerCase();

  if (message.includes("python3") && message.includes("no such file or directory")) {
    return true;
  }

  if (message.includes("/usr/bin/env") && message.includes("python") && message.includes("not found")) {
    return true;
  }

  if (message.includes("spawn") && message.includes("enoent")) {
    return true;
  }

  if (message.includes("eacces")) {
    return true;
  }

  return false;
}

type YtdlpRunOptions = {
  cookiesPath?: string;
  disableCookies?: boolean;
};

type YtdlpFallbackAttempt = {
  client: string;
  disableCookies: boolean;
};

function buildYtdlpFallbackAttempts(hasCookies: boolean): YtdlpFallbackAttempt[] {
  const clients = getYouTubePlayerClientFallbacks();
  const attempts = clients.map((client) => ({ client, disableCookies: false }));
  if (hasCookies) {
    attempts.push(...clients.map((client) => ({ client, disableCookies: true })));
  }
  return attempts;
}

async function runYtdlp(
  url: string,
  extraOptions: Record<string, any> = {},
  runOptions: YtdlpRunOptions = {}
): Promise<any> {
  const options: Record<string, any> = {
    dumpSingleJson: true,
    noCheckCertificates: true,
    noWarnings: true,
    preferFreeFormats: true,
    socketTimeout: 15,
    retries: 2,
    userAgent: ytdlpUserAgent,
    ...extraOptions,
  };

  if (!runOptions.disableCookies) {
    const cookiesPath =
      runOptions.cookiesPath ?? (await resolveYtdlpCookiesPath());
    if (cookiesPath) {
      options.cookies = cookiesPath;
    }
  }

  if (proxyUrl) {
    options.proxy = proxyUrl;
  }

  try {
    return (await ytdlp(url, options)) as any;
  } catch (error) {
    if (ytdlpFallbackEnabled) throw error;
    if (!isYtdlpRuntimeError(error)) throw error;

    const fallbackBinaryPath = await ensureYtdlpFallbackBinary();
    ytdlpFallbackEnabled = true;
    ytdlp = youtubedl.create(fallbackBinaryPath);

    return (await ytdlp(url, options)) as any;
  }
}

async function runYtdlpWithFallback(url: string): Promise<any> {
  const cookiesPath = await resolveYtdlpCookiesPath();

  try {
    return await runYtdlp(url, {}, { cookiesPath });
  } catch (error) {
    if (!shouldAttemptPlayerClientFallback(error)) {
      throw error;
    }
  }

  let lastError: unknown = null;
  const attempts = buildYtdlpFallbackAttempts(Boolean(cookiesPath));

  for (const attempt of attempts) {
    try {
      return await runYtdlp(
        url,
        { extractorArgs: `youtube:player_client=${attempt.client}` },
        { cookiesPath, disableCookies: attempt.disableCookies }
      );
    } catch (fallbackError) {
      lastError = fallbackError;
      if (!shouldAttemptPlayerClientFallback(fallbackError)) {
        throw fallbackError;
      }
    }
  }

  if (lastError) throw lastError;
  throw new Error("Failed to resolve YouTube stream metadata");
}

export interface StreamFormat {
  formatId: string;
  url: string;
  ext: string;
  quality: string;
  filesize?: number;
  vcodec?: string;
  acodec?: string;
  width?: number;
  height?: number;
  fps?: number;
  abr?: number; // audio bitrate
}

export interface VideoInfo {
  id: string;
  title: string;
  description: string;
  thumbnailUrl: string;
  duration: number;
  viewCount: number;
  channelId: string;
  channelTitle: string;
  uploadDate: string;
  videoUrl?: string;
  audioUrl?: string;
  formats: StreamFormat[];
}

export interface StreamUrls {
  videoUrl: string | null;
  audioUrl: string | null;
  thumbnailUrl: string;
  title: string;
  duration: number;
}

// Cache for stream URLs (they expire after ~6 hours)
const streamCache = new Map<
  string,
  { data: StreamUrls; timestamp: number }
>();
const CACHE_TTL = 5 * 60 * 60 * 1000; // 5 hours

export async function getVideoInfo(videoId: string): Promise<VideoInfo> {
  const url = `https://www.youtube.com/watch?v=${videoId}`;

  const info = (await runYtdlpWithFallback(url)) as any;

  const formats: StreamFormat[] = (info.formats || []).map((f: any) => ({
    formatId: f.format_id,
    url: f.url,
    ext: f.ext,
    quality: f.format_note || f.quality || "unknown",
    filesize: f.filesize,
    vcodec: f.vcodec,
    acodec: f.acodec,
    width: f.width,
    height: f.height,
    fps: f.fps,
    abr: f.abr,
  }));

  return {
    id: info.id,
    title: info.title,
    description: info.description || "",
    thumbnailUrl: info.thumbnail || "",
    duration: info.duration || 0,
    viewCount: info.view_count || 0,
    channelId: info.channel_id || "",
    channelTitle: info.channel || "",
    uploadDate: info.upload_date || "",
    formats,
  };
}

export async function getStreamUrls(videoId: string): Promise<StreamUrls> {
  // Check cache first
  const cached = streamCache.get(videoId);
  if (cached && Date.now() - cached.timestamp < CACHE_TTL) {
    return cached.data;
  }

  const url = `https://www.youtube.com/watch?v=${videoId}`;

  const info = (await runYtdlpWithFallback(url)) as any;

  const formats = info.formats || [];

  // Find best video format (prefer mp4 with audio, or separate streams)
  let videoUrl: string | null = null;
  let audioUrl: string | null = null;

  // Try to find combined video+audio format first (easier to play)
  const combinedFormats = formats
    .filter(
      (f: any) =>
        f.vcodec !== "none" &&
        f.acodec !== "none" &&
        f.ext === "mp4" &&
        f.url
    )
    .sort((a: any, b: any) => (b.height || 0) - (a.height || 0));

  if (combinedFormats.length > 0) {
    // Get 720p or lower for better compatibility
    const preferred =
      combinedFormats.find((f: any) => f.height <= 720) || combinedFormats[0];
    videoUrl = preferred.url;
  }

  // If no combined format, get separate video and audio
  if (!videoUrl) {
    const videoOnlyFormats = formats
      .filter(
        (f: any) =>
          f.vcodec !== "none" &&
          f.acodec === "none" &&
          f.ext === "mp4" &&
          f.url
      )
      .sort((a: any, b: any) => (b.height || 0) - (a.height || 0));

    if (videoOnlyFormats.length > 0) {
      const preferred =
        videoOnlyFormats.find((f: any) => f.height <= 720) ||
        videoOnlyFormats[0];
      videoUrl = preferred.url;
    }
  }

  // Find best audio-only format (for background playback)
  const audioFormats = formats
    .filter(
      (f: any) =>
        f.vcodec === "none" &&
        f.acodec !== "none" &&
        (f.ext === "m4a" || f.ext === "mp4" || f.ext === "webm") &&
        f.url
    )
    .sort((a: any, b: any) => (b.abr || 0) - (a.abr || 0));

  if (audioFormats.length > 0) {
    // Prefer m4a for iOS compatibility
    const m4aFormat = audioFormats.find((f: any) => f.ext === "m4a");
    audioUrl = m4aFormat?.url || audioFormats[0].url;
  }

  // If still no audio, extract from combined format
  if (!audioUrl && videoUrl) {
    // The combined format URL can also be used for audio
    audioUrl = videoUrl;
  }

  const result: StreamUrls = {
    videoUrl,
    audioUrl,
    thumbnailUrl: info.thumbnail || "",
    title: info.title || "",
    duration: info.duration || 0,
  };

  // Cache the result
  streamCache.set(videoId, { data: result, timestamp: Date.now() });

  return result;
}

// Get audio-only stream URL (for background playback)
export async function getAudioStreamUrl(
  videoId: string
): Promise<string | null> {
  const streams = await getStreamUrls(videoId);
  return streams.audioUrl;
}

// Get video stream URL
export async function getVideoStreamUrl(
  videoId: string
): Promise<string | null> {
  const streams = await getStreamUrls(videoId);
  return streams.videoUrl;
}

// Clear expired cache entries
export function cleanupCache(): void {
  const now = Date.now();
  for (const [key, value] of streamCache.entries()) {
    if (now - value.timestamp >= CACHE_TTL) {
      streamCache.delete(key);
    }
  }
}

// Run cleanup every hour
setInterval(cleanupCache, 60 * 60 * 1000);
