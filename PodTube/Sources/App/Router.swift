import UIKit

/// Navigation controller that keeps the swipe-back gesture working when the bar is hidden.
final class NavController: UINavigationController, UIGestureRecognizerDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
        Theme.style(navigationBar)
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .themeChanged, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func themeChanged() {
        Theme.style(navigationBar)
        view.backgroundColor = Theme.background
        setNeedsStatusBarAppearanceUpdate()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { return Theme.statusBarStyle }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return viewControllers.count > 1
    }
}

/// Central place that knows how to open videos, channels, playlists… from anywhere in the UI.
final class Router {
    static let shared = Router()

    weak var window: UIWindow?
    weak var root: RootViewController?

    // MARK: Playback

    func play(_ video: VideoItem, queue: [VideoItem]? = nil, playlistId: String? = nil) {
        root?.openWatch(video: video, queue: queue, playlistId: playlistId)
    }

    func openShorts(_ videos: [VideoItem], index: Int) {
        root?.openShorts(videos: videos, index: index)
    }

    // MARK: Pages

    func push(_ vc: UIViewController) {
        root?.pushOnCurrentTab(vc)
    }

    func openChannel(id: String, name: String? = nil) {
        if id.isEmpty { return }
        root?.minimizeWatchIfNeeded()
        push(ChannelViewController(channelId: id, name: name))
    }

    func openPlaylist(id: String, title: String? = nil) {
        root?.minimizeWatchIfNeeded()
        push(PlaylistViewController(playlistId: id, title: title))
    }

    func openSearch(query: String) {
        root?.minimizeWatchIfNeeded()
        Store.shared.addSearch(query)
        push(SearchResultsViewController(query: query))
    }

    func openSettings() {
        root?.minimizeWatchIfNeeded()
        push(SettingsViewController())
    }

    /// Opens whatever a pasted / shared link points at. Returns false when the text is not a YouTube link.
    @discardableResult
    func open(link text: String) -> Bool {
        guard let target = LinkParser.parse(text) else { return false }
        switch target {
        case .video(let id, let list):
            play(VideoItem(id: id), queue: nil, playlistId: list)
        case .playlist(let id):
            openPlaylist(id: id)
        case .channel(let id):
            openChannel(id: id)
        case .resolve(let url):
            InnerTube.shared.resolveChannel(url: url) { [weak self] result in
                DispatchQueue.main.async {
                    if case .success(let id) = result { self?.openChannel(id: id) } else { Toast.show(L10n.t("link.failed")) }
                }
            }
        }
        return true
    }

    // MARK: Menus

    func showVideoMenu(_ video: VideoItem, extra: [SheetAction] = []) {
        var actions: [SheetAction] = []
        let saved = Store.shared.isWatchLater(video.id)
        actions.append(SheetAction(title: saved ? L10n.t("video.removeWatchLater") : L10n.t("video.watchLater"),
                                   icon: "watch_later_outline") {
            Account.shared.setWatchLater(video, !saved)
            Toast.show(saved ? L10n.t("video.removed") : L10n.t("video.saved"))
        })
        actions.append(SheetAction(title: L10n.t("video.addToPlaylist"), icon: "playlist_add") { [weak self] in
            self?.showPlaylistPicker(for: video)
        })
        if !video.isLive && !video.isUpcoming {
            actions.append(SheetAction(title: L10n.t("video.download"), icon: "file_download") { [weak self] in
                self?.startDownload(video)
            })
        }
        if !video.channelId.isEmpty {
            actions.append(SheetAction(title: L10n.t("video.channel"), icon: "account_circle_outline") { [weak self] in
                self?.openChannel(id: video.channelId, name: video.channelName)
            })
        }
        actions.append(SheetAction(title: L10n.t("video.share"), icon: "share_outline") { [weak self] in
            self?.share(video: video)
        })
        actions.append(contentsOf: extra)
        SheetView.show(actions: actions)
    }

