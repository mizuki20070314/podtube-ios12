import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Subscriptions page of the signed-in account: the video feed plus the channel strip on the left of the TV page.
struct AccountSubscriptions {
    var feed: FeedPage
    var channels: [ChannelItem]
}

/// Hook of the demo / CI mode: when set, signed-in requests are answered from it (nil = ask YouTube) instead of the network.
enum AccountDemo {
    static var responder: ((String, [String: Any]) -> JSON?)?
}

/// Everything that needs the signed-in account. Google only accepts OAuth bearer tokens for the TVHTML5
/// InnerTube client, so these calls use it instead of the anonymous VISIONOS client (see README "Signing in").
extension InnerTube {

    // MARK: Authenticated transport

    /// POST as the signed-in account (TV client + bearer token). A 401 refreshes the token and retries once.
    func postAuthed(_ endpoint: String, body: [String: Any], completion: @escaping (Result<JSON, Error>) -> Void) {
        sendAuthed(endpoint, body: body, retried: false, completion: completion)
    }

    private func sendAuthed(_ endpoint: String, body: [String: Any], retried: Bool,
                            completion: @escaping (Result<JSON, Error>) -> Void) {
        if let canned = AccountDemo.responder?(endpoint, body) {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { completion(.success(canned)) }
            return
        }
        AuthSession.shared.validAccessToken { [weak self] tokenResult in
            guard let self = self else { return }
            switch tokenResult {
            case .failure(let e):
                if case AuthError.notSignedIn = e {
                    completion(.failure(InnerTubeError.authRequired))
                } else {
                    completion(.failure(e))
                }
            case .success(let token):
                self.post(endpoint, body: body, profile: Clients.tv, extraHeaders: ["Authorization": "Bearer " + token]) { r in
                    if case .failure(let err) = r, InnerTube.isUnauthorized(err) {
                        if retried {
                            completion(.failure(InnerTubeError.authRequired))
                        } else {
                            AuthSession.shared.invalidateAccessToken()
                            self.sendAuthed(endpoint, body: body, retried: true, completion: completion)
                        }
                        return
                    }
                    completion(r)
                }
            }
        }
    }

    private static func isUnauthorized(_ e: Error) -> Bool {
        guard let t = e as? InnerTubeError else { return false }
        switch t {
        case .http(let c), .api(let c, _): return c == 401
        default: return false
        }
    }

    // MARK: Account feeds

    /// Personalised home ("おすすめ").
    func accountHome(_ done: @escaping Done<FeedPage>) {
        accountBrowse("FEwhat_to_watch", done)
    }

    /// Any TV browse page (history, library, playlists, …) read as a feed.
    func accountBrowse(_ browseId: String, _ done: @escaping Done<FeedPage>) {
        postAuthed("browse", body: ["browseId": browseId]) { r in
            done(r.map { Parse.feed($0) })
        }
    }

    func accountContinuation(_ token: String, _ done: @escaping Done<FeedPage>) {
        postAuthed("browse", body: ["continuation": token]) { r in
            done(r.map { Parse.feed($0) })
        }
    }

    func accountSubscriptions(_ done: @escaping Done<AccountSubscriptions>) {
        postAuthed("browse", body: ["browseId": "FEsubscriptions"]) { r in
            done(r.map { AccountSubscriptions(feed: Parse.feed($0), channels: Parse.subscriptionTabs($0)) })
        }
    }

    /// The channels of the account's "Channels" page (only the most recently active ones – the TV API gives no more).
    func accountChannels(_ done: @escaping Done<[ChannelItem]>) {
        postAuthed("browse", body: ["browseId": "FEchannels"]) { r in
            done(r.map { json -> [ChannelItem] in
                var out: [ChannelItem] = []
                for it in Parse.feed(json).items {
                    if case .channel(let c) = it { out.append(c) }
                }
                return out
            })
        }
    }

    /// Any playlist, including the private ones ("WL", "LL", the account's own lists).
    func accountPlaylist(id: String, _ done: @escaping Done<PlaylistInfo>) {
        postAuthed("browse", body: ["browseId": "VL" + id]) { r in
            done(r.map { Parse.accountPlaylistInfo($0, id: id) })
        }
    }

