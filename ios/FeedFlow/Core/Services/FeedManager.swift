import Foundation
import SwiftData

enum SyncMode {
    case local
    case cloud
}

@MainActor
class FeedManager: ObservableObject {
    private let modelContext: ModelContext
    private let rssService = RSSService.shared
    private let apiClient = APIClient.shared
    private let authManager = AuthManager.shared

    @Published var isRefreshing = false
    @Published var isSyncing = false
    @Published var error: Error?
    @Published var lastSyncTime: Date?

    var syncMode: SyncMode {
        authManager.isLoggedIn ? .cloud : .local
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Cloud Sync

    func syncWithCloud() async {
        guard syncMode == .cloud else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            // Fetch feeds from cloud
            let cloudFeeds = try await apiClient.getFeeds()

            // Get local feeds
            let descriptor = FetchDescriptor<Feed>()
            let localFeeds = try modelContext.fetch(descriptor)
            let localFeedURLs = Set(localFeeds.map { $0.feedURL })

            // Add new feeds from cloud (cloud-first strategy)
            for cloudFeed in cloudFeeds {
                if !localFeedURLs.contains(cloudFeed.feedUrl) {
                    let feed = Feed(
                        title: cloudFeed.title,
                        feedURL: cloudFeed.feedUrl,
                        siteURL: cloudFeed.siteUrl,
                        iconURL: cloudFeed.iconUrl,
                        feedDescription: cloudFeed.description,
                        kind: FeedKind.infer(from: cloudFeed.feedUrl).rawValue
                    )
                    modelContext.insert(feed)

	                    // Fetch articles for this feed
	                    let cloudArticles = try await apiClient.getFeedArticles(feedId: cloudFeed.id)
	                    for cloudArticle in cloudArticles {
	                        let audioURL = FeedKind.isAudioEnclosureURL(cloudArticle.imageUrl) ? cloudArticle.imageUrl : nil
	                        let imageURL = audioURL == nil ? cloudArticle.imageUrl : nil
	                        let article = Article(
	                            guid: cloudArticle.guid,
	                            title: cloudArticle.title,
	                            content: cloudArticle.content,
	                            summary: cloudArticle.summary,
	                            articleURL: cloudArticle.url,
	                            author: cloudArticle.author,
	                            imageURL: imageURL,
	                            audioURL: audioURL,
	                            publishedAt: cloudArticle.publishedAt
	                        )
	                        article.isRead = cloudArticle.isRead
	                        article.isStarred = cloudArticle.isStarred
	                        article.feed = feed
                        modelContext.insert(article)
                    }

                    feed.unreadCount = cloudArticles.filter { !$0.isRead }.count
                    feed.lastUpdated = cloudFeed.lastFetchedAt

                    if feed.kind == FeedKind.rss.rawValue {
                        let hasAudioEnclosure = cloudArticles.contains { FeedKind.isAudioEnclosureURL($0.imageUrl) }
                        if hasAudioEnclosure {
                            feed.kind = FeedKind.podcast.rawValue
                        }
                    }
                }
            }

            try modelContext.save()
            lastSyncTime = Date()
        } catch {
            self.error = error
        }
    }

    func addFeed(url: String, kindHint: FeedKind? = nil) async throws -> Feed {
        let feedURL: String
        if url.hasPrefix("http://") || url.hasPrefix("https://") {
            feedURL = url
        } else {
            feedURL = "https://\(url)"
        }

        // If logged in, add via cloud API (which handles RSS parsing)
        if syncMode == .cloud {
            let cloudFeed = try await apiClient.addFeed(url: feedURL)

            let inferredKind = kindHint ?? FeedKind.infer(from: cloudFeed.feedUrl)
            let feed = Feed(
                title: cloudFeed.title,
                feedURL: cloudFeed.feedUrl,
                siteURL: cloudFeed.siteUrl,
                iconURL: cloudFeed.iconUrl,
                feedDescription: cloudFeed.description,
                kind: inferredKind.rawValue
            )

            modelContext.insert(feed)

	            // Fetch articles from cloud
	            let cloudArticles = try await apiClient.getFeedArticles(feedId: cloudFeed.id)
	            for cloudArticle in cloudArticles {
	                let audioURL = FeedKind.isAudioEnclosureURL(cloudArticle.imageUrl) ? cloudArticle.imageUrl : nil
	                let imageURL = audioURL == nil ? cloudArticle.imageUrl : nil
	                let article = Article(
	                    guid: cloudArticle.guid,
	                    title: cloudArticle.title,
	                    content: cloudArticle.content,
	                    summary: cloudArticle.summary,
	                    articleURL: cloudArticle.url,
	                    author: cloudArticle.author,
	                    imageURL: imageURL,
	                    audioURL: audioURL,
	                    publishedAt: cloudArticle.publishedAt
	                )
	                article.feed = feed
	                modelContext.insert(article)
	            }

            feed.unreadCount = cloudArticles.count
            feed.lastUpdated = Date()

            if inferredKind == .rss {
                let hasAudioEnclosure = cloudArticles.contains { FeedKind.isAudioEnclosureURL($0.imageUrl) }
                if hasAudioEnclosure {
                    feed.kind = FeedKind.podcast.rawValue
                }
            }

            try modelContext.save()
            return feed
        }

        // Local mode: parse RSS directly
        var finalURL = feedURL
        do {
            _ = try await rssService.fetchFeed(from: feedURL)
        } catch {
            finalURL = try await rssService.discoverFeedURL(from: feedURL)
        }

        let parsedFeed = try await rssService.fetchFeed(from: finalURL)

        let inferredKind = kindHint ?? parsedFeed.kind
        let feed = Feed(
            title: parsedFeed.title,
            feedURL: finalURL,
            siteURL: parsedFeed.siteURL,
            iconURL: parsedFeed.iconURL,
            feedDescription: parsedFeed.description,
            kind: inferredKind.rawValue
        )

        modelContext.insert(feed)

	        for parsedArticle in parsedFeed.articles {
	            let article = Article(
	                guid: parsedArticle.guid,
	                title: parsedArticle.title,
	                content: parsedArticle.content,
	                summary: parsedArticle.summary,
	                articleURL: parsedArticle.url,
	                author: parsedArticle.author,
	                imageURL: parsedArticle.imageURL,
	                audioURL: parsedArticle.audioURL,
	                publishedAt: parsedArticle.publishedAt
	            )
	            article.feed = feed
	            modelContext.insert(article)
	        }

        feed.unreadCount = parsedFeed.articles.count
        feed.lastUpdated = Date()

        try modelContext.save()

        return feed
    }

