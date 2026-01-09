import { google, youtube_v3 } from "googleapis";

const youtube = google.youtube({
  version: "v3",
  auth: process.env.YOUTUBE_API_KEY,
});

export interface YouTubeChannel {
  id: string;
  title: string;
  description: string;
  thumbnailUrl: string;
  subscriberCount: string;
  videoCount: string;
  customUrl?: string;
}

export interface YouTubeVideo {
  id: string;
  title: string;
  description: string;
  thumbnailUrl: string;
  publishedAt: string;
  duration?: string;
  viewCount?: string;
  channelId: string;
  channelTitle: string;
}

export async function searchChannels(
  query: string,
  maxResults: number = 10
): Promise<YouTubeChannel[]> {
  if (!process.env.YOUTUBE_API_KEY) {
    throw new Error("YOUTUBE_API_KEY is not configured. Please add it to your .env file.");
  }

  try {
    const response = await youtube.search.list({
      part: ["snippet"],
      q: query,
      type: ["channel"],
      maxResults,
    });

    const channelIds =
      response.data.items
        ?.map((item) => item.snippet?.channelId)
        .filter(Boolean) as string[];

    if (!channelIds?.length) {
      return [];
    }

    // Get detailed channel info
    const channelResponse = await youtube.channels.list({
      part: ["snippet", "statistics"],
      id: channelIds,
    });

    return (
      channelResponse.data.items?.map((channel) => ({
        id: channel.id!,
        title: channel.snippet?.title || "Unknown",
        description: channel.snippet?.description || "",
        thumbnailUrl:
          channel.snippet?.thumbnails?.medium?.url ||
          channel.snippet?.thumbnails?.default?.url ||
          "",
        subscriberCount: channel.statistics?.subscriberCount || "0",
        videoCount: channel.statistics?.videoCount || "0",
        customUrl: channel.snippet?.customUrl,
      })) || []
    );
  } catch (error: any) {
    console.error("YouTube API search error:", error.message);
    if (error.code === 403) {
      throw new Error("YouTube API quota exceeded or API key invalid. Check your Google Cloud Console.");
    }
    if (error.code === 400) {
      throw new Error("Invalid YouTube API request. Check your API key configuration.");
    }
    throw new Error(`YouTube API error: ${error.message || "Unknown error"}`);
  }
}

export async function getChannelInfo(
  channelId: string
): Promise<YouTubeChannel | null> {
  const response = await youtube.channels.list({
    part: ["snippet", "statistics"],
    id: [channelId],
  });

  const channel = response.data.items?.[0];
  if (!channel) return null;

  return {
    id: channel.id!,
    title: channel.snippet?.title || "Unknown",
    description: channel.snippet?.description || "",
    thumbnailUrl:
      channel.snippet?.thumbnails?.medium?.url ||
      channel.snippet?.thumbnails?.default?.url ||
      "",
    subscriberCount: channel.statistics?.subscriberCount || "0",
    videoCount: channel.statistics?.videoCount || "0",
    customUrl: channel.snippet?.customUrl,
  };
}

export async function getChannelVideos(
  channelId: string,
  maxResults: number = 20
): Promise<YouTubeVideo[]> {
  const response = await youtube.search.list({
    part: ["snippet"],
    channelId,
    order: "date",
    type: ["video"],
    maxResults,
  });

  const videoIds =
    response.data.items?.map((item) => item.id?.videoId).filter(Boolean) as
      | string[]
      | undefined;

  if (!videoIds?.length) {
    return [];
  }

  // Get video details (duration, view count)
  const videoResponse = await youtube.videos.list({
    part: ["snippet", "contentDetails", "statistics"],
    id: videoIds,
  });

  return (
    videoResponse.data.items?.map((video) => ({
      id: video.id!,
      title: video.snippet?.title || "Untitled",
      description: video.snippet?.description || "",
      thumbnailUrl:
        video.snippet?.thumbnails?.medium?.url ||
        video.snippet?.thumbnails?.default?.url ||
        "",
      publishedAt: video.snippet?.publishedAt || "",
      duration: video.contentDetails?.duration || "",
      viewCount: video.statistics?.viewCount || "0",
      channelId: video.snippet?.channelId || "",
      channelTitle: video.snippet?.channelTitle || "",
    })) || []
  );
}

