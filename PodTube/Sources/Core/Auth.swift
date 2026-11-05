import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Storage

/// Where the sign-in secrets live. The app uses the Keychain; the Linux test CLI uses a file.
protocol TokenStorage: AnyObject {
    func load() -> Data?
    func save(_ data: Data)
    func clear()
}

final class FileTokenStorage: TokenStorage {
    private let url: URL

    init(url: URL) { self.url = url }

    func load() -> Data? { return try? Data(contentsOf: url) }

    func save(_ data: Data) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        try? data.write(to: url, options: .atomic)
    }

    func clear() { try? FileManager.default.removeItem(at: url) }
}

// MARK: - Models

struct AuthTokens: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date

    var isFresh: Bool { return expiresAt.timeIntervalSinceNow > 90 }
}

struct AccountProfile: Codable, Equatable {
    var name: String
    var handle: String
    var avatar: String
}

private struct AuthRecord: Codable {
    var tokens: AuthTokens
    var profile: AccountProfile?
}

struct DeviceCode {
    var userCode: String
    var verificationURL: String
    var deviceCode: String
    var interval: TimeInterval
    var expiresAt: Date
}

enum AuthError: Error, LocalizedError {
    case notSignedIn
    case pending
    case slowDown
    case denied
    case expired
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Not signed in"
        case .pending: return "Waiting for approval"
        case .slowDown: return "Slow down"
        case .denied: return "Access denied"
        case .expired: return "Code expired"
        case .server(let s): return s
        }
    }
}

// MARK: - OAuth configuration (YouTube on TV, "limited input device" flow)

/// YouTube's own TV client credentials. They are public (every smart TV carries them) and the same ones
/// used by YouTube.js / SmartTube. Google only honours OAuth for the TVHTML5 InnerTube client.
enum OAuthConfig {
    static var clientId = "861556708454-d6dlm3lh05idd8npek18k6be8ba3oc68.apps.googleusercontent.com"
    static var clientSecret = "SboVhoG9s0rNafixCSGGKXAT"
    static let scope = "http://gdata.youtube.com https://www.googleapis.com/auth/youtube-paid-content"
    static let deviceURL = URL(string: "https://www.youtube.com/o/oauth2/device/code")!
    static let tokenURL = URL(string: "https://www.youtube.com/o/oauth2/token")!
    static let revokeURL = URL(string: "https://oauth2.googleapis.com/revoke")!
    static let tvUserAgent = "Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold (unlike Gecko), Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)"
}

// MARK: - Session

final class AuthSession {
    static let shared = AuthSession()

    var storage: TokenStorage? {
        didSet { loadFromStorage() }
    }

    /// Called (on an arbitrary queue) after sign-in, sign-out and profile updates.
    var onChange: (() -> Void)?

    private let lock = NSLock()
    private var record: AuthRecord?
    private var refreshing = false
    private var refreshWaiters: [(Result<String, Error>) -> Void] = []

    var isSignedIn: Bool {
        lock.lock()
        defer { lock.unlock() }
        return record != nil
    }

    var profile: AccountProfile? {
        lock.lock()
        defer { lock.unlock() }
        return record?.profile
    }

    private func loadFromStorage() {
        guard let data = storage?.load(), let r = try? JSONDecoder().decode(AuthRecord.self, from: data) else { return }
        lock.lock()
        record = r
        lock.unlock()
    }

    private func persist() {
        lock.lock()
        let r = record
        lock.unlock()
        if let r = r, let data = try? JSONEncoder().encode(r) { storage?.save(data) }
    }

    // MARK: Form helpers

