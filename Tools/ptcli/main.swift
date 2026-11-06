import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Command line harness for the Core layer (Linux / macOS). Build + run with Tools/linux_build.sh.
// It talks to the real YouTube API, so it doubles as an end-to-end check that the parsers still match.

func wait<T>(_ call: (@escaping Done<T>) -> Void) -> Result<T, Error> {
    let sem = DispatchSemaphore(value: 0)
    var out: Result<T, Error> = .failure(InnerTubeError.empty)
    call { r in
        out = r
        sem.signal()
    }
    sem.wait()
    return out
}

func show(_ it: FeedItem) {
    switch it {
    case .video(let v):
        let tag = (v.isLive ? " LIVE" : (v.isShort ? " SHORT" : "")) + (v.watchedPercent.map { " \($0)%" } ?? "")
        print("  V \(v.id) [\(v.duration)] \(v.title) | \(v.channelName)(\(v.channelId)) | \(v.views) | \(v.published)\(tag)")
    case .channel(let c):
        print("  C \(c.id) \(c.name) \(c.handle) \(c.subscribers) avatar=\(c.avatar.isEmpty ? "-" : "ok")")
    case .playlist(let p):
        print("  P \(p.id) \(p.title) | \(p.channelName) | \(p.videoCount) thumb=\(p.thumbnail.isEmpty ? "-" : "ok")")
    case .shorts(let l):
        print("  S shorts x\(l.count): " + l.prefix(3).map { $0.title }.joined(separator: " / "))
    case .text(let t):
        print("  T text (\(t.count) chars): " + t.prefix(80).replacingOccurrences(of: "\n", with: " "))
    }
}

func showPage(_ p: FeedPage, limit: Int = 12) {
    print("items=\(p.items.count) sections=\(p.sections.count) continuation=\(p.continuation == nil ? "none" : "yes(\(p.continuation!.count))")")
    for s in p.sections { print("  section '\(s.title)': \(s.items.count)") }
    for it in p.items.prefix(limit) { show(it) }
}

func check(_ url: URL, range: String? = nil, ua: String? = nil) -> String {
    var req = URLRequest(url: url)
    if let r = range { req.setValue(r, forHTTPHeaderField: "Range") }
    if let u = ua { req.setValue(u, forHTTPHeaderField: "User-Agent") }
    let sem = DispatchSemaphore(value: 0)
    var out = "?"
    URLSession.shared.dataTask(with: req) { data, resp, err in
        if let h = resp as? HTTPURLResponse {
            out = "HTTP \(h.statusCode) \(h.value(forHTTPHeaderField: "Content-Type") ?? "") bytes=\(data?.count ?? 0)"
        } else {
            out = "error \(String(describing: err))"
        }
        sem.signal()
    }.resume()
    sem.wait()
    return out
}

func fail(_ e: Error) { print("ERROR:", e) }

/// Account commands read a token file ({access_token, refresh_token, expires_at}) named by PT_TOKEN_FILE.
/// The session has no storage here, so nothing is written back and the file stays valid.
func signInFromEnvironment() -> Bool {
    guard let path = ProcessInfo.processInfo.environment["PT_TOKEN_FILE"],
          let data = FileManager.default.contents(atPath: path) else {
        print("set PT_TOKEN_FILE to a token json file")
        return false
    }
    let j = JSON.parse(data)
    guard let access = j["access_token"].string, let refresh = j["refresh_token"].string else {
        print("token file has no access_token / refresh_token")
        return false
    }
    let expires = Date(timeIntervalSince1970: j["expires_at"].double ?? 0)
    AuthSession.shared.adopt(AuthTokens(accessToken: access, refreshToken: refresh, expiresAt: expires))
    return true
}

let args = Array(CommandLine.arguments.dropFirst())
let cmd = args.first ?? "help"
let tub = InnerTube.shared
if cmd.hasPrefix("a-") && !signInFromEnvironment() { exit(1) }

