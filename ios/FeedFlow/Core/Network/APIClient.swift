import Foundation

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
    private var baseURL: String {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "useLocalAPI") {
            return "http://172.16.1.16:3000/api"
        }
        #endif
        return "https://feedflow-silk.vercel.app/api"
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
        body: Encodable? = nil
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            request.httpBody = try encoder.encode(body)
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

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
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

    struct YouTubeVideoDTO: Decodable {
        let id: String
        let title: String
        let description: String
        let thumbnailUrl: String
        let publishedAt: String
        let formattedDuration: String?
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

    struct YouTubeResolveRequest: Encodable {
        let url: String
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
        return try await request(
            endpoint: "/youtube/stream/\(videoId)?type=\(type)"
        )
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
