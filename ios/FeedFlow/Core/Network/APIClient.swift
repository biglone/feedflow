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
            return "Please sign in to continue"
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

    private var authToken: String?
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    // Debug builds can switch between remote and local API endpoints via the Settings toggle.
    nonisolated private var baseURL: String {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "useLocalAPI") {
            return "http://172.16.1.16:3000/api"
        }
        #endif
        return "https://feedflow.biglone.tech/api"
    }

    nonisolated func currentBaseURL() -> String {
        baseURL
    }

    private init() {
        #if DEBUG
        UserDefaults.standard.register(defaults: ["useLocalAPI": false])
        #endif
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

    private func request<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: Encodable? = nil,
        headers extraHeaders: [String: String] = [:]
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
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
    }

    struct YouTubeChannelResponse: Decodable {
        let channel: YouTubeChannelDTO?
    }

    struct YouTubeVideosResponse: Decodable {
        let videos: [YouTubeVideoDTO]
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
            token: accessToken
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

    func searchYouTubeChannels(query: String, limit: Int = 10) async throws -> [YouTubeChannelDTO] {
        let response: YouTubeSearchResponse = try await request(
            endpoint: "/youtube/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)&limit=\(limit)"
        )
        return response.channels
    }

    func getYouTubeChannel(id: String) async throws -> YouTubeChannelDTO? {
        let response: YouTubeChannelResponse = try await request(
            endpoint: "/youtube/channel/\(id)"
        )
        return response.channel
    }

    func getYouTubeChannelVideos(channelId: String, limit: Int = 20) async throws -> [YouTubeVideoDTO] {
        let response: YouTubeVideosResponse = try await request(
            endpoint: "/youtube/channel/\(channelId)/videos?limit=\(limit)"
        )
        return response.videos
    }

    func resolveYouTubeUrl(url: String) async throws -> YouTubeResolveResponse {
        return try await request(
            endpoint: "/youtube/resolve",
            method: "POST",
            body: YouTubeResolveRequest(url: url)
        )
    }

    func getYouTubeChannelRssUrl(channelId: String) async throws -> String {
        struct RssResponse: Decodable {
            let rssUrl: String
        }
        let response: RssResponse = try await request(
            endpoint: "/youtube/channel/\(channelId)/rss"
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
                "YouTube stream request videoId=\(videoId, privacy: .public) type=\(type, privacy: .public) token=\(!streamProxyToken.isEmpty, privacy: .public)"
            )
        }
        #endif

        do {
            let response: YouTubeStreamResponse = try await request(
                endpoint: "/youtube/stream/\(videoId)?type=\(type)",
                headers: extraHeaders
            )
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "enableNetworkDebugLogs") {
                AppLog.player.debug(
                    "YouTube stream response videoId=\(videoId, privacy: .public) videoUrl=\(response.videoUrl != nil, privacy: .public) audioUrl=\(response.audioUrl != nil, privacy: .public) duration=\(response.duration, privacy: .public)"
                )
            }
            #endif
            return response
        } catch {
            AppLog.player.error("YouTube stream error videoId=\(videoId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    nonisolated func getYouTubeDownloadURL(videoId: String, type: String = "video") -> URL {
        return URL(string: "\(baseURL)/youtube/download/\(videoId)?type=\(type)")!
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
        body: [String: Any]? = nil
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
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