    /// Whether the account subscribes to a channel (the TV channel page carries the exact state; the response is large).
    func accountChannelSubscribed(id: String, _ done: @escaping Done<Bool>) {
        postAuthed("browse", body: ["browseId": id]) { r in
            switch r {
            case .success(let json):
                let s = Parse.accountWatchState(json)
                if let on = s.subscribed { done(.success(on)) } else { done(.failure(InnerTubeError.empty)) }
            case .failure(let e):
                done(.failure(e))
            }
        }
    }

    func accountProfile(_ done: @escaping Done<AccountProfile>) {
        postAuthed("account/accounts_list", body: [:]) { r in
            switch r {
            case .success(let json):
                if let p = Parse.accountProfile(json) { done(.success(p)) } else { done(.failure(InnerTubeError.empty)) }
            case .failure(let e):
                done(.failure(e))
            }
        }
    }

    /// Like / subscribe state of a video for this account (the anonymous watch page cannot know it).
    func accountWatchState(videoId: String, _ done: @escaping Done<AccountWatchState>) {
        postAuthed("next", body: ["videoId": videoId]) { r in
            done(r.map { Parse.accountWatchState($0) })
        }
    }

    // MARK: Actions

    func setLike(videoId: String, _ status: LikeStatus, _ done: @escaping Done<Void>) {
        let endpoint: String
        switch status {
        case .like: endpoint = "like/like"
        case .dislike: endpoint = "like/dislike"
        case .none: endpoint = "like/removelike"
        }
        postAuthed(endpoint, body: ["target": ["videoId": videoId]]) { r in
            done(r.map { _ in () })
        }
    }

    func setSubscribed(channelId: String, _ subscribed: Bool, _ done: @escaping Done<Void>) {
        let body: [String: Any] = [
            "channelIds": [channelId],
            "params": subscribed ? "EgIIAxgA" : "CgIIAxgA"
        ]
        postAuthed(subscribed ? "subscription/subscribe" : "subscription/unsubscribe", body: body) { r in
            done(r.map { _ in () })
        }
    }

    /// Adds / removes one video of a playlist ("WL" = Watch later). Adding an already present video is skipped.
    func editPlaylist(id: String, videoId: String, add: Bool, _ done: @escaping Done<Void>) {
        let action: [String: Any]
        if add {
            action = ["action": "ACTION_ADD_VIDEO", "addedVideoId": videoId, "dedupeOption": "DEDUPE_OPTION_SKIP"]
        } else {
            action = ["action": "ACTION_REMOVE_VIDEO_BY_VIDEO_ID", "removedVideoId": videoId]
        }
        postAuthed("browse/edit_playlist", body: ["playlistId": id, "actions": [action]]) { r in
            switch r {
            case .success(let json):
                let status = json["status"].stringValue
                if status.isEmpty || status == "STATUS_SUCCEEDED" {
                    done(.success(()))
                } else {
                    done(.failure(InnerTubeError.parse(status)))
                }
            case .failure(let e):
                done(.failure(e))
            }
        }
    }

    // MARK: Watch history

    /// Tells YouTube that playback started, which is what puts a video into the account's watch history.
    /// `url` is `playbackTracking.videostatsPlaybackUrl` of the player response. Best effort: errors are ignored.
    func reportPlaybackStart(_ url: URL) {
        guard AccountDemo.responder == nil, AuthSession.shared.isSignedIn,
              var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        var cpn = ""
        for _ in 0..<16 { cpn.append(alphabet.randomElement() ?? "a") }
        var items = (comps.queryItems ?? []).filter { !["ver", "cpn", "cmt", "el"].contains($0.name) }
        items.append(URLQueryItem(name: "ver", value: "2"))
        items.append(URLQueryItem(name: "cpn", value: cpn))
        items.append(URLQueryItem(name: "cmt", value: "0"))
        items.append(URLQueryItem(name: "el", value: "detailpage"))
        comps.queryItems = items
        guard let target = comps.url else { return }
        AuthSession.shared.validAccessToken { r in
            guard case .success(let token) = r else { return }
            var req = URLRequest(url: target)
            req.timeoutInterval = 15
            req.setValue(Clients.tv.userAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            Http.shared.send(req) { _ in }
        }
    }
}
