import Foundation

struct HistoryEntry: Codable {
    var video: VideoItem
    var watchedAt: Date
    var position: Double
    var duration: Double
}

struct UserPlaylist: Codable {
    var id: String
    var name: String
    var videos: [VideoItem]
}

/// Local data: watch history, subscriptions, watch later, likes, playlists, search history.
/// Everything lives in small JSON files under Application Support.
final class Store {
    static let shared = Store()

    private(set) var history: [HistoryEntry] = []
    private(set) var subscriptions: [ChannelItem] = []
    private(set) var watchLater: [VideoItem] = []
    private(set) var liked: [VideoItem] = []
    private(set) var playlists: [UserPlaylist] = []
    private(set) var searches: [String] = []

    private let queue = DispatchQueue(label: "podtube.store", qos: .utility)
    private let dir: URL
    private var pendingSaves = Set<String>()

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        dir = base.appendingPathComponent("PodTube", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        history = load("history.json") ?? []
        subscriptions = load("subscriptions.json") ?? []
        watchLater = load("watchlater.json") ?? []
        liked = load("liked.json") ?? []
        playlists = load("playlists.json") ?? []
        searches = load("searches.json") ?? []
    }

    // MARK: Persistence

    private func load<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, as name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let url = dir.appendingPathComponent(name)
        queue.async {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func changed() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: .storeChanged, object: nil)
        } else {
            DispatchQueue.main.async { NotificationCenter.default.post(name: .storeChanged, object: nil) }
        }
    }

    // MARK: History

    func addHistory(_ video: VideoItem, position: Double = 0, duration: Double = 0) {
        if Settings.pauseHistory { return }
        history.removeAll { $0.video.id == video.id }
        history.insert(HistoryEntry(video: video, watchedAt: Date(), position: position, duration: duration), at: 0)
        if history.count > 500 { history.removeLast(history.count - 500) }
        save(history, as: "history.json")
        changed()
    }

    /// Fills in title / channel of an entry that was created from a bare id.
    func updateHistoryVideo(_ video: VideoItem) {
        guard let i = history.firstIndex(where: { $0.video.id == video.id }) else { return }
        var v = history[i].video
        if !video.title.isEmpty { v.title = video.title }
        if !video.channelName.isEmpty { v.channelName = video.channelName }
        if !video.channelId.isEmpty { v.channelId = video.channelId }
        if !video.channelAvatar.isEmpty { v.channelAvatar = video.channelAvatar }
        if !video.thumbnail.isEmpty { v.thumbnail = video.thumbnail }
        history[i].video = v
        save(history, as: "history.json")
    }

    func updateProgress(videoId: String, position: Double, duration: Double) {
        guard let i = history.firstIndex(where: { $0.video.id == videoId }) else { return }
        history[i].position = position
        if duration > 0 { history[i].duration = duration }
        save(history, as: "history.json")
    }

    /// Watched fraction 0...1 (nil when never watched).
    func progress(for videoId: String) -> Double? {
        guard let e = history.first(where: { $0.video.id == videoId }), e.duration > 0 else { return nil }
        return min(1, max(0, e.position / e.duration))
    }

    func resumePosition(for videoId: String) -> Double? {
        guard let e = history.first(where: { $0.video.id == videoId }), e.duration > 0 else { return nil }
        if e.position < 5 || e.position > e.duration - 10 { return nil }
        return e.position
    }

    func removeHistory(_ videoId: String) {
        history.removeAll { $0.video.id == videoId }
        save(history, as: "history.json")
        changed()
    }

    func clearHistory() {
        history = []
        save(history, as: "history.json")
        changed()
    }

    // MARK: Subscriptions

    func isSubscribed(_ channelId: String) -> Bool {
        return subscriptions.contains { $0.id == channelId }
    }

    func subscribe(_ channel: ChannelItem) {
        if isSubscribed(channel.id) { return }
        subscriptions.insert(channel, at: 0)
        save(subscriptions, as: "subscriptions.json")
        changed()
    }

    func unsubscribe(_ channelId: String) {
        subscriptions.removeAll { $0.id == channelId }
        save(subscriptions, as: "subscriptions.json")
        changed()
    }

    func replaceSubscriptions(_ list: [ChannelItem]) {
        subscriptions = list
        save(subscriptions, as: "subscriptions.json")
        changed()
    }

    // MARK: Watch later / liked

    func isWatchLater(_ id: String) -> Bool { return watchLater.contains { $0.id == id } }

    func toggleWatchLater(_ video: VideoItem) {
        if let i = watchLater.firstIndex(where: { $0.id == video.id }) {
            watchLater.remove(at: i)
        } else {
            watchLater.insert(video, at: 0)
        }
        save(watchLater, as: "watchlater.json")
        changed()
    }

    func isLiked(_ id: String) -> Bool { return liked.contains { $0.id == id } }

    func toggleLike(_ video: VideoItem) {
        if let i = liked.firstIndex(where: { $0.id == video.id }) {
            liked.remove(at: i)
        } else {
            liked.insert(video, at: 0)
        }
        save(liked, as: "liked.json")
        changed()
    }

    // MARK: Playlists

    @discardableResult
    func createPlaylist(name: String, with video: VideoItem? = nil) -> UserPlaylist {
        var p = UserPlaylist(id: UUID().uuidString, name: name, videos: [])
        if let v = video { p.videos = [v] }
        playlists.insert(p, at: 0)
        save(playlists, as: "playlists.json")
        changed()
        return p
    }

    func deletePlaylist(_ id: String) {
        playlists.removeAll { $0.id == id }
        save(playlists, as: "playlists.json")
        changed()
    }

    func toggle(_ video: VideoItem, inPlaylist id: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        if let j = playlists[i].videos.firstIndex(where: { $0.id == video.id }) {
            playlists[i].videos.remove(at: j)
        } else {
            playlists[i].videos.append(video)
        }
        save(playlists, as: "playlists.json")
        changed()
    }

    func remove(videoId: String, fromPlaylist id: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].videos.removeAll { $0.id == videoId }
        save(playlists, as: "playlists.json")
        changed()
    }

    // MARK: Search history

    func addSearch(_ q: String) {
        let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || Settings.pauseHistory { return }
        searches.removeAll { $0 == t }
        searches.insert(t, at: 0)
        if searches.count > 50 { searches.removeLast(searches.count - 50) }
        save(searches, as: "searches.json")
    }

    func removeSearch(_ q: String) {
        searches.removeAll { $0 == q }
        save(searches, as: "searches.json")
    }

    func clearSearches() {
        searches = []
        save(searches, as: "searches.json")
    }
}
