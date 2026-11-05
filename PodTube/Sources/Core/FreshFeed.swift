import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Keeps the Home feed from repeating itself. YouTube is never told what the app already displayed (no impression
/// pings are sent), so a refresh brings back mostly the same videos. The app remembers what it showed and moves those
/// behind the rest; when too little of the first page is new, the next pages are read as well.
enum FeedFreshness {
    /// Stable partition: videos whose id is in `seen` go to the end, everything else (unseen videos, shelves, ...)
    /// keeps its place. `fresh` is the number of videos that are not in `seen`.
    static func demote(_ items: [FeedItem], seen: Set<String>) -> (items: [FeedItem], fresh: Int) {
        var front: [FeedItem] = []
        var back: [FeedItem] = []
        var fresh = 0
        for it in items {
            if case .video(let v) = it {
                if seen.contains(v.id) {
                    back.append(it)
                } else {
                    front.append(it)
                    fresh += 1
                }
            } else {
                front.append(it)
            }
        }
        return (front + back, fresh)
    }
}

/// A first page together with the endpoint its continuation token belongs to ("tv" or "browse").
struct HomeFeed {
    var page: FeedPage
    var endpoint: String
}

extension InnerTube {

    /// One more page of a list; `endpoint` is the one that produced the token ("tv" = signed-in account).
    func continuationPage(_ token: String, endpoint: String, _ done: @escaping Done<FeedPage>) {
        if endpoint == "tv" {
            accountContinuation(token, done)
        } else {
            continuation(token, endpoint: endpoint, done)
        }
    }

    /// The Home "All" feed: the account's recommendations when signed in (falling back to the anonymous feed when
    /// they cannot be read), otherwise the anonymous feed. Videos in `seen` are moved behind the new ones; when fewer
    /// than `minFresh` videos are new, up to `maxExtraPages` further pages are read first. `newVisitor` asks for a
    /// fresh anonymous visitor id (a refresh the user asked for): the anonymous feed depends on it and changes far
    /// more than it does for the same visitor.
    func freshHome(signedIn: Bool, seen: Set<String>, newVisitor: Bool, minFresh: Int = 12, maxExtraPages: Int = 3,
                   _ done: @escaping Done<HomeFeed>) {
        let anonymous: (@escaping Done<HomeFeed>) -> Void = { cb in
            self.home { cb($0.map { HomeFeed(page: $0, endpoint: "browse") }) }
        }
        let start: (@escaping Done<HomeFeed>) -> Void = { cb in
            guard signedIn else {
                anonymous(cb)
                return
            }
            self.accountHome { r in
                if case .success(let page) = r, !page.items.isEmpty {
                    cb(.success(HomeFeed(page: page, endpoint: "tv")))
                } else {
                    anonymous(cb)
                }
            }
        }
        let begin = {
            start { r in
                switch r {
                case .failure(let e): done(.failure(e))
                case .success(let feed): self.gather(feed, seen: seen, minFresh: minFresh, extraPages: maxExtraPages, done)
                }
            }
        }
        if newVisitor && !signedIn {
            refreshVisitor(begin)
        } else {
            begin()
        }
    }

    private func gather(_ first: HomeFeed, seen: Set<String>, minFresh: Int, extraPages: Int, _ done: @escaping Done<HomeFeed>) {
        var items = first.page.items
        var have = Set<String>()
        for it in items { if case .video(let v) = it { have.insert(v.id) } }
        var token = first.page.continuation

        func finish() {
            var page = FeedPage()
            page.items = FeedFreshness.demote(items, seen: seen).items
            page.sections = first.page.sections
            page.continuation = token
            done(.success(HomeFeed(page: page, endpoint: first.endpoint)))
        }

        func step(_ remaining: Int) {
            guard FeedFreshness.demote(items, seen: seen).fresh < minFresh, remaining > 0, let t = token else {
                finish()
                return
            }
            continuationPage(t, endpoint: first.endpoint) { r in
                guard case .success(let more) = r else {
                    finish()
                    return
                }
                for it in more.items {
                    if case .video(let v) = it {
                        if have.contains(v.id) { continue }
                        have.insert(v.id)
                    }
                    items.append(it)
                }
                token = more.continuation
                step(remaining - 1)
            }
        }

        step(extraPages)
    }
}
