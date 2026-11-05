import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Identity the app presents to YouTube's InnerTube API.
///
/// VISIONOS is used for everything: as of late 2026 it is the only client that returns a
/// complete logged-out home feed, classic (mobile app) renderers, and HLS / adaptive stream
/// URLs without a PO token or the JS player (see README "How playback works").
struct ClientProfile {
    let name: String
    let version: String
    let numericId: Int
    let userAgent: String
    let extra: [String: Any]
}

enum Clients {
    static var visionOS: ClientProfile { return visionOSBase.overridden("visionos") }
    static var androidVR: ClientProfile { return androidVRBase.overridden("android_vr") }
    static var ios: ClientProfile { return iosBase.overridden("ios") }
    /// The only client Google accepts OAuth bearer tokens for (everything account related goes through it).
    static var tv: ClientProfile { return tvBase.overridden("tv") }

    private static let tvBase = ClientProfile(
        name: "TVHTML5",
        version: "7.20260707.07.00",
        numericId: 7,
        userAgent: OAuthConfig.tvUserAgent,
        extra: [:])

    private static let visionOSBase = ClientProfile(
        name: "VISIONOS",
        version: "1.02",
        numericId: 101,
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
        extra: [
            "deviceMake": "Apple",
            "deviceModel": "RealityDevice17,1",
            "osName": "visionOS",
            "osVersion": "26.5.23O471"
        ])

    private static let androidVRBase = ClientProfile(
        name: "ANDROID_VR",
        version: "1.65.10",
        numericId: 28,
        userAgent: "com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip",
        extra: [
            "deviceMake": "Oculus",
            "deviceModel": "Quest 3",
            "androidSdkVersion": 32,
            "osName": "Android",
            "osVersion": "12L"
        ])

    private static let iosBase = ClientProfile(
        name: "IOS",
        version: "21.26.4",
        numericId: 5,
        userAgent: "com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)",
        extra: [
            "deviceMake": "Apple",
            "deviceModel": "iPhone16,2",
            "osName": "iPhone",
            "osVersion": "18.3.2.22D82"
        ])
}

final class InnerTube {
    static let shared = InnerTube()

    /// UI language / region sent as `hl` / `gl`.
    var language: String = "ja"
    var region: String = "JP"

    private let lock = NSLock()
    private var storedVisitor: String?
    private var visitorLoading = false
    private var visitorWaiters: [() -> Void] = []

    var visitorData: String? {
        lock.lock()
        defer { lock.unlock() }
        return storedVisitor
    }

    init() {
        let d = UserDefaults.standard
        let stamp = d.double(forKey: "visitorDataTime")
        let age = Date().timeIntervalSince1970 - stamp
        if let v = d.string(forKey: "visitorData"), stamp > 0, age < 14 * 86400 {
            storedVisitor = v
        }
    }

    // MARK: Visitor data
    //
    // Requests that carry no `visitorData` are frequently answered with LOGIN_REQUIRED
    // ("confirm you're not a bot"). A visitor id is cheap to get, so every request waits for one.

    func ensureVisitor(_ done: @escaping () -> Void) {
        lock.lock()
        if storedVisitor != nil {
            lock.unlock()
            done()
            return
        }
        visitorWaiters.append(done)
        if visitorLoading {
            lock.unlock()
            return
        }
        visitorLoading = true
        lock.unlock()
        fetchVisitor()
    }

    /// Drops the current visitor id and gets a fresh one (used after a bot check).
    func refreshVisitor(_ done: @escaping () -> Void) {
        lock.lock()
        storedVisitor = nil
        lock.unlock()
        ensureVisitor(done)
    }

    private func fetchVisitor() {
        guard let req = makeRequest(endpoint: "visitor_id", body: [:], profile: Clients.visionOS, useVisitor: false) else {
            finishVisitor(nil)
            return
        }
        Http.shared.send(req) { [weak self] r in
            var vd: String?
            if case .success(let data) = r {
                vd = JSON.parse(data)["responseContext"]["visitorData"].string
            }
            self?.finishVisitor(vd)
        }
    }

    private func finishVisitor(_ vd: String?) {
        lock.lock()
        if let vd = vd {
            storedVisitor = vd
            let d = UserDefaults.standard
            d.set(vd, forKey: "visitorData")
            d.set(Date().timeIntervalSince1970, forKey: "visitorDataTime")
        }
        visitorLoading = false
        let waiters = visitorWaiters
        visitorWaiters = []
        lock.unlock()
        for w in waiters { w() }
    }

    // MARK: Requests

    private func makeRequest(endpoint: String, body: [String: Any], profile: ClientProfile, useVisitor: Bool = true,
                             extraHeaders: [String: String] = [:]) -> URLRequest? {
        guard let url = URL(string: "https://www.youtube.com/youtubei/v1/\(endpoint)?prettyPrint=false") else { return nil }
        var client: [String: Any] = [
            "clientName": profile.name,
            "clientVersion": profile.version,
            "userAgent": profile.userAgent,
            "hl": language,
            "gl": region
        ]
        for (k, v) in profile.extra { client[k] = v }
        let visitor = useVisitor ? visitorData : nil
        if let v = visitor { client["visitorData"] = v }

        var payload: [String: Any] = ["context": ["client": client]]
        for (k, v) in body { payload[k] = v }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = data
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(profile.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(String(profile.numericId), forHTTPHeaderField: "X-YouTube-Client-Name")
        req.setValue(profile.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        req.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        req.setValue(language, forHTTPHeaderField: "Accept-Language")
        req.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        if let v = visitor { req.setValue(v, forHTTPHeaderField: "X-Goog-Visitor-Id") }
        for (k, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: k) }
        return req
    }

    /// POST to an InnerTube endpoint. The completion is called on a background queue.
    func post(_ endpoint: String,
              body: [String: Any],
              profile: ClientProfile = Clients.visionOS,
              extraHeaders: [String: String] = [:],
              completion: @escaping (Result<JSON, Error>) -> Void) {
        ensureVisitor { [weak self] in
            guard let self = self, let req = self.makeRequest(endpoint: endpoint, body: body, profile: profile,
                                                              extraHeaders: extraHeaders) else {
                completion(.failure(InnerTubeError.parse("bad request")))
                return
            }
            Http.shared.send(req) { result in
                switch result {
                case .failure(let err):
                    if case HttpError.badStatus(let code, let data) = err {
                        if let data = data, let msg = JSON.parse(data)["error"]["message"].string {
                            completion(.failure(InnerTubeError.api(code, msg)))
                        } else {
                            completion(.failure(InnerTubeError.http(code)))
                        }
                    } else {
                        completion(.failure(err))
                    }
                case .success(let data):
                    let json = JSON.parse(data)
                    if !json.exists {
                        completion(.failure(InnerTubeError.parse("invalid JSON")))
                        return
                    }
                    if let msg = json["error"]["message"].string {
                        completion(.failure(InnerTubeError.parse(msg)))
                        return
                    }
                    completion(.success(json))
                }
            }
        }
    }
}