    private func postJSON(_ url: URL, _ body: [String: Any], completion: @escaping (Int, JSON) -> Void) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(OAuthConfig.tvUserAgent, forHTTPHeaderField: "User-Agent")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        let task = Http.shared.session.dataTask(with: req) { data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            completion(code, JSON.parse(data ?? Data()))
        }
        task.resume()
    }

    // MARK: Device flow

    func requestDeviceCode(_ done: @escaping (Result<DeviceCode, Error>) -> Void) {
        let body: [String: Any] = [
            "client_id": OAuthConfig.clientId,
            "scope": OAuthConfig.scope,
            "device_id": UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
            "model_name": "ytlr::"
        ]
        postJSON(OAuthConfig.deviceURL, body) { code, json in
            guard code == 200, let user = json["user_code"].string, let dev = json["device_code"].string else {
                done(.failure(AuthError.server(json["error_description"].string ?? json["error"].string ?? "HTTP \(code)")))
                return
            }
            let c = DeviceCode(userCode: user,
                               verificationURL: json["verification_url"].string ?? "https://www.google.com/device",
                               deviceCode: dev,
                               interval: TimeInterval(json["interval"].int ?? 5),
                               expiresAt: Date().addingTimeInterval(TimeInterval(json["expires_in"].int ?? 1800)))
            done(.success(c))
        }
    }

    /// One poll of the token endpoint: `.success` when approved, `.failure(.pending / .slowDown / …)` otherwise.
    func pollToken(_ code: DeviceCode, _ done: @escaping (Result<AuthTokens, Error>) -> Void) {
        let body: [String: Any] = [
            "client_id": OAuthConfig.clientId,
            "client_secret": OAuthConfig.clientSecret,
            "code": code.deviceCode,
            "grant_type": "http://oauth.net/grant_type/device/1.0"
        ]
        postJSON(OAuthConfig.tokenURL, body) { [weak self] status, json in
            if let access = json["access_token"].string, let refresh = json["refresh_token"].string {
                let tokens = AuthTokens(accessToken: access, refreshToken: refresh,
                                        expiresAt: Date().addingTimeInterval(TimeInterval(json["expires_in"].int ?? 3600)))
                self?.lock.lock()
                self?.record = AuthRecord(tokens: tokens, profile: nil)
                self?.lock.unlock()
                self?.persist()
                self?.onChange?()
                done(.success(tokens))
                return
            }
            switch json["error"].stringValue {
            case "authorization_pending": done(.failure(AuthError.pending))
            case "slow_down": done(.failure(AuthError.slowDown))
            case "access_denied": done(.failure(AuthError.denied))
            case "expired_token": done(.failure(AuthError.expired))
            default: done(.failure(AuthError.server(json["error_description"].string ?? json["error"].string ?? "HTTP \(status)")))
            }
        }
    }

    // MARK: Access token

    /// A valid access token, refreshed first when it is about to expire.
    func validAccessToken(_ done: @escaping (Result<String, Error>) -> Void) {
        lock.lock()
        guard let r = record else {
            lock.unlock()
            done(.failure(AuthError.notSignedIn))
            return
        }
        if r.tokens.isFresh {
            let t = r.tokens.accessToken
            lock.unlock()
            done(.success(t))
            return
        }
        refreshWaiters.append(done)
        if refreshing {
            lock.unlock()
            return
        }
        refreshing = true
        let refresh = r.tokens.refreshToken
        lock.unlock()
        refreshAccessToken(refresh)
    }

    /// Forces the next `validAccessToken` to refresh (after a 401).
    func invalidateAccessToken() {
        lock.lock()
        if var r = record {
            r.tokens.expiresAt = Date(timeIntervalSince1970: 0)
            record = r
        }
        lock.unlock()
    }

    private func refreshAccessToken(_ refreshToken: String) {
        let body: [String: Any] = [
            "client_id": OAuthConfig.clientId,
            "client_secret": OAuthConfig.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        postJSON(OAuthConfig.tokenURL, body) { [weak self] status, json in
            guard let self = self else { return }
            var result: Result<String, Error>
            if let access = json["access_token"].string {
                self.lock.lock()
                if var r = self.record {
                    r.tokens.accessToken = access
                    r.tokens.expiresAt = Date().addingTimeInterval(TimeInterval(json["expires_in"].int ?? 3600))
                    self.record = r
                }
                self.lock.unlock()
                self.persist()
                result = .success(access)
            } else if json["error"].stringValue == "invalid_grant" {
                // the refresh token was revoked (e.g. from the Google account page): sign out locally
                self.clearLocal()
                result = .failure(AuthError.notSignedIn)
            } else {
                result = .failure(AuthError.server(json["error_description"].string ?? "HTTP \(status)"))
            }
            self.lock.lock()
            let waiters = self.refreshWaiters
            self.refreshWaiters = []
            self.refreshing = false
            self.lock.unlock()
            for w in waiters { w(result) }
        }
    }

    // MARK: Profile / sign-out

    /// Signs in with tokens obtained elsewhere (the Linux test CLI and the debug fake-account mode).
    func adopt(_ tokens: AuthTokens, profile: AccountProfile? = nil) {
        lock.lock()
        record = AuthRecord(tokens: tokens, profile: profile)
        lock.unlock()
        persist()
        onChange?()
    }

    func updateProfile(_ p: AccountProfile) {
        lock.lock()
        if var r = record {
            r.profile = p
            record = r
        }
        lock.unlock()
        persist()
        onChange?()
    }

    private func clearLocal() {
        lock.lock()
        record = nil
        lock.unlock()
        storage?.clear()
        onChange?()
    }

    func signOut() {
        lock.lock()
        let refresh = record?.tokens.refreshToken
        lock.unlock()
        clearLocal()
        if let token = refresh, var comps = URLComponents(url: OAuthConfig.revokeURL, resolvingAgainstBaseURL: false) {
            comps.queryItems = [URLQueryItem(name: "token", value: token)]
            if let url = comps.url {
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.timeoutInterval = 15
                Http.shared.session.dataTask(with: req) { _, _, _ in }.resume()
            }
        }
    }
}
