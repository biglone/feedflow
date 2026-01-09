import Parser from "rss-parser";
import { resolveChannelUrl } from "./youtube.js";

const parser = new Parser({
  customFields: {
    item: [
      ["content:encoded", "contentEncoded"],
      ["media:content", "mediaContent"],
      ["media:thumbnail", "mediaThumbnail"],
    ],
  },
});

// Check if URL is a YouTube URL
function isYouTubeUrl(url: string): boolean {
  try {
    const urlObj = new URL(url);
    return (
      urlObj.hostname === "youtube.com" ||
      urlObj.hostname === "www.youtube.com" ||
      urlObj.hostname === "m.youtube.com" ||
      urlObj.hostname === "youtu.be"
    );
  } catch {
    return false;
  }
}

// Convert YouTube channel URL to RSS feed URL
async function resolveYouTubeFeedUrl(url: string): Promise<string | null> {
  // If it's already an RSS feed URL, return it
  if (url.includes("/feeds/videos.xml")) {
    return url;
  }

  try {
    const result = await resolveChannelUrl(url);
    return result?.rssUrl || null;
  } catch (error) {
    console.error("Failed to resolve YouTube URL:", error);
    return null;
  }
}

interface ParsedArticle {
  guid: string;
  title: string;
  content: string | null;
  summary: string | null;
  url: string | null;
  author: string | null;
  imageUrl: string | null;
  publishedAt: Date | null;
}

interface ParsedFeed {
  title: string;
  description: string | null;
  siteUrl: string | null;
  iconUrl: string | null;
  articles: ParsedArticle[];
}

export async function fetchAndParseFeed(url: string): Promise<ParsedFeed> {
  const feed = await parser.parseURL(url);

  const articles: ParsedArticle[] = (feed.items || []).map((item) => {
    const guid = item.guid || item.link || item.title || crypto.randomUUID();
    const content =
      (item as any).contentEncoded || item.content || item["content:encoded"];
    const summary = item.contentSnippet || item.summary;

    let imageUrl: string | null = null;
    if ((item as any).mediaContent?.$.url) {
      imageUrl = (item as any).mediaContent.$.url;
    } else if ((item as any).mediaThumbnail?.$.url) {
      imageUrl = (item as any).mediaThumbnail.$.url;
    } else if (item.enclosure?.url) {
      imageUrl = item.enclosure.url;
    }

    if (!imageUrl && content) {
      const imgMatch = content.match(/<img[^>]+src=["']([^"']+)["']/i);
      if (imgMatch) {
        imageUrl = imgMatch[1];
      }
    }

    return {
      guid,
      title: item.title || "Untitled",
      content: content || null,
      summary: summary || null,
      url: item.link || null,
      author: item.creator || item.author || null,
      imageUrl,
      publishedAt: item.pubDate ? new Date(item.pubDate) : null,
    };
  });

  let iconUrl: string | null = null;
  if (feed.image?.url) {
    iconUrl = feed.image.url;
  } else if (feed.link) {
    try {
      const siteUrl = new URL(feed.link);
      iconUrl = `${siteUrl.origin}/favicon.ico`;
    } catch {}
  }

  return {
    title: feed.title || "Unknown Feed",
    description: feed.description || null,
    siteUrl: feed.link || null,
    iconUrl,
    articles,
  };
}

export async function discoverFeedUrl(websiteUrl: string): Promise<string | null> {
  // Handle YouTube URLs specially
  if (isYouTubeUrl(websiteUrl)) {
    const youtubeRssUrl = await resolveYouTubeFeedUrl(websiteUrl);
    if (youtubeRssUrl) {
      return youtubeRssUrl;
    }
  }

  try {
    const response = await fetch(websiteUrl);
    const html = await response.text();

    const rssLinkMatch = html.match(
      /<link[^>]+type=["']application\/(rss|atom)\+xml["'][^>]+href=["']([^"']+)["']/i
    );

    if (rssLinkMatch) {
      let feedUrl = rssLinkMatch[2];
      if (feedUrl.startsWith("/")) {
        const base = new URL(websiteUrl);
        feedUrl = `${base.origin}${feedUrl}`;
      }
      return feedUrl;
    }

    const commonPaths = [
      "/feed",
      "/rss",
      "/feed.xml",
      "/rss.xml",
      "/atom.xml",
      "/index.xml",
    ];

    const base = new URL(websiteUrl);

    for (const path of commonPaths) {
      const potentialUrl = `${base.origin}${path}`;
      try {
        await fetchAndParseFeed(potentialUrl);
        return potentialUrl;
      } catch {}
    }

    return null;
  } catch {
    return null;
  }
}