    func deleteFeed(_ feed: Feed) {
        modelContext.delete(feed)
        try? modelContext.save()
    }

    func refreshFeed(_ feed: Feed) async throws {
        let parsedFeed = try await rssService.fetchFeed(from: feed.feedURL)

        if feed.kind == nil, parsedFeed.kind == .podcast {
            feed.kind = parsedFeed.kind.rawValue
        }

        let existingGUIDs = Set(feed.articles.map { $0.guid })

        var newArticlesCount = 0
        for parsedArticle in parsedFeed.articles {
	            if !existingGUIDs.contains(parsedArticle.guid) {
	                let article = Article(
	                    guid: parsedArticle.guid,
	                    title: parsedArticle.title,
	                    content: parsedArticle.content,
	                    summary: parsedArticle.summary,
	                    articleURL: parsedArticle.url,
	                    author: parsedArticle.author,
	                    imageURL: parsedArticle.imageURL,
	                    audioURL: parsedArticle.audioURL,
	                    publishedAt: parsedArticle.publishedAt
	                )
	                article.feed = feed
	                modelContext.insert(article)
	                newArticlesCount += 1
	            }
	        }

        feed.unreadCount += newArticlesCount
        feed.lastUpdated = Date()

        try modelContext.save()
    }

    func refreshAllFeeds(kind: FeedKind? = nil) async {
        isRefreshing = true
        defer { isRefreshing = false }

        let descriptor = FetchDescriptor<Feed>()
        guard let feeds = try? modelContext.fetch(descriptor) else { return }

        for feed in feeds {
            if let kind, feed.resolvedKind != kind {
                continue
            }
            do {
                try await refreshFeed(feed)
            } catch {
                self.error = error
            }
        }
    }

    // MARK: - Podcast Audio

    enum PodcastAudioError: Error, LocalizedError {
        case missingFeed
        case audioNotFound
        case invalidAudioURL

        var errorDescription: String? {
            switch self {
            case .missingFeed:
                return "Missing feed information for this episode."
            case .audioNotFound:
                return "No audio enclosure found for this episode."
            case .invalidAudioURL:
                return "Invalid audio URL."
            }
        }
    }

    func getPodcastAudioURL(for article: Article) async throws -> URL {
        if let urlString = article.resolvedAudioURL, let url = URL(string: urlString) {
            return url
        }

        guard let feed = article.feed else {
            throw PodcastAudioError.missingFeed
        }

        let parsedFeed = try await rssService.fetchFeed(from: feed.feedURL)

        let targetGuid = article.guid.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetURL = normalizeURLString(article.articleURL)
        let targetTitle = article.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetPublishedAt = article.publishedAt

        let match =
            parsedFeed.articles.first(where: { $0.guid == targetGuid })
            ?? parsedFeed.articles.first(where: { normalizeURLString($0.url) == targetURL && targetURL != nil })
            ?? parsedFeed.articles.first(where: { candidate in
                let candidateTitle = candidate.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !candidateTitle.isEmpty, candidateTitle == targetTitle else { return false }
                guard let targetPublishedAt, let candidatePublishedAt = candidate.publishedAt else { return true }
                return abs(candidatePublishedAt.timeIntervalSince(targetPublishedAt)) < 60 * 60 * 24
            })

        guard let audioURLString = match?.audioURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !audioURLString.isEmpty else {
            throw PodcastAudioError.audioNotFound
        }

        guard let url = URL(string: audioURLString) else {
            throw PodcastAudioError.invalidAudioURL
        }

        article.audioURL = audioURLString
        try? modelContext.save()

        return url
    }

