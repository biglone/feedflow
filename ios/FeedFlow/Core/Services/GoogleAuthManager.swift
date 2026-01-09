import Foundation
import AuthenticationServices

@MainActor
class GoogleAuthManager: NSObject, ObservableObject {
    static let shared = GoogleAuthManager()

    @Published var isAuthenticated = false
    @Published var accessToken: String?
    @Published var isLoading = false
    @Published var error: Error?

    private let apiClient = APIClient.shared
    private var webAuthSession: ASWebAuthenticationSession?

    // Keychain keys
    private let accessTokenKey = "google_access_token"
    private let refreshTokenKey = "google_refresh_token"

    private override init() {
        super.init()
        // Load stored token
        if let token = loadToken(key: accessTokenKey) {
            accessToken = token
            isAuthenticated = true
        }
    }

    // MARK: - OAuth Flow

    func startOAuthFlow() async throws {
        isLoading = true
        error = nil

        defer { isLoading = false }

        // Get OAuth URL from backend
        let response: OAuthURLResponse = try await apiClient.request(
            method: "GET",
            path: "/youtube/oauth/url",
            authenticated: false
        )

        guard let url = URL(string: response.url) else {
            throw GoogleAuthError.invalidURL
        }

        // Open OAuth URL in browser
        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            webAuthSession = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "feedflow"
            ) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let callbackURL = callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: GoogleAuthError.noCallback)
                }
            }

            webAuthSession?.presentationContextProvider = self
            webAuthSession?.prefersEphemeralWebBrowserSession = false
            webAuthSession?.start()
        }

        // Extract code from callback URL
        guard let code = extractCode(from: callbackURL) else {
            throw GoogleAuthError.noAuthorizationCode
        }

        // Exchange code for tokens
        try await exchangeCodeForTokens(code: code)
    }

    private func extractCode(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            return nil
        }
        return code
    }

    private func exchangeCodeForTokens(code: String) async throws {
        let body: [String: Any] = [
            "code": code,
            "redirectUri": "feedflow://oauth/google/callback"
        ]

        let response: TokenResponse = try await apiClient.request(
            method: "POST",
            path: "/youtube/oauth/token",
            body: body,
            authenticated: false
        )

        // Store tokens
        saveToken(response.accessToken, key: accessTokenKey)
        if let refreshToken = response.refreshToken {
            saveToken(refreshToken, key: refreshTokenKey)
        }

        accessToken = response.accessToken
        isAuthenticated = true
    }

    // MARK: - Token Management

    private func saveToken(_ token: String, key: String) {
        let data = token.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadToken(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }

        return token
    }

    func logout() {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: accessTokenKey
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let deleteRefreshQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: refreshTokenKey
        ]
        SecItemDelete(deleteRefreshQuery as CFDictionary)

        accessToken = nil
        isAuthenticated = false
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension GoogleAuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}

// MARK: - Response Types

struct OAuthURLResponse: Codable {
    let url: String
}

struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
}

// MARK: - Errors

enum GoogleAuthError: LocalizedError {
    case invalidURL
    case noCallback
    case noAuthorizationCode
    case tokenExchangeFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid OAuth URL"
        case .noCallback:
            return "No callback received from Google"
        case .noAuthorizationCode:
            return "No authorization code in callback"
        case .tokenExchangeFailed:
            return "Failed to exchange code for tokens"
        }
    }
}
