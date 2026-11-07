import Foundation

extension HistoryMerge {
    /// Only recent plays are added: the account's own entries stay the main content.
    static let days = 30
    static let limit = 40

    /// Videos played in this app lately, newest first. Main thread only (reads `Store`).
    static func recent() -> [VideoItem] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return Store.shared.history.filter { $0.watchedAt >= cutoff }.prefix(limit).map { $0.video }
    }
}