    private func normalizeURLString(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return URL(string: value)?.absoluteString ?? value
    }

    // MARK: - YouTube Backfill (Local)

    func ensureYouTubeChannelIcons() async {
        let descriptor = FetchDescriptor<Feed>()
        guard let feeds = try? modelContext.fetch(descriptor) else { return }
        await ensureYouTubeChannelIcons(for: feeds)
    }

    func ensureYouTubeChannelIcons(for feeds: [Feed]) async {
        var didUpdate = false

        for feed in feeds where feed.resolvedKind == .youtube {
            if Task.isCancelled { break }
            let updated = await ensureYouTubeChannelIcon(for: feed)
            didUpdate = didUpdate || updated
        }

        if didUpdate {
            try? modelContext.save()
        }
    }

    private func ensureYouTubeChannelIcon(for feed: Feed) async -> Bool {
        guard feed.resolvedKind == .youtube else { return false }
        guard FeedKind.isGenericYouTubeIconURL(feed.iconURL) else { return false }
        guard let channelId = FeedKind.extractYouTubeChannelId(from: feed.feedURL) else { return false }

        do {
            guard let channel = try await apiClient.getYouTubeChannel(id: channelId) else { return false }
            let thumbnailUrl = channel.thumbnailUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !thumbnailUrl.isEmpty else { return false }

            if feed.iconURL != thumbnailUrl {
                feed.iconURL = thumbnailUrl
                return true
            }
        } catch {
            return false
        }

        return false
    }

    func loadMoreYouTubeVideos(for feed: Feed, pageSize: Int = 50) async throws -> Int {
        guard let channelId = FeedKind.extractYouTubeChannelId(from: feed.feedURL) else { return 0 }

        let reachedEndKey = "youtubeVideosReachedEnd.\(channelId)"
        if UserDefaults.standard.bool(forKey: reachedEndKey) {
            return 0
        }

        let pageTokenKey = "youtubeVideosNextPageToken.\(channelId)"
        let pageToken = UserDefaults.standard.string(forKey: pageTokenKey)

        let page = try await apiClient.getYouTubeChannelVideosPage(
            channelId: channelId,
            limit: pageSize,
            pageToken: pageToken
        )

        if let nextPageToken = page.nextPageToken, !nextPageToken.isEmpty {
            UserDefaults.standard.set(nextPageToken, forKey: pageTokenKey)
            UserDefaults.standard.set(false, forKey: reachedEndKey)
        } else {
            UserDefaults.standard.removeObject(forKey: pageTokenKey)
            UserDefaults.standard.set(true, forKey: reachedEndKey)
        }

        var existingGUIDs = Set(feed.articles.map { $0.guid })
        var insertedCount = 0

        for video in page.videos {
            let guid = "yt:video:\(video.id)"
            if existingGUIDs.contains(guid) {
                continue
            }
            existingGUIDs.insert(guid)

            let publishedAt = parseYouTubeDate(video.publishedAt)
            let articleURL = "https://www.youtube.com/watch?v=\(video.id)"

            let article = Article(
                guid: guid,
                title: video.title,
                content: nil,
                summary: video.description.isEmpty ? nil : video.description,
                articleURL: articleURL,
                author: video.channelTitle,
                imageURL: video.thumbnailUrl.isEmpty ? nil : video.thumbnailUrl,
                publishedAt: publishedAt
            )
            article.isRead = true
            article.feed = feed
            modelContext.insert(article)
            insertedCount += 1
        }

        if insertedCount > 0 {
            try modelContext.save()
        }

        return insertedCount
    }

    private func parseYouTubeDate(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }

        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: value) {
            return date
        }

        let withoutFractional = ISO8601DateFormatter()
        withoutFractional.formatOptions = [.withInternetDateTime]
        return withoutFractional.date(from: value)
    }

    func markAsRead(_ article: Article) {
        if !article.isRead {
            article.isRead = true
            if let feed = article.feed, feed.unreadCount > 0 {
                feed.unreadCount -= 1
            }
            try? modelContext.save()

            // Sync to cloud in background
            if syncMode == .cloud {
                Task {
                    try? await apiClient.updateArticle(id: article.id.uuidString, isRead: true)
                }
            }
        }
    }

    func toggleStarred(_ article: Article) {
        article.isStarred.toggle()
        try? modelContext.save()

        // Sync to cloud in background
        if syncMode == .cloud {
            let newValue = article.isStarred
            Task {
                try? await apiClient.updateArticle(id: article.id.uuidString, isStarred: newValue)
            }
        }
    }

    func markAllAsRead(in feed: Feed) {
        let articleIds = feed.articles.filter { !$0.isRead }.map { $0.id.uuidString }

        for article in feed.articles where !article.isRead {
            article.isRead = true
        }
        feed.unreadCount = 0
        try? modelContext.save()

        // Sync to cloud in background
        if syncMode == .cloud && !articleIds.isEmpty {
            Task {
                try? await apiClient.batchUpdateArticles(ids: articleIds, isRead: true)
            }
        }
    }
}
