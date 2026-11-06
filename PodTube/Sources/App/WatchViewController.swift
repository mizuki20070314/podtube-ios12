import UIKit
import AVFoundation

// MARK: - Content below the player

/// Title / actions / channel header plus the related-videos list.
final class WatchContentViewController: FeedViewController {
    let header = WatchHeaderView()
    private(set) var video: VideoItem?
    private var playlistId: String?
    private(set) var info: WatchInfo?
    private(set) var firstComments: CommentPage?
    var onOpenComments: (() -> Void)?
    var onSeek: ((Double) -> Void)?
    var onLoaded: ((VideoItem) -> Void)?

    override var showsRefreshControl: Bool { return false }

    override var stateFrame: CGRect {
        let h = header.frame.height
        let f = listFrame
        return CGRect(x: 0, y: min(f.height, h), width: f.width, height: max(0, f.height - h))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        header.onChannel = { [weak self] in
            guard let c = self?.header.video else { return }
            Router.shared.openChannel(id: c.channelId, name: c.channelName)
        }
        header.onOpenComments = { [weak self] in self?.onOpenComments?() }
        header.onSeek = { [weak self] s in self?.onSeek?(s) }
        header.onNeedsLayout = { [weak self] in self?.updateHeader() }
        tableView.tableHeaderView = header
    }

    func load(video v: VideoItem, playlistId pl: String?) {
        video = v
        playlistId = pl
        info = nil
        firstComments = nil
        clearList()
        header.configure(preview: v)
        updateHeader()
        reload()
    }

    override func headerView(width: CGFloat) -> UIView? {
        updateHeader()
        return header
    }

    func updateHeader() {
        let w = tableView.bounds.width > 0 ? tableView.bounds.width : view.bounds.width
        if w <= 0 { return }
        let h = header.layout(width: w)
        header.frame = CGRect(x: 0, y: 0, width: w, height: h)
        tableView.tableHeaderView = header
        view.setNeedsLayout()
    }

    override func fetchFirstPage(_ done: @escaping (Result<FeedPage, Error>) -> Void) {
        guard let v = video else {
            done(.success(FeedPage()))
            return
        }
        continuationEndpoint = "next"
        let vid = v.id
        InnerTube.shared.watch(videoId: vid, playlistId: playlistId) { [weak self] result in
            switch result {
            case .success(let w):
                DispatchQueue.main.async {
                    guard let self = self, self.video?.id == vid else { return }
                    self.apply(w)
                }
                var page = w.related
                if !w.queue.isEmpty {
                    let after = Array(w.queue.dropFirst(w.queueIndex + 1))
                    var items: [FeedItem] = after.map { FeedItem.video($0) }
                    items.append(contentsOf: page.items)
                    page.items = items
                }
                done(.success(page))
            case .failure(let e):
                done(.failure(e))
            }
        }
    }

    private func apply(_ w: WatchInfo) {
        info = w
        header.configure(info: w)
        updateHeader()
        if let merged = header.video {
            onLoaded?(merged)
            PlayerManager.shared.updateMetadata(merged)
            Store.shared.updateHistoryVideo(merged)
        }
        var next: [VideoItem] = []
        if let a = w.autoplay { next.append(a) }
        next.append(contentsOf: w.related.videos)
        PlayerManager.shared.upNext = next
        PlayerManager.shared.chapters = Chapters.parse(w.description)
        if !w.queue.isEmpty {
            PlayerManager.shared.adoptQueue(w.queue, currentId: w.videoId, playlistId: playlistId)
        }
        if let tok = w.commentsToken {
            InnerTube.shared.comments(token: tok) { [weak self] result in
                guard case .success(let page) = result else { return }
                DispatchQueue.main.async {
                    guard let self = self, self.video?.id == w.videoId else { return }
                    self.firstComments = page
                    self.header.configure(previewComment: page.comments.first)
                    self.updateHeader()
                }
            }
        }
        if let v = video {
            Account.shared.loadWatchState(video: v) { [weak self] state in
                guard let self = self, self.video?.id == v.id else { return }
                self.header.apply(account: state)
            }
        }
    }

