import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The statistics URLs of a player response made under the signed-in account (`playbackTracking`). Pinging the
/// playback URL is what makes YouTube put the video into the account's watch history; the watch-time URL tells it how
/// much was watched.
struct PlaybackTracking {
    var playbackURL: URL
    var watchtimeURL: URL?
}

extension Parse {
    /// nil unless the response is playable and carries a playback URL.
    static func playbackTracking(_ root: JSON) -> PlaybackTracking? {
        guard root["playabilityStatus"]["status"].string == "OK",
              let play = root["playbackTracking"]["videostatsPlaybackUrl"]["baseUrl"].string,
              let playURL = URL(string: play) else { return nil }
        let watch = root["playbackTracking"]["videostatsWatchtimeUrl"]["baseUrl"].string.flatMap { URL(string: $0) }
        return PlaybackTracking(playbackURL: playURL, watchtimeURL: watch)
    }
}

/// The `signatureTimestamp` a signed-in `player` request has to carry. YouTube accepts the values of the last few months
/// (20600 was still answered when 20760 was current, 20514 was refused), so the built-in one lasts a while. When a
/// request is refused the current value is read from the watch page ("STS") and kept; `config/clients.json` can also
/// carry one (`tv_samsung.signatureTimestamp`). The largest of them wins: the value only ever grows.
enum SignatureTimestamp {
    static let builtIn = 20760

    private static let valueKey = "signatureTimestamp"
    private static let timeKey = "signatureTimestampTime"

    static var current: Int {
        let stored = UserDefaults.standard.integer(forKey: valueKey)
        let configured = ClientOverrides.values["tv_samsung"]?["signatureTimestamp"].flatMap { Int($0) } ?? 0
        return max(stored, configured, builtIn)
    }

    /// Reads the current value from the watch page (about 1.3 MB, so only after a refusal, and at most every 6 hours).
    static func refresh(_ done: @escaping (Int?) -> Void) {
        let defaults = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        if now - defaults.double(forKey: timeKey) < 6 * 3600 {
            done(nil)
            return
        }
        defaults.set(now, forKey: timeKey)
        guard let url = URL(string: "https://www.youtube.com/watch?v=jNQXAC9IVRw") else {
            done(nil)
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        req.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                     forHTTPHeaderField: "User-Agent")
        Http.shared.send(req) { result in
            guard case .success(let data) = result, let value = parse(data) else {
                done(nil)
                return
            }
            UserDefaults.standard.set(value, forKey: valueKey)
            done(value)
        }
    }

    /// `"STS":20760` in the page's ytcfg (five digits, like today's values).
    static func parse(_ data: Data) -> Int? {
        guard let marker = "\"STS\":".data(using: .utf8), let found = data.range(of: marker) else { return nil }
        var digits = ""
        var i = found.upperBound
        while i < data.endIndex, digits.count < 7 {
            let c = data[i]
            guard c >= 48 && c <= 57 else { break }
            digits.append(Character(UnicodeScalar(c)))
            i = data.index(after: i)
        }
        return digits.count == 5 ? Int(digits) : nil
    }
}

/// Recording what is played in the signed-in account's watch history. Google only accepts the account's bearer token for
/// the TV client, and the `player` request of the generic TV identity is refused ("ページを再読み込みする必要があります");
/// a Samsung (Tizen) TV identity is answered, and its response carries statistics URLs bound to the account (they have a
/// `uga` parameter, the anonymous ones of the VISIONOS client do not, and pinging those never reached the history).
extension InnerTube {

    /// Account-bound statistics URLs of `videoId`.
    func accountPlaybackTracking(videoId: String, _ done: @escaping Done<PlaybackTracking>) {
        requestTracking(videoId: videoId, retry: true, done)
    }

    private func requestTracking(videoId: String, retry: Bool, _ done: @escaping Done<PlaybackTracking>) {
        let body: [String: Any] = [
            "videoId": videoId,
            "contentCheckOk": true,
            "racyCheckOk": true,
            "playbackContext": ["contentPlaybackContext": [
                "html5Preference": "HTML5_PREF_WANTS",
                "signatureTimestamp": SignatureTimestamp.current
            ]]
        ]
        postAuthed("player", body: body, profile: Clients.tvSamsung) { [weak self] result in
            switch result {
            case .failure(let e):
                done(.failure(e))
            case .success(let json):
                if let tracking = Parse.playbackTracking(json) {
                    done(.success(tracking))
                    return
                }
                // refused, typically because the signatureTimestamp is stale: read the current one once and ask again
                guard retry, let self = self else {
                    done(.failure(InnerTubeError.parse(json["playabilityStatus"]["status"].string ?? "no playback tracking")))
                    return
                }
                SignatureTimestamp.refresh { fresh in
                    if fresh == nil {
                        done(.failure(InnerTubeError.parse(json["playabilityStatus"]["status"].string ?? "no playback tracking")))
                    } else {
                        self.requestTracking(videoId: videoId, retry: false, done)
                    }
                }
            }
        }
    }

    /// Tells YouTube that the video is being played (`position` in seconds): this puts it into the watch history.
    func reportPlayed(_ t: PlaybackTracking, cpn: String, position: Double, _ done: ((Bool) -> Void)? = nil) {
        sendStats(t.playbackURL, cpn: cpn, extra: ["cmt=" + InnerTube.seconds(position)], done)
    }

    /// Reports the part of the video that was watched, `from` to `to` in seconds.
    func reportWatched(_ t: PlaybackTracking, cpn: String, from: Double, to: Double, _ done: ((Bool) -> Void)? = nil) {
        guard let url = t.watchtimeURL else {
            done?(false)
            return
        }
        sendStats(url, cpn: cpn, extra: ["cmt=" + InnerTube.seconds(to), "st=" + InnerTube.seconds(from), "et=" + InnerTube.seconds(to)], done)
    }

