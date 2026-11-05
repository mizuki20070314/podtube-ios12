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
    static let visionOS = ClientProfile(
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

    static let androidVR = ClientProfile(
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

    static let ios = ClientProfile(
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

    var visitorData: String? {
        get { lock.lock(); defer { lock.unlock() }; return storedVisitor }
        set { lock.lock(); storedVisitor = newValue; lock.unlock() }
    }

    init() {
        let d = UserDefaults.standard
        storedVisitor = d.string(forKey: "visitorData")
    }

    private func makeRequest(endpoint: String, body: [String: Any], profile: ClientProfile) -> URLRequest? {
        guard let url = URL(string: "https://www.youtube.com/youtubei/v1/\(endpoint)?prettyPrint=false") else { return nil }
        var client: [String: Any] = [
            "clientName": profile.name,
            "clientVersion": profile.version,
            "userAgent": profile.userAgent,
            "hl": language,
            "gl": region
        ]
        for (k, v) in profile.extra { client[k] = v }
        let visitor = visitorData
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
        return req
    }

    /// POST to an InnerTube endpoint. The completion is called on a background queue.
    func post(_ endpoint: String,
              body: [String: Any],
              profile: ClientProfile = Clients.visionOS,
              completion: @escaping (Result<JSON, Error>) -> Void) {
        guard let req = makeRequest(endpoint: endpoint, body: body, profile: profile) else {
            completion(.failure(InnerTubeError.parse("bad request")))
            return
        }
        Http.shared.send(req) { [weak self] result in
            switch result {
            case .failure(let err):
                if case HttpError.badStatus(let code) = err {
                    completion(.failure(InnerTubeError.http(code)))
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
                if let vd = json["responseContext"]["visitorData"].string, let me = self, me.visitorData == nil {
                    me.visitorData = vd
                    UserDefaults.standard.set(vd, forKey: "visitorData")
                }
                completion(.success(json))
            }
        }
    }
}
