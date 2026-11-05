import UIKit

extension Notification.Name {
    /// A channel icon was learned (rows that were waiting for one can pick it up).
    static let channelDirectoryChanged = Notification.Name("PodTubeChannelDirectoryChanged")
}

/// Channel name -> (id, icon). The signed-in account's feeds (YouTube TV format) name the channel of a video but give
/// neither its id nor its icon, so list rows get them from here: remembered from every screen that does know them
/// (subscriptions, history, feeds that carry the icon) or, failing that, asked from the video's watch data.
/// Everything runs on the main thread.
final class ChannelDirectory {
    static let shared = ChannelDirectory()

    private struct Entry: Codable {
        var id: String
        var name: String
        var avatar: String
    }

    private static let maxEntries = 800
    private static let maxRunning = 2
    private static let maxPending = 40
    /// A channel that could not be looked up is asked again after this long (a dropped connection must not leave
    /// its rows without an icon until the next launch).
    private static let retryAfter: TimeInterval = 120

    private var byName: [String: Entry] = [:]
    private var byId: [String: Entry] = [:]
    /// Name keys, oldest first (used to trim the file).
    private var order: [String] = []
    private var inflight = Set<String>()
    private var failed: [String: Date] = [:]
    private var pending: [(videoId: String, key: String)] = []
    private var running = 0
    private var seeded = false
    private var seededSubscriptions = -1
    private var saveScheduled = false
    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("PodTube", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        fileURL = dir.appendingPathComponent("channel_directory.json")
        if let data = try? Data(contentsOf: fileURL), let list = try? JSONDecoder().decode([Entry].self, from: data) {
            for e in list { put(e, key: ChannelDirectory.key(e.name)) }
        }
    }

    static func key(_ name: String) -> String {
        return name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: Learning

    func learn(_ v: VideoItem) { learn(id: v.channelId, name: v.channelName, avatar: v.channelAvatar) }

    func learn(_ c: ChannelItem) { learn(id: c.id, name: c.name, avatar: c.avatar) }

    func learn(id: String, name: String, avatar: String) {
        if name.isEmpty || avatar.isEmpty { return }
        let key = ChannelDirectory.key(name)
        if let old = byName[key], old.avatar == avatar, id.isEmpty || old.id == id { return }
        var e = Entry(id: id, name: name, avatar: avatar)
        if id.isEmpty, let old = byName[key] { e.id = old.id }
        put(e, key: key)
        scheduleSave()
    }

    private func put(_ e: Entry, key: String) {
        if byName[key] == nil { order.append(key) }
        byName[key] = e
        if !e.id.isEmpty { byId[e.id] = e }
        while order.count > ChannelDirectory.maxEntries {
            let oldest = order.removeFirst()
            if let gone = byName.removeValue(forKey: oldest), !gone.id.isEmpty, byId[gone.id]?.name == gone.name {
                byId.removeValue(forKey: gone.id)
            }
        }
    }

    /// What the app already knows by itself: the subscriptions (their icons are kept with them) and the history.
    private func seed() {
        if !seeded {
            seeded = true
            for h in Store.shared.history { learn(h.video) }
        }
        let subs = Store.shared.subscriptions
        if subs.count != seededSubscriptions {
            seededSubscriptions = subs.count
            for c in subs { learn(c) }
        }
    }

    // MARK: Lookup

    /// `v` with its channel icon / id filled in from what is known (a row that already has an icon is only remembered).
    func filled(_ v: VideoItem) -> VideoItem {
        seed()
        if !v.channelAvatar.isEmpty {
            learn(v)
            return v
        }
        var entry: Entry?
        if !v.channelId.isEmpty { entry = byId[v.channelId] }
        if entry == nil, !v.channelName.isEmpty { entry = byName[ChannelDirectory.key(v.channelName)] }
        guard let e = entry else { return v }
        var out = v
        out.channelAvatar = e.avatar
        if out.channelId.isEmpty { out.channelId = e.id }
        return out
    }

    // MARK: Asking YouTube

    /// Asks who owns the video (once per channel name, two requests at a time, newest row first) so that the row
    /// gets its icon later; `.channelDirectoryChanged` is posted when one arrives.
    func resolve(_ v: VideoItem) {
        if !v.channelAvatar.isEmpty || v.id.isEmpty { return }
        let key = ChannelDirectory.key(v.channelName)
        if key.isEmpty || byName[key] != nil || inflight.contains(key) { return }
        if let t = failed[key], Date().timeIntervalSince(t) < ChannelDirectory.retryAfter { return }
        failed.removeValue(forKey: key)
        inflight.insert(key)
        pending.append((videoId: v.id, key: key))
        if pending.count > ChannelDirectory.maxPending {
            // far behind the scrolling: forget the oldest request, it can be asked again when its row returns
            let dropped = pending.removeFirst()
            inflight.remove(dropped.key)
        }
        pump()
    }

    private func pump() {
        while running < ChannelDirectory.maxRunning, let job = pending.popLast() {
            running += 1
            InnerTube.shared.videoOwner(videoId: job.videoId) { [weak self] result in
                DispatchQueue.main.async { self?.finished(job.key, result) }
            }
        }
    }

    private func finished(_ key: String, _ result: Result<ChannelItem?, Error>) {
        running -= 1
        inflight.remove(key)
        if case .success(let found) = result, let ch = found, !ch.avatar.isEmpty {
            let e = Entry(id: ch.id, name: ch.name, avatar: ch.avatar)
            put(e, key: key) // under the name the row used ...
            let own = ChannelDirectory.key(ch.name)
            if !own.isEmpty && own != key { put(e, key: own) } // ... and under the channel's own name
            scheduleSave()
            NotificationCenter.default.post(name: .channelDirectoryChanged, object: nil)
        } else {
            failed[key] = Date()
        }
        pump()
    }

    /// The channel of a video right now (tapping an icon whose channel id is not known yet).
    func owner(of v: VideoItem, completion: @escaping (ChannelItem?) -> Void) {
        let known = filled(v)
        if !known.channelId.isEmpty {
            var c = ChannelItem(id: known.channelId)
            c.name = known.channelName
            c.avatar = known.channelAvatar
            completion(c)
            return
        }
        InnerTube.shared.videoOwner(videoId: v.id) { [weak self] result in
            DispatchQueue.main.async {
                var found: ChannelItem?
                if case .success(let ch) = result { found = ch }
                if let c = found { self?.learn(c) }
                completion(found)
            }
        }
    }

    // MARK: Persistence

    private func scheduleSave() {
        if saveScheduled { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            self.saveScheduled = false
            let list = self.order.compactMap { self.byName[$0] }
            let url = self.fileURL
            DispatchQueue.global(qos: .utility).async {
                if let data = try? JSONEncoder().encode(list) { try? data.write(to: url, options: .atomic) }
            }
        }
    }
}