    func startDownload(_ video: VideoItem) {
        let dm = DownloadManager.shared
        if dm.record(for: video.id) != nil || dm.isDownloading(video.id) {
            Toast.show(L10n.t("downloads.already"))
            return
        }
        Toast.show(L10n.t("common.loading"))
        InnerTube.shared.playback(videoId: video.id) { result in
            DispatchQueue.main.async {
                guard case .success(let info) = result else {
                    Toast.show(L10n.t("downloads.failed"))
                    return
                }
                let heights = Array(Set(info.videoFormats.map { $0.height }.filter { $0 > 0 && $0 <= 1080 })).sorted(by: >)
                if heights.isEmpty || info.audioFormats.isEmpty {
                    Toast.show(L10n.t("downloads.unavailable"))
                    return
                }
                let audio = info.audioFormats.max(by: { $0.bitrate < $1.bitrate })?.contentLength ?? 0
                let actions = heights.map { h -> SheetAction in
                    let vbytes = info.videoFormats.filter { $0.height == h }.map { $0.contentLength }.max() ?? 0
                    let size = ByteCountFormatter.string(fromByteCount: vbytes + audio, countStyle: .file)
                    return SheetAction(title: "\(h)p", icon: "file_download", subtitle: size) {
                        dm.start(video: video, info: info, height: h)
                        Toast.show(L10n.t("downloads.started"))
                    }
                }
                SheetView.show(title: L10n.t("video.download"), actions: actions)
            }
        }
    }

    func showPlaylistPicker(for video: VideoItem) {
        guard Account.shared.isSignedIn else {
            presentPlaylistPicker(for: video, remote: [])
            return
        }
        if !Account.shared.hasPlaylistCache { Toast.show(L10n.t("common.loading")) }
        Account.shared.loadPlaylists { [weak self] list in
            self?.presentPlaylistPicker(for: video, remote: list)
        }
    }

    /// `remote`: the signed-in account's own playlists (adding is all the TV API offers, so they carry no check mark).
    private func presentPlaylistPicker(for video: VideoItem, remote: [PlaylistItem]) {
        var actions: [SheetAction] = []
        let later = Store.shared.isWatchLater(video.id)
        actions.append(SheetAction(title: L10n.t("video.watchLater"), icon: "watch_later_outline", checked: later) {
            Account.shared.setWatchLater(video, !later)
            Toast.show(later ? L10n.t("video.removed") : L10n.t("video.saved"))
        })
        for p in remote {
            actions.append(SheetAction(title: p.title, icon: "playlist_play", subtitle: p.videoCount.isEmpty ? nil : p.videoCount) {
                Account.shared.addToPlaylist(p, video: video)
            })
        }
        for p in Store.shared.playlists {
            let has = p.videos.contains { $0.id == video.id }
            actions.append(SheetAction(title: p.name, icon: "playlist_play", subtitle: "\(p.videos.count)", checked: has) {
                Store.shared.toggle(video, inPlaylist: p.id)
                Toast.show(has ? L10n.t("video.removedFrom", p.name) : L10n.t("video.addedTo", p.name))
            })
        }
        actions.append(SheetAction(title: L10n.t("video.newPlaylist"), icon: "add") { [weak self] in
            self?.promptNewPlaylist(video: video)
        })
        SheetView.show(title: L10n.t("video.save"), actions: actions)
    }

    func promptNewPlaylist(video: VideoItem?) {
        guard let host = root else { return }
        let alert = UIAlertController(title: L10n.t("video.newPlaylist"), message: nil, preferredStyle: .alert)
        alert.addTextField { tf in tf.placeholder = L10n.t("video.playlistName") }
        alert.addAction(UIAlertAction(title: L10n.t("common.cancel"), style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: L10n.t("common.create"), style: .default) { _ in
            let name = (alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespaces)
            if name.isEmpty { return }
            let p = Store.shared.createPlaylist(name: name, with: video)
            if video != nil { Toast.show(L10n.t("video.addedTo", p.name)) }
        })
        host.present(alert, animated: true, completion: nil)
    }

    func share(video: VideoItem) {
        guard let url = URL(string: "https://youtu.be/\(video.id)") else { return }
        share(items: [video.title, url])
    }

    func share(items: [Any]) {
        guard let host = root else { return }
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let pop = vc.popoverPresentationController {
            // required on an iPad (crashes without a source); phones ignore it
            pop.sourceView = host.view
            pop.sourceRect = CGRect(x: host.view.bounds.midX, y: host.view.bounds.maxY - 1, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        host.present(vc, animated: true, completion: nil)
    }
}
