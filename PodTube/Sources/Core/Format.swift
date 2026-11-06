import Foundation

enum Format {
    /// "1:02:03" / "3:51" -> seconds
    static func parseDuration(_ s: String) -> Int? {
        if s.isEmpty { return nil }
        let parts = s.split(separator: ":").map { Int($0) }
        if parts.isEmpty { return nil }
        var total = 0
        for p in parts {
            guard let n = p else { return nil }
            total = total * 60 + n
        }
        return total
    }

    static func duration(_ seconds: Double) -> String {
        if !seconds.isFinite || seconds < 0 { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    /// 2_500_000 -> "2.5 Mbps" / 128_000 -> "128 kbps"; unknown (zero or less) -> "-"
    static func bitrate(_ bitsPerSecond: Double) -> String {
        if !bitsPerSecond.isFinite || bitsPerSecond <= 0 { return "-" }
        if bitsPerSecond >= 1_000_000 { return String(format: "%.1f", bitsPerSecond / 1_000_000) + " Mbps" }
        return String(format: "%.0f", bitsPerSecond / 1_000) + " kbps"
    }

    /// 12_345_678 -> "11.8 MB" (1024 based); negative -> "-"
    static func bytes(_ n: Int64) -> String {
        if n < 0 { return "-" }
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(n)
        var i = 0
        while value >= 1024 && i < units.count - 1 {
            value /= 1024
            i += 1
        }
        if i == 0 { return "\(n) B" }
        return String(format: "%.1f", value) + " " + units[i]
    }

    /// Compact count: 1234 -> "1.2K" / "1,234" depending on locale language.
    static func count(_ n: Int, japanese: Bool) -> String {
        if japanese {
            if n >= 100_000_000 { return trimmed(Double(n) / 100_000_000) + "億" }
            if n >= 10_000 { return trimmed(Double(n) / 10_000) + "万" }
            return "\(n)"
        }
        if n >= 1_000_000_000 { return trimmed(Double(n) / 1_000_000_000) + "B" }
        if n >= 1_000_000 { return trimmed(Double(n) / 1_000_000) + "M" }
        if n >= 1_000 { return trimmed(Double(n) / 1_000) + "K" }
        return "\(n)"
    }

    private static func trimmed(_ d: Double) -> String {
        if d >= 100 { return String(format: "%.0f", d) }
        let s = String(format: "%.1f", d)
        if s.hasSuffix(".0") { return String(s.dropLast(2)) }
        return s
    }

    /// Rough "age in seconds" of YouTube relative strings ("3 日前", "2 weeks ago", ...)
    /// so locally merged feeds can be ordered. Unknown strings sort last (huge value).
    static func approximateAge(_ text: String) -> Double {
        let lower = text.lowercased()
        var digits = ""
        for ch in lower {
            if ch.isNumber, let _ = ch.wholeNumberValue { digits.append(ch) } else if !digits.isEmpty { break }
        }
        guard let n = Double(digits) else {
            if lower.contains("ストリーム") || lower.contains("streamed") { return 86400 * 3650 }
            return 86400 * 3650
        }
        let units: [(String, Double)] = [
            ("秒", 1), ("second", 1),
            ("分", 60), ("minute", 60),
            ("時間", 3600), ("hour", 3600),
            ("日", 86400), ("day", 86400),
            ("週", 7 * 86400), ("week", 7 * 86400),
            ("か月", 30 * 86400), ("ヶ月", 30 * 86400), ("ヵ月", 30 * 86400), ("month", 30 * 86400),
            ("年", 365 * 86400), ("year", 365 * 86400)
        ]
        for (key, mult) in units {
            if lower.contains(key) { return n * mult }
        }
        return 86400 * 3650
    }

    static func isJapanese() -> Bool {
        let lang = Locale.preferredLanguages.first ?? "en"
        return lang.hasPrefix("ja")
    }
}