// Convert various YouTube URL formats to channel ID
export async function resolveChannelUrl(
  url: string
): Promise<{ channelId: string; rssUrl: string } | null> {
  const urlObj = new URL(url);

  // Direct channel ID: youtube.com/channel/UCxxxx
  const channelMatch = url.match(/youtube\.com\/channel\/(UC[\w-]+)/);
  if (channelMatch) {
    return {
      channelId: channelMatch[1],
      rssUrl: `https://www.youtube.com/feeds/videos.xml?channel_id=${channelMatch[1]}`,
    };
  }

  // Handle @username format: youtube.com/@username
  const handleMatch = url.match(/youtube\.com\/@([\w-]+)/);
  if (handleMatch) {
    const response = await youtube.search.list({
      part: ["snippet"],
      q: handleMatch[1],
      type: ["channel"],
      maxResults: 1,
    });

    const channelId = response.data.items?.[0]?.snippet?.channelId;
    if (channelId) {
      return {
        channelId,
        rssUrl: `https://www.youtube.com/feeds/videos.xml?channel_id=${channelId}`,
      };
    }
  }

  // Handle /c/channelname format
  const customMatch = url.match(/youtube\.com\/c\/([\w-]+)/);
  if (customMatch) {
    const response = await youtube.search.list({
      part: ["snippet"],
      q: customMatch[1],
      type: ["channel"],
      maxResults: 1,
    });

    const channelId = response.data.items?.[0]?.snippet?.channelId;
    if (channelId) {
      return {
        channelId,
        rssUrl: `https://www.youtube.com/feeds/videos.xml?channel_id=${channelId}`,
      };
    }
  }

  // Handle /user/username format (legacy)
  const userMatch = url.match(/youtube\.com\/user\/([\w-]+)/);
  if (userMatch) {
    const response = await youtube.channels.list({
      part: ["id"],
      forUsername: userMatch[1],
    });

    const channelId = response.data.items?.[0]?.id;
    if (channelId) {
      return {
        channelId,
        rssUrl: `https://www.youtube.com/feeds/videos.xml?channel_id=${channelId}`,
      };
    }
  }

  return null;
}

// Generate RSS feed URL from channel ID
export function getChannelRssUrl(channelId: string): string {
  return `https://www.youtube.com/feeds/videos.xml?channel_id=${channelId}`;
}

// Parse ISO 8601 duration to seconds
export function parseDuration(isoDuration: string): number {
  const match = isoDuration.match(/PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?/);
  if (!match) return 0;

  const hours = parseInt(match[1] || "0");
  const minutes = parseInt(match[2] || "0");
  const seconds = parseInt(match[3] || "0");

  return hours * 3600 + minutes * 60 + seconds;
}

// Format duration to human readable string
export function formatDuration(isoDuration: string): string {
  const totalSeconds = parseDuration(isoDuration);
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;

  if (hours > 0) {
    return `${hours}:${minutes.toString().padStart(2, "0")}:${seconds.toString().padStart(2, "0")}`;
  }
  return `${minutes}:${seconds.toString().padStart(2, "0")}`;
}

export interface YouTubeSubscription {
  channelId: string;
  title: string;
  description: string;
  thumbnailUrl: string;
  rssUrl: string;
}

// Get user's YouTube subscriptions using OAuth access token
export async function getSubscriptions(
  accessToken: string
): Promise<YouTubeSubscription[]> {
  const subscriptions: YouTubeSubscription[] = [];
  let pageToken: string | undefined;

  // Create authenticated YouTube client
  const oauth2Client = new google.auth.OAuth2();
  oauth2Client.setCredentials({ access_token: accessToken });

  const authenticatedYoutube = google.youtube({
    version: "v3",
    auth: oauth2Client,
  });

  do {
    const response = await authenticatedYoutube.subscriptions.list({
      part: ["snippet"],
      mine: true,
      maxResults: 50,
      pageToken,
    });

    if (response.data.items) {
      for (const item of response.data.items) {
        const channelId = item.snippet?.resourceId?.channelId;
        if (channelId) {
          subscriptions.push({
            channelId,
            title: item.snippet?.title || "Unknown",
            description: item.snippet?.description || "",
            thumbnailUrl:
              item.snippet?.thumbnails?.medium?.url ||
              item.snippet?.thumbnails?.default?.url ||
              "",
            rssUrl: getChannelRssUrl(channelId),
          });
        }
      }
    }

    pageToken = response.data.nextPageToken || undefined;
  } while (pageToken);

  return subscriptions;
}
