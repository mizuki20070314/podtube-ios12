import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Lets the client identity be fixed without shipping a new build: `config/clients.json` in the project
/// repository can override the version / user agent of each InnerTube client (strings only).
/// The file is fetched at launch and cached; the built-in defaults in `Clients` always work as a fallback.
enum ClientOverrides {
    private static let storeKey = "clientOverrides"
    static let url = URL(string: "https://raw.githubusercontent.com/mizuki20070314/podtube-ios12/main/config/clients.json")

    private static let lock = NSLock()
    private static var stored: [String: [String: String]] = load()

    static var values: [String: [String: String]] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    private static func load() -> [String: [String: String]] {
        guard let d = UserDefaults.standard.data(forKey: storeKey),
              let obj = try? JSONSerialization.jsonObject(with: d, options: []) as? [String: [String: String]] else { return [:] }
        return obj
    }

    static func refresh() {
        guard let url = url else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.cachePolicy = .reloadIgnoringLocalCacheData
        Http.shared.send(req) { result in
            guard case .success(let data) = result else { return }
            let json = JSON.parse(data)
            var parsed: [String: [String: String]] = [:]
            for client in json.keys {
                var entry: [String: String] = [:]
                for field in ["clientVersion", "userAgent", "osVersion", "signatureTimestamp"] {
                    if let s = json[client][field].string, !s.isEmpty { entry[field] = s }
                }
                if !entry.isEmpty { parsed[client] = entry }
            }
            lock.lock()
            stored = parsed
            lock.unlock()
            if let d = try? JSONSerialization.data(withJSONObject: parsed, options: []) {
                UserDefaults.standard.set(d, forKey: storeKey)
            }
        }
    }
}

extension ClientProfile {
    /// Applies the overrides stored for `id` ("visionos", "ios", "android_vr", "tv", "tv_samsung").
    func overridden(_ id: String) -> ClientProfile {
        guard let o = ClientOverrides.values[id] else { return self }
        var newExtra = extra
        if let v = o["osVersion"] { newExtra["osVersion"] = v }
        return ClientProfile(name: name, version: o["clientVersion"] ?? version, numericId: numericId,
                             userAgent: o["userAgent"] ?? userAgent, extra: newExtra)
    }
}