    override func play(_ v: VideoItem) {
        // Related videos replace the current one in the same watch page.
        Router.shared.play(v)
    }
}

// MARK: - Mini player bar

final class MiniBarView: UIView {
    private let titleLabel = UILabel()
    private let channelLabel = UILabel()
    private let playButton = IconButton(icon: "pause", size: 26)
    private let closeButton = IconButton(icon: "close", size: 24)
    private let progress = UIView()
    private var timer: Timer?
    var onPlayPause: (() -> Void)?
    var onClose: (() -> Void)?

    static var videoWidth: CGFloat { return (WatchViewController.miniHeight * 16 / 9).rounded() }

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = Theme.font(14, .medium)
        channelLabel.font = Theme.font(12)
        progress.backgroundColor = Theme.red
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        addSubviews([titleLabel, channelLabel, playButton, closeButton, progress])
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(stateChanged), name: .playerChanged, object: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        timer?.invalidate()
        if window != nil {
            timer = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        }
    }

    @objc private func applyTheme() {
        backgroundColor = Theme.surface
        titleLabel.textColor = Theme.text
        channelLabel.textColor = Theme.secondaryText
        playButton.tintColor = Theme.text
        closeButton.tintColor = Theme.text
    }

    @objc private func stateChanged() {
        let playing = PlayerManager.shared.state == .playing || PlayerManager.shared.state == .buffering
        playButton.setIcon(playing ? "pause" : "play_arrow")
    }

    @objc private func tick() {
        let pm = PlayerManager.shared
        let d = pm.duration
        let f: CGFloat = d > 0 ? CGFloat(pm.currentTime / d) : 0
        progress.frame = CGRect(x: 0, y: 0, width: bounds.width * min(1, max(0, f)), height: 2)
    }

    @objc private func playTapped() { onPlayPause?() }
    @objc private func closeTapped() { onClose?() }

    func configure(_ v: VideoItem) {
        titleLabel.text = v.title
        channelLabel.text = v.channelName
        stateChanged()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let x = MiniBarView.videoWidth + 10
        let w = bounds.width
        closeButton.frame = CGRect(x: w - 48, y: (bounds.height - 44) / 2, width: 44, height: 44)
        playButton.frame = CGRect(x: w - 96, y: (bounds.height - 44) / 2, width: 44, height: 44)
        let tw = max(20, w - x - 100)
        titleLabel.frame = CGRect(x: x, y: 10, width: tw, height: 18)
        channelLabel.frame = CGRect(x: x, y: 29, width: tw, height: 16)
        tick()
    }
}

// MARK: - Watch container

/// The whole "now playing" surface. `progress` 0 = expanded (full screen), 1 = minimised (mini player).
final class WatchViewController: UIViewController, UIGestureRecognizerDelegate {
    static let miniHeight: CGFloat = 56

    private let topFill = UIView()
    private let miniBar = MiniBarView()
    private let content = WatchContentViewController()
    private let commentsHost = UIView()
    private let playerHost = UIView()
    private let playerView = PlayerView()
    private let controls = PlayerControlsView()
    private var comments: CommentsViewController?

    private(set) var progress: CGFloat = 0
    private var expandedFrame = CGRect.zero
    private var fullscreenMode = false
    private var miniFrame = CGRect.zero
    private var safeTop: CGFloat = 20
    private var panStart: CGFloat = 0

    private(set) var isActive = false
    var onClose: (() -> Void)?
    var onProgress: ((CGFloat) -> Void)?
    var onRequestLandscape: ((Bool) -> Void)?

    var isFullscreenLayout: Bool { return progress == 0 && fullscreenMode }
    var currentVideo: VideoItem? { return content.video }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        view.clipsToBounds = true
        topFill.backgroundColor = .black