    static func seconds(_ value: Double) -> String {
        return String(format: "%.3f", max(0, value.isFinite ? value : 0))
    }

    /// A GET to a statistics URL with the account's bearer token. The query is edited as text: the values of `ei` / `vm`
    /// contain characters (`+`, `/`, `=`) that `URLComponents` would not write back the way they were read.
    private func sendStats(_ url: URL, cpn: String, extra: [String], _ done: ((Bool) -> Void)?) {
        guard AccountDemo.responder == nil, var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            done?(false)
            return
        }
        let replaced: Set<String> = ["ver", "cpn", "cmt", "el", "st", "et"]
        var parts = (comps.percentEncodedQuery ?? "").split(separator: "&", omittingEmptySubsequences: true).map(String.init).filter { part in
            let name = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? part
            return !replaced.contains(name)
        }
        parts.append(contentsOf: ["ver=2", "cpn=" + cpn, "el=leanback"])
        parts.append(contentsOf: extra)
        comps.percentEncodedQuery = parts.joined(separator: "&")
        guard let target = comps.url else {
            done?(false)
            return
        }
        AuthSession.shared.validAccessToken { result in
            guard case .success(let token) = result else {
                done?(false)
                return
            }
            var req = URLRequest(url: target)
            req.timeoutInterval = 15
            req.setValue(Clients.tv.userAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            Http.shared.send(req) { r in
                if case .success = r { done?(true) } else { done?(false) }
            }
        }
    }

    /// A client playback nonce: 16 characters of the URL-safe base64 alphabet.
    static func newCpn() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        var cpn = ""
        for _ in 0..<16 { cpn.append(alphabet.randomElement() ?? "a") }
        return cpn
    }
}

/// Reports what is played in the app to YouTube, one play at a time: the playback ping when the video starts, and the
/// watch-time ping when it ends (or is replaced by another one). Best effort: after three refusals in a row (answers of
/// YouTube that are not OK; a play without network, e.g. of a download, does not count) it stops for ten minutes, and
/// the history screens still show the plays of this app from the device's own history (HistoryMerge).
/// Safe to call from any thread.
final class PlayHistoryReporter {
    static let shared = PlayHistoryReporter()

    /// Plays shorter than this are not reported as watched.
    static let minWatchSeconds = 5.0
    static let maxFailures = 3
    static let retryAfter: TimeInterval = 600

    private final class Session {
        let videoId: String
        let cpn = InnerTube.newCpn()
        let startPosition: Double
        let reportsWatchTime: Bool
        var tracking: PlaybackTracking?
        var endPosition: Double?

        init(videoId: String, startPosition: Double, reportsWatchTime: Bool) {
            self.videoId = videoId
            self.startPosition = startPosition
            self.reportsWatchTime = reportsWatchTime
        }
    }

    private let queue = DispatchQueue(label: "podtube.playhistory")
    private var current: Session?
    private var failures = 0
    private var lastFailure = Date.distantPast

    /// A video started playing at `position` seconds (`reportsWatchTime` false for live streams).
    func started(videoId: String, position: Double, reportsWatchTime: Bool = true) {
        queue.async {
            guard AuthSession.shared.isSignedIn, AccountDemo.responder == nil else { return }
            if self.failures >= PlayHistoryReporter.maxFailures {
                guard Date().timeIntervalSince(self.lastFailure) >= PlayHistoryReporter.retryAfter else { return }
                self.failures = 0
            }
            if let c = self.current, c.videoId == videoId, c.endPosition == nil { return } // this play is already reported
            let session = Session(videoId: videoId, startPosition: max(0, position.isFinite ? position : 0), reportsWatchTime: reportsWatchTime)
            self.current = session
            InnerTube.shared.accountPlaybackTracking(videoId: videoId) { result in
                self.queue.async {
                    switch result {
                    case .failure(let e):
                        if PlayHistoryReporter.isRefusal(e) {
                            self.failures += 1
                            self.lastFailure = Date()
                        }
                    case .success(let tracking):
                        self.failures = 0
                        session.tracking = tracking
                        InnerTube.shared.reportPlayed(tracking, cpn: session.cpn, position: session.startPosition)
                        if session.endPosition != nil { self.sendWatched(session) } // the play ended before the answer came
                    }
                }
            }
        }
    }

    /// The video that is being reported ended, was replaced by another one, or the player stopped, at `position` seconds.
    func finished(position: Double) {
        queue.async {
            guard let session = self.current, session.endPosition == nil else { return }
            session.endPosition = max(0, position.isFinite ? position : 0)
            self.current = nil
            if session.tracking != nil { self.sendWatched(session) }
        }
    }

    /// Forgets earlier failures (after signing in again).
    func reset() {
        queue.async { self.failures = 0 }
    }

    /// An answer of YouTube that is a refusal (an HTTP error status or a response that is not OK), as opposed to no network.
    private static func isRefusal(_ error: Error) -> Bool {
        if error is InnerTubeError { return true }
        if let http = error as? HttpError, case .badStatus = http { return true }
        return false
    }

    private func sendWatched(_ session: Session) {
        guard session.reportsWatchTime, let tracking = session.tracking, let end = session.endPosition,
              end - session.startPosition >= PlayHistoryReporter.minWatchSeconds else { return }
        InnerTube.shared.reportWatched(tracking, cpn: session.cpn, from: session.startPosition, to: end)
    }
}
