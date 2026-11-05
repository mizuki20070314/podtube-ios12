import Foundation

struct Chapter {
    let start: Double
    let title: String
}

enum Chapters {
    /// YouTube chapters are timestamps in the description ("0:00 Intro"). They count only when the list starts at 0:00,
    /// has at least two entries and is ascending.
    static func parse(_ description: String) -> [Chapter] {
        var out: [Chapter] = []
        for rawLine in description.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            guard let (secs, rest) = leadingTimestamp(line) else { continue }
            let title = rest.trimmingCharacters(in: CharacterSet(charactersIn: " -–—:|・.)(").union(.whitespaces))
            out.append(Chapter(start: secs, title: title.isEmpty ? Format.duration(secs) : title))
        }
        guard out.count >= 2, out[0].start == 0 else { return [] }
        for i in 1..<out.count where out[i].start <= out[i - 1].start { return [] }
        return out
    }

    /// "1:02:03 Title" / "[1:02] Title" / "01:02 - Title" -> (seconds, "Title")
    private static func leadingTimestamp(_ line: String) -> (Double, String)? {
        var s = Substring(line)
        if s.first == "[" || s.first == "(" { s = s.dropFirst() }
        var token = ""
        var idx = s.startIndex
        while idx < s.endIndex {
            let c = s[idx]
            if c.isNumber || c == ":" {
                token.append(c)
                idx = s.index(after: idx)
            } else {
                break
            }
        }
        guard token.contains(":"), let secs = Format.parseDuration(token), token.count <= 8 else { return nil }
        var rest = String(s[idx...])
        if rest.first == "]" || rest.first == ")" { rest = String(rest.dropFirst()) }
        return (Double(secs), rest)
    }

    static func current(_ list: [Chapter], at time: Double) -> Chapter? {
        var cur: Chapter?
        for c in list {
            if c.start <= time { cur = c } else { break }
        }
        return cur
    }
}
