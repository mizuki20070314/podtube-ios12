import Foundation

/// Signed in, the history screens show the account's watch history. Plays of this app normally reach it too
/// (PlayHistoryReporter), but the report can be refused or still be on its way, so the recent plays of this app are
/// kept on the device and put in front of the account's entries here. The full history screen and the shelf on the
/// Library tab both take their list from `merge`, so they cannot disagree about the order.
enum HistoryMerge {
    /// `local` in front of `account`, without the ones the account already lists (anywhere in `account`, the
    /// videos of a run of Shorts included).
    static func merge(local: [VideoItem], account: [FeedItem]) -> [FeedItem] {
        var listed = Set<String>()
        for it in account {
            switch it {
            case .video(let v): listed.insert(v.id)
            case .shorts(let list): for v in list { listed.insert(v.id) }
            default: break
            }
        }
        return local.filter { !listed.contains($0.id) }.map { FeedItem.video($0) } + account
    }

    /// The shelf on the Library tab: the first `limit` videos of the very list `merge` gives the full history screen
    /// (a run of Shorts counts as the videos in it).
    static func shelf(local: [VideoItem], account: [FeedItem], limit: Int) -> [VideoItem] {
        var page = FeedPage()
        page.items = merge(local: local, account: account)
        return Array(page.videos.prefix(limit))
    }
}
