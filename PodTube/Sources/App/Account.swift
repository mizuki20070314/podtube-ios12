import UIKit
import Security

extension Notification.Name {
    /// Signed in or out.
    static let accountChanged = Notification.Name("PodTubeAccountChanged")
    /// Name / avatar of the signed-in account changed.
    static let accountProfileChanged = Notification.Name("PodTubeAccountProfileChanged")
}

// MARK: - Token storage

/// Keeps the sign-in secrets in the Keychain. Installs that were signed without the Keychain entitlement
/// (some sideloading tools) reject Keychain writes, so the secrets then go to a protected file instead.
final class KeychainTokenStorage: TokenStorage {
    private let service = "com.podtube.ios12.google"
    private let account = "oauth"
    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("PodTube", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        fileURL = dir.appendingPathComponent("account.json")
    }

    private func baseQuery() -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    func load() -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
            return data
        }
        return try? Data(contentsOf: fileURL)
    }

    func save(_ data: Data) {
        var stored = false
        let update = SecItemUpdate(baseQuery() as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess {
            stored = true
        } else if update == errSecItemNotFound {
            var add = baseQuery()
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            stored = SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        if stored {
            try? FileManager.default.removeItem(at: fileURL)
        } else {
            try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
        try? FileManager.default.removeItem(at: fileURL)
    }
}

// MARK: - Account

/// App side of the Google sign-in: storage, notifications and the account actions (like, subscribe, save).
/// The local `Store` stays the source of truth for the UI; while signed in, each change is also sent to the account
/// and rolled back if YouTube refuses it.
final class Account {
    static let shared = Account()

    private var lastSignedIn = false
    private var playlistCache: [PlaylistItem]?

    var isSignedIn: Bool { return AuthSession.shared.isSignedIn }
    var profile: AccountProfile? { return AuthSession.shared.profile }

    func start() {
        AuthSession.shared.onChange = { [weak self] in self?.authChanged() }
        AuthSession.shared.storage = KeychainTokenStorage()
        lastSignedIn = isSignedIn
        if isSignedIn && profile == nil { refreshProfile() }
    }

    private func authChanged() {
        DispatchQueue.main.async {
            let now = AuthSession.shared.isSignedIn
            if now != self.lastSignedIn {
                self.lastSignedIn = now
                self.playlistCache = nil
                NotificationCenter.default.post(name: .accountChanged, object: nil)
            } else {
                NotificationCenter.default.post(name: .accountProfileChanged, object: nil)
            }
        }
    }

    func refreshProfile() {
        InnerTube.shared.accountProfile { r in
            if case .success(let p) = r { AuthSession.shared.updateProfile(p) }
        }
    }

    /// After the device code was approved: name / avatar and the channels that can be mirrored locally.
    func didSignIn() {
        refreshProfile()
        InnerTube.shared.accountSubscriptions { r in
            if case .success(let s) = r { DispatchQueue.main.async { Store.shared.mergeSubscriptions(s.channels) } }
        }
        InnerTube.shared.accountChannels { r in
            if case .success(let list) = r { DispatchQueue.main.async { Store.shared.mergeSubscriptions(list) } }
        }
    }

    func signOut() {
        AuthSession.shared.signOut()
    }

    // MARK: Actions

    private func rollback(_ undo: @escaping () -> Void) {
        DispatchQueue.main.async {
            undo()
            Toast.show(L10n.t("account.actionFailed"))
        }
    }

    func toggleLike(_ video: VideoItem) {
        setLike(video, Store.shared.isLiked(video.id) ? .none : .like)
    }

    func setLike(_ video: VideoItem, _ status: LikeStatus) {
        let before = Store.shared.isLiked(video.id)
        Store.shared.setLiked(video, status == .like)
        guard isSignedIn else { return }
        InnerTube.shared.setLike(videoId: video.id, status) { [weak self] r in
            if case .failure = r { self?.rollback { Store.shared.setLiked(video, before) } }
        }
    }

    func setSubscribed(_ channel: ChannelItem, _ on: Bool) {
        let before = Store.shared.isSubscribed(channel.id)
        if on { Store.shared.subscribe(channel) } else { Store.shared.unsubscribe(channel.id) }
        guard isSignedIn else { return }
        InnerTube.shared.setSubscribed(channelId: channel.id, on) { [weak self] r in
            if case .failure = r {
                self?.rollback {
                    if before { Store.shared.subscribe(channel) } else { Store.shared.unsubscribe(channel.id) }
                }
            }
        }
    }

    func toggleSubscribe(_ channel: ChannelItem) {
        setSubscribed(channel, !Store.shared.isSubscribed(channel.id))
    }

    func setWatchLater(_ video: VideoItem, _ on: Bool) {
        let before = Store.shared.isWatchLater(video.id)
        if before != on { Store.shared.toggleWatchLater(video) }
        guard isSignedIn else { return }
        InnerTube.shared.editPlaylist(id: "WL", videoId: video.id, add: on) { [weak self] r in
            if case .failure = r {
                self?.rollback { if Store.shared.isWatchLater(video.id) != before { Store.shared.toggleWatchLater(video) } }
            }
        }
    }

    func addToPlaylist(_ playlist: PlaylistItem, video: VideoItem) {
        InnerTube.shared.editPlaylist(id: playlist.id, videoId: video.id, add: true) { r in
            DispatchQueue.main.async {
                if case .failure = r {
                    Toast.show(L10n.t("account.actionFailed"))
                } else {
                    Toast.show(L10n.t("video.addedTo", playlist.title))
                }
            }
        }
    }

    // MARK: Playlists of the account

    var hasPlaylistCache: Bool { return playlistCache != nil }

    /// The account's own playlists (without "Watch later" / "Liked videos"), cached for the save sheet.
    func loadPlaylists(force: Bool = false, _ done: @escaping ([PlaylistItem]) -> Void) {
        if !force, let cached = playlistCache {
            done(cached)
            return
        }
        InnerTube.shared.accountBrowse("FEplaylist_aggregation") { [weak self] r in
            var list: [PlaylistItem] = []
            if case .success(let page) = r {
                for it in page.items {
                    if case .playlist(let p) = it, p.id != "WL", p.id != "LL" { list.append(p) }
                }
            }
            DispatchQueue.main.async {
                if case .success = r { self?.playlistCache = list }
                done(list)
            }
        }
    }

    // MARK: Watch page / history

    /// Applies what the account knows about a video (like state, subscription) to the local mirror.
    func loadWatchState(video: VideoItem, _ done: @escaping (AccountWatchState) -> Void) {
        guard isSignedIn else { return }
        InnerTube.shared.accountWatchState(videoId: video.id) { r in
            if case .success(let s) = r { DispatchQueue.main.async { done(s) } }
        }
    }

    /// Registers the view in the account's watch history (best effort, skipped while history is paused).
    func reportPlayback(_ info: PlaybackInfo) {
        guard isSignedIn, !Settings.pauseHistory, let url = info.statsURL else { return }
        InnerTube.shared.reportPlaybackStart(url)
    }
}
