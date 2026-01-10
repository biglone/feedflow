import youtubedl from "youtube-dl-exec";
import { execSync } from "child_process";

// Get system yt-dlp path
const ytdlpPath = (() => {
  try {
    return execSync("which yt-dlp").toString().trim();
  } catch {
    return undefined;
  }
})();

const ytdlp = ytdlpPath ? youtubedl.create(ytdlpPath) : youtubedl;

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

  const info = (await ytdlp(url, {
    dumpSingleJson: true,
    noCheckCertificates: true,
    noWarnings: true,
    preferFreeFormats: true,
  })) as any;

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

  const info = (await ytdlp(url, {
    dumpSingleJson: true,
    noCheckCertificates: true,
    noWarnings: true,
    preferFreeFormats: true,
  })) as any;

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
