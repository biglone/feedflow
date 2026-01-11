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
                        feedDescription: cloudFeed.description
                    )
                    modelContext.insert(feed)

                    // Fetch articles for this feed
                    let cloudArticles = try await apiClient.getFeedArticles(feedId: cloudFeed.id)
                    for cloudArticle in cloudArticles {
                        let article = Article(
                            guid: cloudArticle.guid,
                            title: cloudArticle.title,
                            content: cloudArticle.content,
                            summary: cloudArticle.summary,
                            articleURL: cloudArticle.url,
                            author: cloudArticle.author,
                            imageURL: cloudArticle.imageUrl,
                            publishedAt: cloudArticle.publishedAt
                        )
                        article.isRead = cloudArticle.isRead
                        article.isStarred = cloudArticle.isStarred
                        article.feed = feed
                        modelContext.insert(article)
                    }

                    feed.unreadCount = cloudArticles.filter { !$0.isRead }.count
                    feed.lastUpdated = cloudFeed.lastFetchedAt
                }
            }

            try modelContext.save()
            lastSyncTime = Date()
        } catch {
            self.error = error
        }
    }

    func addFeed(url: String) async throws -> Feed {
        let feedURL: String
        if url.hasPrefix("http://") || url.hasPrefix("https://") {
            feedURL = url
        } else {
            feedURL = "https://\(url)"
        }

        // If logged in, add via cloud API (which handles RSS parsing)
        if syncMode == .cloud {
            let cloudFeed = try await apiClient.addFeed(url: feedURL)

            let feed = Feed(
                title: cloudFeed.title,
                feedURL: cloudFeed.feedUrl,
                siteURL: cloudFeed.siteUrl,
                iconURL: cloudFeed.iconUrl,
                feedDescription: cloudFeed.description
            )

            modelContext.insert(feed)

            // Fetch articles from cloud
            let cloudArticles = try await apiClient.getFeedArticles(feedId: cloudFeed.id)
            for cloudArticle in cloudArticles {
                let article = Article(
                    guid: cloudArticle.guid,
                    title: cloudArticle.title,
                    content: cloudArticle.content,
                    summary: cloudArticle.summary,
                    articleURL: cloudArticle.url,
                    author: cloudArticle.author,
                    imageURL: cloudArticle.imageUrl,
                    publishedAt: cloudArticle.publishedAt
                )
                article.feed = feed
                modelContext.insert(article)
            }

            feed.unreadCount = cloudArticles.count
            feed.lastUpdated = Date()

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

        let feed = Feed(
            title: parsedFeed.title,
            feedURL: finalURL,
            siteURL: parsedFeed.siteURL,
            iconURL: parsedFeed.iconURL,
            feedDescription: parsedFeed.description
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

    func refreshAllFeeds() async {
        isRefreshing = true
        defer { isRefreshing = false }

        let descriptor = FetchDescriptor<Feed>()
        guard let feeds = try? modelContext.fetch(descriptor) else { return }

        for feed in feeds {
            do {
                try await refreshFeed(feed)
            } catch {
                self.error = error
            }
        }
    }

    // MARK: - YouTube Backfill (Local)

    func loadMoreYouTubeVideos(for feed: Feed, pageSize: Int = 50) async throws -> Int {
        guard let channelId = extractYouTubeChannelId(from: feed.feedURL) else { return 0 }

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

    private func extractYouTubeChannelId(from feedUrl: String) -> String? {
        guard let url = URL(string: feedUrl) else { return nil }
        guard (url.host ?? "").contains("youtube.com") else { return nil }
        guard url.path.contains("/feeds/videos.xml") else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first(where: { $0.name == "channel_id" })?.value
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
