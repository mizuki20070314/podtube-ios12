import Foundation

/// Signed in, the history screens show the account's watch history. YouTube cannot be told about what is played in
/// this app (the playback ping needs a player response made under the account, and the TV client's player request is
/// refused: see README), so those videos never reach the account's history. They are kept on the device and put in
/// front of the account's entries here. Main thread only (reads `Store`).
enum HistoryMerge {
    /// Only recent plays are added: the account's own entries stay the main content.
    static let days = 30
    static let limit = 40

    /// Videos played in this app lately, newest first.
    static func recent() -> [VideoItem] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return Store.shared.history.filter { $0.watchedAt >= cutoff }.prefix(limit).map { $0.video }
    }

    /// `local` in front of `account`, without the ones the account already lists.
    static func merge(local: [VideoItem], account: [FeedItem]) -> [FeedItem] {
        var listed = Set<String>()
        for it in account {
            if case .video(let v) = it { listed.insert(v.id) }
        }
        return local.filter { !listed.contains($0.id) }.map { FeedItem.video($0) } + account
    }

    /// The same for a short shelf of videos.
    static func merge(local: [VideoItem], account: [VideoItem], limit: Int) -> [VideoItem] {
        let listed = Set(account.map { $0.id })
        return Array((local.filter { !listed.contains($0.id) } + account).prefix(limit))
    }
}
