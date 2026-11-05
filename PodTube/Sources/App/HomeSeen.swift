import Foundation

/// The Home videos that were shown on screen (newest last), kept between launches. A refresh moves these behind new
/// videos (see `FeedFreshness`): YouTube is not told what was displayed, so without this the same videos keep coming
/// back. Main thread only.
final class HomeSeen {
    static let shared = HomeSeen()

    private static let maxEntries = 600

    private var order: [String] = []
    private var set = Set<String>()
    private var saveScheduled = false
    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("PodTube", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        fileURL = dir.appendingPathComponent("home_seen.json")
        if let data = try? Data(contentsOf: fileURL), let list = try? JSONDecoder().decode([String].self, from: data) {
            order = Array(list.suffix(HomeSeen.maxEntries))
            set = Set(order)
        }
    }

    /// Everything shown before, plus the videos that were played (they are in the history).
    var ids: Set<String> {
        var all = set
        for h in Store.shared.history { all.insert(h.video.id) }
        return all
    }

    func mark(_ id: String) {
        if id.isEmpty || set.contains(id) { return }
        set.insert(id)
        order.append(id)
        if order.count > HomeSeen.maxEntries { set.remove(order.removeFirst()) }
        scheduleSave()
    }

    private func scheduleSave() {
        if saveScheduled { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self else { return }
            self.saveScheduled = false
            let list = self.order
            let url = self.fileURL
            DispatchQueue.global(qos: .utility).async {
                if let data = try? JSONEncoder().encode(list) { try? data.write(to: url, options: .atomic) }
            }
        }
    }
}
