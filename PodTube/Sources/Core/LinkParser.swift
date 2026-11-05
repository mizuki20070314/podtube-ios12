import Foundation

/// What a pasted / opened YouTube link points at.
enum LinkTarget: Equatable {
    case video(id: String, playlist: String?)
    case playlist(String)
    case channel(String)
    /// Vanity URLs (@handle, /user/…) have to be resolved through the API first.
    case resolve(String)
}

enum LinkParser {
    static func isVideoId(_ s: String) -> Bool {
        if s.count != 11 { return false }
        for ch in s.unicodeScalars {
            let ok = (ch.value >= 48 && ch.value <= 57) || (ch.value >= 65 && ch.value <= 90)
                || (ch.value >= 97 && ch.value <= 122) || ch == "_" || ch == "-"
            if !ok { return false }
        }
        return true
    }

    /// `podtube://watch?v=ID`, `podtube://https%3A%2F%2Fyoutu.be%2FID` (bookmarklet style) and normal https links.
    static func parse(_ text: String) -> LinkTarget? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t.contains(" ") || t.contains("\n") { return nil }

        if t.lowercased().hasPrefix("podtube://") {
            let rest = String(t.dropFirst("podtube://".count))
            let decoded = rest.removingPercentEncoding ?? rest
            if decoded.lowercased().hasPrefix("http") || decoded.lowercased().contains("youtu") { return parse(decoded) }
            if let comps = URLComponents(string: "https://youtube.com/" + decoded) {
                // podtube://watch?v=ID  /  podtube://playlist?list=ID  /  podtube://channel/UC…
                return parse(comps.url?.absoluteString ?? "")
            }
            return nil
        }

        var s = t
        if !s.contains("://") { s = "https://" + s }
        guard let comps = URLComponents(string: s), let rawHost = comps.host?.lowercased() else { return nil }
        var host = rawHost
        for prefix in ["www.", "m.", "music."] where host.hasPrefix(prefix) { host = String(host.dropFirst(prefix.count)) }

        var query: [String: String] = [:]
        for item in comps.queryItems ?? [] where query[item.name] == nil { query[item.name] = item.value ?? "" }
        let parts = comps.path.split(separator: "/").map { String($0) }

        if host == "youtu.be" {
            if let id = parts.first, isVideoId(id) { return .video(id: id, playlist: query["list"]) }
            return nil
        }
        guard host == "youtube.com" || host == "youtube-nocookie.com" else { return nil }
        guard let first = parts.first else { return nil }

        switch first {
        case "watch":
            if let v = query["v"], isVideoId(v) { return .video(id: v, playlist: query["list"]) }
            return nil
        case "shorts", "live", "embed", "v", "e":
            if parts.count > 1, isVideoId(parts[1]) { return .video(id: parts[1], playlist: nil) }
            return nil
        case "playlist":
            if let l = query["list"], !l.isEmpty { return .playlist(l) }
            return nil
        case "channel":
            if parts.count > 1, parts[1].hasPrefix("UC") { return .channel(parts[1]) }
            return nil
        case "user", "c":
            return .resolve("https://www.youtube.com" + comps.path)
        default:
            if first.hasPrefix("@") { return .resolve("https://www.youtube.com/" + first) }
            return nil
        }
    }
}
