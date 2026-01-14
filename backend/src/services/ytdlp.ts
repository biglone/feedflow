import youtubedl from "youtube-dl-exec";
import { execSync } from "child_process";
import fs from "node:fs";
import { chmod, mkdir, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { ProxyAgent, fetch as undiciFetch, type Response as UndiciResponse } from "undici";

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

const ytdlpFallbackAsset = getYtdlpBinaryAssetName();
const ytdlpFallbackPath = ytdlpFallbackAsset
  ? path.join(os.tmpdir(), "feedflow", ytdlpFallbackAsset)
  : null;
let ytdlpFallbackPromise: Promise<string> | null = null;
let ytdlpFallbackEnabled = false;

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

async function runYtdlp(url: string): Promise<any> {
  const options: Record<string, any> = {
    dumpSingleJson: true,
    noCheckCertificates: true,
    noWarnings: true,
    preferFreeFormats: true,
    socketTimeout: 15,
    retries: 2,
  };


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

  const info = (await runYtdlp(url)) as any;

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

  const info = (await runYtdlp(url)) as any;

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
