import Foundation
import FeedKit
import SwiftData

enum RSSError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case parsingError(String)
    case feedNotFound

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid feed URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .parsingError(let message):
            return "Parsing error: \(message)"
        case .feedNotFound:
            return "Feed not found"
        }
    }
}

struct ParsedFeed {
    let title: String
    let description: String?
    let siteURL: String?
    let iconURL: String?
    let kind: FeedKind
    let articles: [ParsedArticle]
}

struct ParsedArticle {
    let guid: String
    let title: String
    let content: String?
    let summary: String?
    let url: String?
    let author: String?
    let imageURL: String?
    let publishedAt: Date?
}

actor RSSService {
    static let shared = RSSService()

    private init() {}

    func fetchFeed(from urlString: String) async throws -> ParsedFeed {
        guard let url = URL(string: urlString) else {
            throw RSSError.invalidURL
        }

        let parser = FeedParser(URL: url)
        let result = await withCheckedContinuation { continuation in
            parser.parseAsync { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success(let feed):
            return try parseFeed(feed, feedURL: urlString)
        case .failure(let error):
            throw RSSError.parsingError(error.localizedDescription)
        }
    }

    private func parseFeed(_ feed: FeedKit.Feed, feedURL: String) throws -> ParsedFeed {
        switch feed {
        case .rss(let rssFeed):
            return parseRSSFeed(rssFeed, feedURL: feedURL)
        case .atom(let atomFeed):
            return parseAtomFeed(atomFeed, feedURL: feedURL)
        case .json(let jsonFeed):
            return parseJSONFeed(jsonFeed, feedURL: feedURL)
        }
    }

    private func parseRSSFeed(_ feed: RSSFeed, feedURL: String) -> ParsedFeed {
        let isYouTube = FeedKind.isYouTubeFeedURL(feedURL)
        var containsAudioEnclosure = false

        let articles = feed.items?.compactMap { item -> ParsedArticle? in
            let guid = item.guid?.value ?? item.link ?? UUID().uuidString
            let title = item.title ?? "Untitled"

            let enclosureURL = item.enclosure?.attributes?.url
            if FeedKind.isAudioEnclosureURL(enclosureURL) {
                containsAudioEnclosure = true
            }

            return ParsedArticle(
                guid: guid,
                title: title,
                content: item.content?.contentEncoded,
                summary: item.description,
                url: item.link,
                author: item.author ?? item.dublinCore?.dcCreator,
                imageURL: item.media?.mediaThumbnails?.first?.attributes?.url
                    ?? (FeedKind.isImageURL(enclosureURL) ? enclosureURL : nil),
                publishedAt: item.pubDate
            )
        } ?? []

        return ParsedFeed(
            title: feed.title ?? "Unknown Feed",
            description: feed.description,
            siteURL: feed.link,
            iconURL: feed.image?.url,
            kind: isYouTube ? .youtube : (containsAudioEnclosure ? .podcast : .rss),
            articles: articles
        )
    }

    private func parseAtomFeed(_ feed: AtomFeed, feedURL: String) -> ParsedFeed {
        let articles = feed.entries?.compactMap { entry -> ParsedArticle? in
            let guid = entry.id ?? entry.links?.first?.attributes?.href ?? UUID().uuidString
            let title = entry.title ?? "Untitled"

            return ParsedArticle(
                guid: guid,
                title: title,
                content: entry.content?.value,
                summary: entry.summary?.value,
                url: entry.links?.first?.attributes?.href,
                author: entry.authors?.first?.name,
                imageURL: entry.media?.mediaThumbnails?.first?.attributes?.url,
                publishedAt: entry.published ?? entry.updated
            )
        } ?? []

        return ParsedFeed(
            title: feed.title ?? "Unknown Feed",
            description: feed.subtitle?.value,
            siteURL: feed.links?.first?.attributes?.href,
            iconURL: feed.icon ?? feed.logo,
            kind: FeedKind.infer(from: feedURL),
            articles: articles
        )
    }

    private func parseJSONFeed(_ feed: JSONFeed, feedURL: String) -> ParsedFeed {
        let articles = feed.items?.compactMap { item -> ParsedArticle? in
            let guid = item.id ?? item.url ?? UUID().uuidString
            let title = item.title ?? "Untitled"

            return ParsedArticle(
                guid: guid,
                title: title,
                content: item.contentHtml ?? item.contentText,
                summary: item.summary,
                url: item.url,
                author: item.author?.name,
                imageURL: item.image ?? item.bannerImage,
                publishedAt: item.datePublished
            )
        } ?? []

        return ParsedFeed(
            title: feed.title ?? "Unknown Feed",
            description: feed.description,
            siteURL: feed.homePageURL,
            iconURL: feed.icon ?? feed.favicon,
            kind: FeedKind.infer(from: feedURL),
            articles: articles
        )
    }

    func discoverFeedURL(from websiteURL: String) async throws -> String {
        guard let url = URL(string: websiteURL) else {
            throw RSSError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else {
            throw RSSError.feedNotFound
        }

        let feedPatterns = [
            #"<link[^>]+type=[\"']application/rss\+xml[\"'][^>]+href=[\"']([^\"']+)[\"']"#,
            #"<link[^>]+type=[\"']application/atom\+xml[\"'][^>]+href=[\"']([^\"']+)[\"']"#,
            #"<link[^>]+href=[\"']([^\"']+)[\"'][^>]+type=[\"']application/rss\+xml[\"']"#,
            #"<link[^>]+href=[\"']([^\"']+)[\"'][^>]+type=[\"']application/atom\+xml[\"']"#,
        ]

        for pattern in feedPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(html.startIndex..., in: html)
                if let match = regex.firstMatch(in: html, options: [], range: range) {
                    if let feedURLRange = Range(match.range(at: 1), in: html) {
                        var feedURL = String(html[feedURLRange])
                        if feedURL.hasPrefix("/") {
                            feedURL = "\(url.scheme ?? "https")://\(url.host ?? "")\(feedURL)"
                        }
                        return feedURL
                    }
                }
            }
        }

        let commonFeedPaths = ["/feed", "/rss", "/feed.xml", "/rss.xml", "/atom.xml", "/index.xml"]
        let baseURL = "\(url.scheme ?? "https")://\(url.host ?? "")"

        for path in commonFeedPaths {
            let potentialURL = "\(baseURL)\(path)"
            do {
                _ = try await fetchFeed(from: potentialURL)
                return potentialURL
            } catch {
                continue
            }
        }

        throw RSSError.feedNotFound
    }
}