        addChild(content)
        view.addSubview(miniBar)
        view.addSubview(content.view)
        content.didMove(toParent: self)
        view.addSubview(commentsHost)
        commentsHost.isHidden = true
        commentsHost.clipsToBounds = true
        view.addSubview(topFill)
        view.addSubview(playerHost)
        playerHost.backgroundColor = .black
        playerHost.clipsToBounds = true
        playerHost.addSubview(playerView)
        playerHost.addSubview(controls)

        content.onOpenComments = { [weak self] in self?.openComments() }
        content.onSeek = { seconds in PlayerManager.shared.seek(to: seconds) }
        content.onLoaded = { [weak self] v in self?.miniBar.configure(v) }
        miniBar.onPlayPause = { PlayerManager.shared.toggle() }
        miniBar.onClose = { [weak self] in self?.closePlayer() }
        controls.onCollapse = { [weak self] in self?.setMinimized(true, animated: true) }
        controls.onFullscreen = { [weak self] in
            guard let self = self else { return }
            self.onRequestLandscape?(!self.fullscreenMode)
        }
        controls.onSettings = { [weak self] in self?.showSettings() }
        controls.onCaptions = { [weak self] in self?.showCaptions() }
        controls.onPictureInPicture = { PictureInPicture.shared.toggle() }
        // PiP: once its window is up the watch screen steps aside; "back to app" in that window brings it back
        PictureInPicture.shared.bind(to: playerView.playerLayer)
        PictureInPicture.shared.onStarted = { [weak self] in self?.setMinimized(true, animated: true) }
        PictureInPicture.shared.onRestore = { [weak self] in self?.setMinimized(false, animated: true) }

        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tappedMini(_:)))
        tap.delegate = self
        view.addGestureRecognizer(tap)

        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .themeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(itemChanged), name: .playerItemChanged, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func themeChanged() {
        view.backgroundColor = Theme.background
        commentsHost.backgroundColor = Theme.background
    }

    @objc private func itemChanged() {
        let pm = PlayerManager.shared
        if let i = pm.info, i.videoId == pm.video?.id {
            SubtitleController.shared.setTracks(i.captions, videoId: i.videoId)
        }
        if let v = pm.video, v.id != content.video?.id, isActive {
            // The player moved on by itself (autoplay / queue): follow it.
            miniBar.configure(v)
            content.load(video: v, playlistId: pm.playlistId)
            hideComments()
        }
    }

    // MARK: Geometry (provided by the root controller)

    func updateGeometry(expanded: CGRect, mini: CGRect, safeTop: CGFloat, fullscreen: Bool) {
        expandedFrame = expanded
        fullscreenMode = fullscreen
        miniFrame = mini
        self.safeTop = safeTop
        applyProgress(progress)
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { return a + (b - a) * t }

    func applyProgress(_ p: CGFloat) {
        guard expandedFrame.width > 0 else { return }
        let W = expandedFrame.width
        let landscape = fullscreenMode
        let y = lerp(expandedFrame.minY, miniFrame.minY, p)
        let h = lerp(expandedFrame.height, miniFrame.height, p)
        view.frame = CGRect(x: lerp(expandedFrame.minX, miniFrame.minX, p), y: y, width: W, height: h)
        let b = view.bounds
        let top: CGFloat = landscape ? 0 : safeTop

        if p == 0 && landscape {
            playerHost.frame = b
            topFill.frame = .zero
        } else {
            let ex = CGRect(x: 0, y: top, width: W, height: (W * 9 / 16).rounded())
            let mn = CGRect(x: 0, y: 0, width: MiniBarView.videoWidth, height: WatchViewController.miniHeight)
            playerHost.frame = CGRect(x: lerp(ex.minX, mn.minX, p), y: lerp(ex.minY, mn.minY, p),
                                      width: lerp(ex.width, mn.width, p), height: lerp(ex.height, mn.height, p))
            topFill.frame = CGRect(x: 0, y: 0, width: W, height: max(0, top * (1 - p)))
        }
        playerView.frame = playerHost.bounds
        controls.frame = playerHost.bounds
        controls.alpha = max(0, 1 - p * 4)
        controls.isUserInteractionEnabled = p < 0.05
        controls.isFullscreen = (p == 0 && landscape)

        let contentTop = playerHost.frame.maxY
        content.view.frame = CGRect(x: 0, y: contentTop, width: W, height: max(0, b.height - contentTop))
        content.view.alpha = max(0, 1 - p * 3)
        commentsHost.frame = content.view.frame
        commentsHost.alpha = content.view.alpha
        comments?.view.frame = commentsHost.bounds
        miniBar.frame = CGRect(x: 0, y: 0, width: W, height: WatchViewController.miniHeight)
        miniBar.alpha = min(1, max(0, (p - 0.5) * 2))
    }

    // MARK: Presentation

    func start(video: VideoItem, queue: [VideoItem]?, playlistId: String?) {
        // a new video goes to the inline player, not to a PiP window left over from the old one
        PictureInPicture.shared.stop()
        let wasActive = isActive
        isActive = true
        view.isHidden = false
        hideComments()
        SubtitleController.shared.clear()
        miniBar.configure(video)
        content.load(video: video, playlistId: playlistId)
        PlayerManager.shared.play(video, queue: queue, playlistId: playlistId)
        if !wasActive || progress > 0.001 {
            progress = 0
            if !wasActive {
                view.frame = expandedFrame.offsetBy(dx: 0, dy: expandedFrame.height)
                UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut], animations: {
                    self.applyProgress(0)
                }, completion: { _ in self.onProgress?(0) })
            } else {
                UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseInOut], animations: {
                    self.applyProgress(0)
                }, completion: { _ in self.onProgress?(0) })
            }
        } else {
            onProgress?(0)
        }
    }

    func setMinimized(_ minimized: Bool, animated: Bool) {
        guard isActive else { return }
        if minimized && isFullscreenLayout {
            onRequestLandscape?(false)
        }
        let target: CGFloat = minimized ? 1 : 0
        progress = target
        let changes = { self.applyProgress(target) }
        if animated {
            UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseInOut, .allowUserInteraction], animations: changes,
                           completion: { _ in self.onProgress?(target) })
        } else {
            changes()
            onProgress?(target)
        }
    }

    func closePlayer() {
        PictureInPicture.shared.stop()
        PlayerManager.shared.stop()
        SubtitleController.shared.clear()
        isActive = false
        UIView.animate(withDuration: 0.22, animations: {
            self.view.frame = self.miniFrame.offsetBy(dx: 0, dy: self.miniFrame.height + 80)
        }, completion: { _ in
            self.view.isHidden = true
            self.progress = 0
            self.onClose?()
            self.onProgress?(1)
        })
    }

    // MARK: Gestures

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        if let pan = g as? UIPanGestureRecognizer {
            let v = pan.velocity(in: view)
            if abs(v.y) < abs(v.x) * 1.2 { return false }
            if progress < 0.02 {
                if fullscreenMode { return false }
                return pan.location(in: view).y <= playerHost.frame.maxY
            }
            return true
        }
        if g is UITapGestureRecognizer { return progress > 0.5 }
        return true
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var v: UIView? = touch.view
        while let cur = v, cur !== view {
            if cur is SeekBar { return false }
            v = cur.superview
        }
        if g is UITapGestureRecognizer, progress > 0.5 {
            var w: UIView? = touch.view
            while let cur = w, cur !== view {
                if cur is UIControl { return false }
                w = cur.superview
            }
        }
        return true
    }

    @objc private func tappedMini(_ g: UITapGestureRecognizer) {
        if progress > 0.5 { setMinimized(false, animated: true) }
    }

    @objc private func panned(_ g: UIPanGestureRecognizer) {
        let travel = max(1, miniFrame.minY - expandedFrame.minY)
        switch g.state {
        case .began:
            panStart = progress
        case .changed:
            let dy = g.translation(in: view.superview).y
            progress = min(1, max(0, panStart + dy / travel))
            applyProgress(progress)
        case .ended, .cancelled:
            let vy = g.velocity(in: view.superview).y
            var target: CGFloat = progress > 0.5 ? 1 : 0
            if vy > 700 { target = 1 } else if vy < -700 { target = 0 }
            setMinimized(target == 1, animated: true)
        default:
            break
        }
    }

    // MARK: Comments panel

    func openComments() {
        guard let info = content.info, let token = info.commentsToken else { return }
        hideComments()
        let vc = CommentsViewController(token: token, sortTokens: info.commentSortTokens, countText: info.commentCount,
                                        firstPage: content.firstComments)
        vc.onClose = { [weak self] in self?.hideComments(animated: true) }
        addChild(vc)
        commentsHost.addSubview(vc.view)
        vc.view.frame = commentsHost.bounds
        vc.didMove(toParent: self)
        comments = vc
        commentsHost.isHidden = false
        commentsHost.backgroundColor = Theme.background
        commentsHost.transform = CGAffineTransform(translationX: 0, y: commentsHost.frame.height)
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut], animations: {
            self.commentsHost.transform = .identity
        }, completion: nil)
    }

    private func hideComments(animated: Bool = false) {
        guard let vc = comments else { return }
        comments = nil
        let finish = {
            vc.willMove(toParent: nil)
            vc.view.removeFromSuperview()
            vc.removeFromParent()
            self.commentsHost.isHidden = true
            self.commentsHost.transform = .identity
        }
        if animated {
            UIView.animate(withDuration: 0.22, animations: {
                self.commentsHost.transform = CGAffineTransform(translationX: 0, y: self.commentsHost.frame.height)
            }, completion: { _ in finish() })
        } else {
            finish()
        }
    }

    /// Back button behaviour: close the comments panel first.
    func handleBack() -> Bool {
        if comments != nil {
            hideComments(animated: true)
            return true
        }
        return false
    }

    /// CI screenshot helper (see DebugRoutes).
    func debug(_ command: String) {
        switch command {
        case "controls": controls.debugShow()
        case "expand": content.header.expandDescription()
        case "captions":
            let sc = SubtitleController.shared
            if let t = sc.tracks.first(where: { $0.languageCode.hasPrefix("en") }) ?? sc.tracks.first { sc.select(t) }
        case "settings": showSettings()
        case "quality": showQuality()
        case "speed": showSpeed()
        case "seek60": PlayerManager.shared.seek(to: 60)
        case "chapters": showChapters()
        case "stats": PlayerManager.shared.showsStats = true
        case "pip": PictureInPicture.shared.start()
        default: break
        }
    }

    // MARK: Player menus

    private func qualityLabel(_ h: Int) -> String { return h == 0 ? L10n.t("player.auto") : "\(h)p" }

    private func showSettings() {
        let pm = PlayerManager.shared
        let acts = [
            SheetAction(title: L10n.t("player.quality"), icon: "hd", subtitle: qualityLabel(pm.maxHeight)) { [weak self] in self?.showQuality() },
            SheetAction(title: L10n.t("player.speed"), icon: "speed",
                        subtitle: pm.speed == 1 ? L10n.t("player.normal") : "\(pm.speed)x") { [weak self] in self?.showSpeed() },
            SheetAction(title: L10n.t("player.captions"), icon: "closed_caption",
                        subtitle: SubtitleController.shared.current?.name ?? L10n.t("player.captionsOff")) { [weak self] in self?.showCaptions() },
            SheetAction(title: L10n.t("player.loop"), icon: "repeat", checked: pm.loops) {
                pm.loops = !pm.loops
            },
            SheetAction(title: L10n.t("player.sleep"), icon: "timer",
                        subtitle: pm.sleepEndsAt != nil || pm.sleepAtEnd ? "●" : L10n.t("player.sleepOff")) { [weak self] in self?.showSleep() }
        ]
        var all = acts
        let audio = pm.audioOptions
        if audio.count > 1 {
            all.insert(SheetAction(title: L10n.t("player.audio"), icon: "audiotrack",
                                   subtitle: audio.first(where: { $0.isSelected })?.title) { [weak self] in
                self?.showAudioTracks()
            }, at: 3)
        }
        all.append(SheetAction(title: L10n.t("player.stats"), icon: "analytics", checked: pm.showsStats) {
            pm.showsStats = !pm.showsStats
        })
        if pm.chapters.count >= 2 {
            all.insert(SheetAction(title: L10n.t("player.chapters"), icon: "format_list_bulleted",
                                   subtitle: Chapters.current(pm.chapters, at: pm.currentTime)?.title) { [weak self] in
                self?.showChapters()
            }, at: 0)
        }
        SheetView.show(title: L10n.t("player.settings"), actions: all)
    }

    private func showChapters() {
        let pm = PlayerManager.shared
        let now = Chapters.current(pm.chapters, at: pm.currentTime)?.start
        let acts = pm.chapters.map { c in
            SheetAction(title: c.title, subtitle: Format.duration(c.start), checked: c.start == now) {
                pm.seek(to: c.start)
            }
        }
        SheetView.show(title: L10n.t("player.chapters"), actions: acts)
    }

    /// Only offered when the video has several audio tracks. "Automatic" follows the system language.
    private func showAudioTracks() {
        let pm = PlayerManager.shared
        let auto = Settings.preferredAudio.isEmpty
        var acts = [SheetAction(title: L10n.t("player.audioAuto"), checked: auto) { pm.selectAutomaticAudio() }]
        for o in pm.audioOptions {
            acts.append(SheetAction(title: o.title, checked: !auto && o.isSelected) { pm.selectAudio(o) })
        }
        SheetView.show(title: L10n.t("player.audio"), actions: acts)
    }

    private func showQuality() {
        let pm = PlayerManager.shared
        var options = [0, 1080, 720, 480, 360, 240, 144]
        if let m = pm.info?.maxHeight, m > 0 { options = options.filter { $0 == 0 || $0 <= max(m, 144) } }
        let acts = options.map { h in
            SheetAction(title: qualityLabel(h), checked: h == pm.maxHeight) {
                pm.setMaxHeight(h)
            }
        }
        SheetView.show(title: L10n.t("player.quality"), actions: acts)
    }

    private func showSpeed() {
        let pm = PlayerManager.shared
        let speeds: [Double] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
        let acts = speeds.map { s in
            SheetAction(title: s == 1 ? L10n.t("player.normal") : "\(s)x", checked: s == pm.speed) {
                pm.setSpeed(s)
            }
        }
        SheetView.show(title: L10n.t("player.speed"), actions: acts)
    }

    private func showCaptions() {
        let sc = SubtitleController.shared
        var acts: [SheetAction] = []
        acts.append(SheetAction(title: L10n.t("player.captionsOff"), checked: !sc.isEnabled) { sc.disable() })
        for t in sc.tracks {
            acts.append(SheetAction(title: t.name, checked: sc.current?.url == t.url) { sc.select(t) })
        }
        SheetView.show(title: L10n.t("player.captions"), actions: acts)
    }

    private func showSleep() {
        let pm = PlayerManager.shared
        var acts: [SheetAction] = [SheetAction(title: L10n.t("player.sleepOff")) { pm.setSleepTimer(minutes: nil) }]
        for m in [10, 15, 30, 45, 60] {
            acts.append(SheetAction(title: L10n.t("player.sleepMinutes", "\(m)")) { pm.setSleepTimer(minutes: m) })
        }
        acts.append(SheetAction(title: L10n.t("player.sleepEnd")) { pm.setSleepTimer(minutes: nil, atEnd: true) })
        SheetView.show(title: L10n.t("player.sleep"), actions: acts)
    }
}
