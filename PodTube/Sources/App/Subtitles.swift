import Foundation

struct Cue {
    let start: Double
    let end: Double
    let text: String
}

extension Notification.Name {
    static let subtitlesChanged = Notification.Name("PodTubeSubtitlesChanged")
}

/// Loads a YouTube caption track (timedtext json3) and answers "what is on screen at time t".
/// Used instead of HLS-embedded subtitles so captions also work for non-HLS playback.
final class SubtitleController {
    static let shared = SubtitleController()

    private(set) var tracks: [CaptionTrack] = []
    private(set) var current: CaptionTrack?
    private(set) var translateTo: String?
    private var cues: [Cue] = []
    private var generation = 0
    private(set) var isLoading = false

    var isEnabled: Bool { return current != nil }

    func setTracks(_ list: [CaptionTrack], videoId: String) {
        generation += 1
        tracks = list
        current = nil
        translateTo = nil
        cues = []
        isLoading = false
        NotificationCenter.default.post(name: .subtitlesChanged, object: nil)
        if Settings.captionsAlways, let t = preferredTrack(in: list) {
            select(t)
        }
    }

    func clear() {
        generation += 1
        tracks = []
        current = nil
        translateTo = nil
        cues = []
        isLoading = false
        NotificationCenter.default.post(name: .subtitlesChanged, object: nil)
    }

    private func preferredTrack(in list: [CaptionTrack]) -> CaptionTrack? {
        let lang = InnerTube.shared.language
        if let t = list.first(where: { $0.languageCode.hasPrefix(lang) && !$0.isAuto }) { return t }
        if let t = list.first(where: { $0.languageCode.hasPrefix(lang) }) { return t }
        if let t = list.first(where: { !$0.isAuto }) { return t }
        return list.first
    }

    func disable() {
        generation += 1
        current = nil
        translateTo = nil
        cues = []
        isLoading = false
        NotificationCenter.default.post(name: .subtitlesChanged, object: nil)
    }

    func select(_ track: CaptionTrack, translateTo lang: String? = nil) {
        generation += 1
        let gen = generation
        current = track
        translateTo = lang
        cues = []
        isLoading = true
        NotificationCenter.default.post(name: .subtitlesChanged, object: nil)

        var urlString = track.url
        if !urlString.contains("fmt=") { urlString += "&fmt=json3" }
        if let l = lang { urlString += "&tlang=" + l }
        guard let url = URL(string: urlString) else { return }
        Http.shared.get(url) { [weak self] result in
            var parsed: [Cue] = []
            if case .success(let data) = result { parsed = SubtitleController.parseJSON3(data) }
            DispatchQueue.main.async {
                guard let self = self, gen == self.generation else { return }
                self.cues = parsed
                self.isLoading = false
                NotificationCenter.default.post(name: .subtitlesChanged, object: nil)
            }
        }
    }

    func text(at time: Double) -> String? {
        if cues.isEmpty { return nil }
        // binary search for the last cue starting at or before `time`
        var lo = 0
        var hi = cues.count - 1
        var found = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if cues[mid].start <= time {
                found = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        if found < 0 { return nil }
        // Cues can overlap slightly; look back a couple of entries.
        var i = found
        while i >= 0 && i > found - 3 {
            let c = cues[i]
            if time >= c.start && time <= c.end { return c.text }
            i -= 1
        }
        return nil
    }

    static func parseJSON3(_ data: Data) -> [Cue] {
        let root = JSON.parse(data)
        var out: [Cue] = []
        for e in root["events"].array {
            let segs = e["segs"].array
            if segs.isEmpty { continue }
            var text = ""
            for s in segs { text += s["utf8"].stringValue }
            text = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            let start = (e["tStartMs"].double ?? 0) / 1000
            let dur = (e["dDurationMs"].double ?? 2000) / 1000
            out.append(Cue(start: start, end: start + dur, text: text))
        }
        out.sort { $0.start < $1.start }
        // Rolling (auto-generated) captions: trim an end that overlaps the next cue's start.
        if out.count > 1 {
            for i in 0..<(out.count - 1) where out[i].end > out[i + 1].start {
                out[i] = Cue(start: out[i].start, end: out[i + 1].start, text: out[i].text)
            }
        }
        return out
    }
}
