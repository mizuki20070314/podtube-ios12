import Foundation

/// Tiny dynamic JSON wrapper. InnerTube responses are deeply nested and change shape often,
/// so everything is read leniently: a missing key simply yields an empty `JSON`.
struct JSON {
    let raw: Any?

    init(_ raw: Any?) { self.raw = raw }

    static func parse(_ data: Data) -> JSON {
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: [.allowFragments]) else {
            return JSON(nil)
        }
        return JSON(obj)
    }

    subscript(key: String) -> JSON {
        if let d = raw as? [String: Any] { return JSON(d[key]) }
        return JSON(nil)
    }

    subscript(index: Int) -> JSON {
        if let a = raw as? [Any], index >= 0, index < a.count { return JSON(a[index]) }
        return JSON(nil)
    }

    var exists: Bool {
        if raw == nil { return false }
        if raw is NSNull { return false }
        return true
    }

    var dict: [String: Any]? { return raw as? [String: Any] }
    var isArray: Bool { return raw is [Any] }
    var array: [JSON] {
        guard let a = raw as? [Any] else { return [] }
        return a.map { JSON($0) }
    }
    var keys: [String] {
        guard let d = raw as? [String: Any] else { return [] }
        return d.keys.sorted()
    }

    var string: String? { return raw as? String }
    var stringValue: String { return (raw as? String) ?? "" }

    var int: Int? {
        if let i = raw as? Int { return i }
        if let d = raw as? Double, d.isFinite, abs(d) < 9.0e18 { return Int(d) }
        if let s = raw as? String { return Int(s) }
        return nil
    }

    var double: Double? {
        if let d = raw as? Double { return d }
        if let i = raw as? Int { return Double(i) }
        if let s = raw as? String { return Double(s) }
        return nil
    }

    var bool: Bool? {
        if let b = raw as? Bool { return b }
        if let s = raw as? String { return s == "true" ? true : (s == "false" ? false : nil) }
        return nil
    }

    /// YouTube text objects: `{"simpleText": "..."}` or `{"runs": [{"text": "..."}, ...]}`.
    var text: String? {
        if let s = raw as? String { return s }
        if let s = self["simpleText"].string { return s }
        let runs = self["runs"].array
        if !runs.isEmpty {
            var out = ""
            for r in runs { out += r["text"].stringValue }
            return out
        }
        if let c = self["content"].string { return c }
        return nil
    }

    var textValue: String { return text ?? "" }

    /// Depth-first search for every value stored under `key` (dictionary keys visited in sorted
    /// order so the result is deterministic; arrays keep their order).
    func findAll(_ key: String, limit: Int = 100_000) -> [JSON] {
        var out: [JSON] = []
        func walk(_ o: Any?) {
            if out.count >= limit { return }
            if let d = o as? [String: Any] {
                if let v = d[key] { out.append(JSON(v)) }
                for k in d.keys.sorted() { walk(d[k]) }
            } else if let a = o as? [Any] {
                for v in a { walk(v) }
            }
        }
        walk(raw)
        return out
    }

    func findFirst(_ key: String) -> JSON? {
        var result: JSON?
        func walk(_ o: Any?) -> Bool {
            if let d = o as? [String: Any] {
                if let v = d[key] { result = JSON(v); return true }
                for k in d.keys.sorted() { if walk(d[k]) { return true } }
            } else if let a = o as? [Any] {
                for v in a { if walk(v) { return true } }
            }
            return false
        }
        _ = walk(raw)
        return result
    }
}