switch cmd {
case "home":
    switch wait({ tub.home($0) }) {
    case .success(let p):
        showPage(p, limit: 20)
        if let c = p.continuation {
            print("-- continuation page")
            if case .success(let p2) = wait({ tub.continuation(c, endpoint: "browse", $0) }) { showPage(p2, limit: 5) }
        }
    case .failure(let e): fail(e)
    }

case "home-fresh":
    // Simulates refreshing the anonymous Home feed: the user "sees" the first 5 videos of every load.
    let rounds = args.count > 1 ? (Int(args[1]) ?? 4) : 4
    let minFresh = args.count > 2 ? (Int(args[2]) ?? 12) : 12
    var seenIds = Set<String>()
    var previous: [String] = []
    for i in 0..<rounds {
        switch wait({ tub.freshHome(signedIn: false, seen: seenIds, newVisitor: i > 0, minFresh: minFresh, $0) }) {
        case .success(let feed):
            let ids = feed.page.items.compactMap { item -> String? in
                if case .video(let v) = item { return v.id }
                return nil
            }
            let top = Array(ids.prefix(10))
            let alreadySeen = top.filter { seenIds.contains($0) }.count
            let repeated = top.filter { previous.contains($0) }.count
            print("refresh \(i + 1): \(ids.count) videos, top10 already seen: \(alreadySeen), top10 also in the previous refresh's top10: \(repeated), continuation=\(feed.page.continuation == nil ? "none" : "yes")")
            print("   top10: " + top.joined(separator: " "))
            previous = top
            for id in ids.prefix(5) { seenIds.insert(id) }
        case .failure(let e): fail(e)
        }
    }

case "search":
    let q = args.count > 1 ? args[1] : "swift"
    var filter = SearchFilter()
    if args.count > 2 {
        switch args[2] {
        case "channel": filter.kind = .channel
        case "playlist": filter.kind = .playlist
        case "video": filter.kind = .video
        case "date": filter.sort = .uploadDate
        default: break
        }
    }
    print("filter params:", filter.params ?? "nil")
    switch wait({ tub.search(q, filter: filter, $0) }) {
    case .success(let p):
        showPage(p, limit: 25)
        if let c = p.continuation, args.count > 3 {
            print("-- continuation page")
            if case .success(let p2) = wait({ tub.continuation(c, endpoint: "search", $0) }) { showPage(p2, limit: 5) }
        }
    case .failure(let e): fail(e)
    }

case "suggest":
    let q = args.count > 1 ? args[1] : "ねこ"
    let sem = DispatchSemaphore(value: 0)
    tub.suggestions(q) { list in print(list); sem.signal() }
    sem.wait()

case "watch":
    let id = args.count > 1 ? args[1] : "dQw4w9WgXcQ"
    let pl: String? = args.count > 2 ? args[2] : nil
    switch wait({ tub.watch(videoId: id, playlistId: pl, $0) }) {
    case .success(let w):
        print("title: \(w.title)")
        print("views: \(w.views) (\(w.viewsShort)) date: \(w.date) likes: \(w.likeText) (\(w.likeCount ?? -1))")
        print("channel: \(w.channel?.name ?? "-") \(w.channel?.id ?? "-") subs: \(w.channel?.subscribers ?? "-") avatar=\(w.channel?.avatar.isEmpty == false ? "ok" : "-")")
        print("description: \(w.description.prefix(100).replacingOccurrences(of: "\n", with: " "))…")
        print("comments: \(w.commentCount) token=\(w.commentsToken == nil ? "none" : "yes") sorts=\(w.commentSortTokens.map { $0.title })")
        print("autoplay: \(w.autoplay?.title ?? "-")")
        print("queue: \(w.queueTitle) idx=\(w.queueIndex) count=\(w.queue.count)")
        showPage(w.related, limit: 6)
    case .failure(let e): fail(e)
    }

case "comments":
    let id = args.count > 1 ? args[1] : "dQw4w9WgXcQ"
    if case .success(let w) = wait({ tub.watch(videoId: id, $0) }), let tok = w.commentsToken {
        switch wait({ tub.comments(token: tok, $0) }) {
        case .success(let cp):
            print("comments=\(cp.comments.count) continuation=\(cp.continuation == nil ? "none" : "yes") total=\(cp.totalText)")
            for c in cp.comments.prefix(5) {
                print("  \(c.author) (\(c.published)) 👍\(c.likes) replies=\(c.replyCount) owner=\(c.isOwner): \(c.text.prefix(70).replacingOccurrences(of: "\n", with: " "))")
            }
            if let c = cp.continuation, case .success(let p2) = wait({ tub.comments(token: c, $0) }) {
                print("page2 comments=\(p2.comments.count) continuation=\(p2.continuation == nil ? "none" : "yes")")
            }
        case .failure(let e): fail(e)
        }
    } else { print("no comments token") }

case "channel":
    let id = args.count > 1 ? args[1] : "UCuAXFkgsw1L7xaCfnd5JJOw"
    switch wait({ tub.channel(id: id, $0) }) {
    case .success(let c):
        print("name=\(c.name) handle=\(c.handle) subs=\(c.subscribers) videos=\(c.videoCount) verified=\(c.verified)")
        print("avatar=\(c.avatar.prefix(60)) banner=\(c.banner.prefix(60))")
        for t in c.tabs { print("  tab '\(t.title)' selected=\(t.selected) params=\(t.params.prefix(24))") }
        showPage(c.firstPage, limit: 8)
        if args.count > 2, let idx = Int(args[2]), idx < c.tabs.count {
            print("-- tab \(c.tabs[idx].title)")
            if case .success(let p) = wait({ tub.channelTab(id: c.id, params: c.tabs[idx].params, $0) }) {
                showPage(p, limit: 8)
                if let cont = p.continuation, case .success(let p2) = wait({ tub.continuation(cont, endpoint: "browse", $0) }) {
                    print("-- tab page 2"); showPage(p2, limit: 3)
                }
            }
        }
    case .failure(let e): fail(e)
    }

case "playlist":
    let id = args.count > 1 ? args[1] : "PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI"
    switch wait({ tub.playlist(id: id, $0) }) {
    case .success(let p):
        print("title=\(p.title) owner=\(p.owner) stats=\(p.stats)")
        showPage(p.firstPage, limit: 5)
        if let c = p.firstPage.continuation, case .success(let p2) = wait({ tub.continuation(c, endpoint: "browse", $0) }) {
            print("-- page 2"); showPage(p2, limit: 3)
        }
    case .failure(let e): fail(e)
    }

case "play":
    let id = args.count > 1 ? args[1] : "dQw4w9WgXcQ"
    switch wait({ tub.playback(videoId: id, $0) }) {
    case .success(let p):
        print("title=\(p.title) author=\(p.author) duration=\(p.duration) live=\(p.isLive) maxHeight=\(p.maxHeight)")
        if let u = p.hlsURL { print("HLS:", u.absoluteString.prefix(90), "->", check(u)) }
        if let u = p.hlsURL, ProcessInfo.processInfo.environment["PT_DUMP"] != nil {
            func fetch(_ u: URL) -> String { return (try? String(contentsOf: u, encoding: .utf8)) ?? "" }
            let master = fetch(u)
            let lines = master.components(separatedBy: "\n")
            for l in lines where l.hasPrefix("#EXT-X-STREAM-INF") || l.hasPrefix("#EXT-X-MEDIA") { print("  ", l.prefix(170)) }
            if let first = lines.first(where: { $0.hasPrefix("https://") }), let fu = URL(string: first) {
                print("-- first media playlist:")
                for l in fetch(fu).components(separatedBy: "\n").prefix(14) { print("  ", l.prefix(150)) }
            }
        }
        if let u = p.progressiveURL { print("progressive ->", check(u, range: "bytes=0-1023")) }
        if let u = p.videoURL { print("video ->", check(u, range: "bytes=0-1023")) }
        if let u = p.audioURL { print("audio ->", check(u, range: "bytes=0-1023")) }
        for c in p.captions.prefix(8) { print("  caption \(c.languageCode) '\(c.name)' auto=\(c.isAuto)") }
        if let sb = Storyboard(spec: p.storyboardSpec, duration: p.duration) {
            print("storyboard: \(sb.levels.count) levels")
            for l in sb.levels {
                var line = "  L\(l.index) \(l.width)x\(l.height) frames=\(l.count) grid=\(l.columns)x\(l.rows) sheets=\(l.sheetCount) interval=\(sb.spacing(of: l))s"
                if let u = sb.sheetURL(l, sheet: 0) { line += " -> " + check(u) }
                print(line)
            }
            let l = sb.level(minWidth: 160)
            let mid = sb.cell(l, at: p.duration / 2)
            print("  middle of the video is frame \(mid.frame): sheet \(mid.sheet) column \(mid.column) row \(mid.row) of L\(l.index)")
            if let dir = ProcessInfo.processInfo.environment["PT_SB_SAVE"], let u = sb.sheetURL(l, sheet: mid.sheet),
               let data = try? Data(contentsOf: u) {
                let path = dir + "/sb_L\(l.index)_sheet\(mid.sheet).jpg"
                try? data.write(to: URL(fileURLWithPath: path))
                print("  saved \(path) (\(data.count) bytes)")
            }
        } else {
            print("storyboard: none (spec \(p.storyboardSpec.count) chars)")
        }
        if !p.audioTracks.isEmpty {
            print("audio tracks: \(p.audioTracks.count) (formats of the original track: \(p.audioFormats.count))")
            for t in p.audioTracks.prefix(30) { print("  audio \(t.id) lang=\(t.languageTag) '\(t.name)' original=\(t.isDefault)") }
        }
    case .failure(let e): fail(e)
    }

case "owner":
    // owner <videoId>: channel id / name / icon of a video (what the feed rows without an icon ask for)
    let id = args.count > 1 ? args[1] : "dQw4w9WgXcQ"
    switch wait({ tub.videoOwner(videoId: id, $0) }) {
    case .success(let c):
        if let c = c { print("owner: \(c.name) \(c.id) \(c.handle) avatar=\(c.avatar.isEmpty ? "-" : String(c.avatar.prefix(70)))") } else { print("no owner found") }
    case .failure(let e): fail(e)
    }

case "chapters":
    let id = args.count > 1 ? args[1] : "aircAruvnKk"
    if case .success(let w) = wait({ tub.watch(videoId: id, $0) }) {
        let list = Chapters.parse(w.description)
        print("chapters: \(list.count)")
        for c in list.prefix(12) { print("  \(Format.duration(c.start))  \(c.title)") }
    }

case "parsefile":
    // parsefile <json file>: run the generic list parser on a saved response (fixtures from other clients)
    guard args.count > 1, let data = FileManager.default.contents(atPath: args[1]) else {
        print("usage: parsefile <file>")
        exit(1)
    }
    let page = Parse.feed(JSON.parse(data))
    showPage(page, limit: 8)

case "link":
    for a in args.dropFirst() { print("\(a)  ->  \(String(describing: LinkParser.parse(a)))") }
    if args.count > 1, case .some(.resolve(let u)) = LinkParser.parse(args[1]) {
        if case .success(let id) = wait({ tub.resolveChannel(url: u, $0) }) { print("resolved channel id: \(id)") }
    }

case "import":
    // import <file>: shows what the subscription importer would find
    guard args.count > 1, let data = FileManager.default.contents(atPath: args[1]) else {
        print("usage: import <file>")
        exit(1)
    }
    let channels = SubscriptionParser.parse(data)
    print("channels: \(channels.count)")
    for c in channels.prefix(10) { print("  \(c.id)  \(c.name)") }

case "shorts":
    let seed = args.count > 1 ? args[1] : "dJstTDocXr8"
    switch wait({ tub.reelSequence(seed: seed, $0) }) {
    case .success(let ids):
        print("next shorts:", ids)
        if let first = ids.first, case .success(let e) = wait({ tub.reelItem(videoId: first, $0) }) {
            print("first: \(e.video.title) | \(e.video.channelName) | likes \(e.likes) | comments \(e.comments) | avatar \(e.video.channelAvatar.isEmpty ? "-" : "ok")")
        }
    case .failure(let e): fail(e)
    }

case "login-test":
    // Requests a real device code and polls once (nobody approves it, so Google must answer "pending"). Anonymous.
    switch wait({ AuthSession.shared.requestDeviceCode($0) }) {
    case .success(let c):
        print("user code: \(c.userCode)  url: \(c.verificationURL)  interval: \(c.interval)s  expires in: \(Int(c.expiresAt.timeIntervalSinceNow))s")
        switch wait({ AuthSession.shared.pollToken(c, $0) }) {
        case .success: print("unexpected: tokens were issued")
        case .failure(let e): print("poll ->", e)
        }
    case .failure(let e): fail(e)
    }

case "a-whoami":
    switch wait({ tub.accountProfile($0) }) {
    case .success(let p): print("name=\(p.name) handle=\(p.handle) avatar=\(p.avatar.isEmpty ? "-" : "ok")")
    case .failure(let e): fail(e)
    }

case "a-home":
    switch wait({ tub.accountHome($0) }) {
    case .success(let p):
        showPage(p, limit: 12)
        if let c = p.continuation {
            print("-- continuation page")
            if case .success(let p2) = wait({ tub.accountContinuation(c, $0) }) { showPage(p2, limit: 5) }
        }
    case .failure(let e): fail(e)
    }

case "a-subs":
    switch wait({ tub.accountSubscriptions($0) }) {
    case .success(let s):
        print("channels in strip: \(s.channels.count)")
        for c in s.channels.prefix(20) { print("  C \(c.id) \(c.name) avatar=\(c.avatar.isEmpty ? "-" : "ok")") }
        showPage(s.feed, limit: 8)
        if let c = s.feed.continuation {
            print("-- continuation page")
            if case .success(let p2) = wait({ tub.accountContinuation(c, $0) }) { showPage(p2, limit: 3) }
        }
    case .failure(let e): fail(e)
    }

case "a-channels":
    switch wait({ tub.accountChannels($0) }) {
    case .success(let list): for c in list { print("  C \(c.id) \(c.name) \(c.handle) \(c.subscribers)") }
    case .failure(let e): fail(e)
    }

case "a-browse":
    // a-browse <browseId> [more]: FEhistory / FElibrary / VLWL / VLLL / FEplaylist_aggregation / VL<playlist id>
    let id = args.count > 1 ? args[1] : "FEhistory"
    switch wait({ tub.accountBrowse(id, $0) }) {
    case .success(let p):
        showPage(p, limit: 10)
        if args.count > 2, let c = p.continuation, case .success(let p2) = wait({ tub.accountContinuation(c, $0) }) {
            print("-- continuation page")
            showPage(p2, limit: 5)
        }
    case .failure(let e): fail(e)
    }

case "a-playlist":
    // a-playlist <id> [more]: WL / LL / any playlist id through the TV client
    let id = args.count > 1 ? args[1] : "WL"
    switch wait({ tub.accountPlaylist(id: id, $0) }) {
    case .success(let p):
        print("title=\(p.title) owner=\(p.owner) stats=\(p.stats)")
        showPage(p.firstPage, limit: 5)
        if args.count > 2, let c = p.firstPage.continuation, case .success(let p2) = wait({ tub.accountContinuation(c, $0) }) {
            print("-- continuation page")
            showPage(p2, limit: 3)
        }
    case .failure(let e): fail(e)
    }

case "a-chan":
    let id = args.count > 1 ? args[1] : "UCuAXFkgsw1L7xaCfnd5JJOw"
    switch wait({ tub.accountChannelSubscribed(id: id, $0) }) {
    case .success(let on): print("subscribed=\(on)")
    case .failure(let e): fail(e)
    }

case "a-track":
    // Account-bound statistics URLs of a video (read-only): which parameters they carry, nothing else is printed.
    let tid = args.count > 1 ? args[1] : "jNQXAC9IVRw"
    switch wait({ tub.accountPlaybackTracking(videoId: tid, $0) }) {
    case .success(let t):
        func names(_ u: URL?) -> String {
            guard let u = u, let c = URLComponents(url: u, resolvingAgainstBaseURL: false) else { return "-" }
            return (c.host ?? "?") + " " + (c.queryItems ?? []).map { $0.name }.sorted().joined(separator: ",")
        }
        print("playback : \(names(t.playbackURL))")
        print("watchtime: \(names(t.watchtimeURL))")
        print("account-bound (uga): \(t.playbackURL.absoluteString.contains("uga="))  sts used: \(SignatureTimestamp.current)")
    case .failure(let e): fail(e)
    }

case "a-played":
    // WRITES TO THE ACCOUNT'S WATCH HISTORY (test videos only): the playback ping, then a watch-time ping of N seconds.
    let pid = args.count > 1 ? args[1] : "jNQXAC9IVRw"
    let watched = args.count > 2 ? (Double(args[2]) ?? 30) : 30
    switch wait({ tub.accountPlaybackTracking(videoId: pid, $0) }) {
    case .success(let t):
        let cpn = InnerTube.newCpn()
        let a = wait({ r in tub.reportPlayed(t, cpn: cpn, position: 0) { r(.success($0)) } })
        print("playback ping sent:", a)
        if case .success(true) = a, watched > 0 {
            let b = wait({ r in tub.reportWatched(t, cpn: cpn, from: 0, to: watched) { r(.success($0)) } })
            print("watch-time ping sent:", b)
        }
    case .failure(let e): fail(e)
    }

case "a-session":
    // WRITES TO THE ACCOUNT'S WATCH HISTORY (test videos only): a play through PlayHistoryReporter, as the app does it.
    // a-session <videoId> <watchedSeconds> [fast]   "fast" ends the play before the tracking answer can arrive.
    let sid = args.count > 1 ? args[1] : "jNQXAC9IVRw"
    let secs = args.count > 2 ? (Double(args[2]) ?? 20) : 20
    PlayHistoryReporter.shared.started(videoId: sid, position: 0)
    if args.count > 3 && args[3] == "fast" { PlayHistoryReporter.shared.finished(position: secs) } else {
        Thread.sleep(forTimeInterval: 5)
        PlayHistoryReporter.shared.finished(position: secs)
    }
    Thread.sleep(forTimeInterval: 6) // the pings are sent in the background
    print("session done (check the history for \(sid))")

case "a-state":
    let id = args.count > 1 ? args[1] : "dQw4w9WgXcQ"
    switch wait({ tub.accountWatchState(videoId: id, $0) }) {
    case .success(let s): print("likeStatus=\(s.likeStatus) subscribed=\(s.subscribed.map { String($0) } ?? "-") channel=\(s.channelId)")
    case .failure(let e): fail(e)
    }

default:
    print("commands: home | search q [channel|playlist|video|date] [more] | suggest q | watch id [playlist] | comments id | channel id [tabIndex] | playlist id | play id | shorts seed")
    print("home-fresh [rounds] [minFresh]: anonymous Home refreshed repeatedly (seen videos go behind new ones)")
    print("sign-in: login-test (anonymous: requests a device code and polls once)")
    print("account (PT_TOKEN_FILE): a-whoami | a-home | a-subs | a-channels | a-browse id [more] | a-playlist id [more] | a-chan id | a-state videoId | a-track videoId | a-played videoId [seconds] | a-session videoId seconds [fast] (the last two write history!)")
}
