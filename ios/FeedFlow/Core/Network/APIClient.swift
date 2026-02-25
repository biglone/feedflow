import Foundation
import os

enum AppLog {
    static let subsystem = Bundle.main.bundleIdentifier ?? "FeedFlow"
    static let network = Logger(subsystem: subsystem, category: "network")
    static let player = Logger(subsystem: subsystem, category: "player")
}

enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case serverError(String)
    case networkError(Error)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid server response"
        case .unauthorized:
            return "Please sign in to FeedFlow (Settings → Account) to continue"
        case .serverError(let message):
            return message
        case .networkError(let error):
            return error.localizedDescription
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}

actor APIClient {
    static let shared = APIClient()

    nonisolated private static let didMigrateYouTubeBackendSplitKey = "didMigrateYouTubeBackendSplit.v1"

    private var authToken: String?
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    // Debug builds can switch between remote and local API endpoints via the Settings toggle.
    nonisolated private var baseURL: String {
        if let storedOverride = Self.normalizeBaseURL(
            UserDefaults.standard.string(forKey: "apiBaseURLOverride")
        ) {
            return storedOverride
        }

        if let plistOverride = Self.normalizeBaseURL(
            Bundle.main.object(forInfoDictionaryKey: "FeedFlowAPIBaseURL") as? String
        ) {
            return plistOverride
        }

        #if DEBUG
        if UserDefaults.standard.bool(forKey: "useLocalAPI") {
            return "http://172.16.1.16:3000/api"
        }
        #endif
        return "https://feedflow.biglone.tech/api"
    }

    nonisolated private var youTubeStreamBaseURL: String {
        if let storedOverride = Self.normalizeBaseURL(
            UserDefaults.standard.string(forKey: "youTubeStreamBaseURL")
        ) {
            return storedOverride
        }

        if let plistOverride = Self.normalizeBaseURL(
            Bundle.main.object(forInfoDictionaryKey: "FeedFlowYouTubeStreamBaseURL") as? String
        ) {
            return plistOverride
        }

        return baseURL
    }

    nonisolated func currentBaseURL() -> String {
        baseURL
    }

    nonisolated func currentYouTubeStreamBaseURL() -> String {
        youTubeStreamBaseURL
    }

    private init() {
        Self.migrateLegacyBackendOverridesIfNeeded()

        #if DEBUG
        UserDefaults.standard.register(defaults: ["useLocalAPI": false])
        #endif

        let streamToken =
            (Bundle.main.object(forInfoDictionaryKey: "FeedFlowStreamProxyAccessToken") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !streamToken.isEmpty {
            let existing = (UserDefaults.standard.string(forKey: "streamProxyAccessToken") ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if existing.isEmpty {
                UserDefaults.standard.set(streamToken, forKey: "streamProxyAccessToken")
            }
        }

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    func setAuthToken(_ token: String?) {
        self.authToken = token
    }

    func getAuthToken() -> String? {
        return authToken
    }

    nonisolated private static func normalizeBaseURL(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withScheme: String
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            withScheme = trimmed
        } else {
            withScheme = "https://\(trimmed)"
        }

        var normalized = withScheme.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !normalized.lowercased().hasSuffix("/api") {
            normalized += "/api"
        }

        return normalized
    }

    nonisolated private static func migrateLegacyBackendOverridesIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: didMigrateYouTubeBackendSplitKey) {
            return
        }

        let apiOverride = defaults.string(forKey: "apiBaseURLOverride")
        let youTubeOverride = defaults.string(forKey: "youTubeStreamBaseURL")

        guard let normalizedAPI = normalizeBaseURL(apiOverride) else {
            defaults.set(true, forKey: didMigrateYouTubeBackendSplitKey)
            return
        }

        let normalizedYouTube = normalizeBaseURL(youTubeOverride)

        // Older builds used a single "Vercel" switch that pointed the entire app to a `.vercel.app` base URL.
        // Migrate that config to only affect YouTube requests.
        if normalizedAPI.contains(".vercel.app"), (normalizedYouTube == nil || normalizedYouTube == normalizedAPI) {
            defaults.set("", forKey: "apiBaseURLOverride")
            defaults.set(normalizedAPI, forKey: "youTubeStreamBaseURL")
        }

        defaults.set(true, forKey: didMigrateYouTubeBackendSplitKey)
    }

    private func request<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: Encodable? = nil,
        headers extraHeaders: [String: String] = [:],
        baseURLOverride: String? = nil
    ) async throws -> T {
        let base = baseURLOverride ?? baseURL
        guard let url = URL(string: "\(base)\(endpoint)") else {
            throw APIError.invalidURL
        }

        #if DEBUG
        let networkDebugLogsEnabled = UserDefaults.standard.bool(forKey: "enableNetworkDebugLogs")
        if networkDebugLogsEnabled {
            AppLog.network.debug("HTTP \(method, privacy: .public) \(url.absoluteString, privacy: .public)")
        }
        #endif

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            request.httpBody = try encoder.encode(body)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw error
            }
            AppLog.network.error("HTTP \(method, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        #if DEBUG
        if networkDebugLogsEnabled {
            AppLog.network.debug("HTTP \(method, privacy: .public) \(httpResponse.statusCode, privacy: .public) \(url.absoluteString, privacy: .public)")
        }
        #endif

        if httpResponse.statusCode == 401 {
            if let errorResponse = try? decoder.decode(ErrorResponse.self, from: data) {
                let message = errorResponse.error.trimmingCharacters(in: .whitespacesAndNewlines)
                if !message.isEmpty {
                    let normalized = message.lowercased()
                    if normalized.contains("token") || normalized.contains("unauthorized") || normalized.contains("expired") {
                        throw APIError.unauthorized
                    }
                    throw APIError.serverError(message)
                }
            }
            throw APIError.unauthorized
        }

        if httpResponse.statusCode >= 400 {
            if let errorResponse = try? decoder.decode(ErrorResponse.self, from: data) {
                AppLog.network.error("HTTP \(method, privacy: .public) \(httpResponse.statusCode, privacy: .public) error: \(errorResponse.error, privacy: .public)")
                throw APIError.serverError(errorResponse.error)
            }
            AppLog.network.error("HTTP \(method, privacy: .public) \(httpResponse.statusCode, privacy: .public) error")
            throw APIError.serverError("Server error: \(httpResponse.statusCode)")
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            #if DEBUG
            if networkDebugLogsEnabled {
                let bodyPreview = String(data: data.prefix(512), encoding: .utf8) ?? "<non-utf8>"
                AppLog.network.error("Decode failed: \(bodyPreview, privacy: .public)")
            }
            #endif
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Auth

    struct RegisterRequest: Encodable {
        let email: String
        let password: String
    }

    struct LoginRequest: Encodable {
        let email: String
        let password: String
    }

    struct AuthResponse: Decodable {
        let user: UserDTO
        let token: String
    }

    struct UserDTO: Decodable {
        let id: String
        let email: String
    }

    struct ErrorResponse: Decodable {
        let error: String
    }

    func register(email: String, password: String) async throws -> AuthResponse {
        let response: AuthResponse = try await request(
            endpoint: "/auth/register",
            method: "POST",
            body: RegisterRequest(email: email, password: password)
        )
        authToken = response.token
        return response
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        let response: AuthResponse = try await request(
            endpoint: "/auth/login",
            method: "POST",
            body: LoginRequest(email: email, password: password)
        )
        authToken = response.token
        return response
    }

    // MARK: - Feeds

    struct FeedDTO: Decodable {
        let id: String
        let title: String
        let feedUrl: String
        let siteUrl: String?
        let iconUrl: String?
        let description: String?
        let lastFetchedAt: Date?
    }

    struct FeedsResponse: Decodable {
        let feeds: [FeedDTO]
    }

    struct AddFeedRequest: Encodable {
        let url: String
        let folderId: String?
    }

    struct FeedResponse: Decodable {
        let feed: FeedDTO
    }

    func getFeeds() async throws -> [FeedDTO] {
        let response: FeedsResponse = try await request(endpoint: "/feeds")
        return response.feeds
    }

    func addFeed(url: String, folderId: String? = nil) async throws -> FeedDTO {
        let response: FeedResponse = try await request(
            endpoint: "/feeds",
            method: "POST",
            body: AddFeedRequest(url: url, folderId: folderId)
        )
        return response.feed
    }

    func deleteFeed(id: String) async throws {
        let _: EmptyResponse = try await request(
            endpoint: "/feeds/\(id)",
            method: "DELETE"
        )
    }

    func refreshFeed(id: String) async throws -> Int {
        struct RefreshResponse: Decodable {
            let newArticlesCount: Int
        }
        let response: RefreshResponse = try await request(
            endpoint: "/feeds/\(id)/refresh",
            method: "POST"
        )
        return response.newArticlesCount
    }

    // MARK: - Articles

    struct ArticleDTO: Decodable {
        let id: String
        let guid: String
        let title: String
        let content: String?
        let summary: String?
        let url: String?
        let author: String?
        let imageUrl: String?
        let publishedAt: Date?
        let isRead: Bool
        let isStarred: Bool
        let feed: FeedDTO?
    }

    struct ArticlesResponse: Decodable {
        let articles: [ArticleDTO]
    }

    func getArticles(limit: Int = 50, offset: Int = 0, unreadOnly: Bool = false) async throws -> [ArticleDTO] {
        var endpoint = "/articles?limit=\(limit)&offset=\(offset)"
        if unreadOnly {
            endpoint += "&unread=true"
        }
        let response: ArticlesResponse = try await request(endpoint: endpoint)
        return response.articles
    }

    func getStarredArticles(limit: Int = 50, offset: Int = 0) async throws -> [ArticleDTO] {
        let response: ArticlesResponse = try await request(
            endpoint: "/articles/starred?limit=\(limit)&offset=\(offset)"
        )
        return response.articles
    }

    func getFeedArticles(feedId: String, limit: Int = 50, offset: Int = 0) async throws -> [ArticleDTO] {
        let response: ArticlesResponse = try await request(
            endpoint: "/feeds/\(feedId)/articles?limit=\(limit)&offset=\(offset)"
        )
        return response.articles
    }

    struct UpdateArticleRequest: Encodable {
        let isRead: Bool?
        let isStarred: Bool?
    }

    struct EmptyResponse: Decodable {}

    func updateArticle(id: String, isRead: Bool? = nil, isStarred: Bool? = nil) async throws {
        let _: EmptyResponse = try await request(
            endpoint: "/articles/\(id)",
            method: "PATCH",
            body: UpdateArticleRequest(isRead: isRead, isStarred: isStarred)
        )
    }

    struct BatchUpdateRequest: Encodable {
        let articleIds: [String]
        let isRead: Bool?
        let isStarred: Bool?
    }

    func batchUpdateArticles(ids: [String], isRead: Bool? = nil, isStarred: Bool? = nil) async throws {
        let _: EmptyResponse = try await request(
            endpoint: "/articles/batch",
            method: "POST",
            body: BatchUpdateRequest(articleIds: ids, isRead: isRead, isStarred: isStarred)
        )
    }

    // MARK: - YouTube

    struct YouTubeChannelDTO: Decodable {
        let id: String
        let title: String
        let description: String
        let thumbnailUrl: String
        let subscriberCount: String
        let videoCount: String
        let customUrl: String?
    }

    struct YouTubeVideoDTO: Decodable, Identifiable {
        let id: String
        let title: String
        let description: String
        let thumbnailUrl: String
        let publishedAt: String
        let formattedDuration: String?
        let durationSeconds: Int?
        let viewCount: String?
        let channelId: String
        let channelTitle: String
    }

    struct YouTubeSearchResponse: Decodable {
        let channels: [YouTubeChannelDTO]
        let nextPageToken: String?
    }

    struct YouTubeChannelResponse: Decodable {
        let channel: YouTubeChannelDTO?
    }

    struct YouTubeVideosResponse: Decodable {
        let videos: [YouTubeVideoDTO]
        let nextPageToken: String?
    }

    struct ChannelVideosDTO: Decodable, Identifiable {
        let channel: YouTubeChannelDTO
        let videos: [YouTubeVideoDTO]

        var id: String { channel.id }
    }

    struct SubscriptionVideosResponse: Decodable {
        let channels: [ChannelVideosDTO]
    }

    struct YouTubeResolveRequest: Encodable {
        let url: String
    }

    func getYouTubeSubscriptionVideos(accessToken: String, perChannelLimit: Int = 50, maxChannels: Int? = nil) async throws -> [ChannelVideosDTO] {
        var path = "/youtube/subscriptions/videos?perChannelLimit=\(perChannelLimit)"
        if let maxChannels, maxChannels > 0 {
            path += "&maxChannels=\(maxChannels)"
        }

        let response: SubscriptionVideosResponse = try await requestWithToken(
            method: "GET",
            path: path,
            token: accessToken,
            baseURLOverride: youTubeStreamBaseURL
        )
        return response.channels
    }

    struct YouTubeResolveResponse: Decodable {
        let channelId: String
        let rssUrl: String
        let channel: YouTubeChannelDTO?
    }

    struct YouTubeStreamResponse: Decodable {
        let videoUrl: String?
        let audioUrl: String?
        let title: String
        let duration: Int
        let thumbnailUrl: String
    }

    struct YouTubeStreamHealthResponse: Decodable {
        let ok: Bool
        let status: String
        let message: String?
        let checkedAt: Date?
        let videoId: String?
    }

    func searchYouTubeChannels(query: String, limit: Int = 50) async throws -> [YouTubeChannelDTO] {
        let page = try await searchYouTubeChannelsPage(query: query, limit: limit, pageToken: nil)
        return page.channels
    }

    func searchYouTubeChannelsPage(
        query: String,
        limit: Int = 50,
        pageToken: String?
    ) async throws -> (channels: [YouTubeChannelDTO], nextPageToken: String?) {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query

        var endpoint = "/youtube/search?q=\(encodedQuery)&limit=\(limit)"
        if let pageToken, !pageToken.isEmpty {
            let encodedToken = pageToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pageToken
            endpoint += "&pageToken=\(encodedToken)"
        }

        let response: YouTubeSearchResponse = try await request(
            endpoint: endpoint,
            baseURLOverride: youTubeStreamBaseURL
        )
        return (response.channels, response.nextPageToken)
    }

    func getYouTubeChannel(id: String) async throws -> YouTubeChannelDTO? {
        let response: YouTubeChannelResponse = try await request(
            endpoint: "/youtube/channel/\(id)",
            baseURLOverride: youTubeStreamBaseURL
        )
        return response.channel
    }

    func getYouTubeChannelVideos(channelId: String, limit: Int = 20) async throws -> [YouTubeVideoDTO] {
        let page = try await getYouTubeChannelVideosPage(channelId: channelId, limit: limit, pageToken: nil)
        return page.videos
    }

    func getYouTubeChannelVideosPage(
        channelId: String,
        limit: Int = 50,
        pageToken: String?
    ) async throws -> (videos: [YouTubeVideoDTO], nextPageToken: String?) {
        var endpoint = "/youtube/channel/\(channelId)/videos?limit=\(limit)"
        if let pageToken, !pageToken.isEmpty {
            endpoint += "&pageToken=\(pageToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pageToken)"
        }

        let response: YouTubeVideosResponse = try await request(
            endpoint: endpoint,
            baseURLOverride: youTubeStreamBaseURL
        )
        return (response.videos, response.nextPageToken)
    }

    func resolveYouTubeUrl(url: String) async throws -> YouTubeResolveResponse {
        return try await request(
            endpoint: "/youtube/resolve",
            method: "POST",
            body: YouTubeResolveRequest(url: url),
            baseURLOverride: youTubeStreamBaseURL
        )
    }

    func getYouTubeChannelRssUrl(channelId: String) async throws -> String {
        struct RssResponse: Decodable {
            let rssUrl: String
        }
        let response: RssResponse = try await request(
            endpoint: "/youtube/channel/\(channelId)/rss",
            baseURLOverride: youTubeStreamBaseURL
        )
        return response.rssUrl
    }

    func getYouTubeStreamUrls(videoId: String, type: String = "both") async throws -> YouTubeStreamResponse {
        var extraHeaders: [String: String] = [:]
        let streamProxyToken = UserDefaults.standard.string(forKey: "streamProxyAccessToken") ?? ""
        if !streamProxyToken.isEmpty {
            extraHeaders["X-FeedFlow-Stream-Token"] = streamProxyToken
        }

        #if DEBUG
        if UserDefaults.standard.bool(forKey: "enableNetworkDebugLogs") {
            AppLog.player.debug(
                "YouTube stream request videoId=\(videoId, privacy: .public) type=\(type, privacy: .public)"
            )
        }
        #endif

        do {
            let response: YouTubeStreamResponse = try await request(
                endpoint: "/youtube/stream/\(videoId)?type=\(type)",
                headers: extraHeaders,
                baseURLOverride: youTubeStreamBaseURL
            )
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "enableNetworkDebugLogs") {
                AppLog.player.debug(
                    "YouTube stream response videoId=\(videoId, privacy: .public) videoUrl=\(response.videoUrl ?? "nil", privacy: .public) audioUrl=\(response.audioUrl ?? "nil", privacy: .public) duration=\(response.duration, privacy: .public)"
                )
            }
            #endif
            return response
        } catch {
            AppLog.player.error("YouTube stream error videoId=\(videoId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func getYouTubeStreamHealth(videoId: String? = nil) async throws -> YouTubeStreamHealthResponse {
        var extraHeaders: [String: String] = [:]
        let streamProxyToken = UserDefaults.standard.string(forKey: "streamProxyAccessToken") ?? ""
        if !streamProxyToken.isEmpty {
            extraHeaders["X-FeedFlow-Stream-Token"] = streamProxyToken
        }

        var endpoint = "/youtube/health"
        if let videoId, !videoId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let encoded = videoId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? videoId
            endpoint += "?videoId=\(encoded)"
        }

        return try await request(
            endpoint: endpoint,
            headers: extraHeaders,
            baseURLOverride: youTubeStreamBaseURL
        )
    }

    nonisolated func getYouTubeDownloadURL(videoId: String, type: String = "video") -> URL {
        return URL(string: "\(youTubeStreamBaseURL)/youtube/download/\(videoId)?type=\(type)")!
    }

    // MARK: - Generic Request Methods

    func request<T: Decodable>(
        method: String,
        path: String,
        body: [String: Any]? = nil,
        authenticated: Bool = true
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if authenticated, let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }

        if httpResponse.statusCode >= 400 {
            if let errorResponse = try? decoder.decode(ErrorResponse.self, from: data) {
                throw APIError.serverError(errorResponse.error)
            }
            throw APIError.serverError("Server error: \(httpResponse.statusCode)")
        }

        return try decoder.decode(T.self, from: data)
    }

    func requestWithToken<T: Decodable>(
        method: String,
        path: String,
        token: String,
        body: [String: Any]? = nil,
        baseURLOverride: String? = nil
    ) async throws -> T {
        let base = baseURLOverride ?? baseURL
        guard let url = URL(string: "\(base)\(path)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }

        if httpResponse.statusCode >= 400 {
            if let errorResponse = try? decoder.decode(ErrorResponse.self, from: data) {
                throw APIError.serverError(errorResponse.error)
            }
            throw APIError.serverError("Server error: \(httpResponse.statusCode)")
        }

        return try decoder.decode(T.self, from: data)
    }
}
