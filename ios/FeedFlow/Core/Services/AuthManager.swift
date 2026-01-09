import Foundation
import Security

struct User: Codable {
    let id: String
    let email: String
}

@MainActor
class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published private(set) var isLoggedIn: Bool = false
    @Published private(set) var currentUser: User?
    @Published private(set) var isLoading: Bool = false
    @Published var error: AuthError?

    private let apiClient = APIClient.shared
    private let keychainService = "com.feedflow.auth"
    private let tokenKey = "authToken"
    private let userKey = "currentUser"

    private init() {
        Task {
            await restoreSession()
        }
    }

    // MARK: - Public Methods

    func login(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await apiClient.login(email: email, password: password)
            try saveToken(response.token)
            let user = User(id: response.user.id, email: response.user.email)
            try saveUser(user)
            currentUser = user
            isLoggedIn = true
        } catch let apiError as APIError {
            throw AuthError.apiError(apiError.errorDescription ?? "Login failed")
        } catch {
            throw AuthError.unknown(error.localizedDescription)
        }
    }

    func register(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await apiClient.register(email: email, password: password)
            try saveToken(response.token)
            let user = User(id: response.user.id, email: response.user.email)
            try saveUser(user)
            currentUser = user
            isLoggedIn = true
        } catch let apiError as APIError {
            throw AuthError.apiError(apiError.errorDescription ?? "Registration failed")
        } catch {
            throw AuthError.unknown(error.localizedDescription)
        }
    }

    func logout() {
        deleteToken()
        deleteUser()
        Task {
            await apiClient.setAuthToken(nil)
        }
        currentUser = nil
        isLoggedIn = false
    }

    func getToken() -> String? {
        return loadToken()
    }

    // MARK: - Session Restoration

    private func restoreSession() async {
        guard let token = loadToken() else { return }

        await apiClient.setAuthToken(token)

        if let user = loadUser() {
            currentUser = user
            isLoggedIn = true
        }
    }

    // MARK: - Keychain Operations

    private func saveToken(_ token: String) throws {
        let data = Data(token.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenKey,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AuthError.keychainError("Failed to save token")
        }

        Task {
            await apiClient.setAuthToken(token)
        }
    }

    private func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
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

    private func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenKey
        ]

        SecItemDelete(query as CFDictionary)
    }

    // MARK: - User Storage (UserDefaults for non-sensitive data)

    private func saveUser(_ user: User) throws {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(user) {
            UserDefaults.standard.set(data, forKey: userKey)
        }
    }

    private func loadUser() -> User? {
        guard let data = UserDefaults.standard.data(forKey: userKey) else {
            return nil
        }

        let decoder = JSONDecoder()
        return try? decoder.decode(User.self, from: data)
    }

    private func deleteUser() {
        UserDefaults.standard.removeObject(forKey: userKey)
    }
}

// MARK: - Auth Error

enum AuthError: LocalizedError {
    case apiError(String)
    case keychainError(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .apiError(let message):
            return message
        case .keychainError(let message):
            return message
        case .unknown(let message):
            return message
        }
    }
}
