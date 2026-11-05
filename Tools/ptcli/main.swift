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
        let tag = v.isLive ? " LIVE" : (v.isShort ? " SHORT" : "")
        print("  V \(v.id) [\(v.duration)] \(v.title) | \(v.channelName)(\(v.channelId)) | \(v.views) | \(v.published)\(tag)")
    case .channel(let c):
        print("  C \(c.id) \(c.name) \(c.handle) \(c.subscribers) avatar=\(c.avatar.isEmpty ? "-" : "ok")")
    case .playlist(let p):
        print("  P \(p.id) \(p.title) | \(p.channelName) | \(p.videoCount) thumb=\(p.thumbnail.isEmpty ? "-" : "ok")")
    case .shorts(let l):
        print("  S shorts x\(l.count): " + l.prefix(3).map { $0.title }.joined(separator: " / "))
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

let args = Array(CommandLine.arguments.dropFirst())
let cmd = args.first ?? "help"
let tub = InnerTube.shared

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
        if let u = p.progressiveURL { print("progressive ->", check(u, range: "bytes=0-1023")) }
        if let u = p.videoURL { print("video ->", check(u, range: "bytes=0-1023")) }
        if let u = p.audioURL { print("audio ->", check(u, range: "bytes=0-1023")) }
        for c in p.captions.prefix(8) { print("  caption \(c.languageCode) '\(c.name)' auto=\(c.isAuto)") }
    case .failure(let e): fail(e)
    }

case "chapters":
    let id = args.count > 1 ? args[1] : "aircAruvnKk"
    if case .success(let w) = wait({ tub.watch(videoId: id, $0) }) {
        let list = Chapters.parse(w.description)
        print("chapters: \(list.count)")
        for c in list.prefix(12) { print("  \(Format.duration(c.start))  \(c.title)") }
    }

case "import":
    // import <file>: shows what the subscription importer would find (parser lives in the app target, so only ids here)
    print("(import is exercised through the app)")

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

default:
    print("commands: home | search q [channel|playlist|video|date] [more] | suggest q | watch id [playlist] | comments id | channel id [tabIndex] | playlist id | play id | shorts seed")
}
