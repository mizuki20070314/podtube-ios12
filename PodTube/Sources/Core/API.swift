import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

typealias Done<T> = (Result<T, Error>) -> Void

/// Typed endpoints on top of `InnerTube.post`. Every completion is called on a background queue.
extension InnerTube {

    // MARK: Feeds

    func home(_ done: @escaping Done<FeedPage>) {
        post("browse", body: ["browseId": "FEwhat_to_watch"]) { r in
            done(r.map { Parse.feed($0) })
        }
    }

    func search(_ query: String, filter: SearchFilter? = nil, _ done: @escaping Done<FeedPage>) {
        var body: [String: Any] = ["query": query]
        if let p = filter?.params { body["params"] = p }
        post("search", body: body) { r in
            done(r.map { Parse.feed($0) })
        }
    }

    /// Next page of any list. `endpoint` is the endpoint that produced the token ("browse", "search", "next").
    func continuation(_ token: String, endpoint: String, _ done: @escaping Done<FeedPage>) {
        post(endpoint, body: ["continuation": token]) { r in
            done(r.map { Parse.feed($0) })
        }
    }

    func suggestions(_ query: String, _ done: @escaping ([String]) -> Void) {
        var comps = URLComponents(string: "https://suggestqueries.google.com/complete/search")
        comps?.queryItems = [
            URLQueryItem(name: "client", value: "firefox"),
            URLQueryItem(name: "ds", value: "yt"),
            URLQueryItem(name: "hl", value: language),
            URLQueryItem(name: "q", value: query)
        ]
        guard let url = comps?.url else { done([]); return }
        Http.shared.get(url) { r in
            guard case .success(let data) = r,
                  let obj = try? JSONSerialization.jsonObject(with: data, options: []),
                  let arr = obj as? [Any], arr.count > 1,
                  let list = arr[1] as? [String] else {
                done([])
                return
            }
            done(list)
        }
    }

    // MARK: Watch page

    func watch(videoId: String, playlistId: String? = nil, _ done: @escaping Done<WatchInfo>) {
        var body: [String: Any] = ["videoId": videoId]
        if let p = playlistId, !p.isEmpty { body["playlistId"] = p }
        post("next", body: body) { r in
            done(r.map { Parse.watch($0, videoId: videoId) })
        }
    }

    func comments(token: String, _ done: @escaping Done<CommentPage>) {
        post("next", body: ["continuation": token]) { r in
            done(r.map { Parse.comments($0) })
        }
    }

    // MARK: Channel / playlist

    func channel(id: String, _ done: @escaping Done<ChannelInfo>) {
        post("browse", body: ["browseId": id]) { r in
            done(r.map { Parse.channelInfo($0, id: id) })
        }
    }

    func channelTab(id: String, params: String, _ done: @escaping Done<FeedPage>) {
        post("browse", body: ["browseId": id, "params": params]) { r in
            done(r.map { json -> FeedPage in
                var page = Parse.feed(json["contents"])
                if page.items.isEmpty, let about = Parse.aboutText(json) { page.items = [.text(about)] }
                return page
            })
        }
    }

    /// Resolves vanity URLs (@handle, /user/…) to a channel id.
    func resolveChannel(url: String, _ done: @escaping Done<String>) {
        post("navigation/resolve_url", body: ["url": url]) { r in
            switch r {
            case .success(let json):
                let id = json["endpoint"]["browseEndpoint"]["browseId"].stringValue
                if id.isEmpty { done(.failure(InnerTubeError.empty)) } else { done(.success(id)) }
            case .failure(let e):
                done(.failure(e))
            }
        }
    }

    /// Name / avatar / subscriber text of a channel, fetched cheaply through its Videos tab.
    func channelBasics(id: String, _ done: @escaping Done<ChannelInfo>) {
        post("browse", body: ["browseId": id, "params": "EgZ2aWRlb3PyBgQKAjoA"]) { r in
            done(r.map { Parse.channelInfo($0, id: id) })
        }
    }

    func playlist(id: String, _ done: @escaping Done<PlaylistInfo>) {
        post("browse", body: ["browseId": "VL" + id]) { r in
            done(r.map { Parse.playlistInfo($0, id: id) })
        }
    }

    // MARK: Playback

    private func playerBody(_ videoId: String) -> [String: Any] {
        return [
            "videoId": videoId,
            "contentCheckOk": true,
            "racyCheckOk": true,
            "playbackContext": ["contentPlaybackContext": ["html5Preference": "HTML5_PREF_WANTS"]]
        ]
    }

    /// Resolves streams for a video. HLS is preferred (AVPlayer plays it natively with adaptive quality),
    /// so when the first client has no HLS manifest the iOS client is asked too.
    func playback(videoId: String, _ done: @escaping Done<PlaybackInfo>) {
        runPlaybackChain(videoId: videoId, retried: false, done: done)
    }

    private func runPlaybackChain(videoId: String, retried: Bool, done: @escaping Done<PlaybackInfo>) {
        let chain = [Clients.visionOS, Clients.ios, Clients.androidVR]
        var firstError: Error?
        var fallback: PlaybackInfo?

        func step(_ index: Int) {
            if index >= chain.count {
                if let f = fallback {
                    done(.success(f))
                    return
                }
                if !retried, let e = firstError as? InnerTubeError, case .botCheck = e {
                    refreshVisitor { self.runPlaybackChain(videoId: videoId, retried: true, done: done) }
                    return
                }
                done(.failure(firstError ?? InnerTubeError.unplayable("No playable stream")))
                return
            }
            post("player", body: playerBody(videoId), profile: chain[index]) { r in
                switch r {
                case .failure(let e):
                    if firstError == nil { firstError = e }
                    step(index + 1)
                case .success(let json):
                    do {
                        let info = try Parse.playback(json, videoId: videoId)
                        if info.hlsURL != nil {
                            done(.success(info))
                            return
                        }
                        if fallback == nil { fallback = info }
                        if index + 1 < chain.count - 1 {
                            step(index + 1)
                        } else if let f = fallback {
                            done(.success(f))
                        }
                    } catch {
                        if firstError == nil { firstError = error }
                        step(index + 1)
                    }
                }
            }
        }
        step(0)
    }

    // MARK: Shorts

    static func reelSequenceParams(seed videoId: String) -> String {
        var bytes: [UInt8] = [0x0A, UInt8(videoId.utf8.count)]
        bytes += Array(videoId.utf8)
        bytes += [0x2A, 0x02, 0x18, 0x00, 0x30, 0x01, 0x78, 0x01]
        return Data(bytes).base64EncodedString()
    }

    /// Video ids that follow `seed` in the Shorts feed.
    func reelSequence(seed: String, _ done: @escaping Done<[String]>) {
        post("reel/reel_watch_sequence", body: ["sequenceParams": InnerTube.reelSequenceParams(seed: seed)]) { r in
            done(r.map { Parse.reelSequence($0) })
        }
    }

    func reelItem(videoId: String, _ done: @escaping Done<ShortEntry>) {
        let body: [String: Any] = [
            "disablePlayerResponse": true,
            "playerRequest": ["videoId": videoId, "params": "8AEB"],
            "params": "CA8%3D"
        ]
        post("reel/reel_item_watch", body: body) { r in
            done(r.map { Parse.reelItem($0, videoId: videoId) })
        }
    }
}
