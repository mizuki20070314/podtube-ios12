import UIKit
import AVFoundation

private final class ShortPlayerSurface: UIView {
    override class var layerClass: AnyClass { return AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { return layer as! AVPlayerLayer }
}

final class ShortCell: UICollectionViewCell {
    static let reuseId = "ShortCell"

    private let surface = ShortPlayerSurface()
    private let poster = UIImageView()
    private let gradient = CAGradientLayer()
    private let avatar = UIImageView()
    private let channelLabel = UILabel()
    private let subscribeButton = SubscribeButton()
    private let titleLabel = UILabel()
    private let likeButton = IconButton(icon: "thumb_up", size: 28, frame: CGRect(x: 0, y: 0, width: 52, height: 44))
    private let likeLabel = UILabel()
    private let commentButton = IconButton(icon: "video_library", size: 28, frame: CGRect(x: 0, y: 0, width: 52, height: 44))
    private let commentLabel = UILabel()
    private let shareButton = IconButton(icon: "share", size: 28, frame: CGRect(x: 0, y: 0, width: 52, height: 44))
    private let moreButton = IconButton(icon: "more_vert", size: 28, frame: CGRect(x: 0, y: 0, width: 52, height: 44))
    private let spinner = UIActivityIndicatorView(style: .whiteLarge)
    private let progress = UIView()
    private let pauseIcon = UIImageView(image: Icons.image("play_arrow", size: 64))

    private(set) var video: VideoItem?
    var onTap: (() -> Void)?
    var onChannel: (() -> Void)?
    var onComments: (() -> Void)?
    var onShare: (() -> Void)?
    var onMore: (() -> Void)?
    var onLike: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .black
        poster.contentMode = .scaleAspectFill
        poster.clipsToBounds = true
        surface.playerLayer.videoGravity = .resizeAspectFill
        gradient.colors = [UIColor.clear.cgColor, UIColor(white: 0, alpha: 0.7).cgColor]
        gradient.locations = [0.5, 1]
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = 18
        avatar.isUserInteractionEnabled = true
        avatar.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(channelTapped)))
        channelLabel.font = Theme.font(14, .semibold)
        channelLabel.textColor = .white
        channelLabel.isUserInteractionEnabled = true
        channelLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(channelTapped)))
        titleLabel.font = Theme.font(14)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        for l in [likeLabel, commentLabel] {
            l.font = Theme.font(12, .medium)
            l.textColor = .white
            l.textAlignment = .center
        }
        for b in [likeButton, commentButton, shareButton, moreButton] {
            b.tintColor = .white
            b.useThemeTint = false
        }
        spinner.color = .white
        spinner.hidesWhenStopped = true
        progress.backgroundColor = Theme.red
        pauseIcon.tintColor = UIColor(white: 1, alpha: 0.9)
        pauseIcon.contentMode = .center
        pauseIcon.isHidden = true

        contentView.addSubview(poster)
        contentView.addSubview(surface)
        contentView.layer.addSublayer(gradient)
        contentView.addSubviews([pauseIcon, avatar, channelLabel, subscribeButton, titleLabel, likeButton, likeLabel, commentButton,
                                 commentLabel, shareButton, moreButton, spinner, progress])
        subscribeButton.setSubscribed(false)
        likeButton.addTarget(self, action: #selector(likeTapped), for: .touchUpInside)
        commentButton.addTarget(self, action: #selector(commentsTapped), for: .touchUpInside)
        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        moreButton.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)
        subscribeButton.addTarget(self, action: #selector(subscribeTapped), for: .touchUpInside)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        contentView.addGestureRecognizer(tap)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func tapped() { onTap?() }
    @objc private func channelTapped() { onChannel?() }
    @objc private func commentsTapped() { onComments?() }
    @objc private func shareTapped() { onShare?() }
    @objc private func moreTapped() { onMore?() }
    @objc private func likeTapped() { onLike?(); refreshLike() }

    @objc private func subscribeTapped() {
        guard let v = video, !v.channelId.isEmpty else { return }
        if Store.shared.isSubscribed(v.channelId) {
            Store.shared.unsubscribe(v.channelId)
        } else {
            var c = ChannelItem(id: v.channelId)
            c.name = v.channelName
            c.avatar = v.channelAvatar
            Store.shared.subscribe(c)
        }
        subscribeButton.setSubscribed(Store.shared.isSubscribed(v.channelId))
    }

    private func refreshLike() {
        guard let v = video else { return }
        likeButton.setIcon(Store.shared.isLiked(v.id) ? "thumb_up" : "thumb_up_outline")
        likeButton.tintColor = Store.shared.isLiked(v.id) ? Theme.red : .white
    }

    func configure(video v: VideoItem, entry: ShortEntry?) {
        video = v
        poster.setRemote(v.thumbnail.isEmpty ? v.thumbnailURL?.absoluteString : v.thumbnail, maxPixel: 800, fade: false)
        let e = entry?.video
        let name = (e?.channelName.isEmpty == false ? e?.channelName : v.channelName) ?? ""
        channelLabel.text = name
        titleLabel.text = (e?.title.isEmpty == false ? e?.title : v.title) ?? ""
        let av = (e?.channelAvatar.isEmpty == false ? e?.channelAvatar : v.channelAvatar) ?? ""
        avatar.setRemote(av, maxPixel: 96, fade: false)
        avatar.isHidden = av.isEmpty
        likeLabel.text = entry?.likes ?? ""
        commentLabel.text = entry?.comments ?? ""
        let cid = (e?.channelId.isEmpty == false ? e?.channelId : v.channelId) ?? ""
        subscribeButton.isHidden = cid.isEmpty
        subscribeButton.setSubscribed(Store.shared.isSubscribed(cid))
        refreshLike()
        setNeedsLayout()
    }

    func attach(player: AVPlayer?) { surface.playerLayer.player = player }

    func setLoading(_ on: Bool) {
        if on { spinner.startAnimating() } else { spinner.stopAnimating() }
    }

    func setPaused(_ paused: Bool) { pauseIcon.isHidden = !paused }

    func setProgress(_ f: CGFloat) {
        progress.frame = CGRect(x: 0, y: contentView.bounds.height - 2, width: contentView.bounds.width * min(1, max(0, f)), height: 2)
    }

    func hidePoster(_ hide: Bool) { poster.isHidden = hide }

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = contentView.bounds
        poster.frame = b
        surface.frame = b
        gradient.frame = b
        pauseIcon.frame = CGRect(x: b.midX - 40, y: b.midY - 40, width: 80, height: 80)
        spinner.center = CGPoint(x: b.midX, y: b.midY)
        let rightX = b.width - 56
        var y = b.height - 360
        if y < 90 { y = 90 }
        likeButton.frame = CGRect(x: rightX, y: y, width: 52, height: 44)
        likeLabel.frame = CGRect(x: rightX, y: y + 42, width: 52, height: 16)
        y += 70
        commentButton.frame = CGRect(x: rightX, y: y, width: 52, height: 44)
        commentLabel.frame = CGRect(x: rightX, y: y + 42, width: 52, height: 16)
        y += 70
        shareButton.frame = CGRect(x: rightX, y: y, width: 52, height: 44)
        y += 56
        moreButton.frame = CGRect(x: rightX, y: y, width: 52, height: 44)

        let textW = b.width - 12 - 64
        let titleH = TextMetrics.height(titleLabel.text ?? "", font: Theme.font(14), width: textW, maxLines: 2)
        titleLabel.frame = CGRect(x: 12, y: b.height - 16 - titleH, width: textW, height: titleH)
        let rowY = titleLabel.frame.minY - 10 - 36
        avatar.frame = CGRect(x: 12, y: rowY, width: 36, height: 36)
        let sbw: CGFloat = subscribeButton.isHidden ? 0 : subscribeButton.sizeThatFits(.zero).width
        let nameWidth: CGFloat = ((channelLabel.text ?? "") as NSString).size(withAttributes: [.font: Theme.font(14, .semibold)]).width
        let maxName: CGFloat = max(40, textW - 44 - sbw - 18)
        let nw: CGFloat = min(nameWidth + 2, maxName)
        channelLabel.frame = CGRect(x: 56, y: rowY, width: nw, height: 36)
        subscribeButton.frame = CGRect(x: 56 + nw + 10, y: rowY + 1, width: sbw, height: 34)
        setProgress(0)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        poster.image = nil
        avatar.image = nil
        poster.isHidden = false
        attach(player: nil)
        pauseIcon.isHidden = true
        setLoading(false)
    }
}

final class ShortsViewController: UIViewController, HidesNavigationBar, ScrollsToTop,
                                  UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private let layout = UICollectionViewFlowLayout()
    private lazy var collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private let titleLabel = UILabel()
    private let searchButton = IconButton(icon: "search", size: 24)
    private let stateView = StateView()

    private var videos: [VideoItem] = []
    private var entries: [String: ShortEntry] = [:]
    private var infos: [String: PlaybackInfo] = [:]
    private var requested = Set<String>()
    private let player = AVPlayer()
    private var current = -1
    private var loadingSequence = false
    private var seedStarted = false
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var generation = 0
    private var pausedByUser = false

    override var preferredStatusBarStyle: UIStatusBarStyle { return .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        collection.backgroundColor = .black
        collection.isPagingEnabled = true
        collection.showsVerticalScrollIndicator = false
        collection.dataSource = self
        collection.delegate = self
        collection.register(ShortCell.self, forCellWithReuseIdentifier: ShortCell.reuseId)
        if #available(iOS 11.0, *) { collection.contentInsetAdjustmentBehavior = .never }
        view.addSubview(collection)
        titleLabel.text = L10n.t("shorts.title")
        titleLabel.font = Theme.font(20, .bold)
        titleLabel.textColor = .white
        searchButton.tintColor = .white
        searchButton.useThemeTint = false
        searchButton.addTarget(self, action: #selector(searchTapped), for: .touchUpInside)
        view.addSubviews([titleLabel, searchButton, stateView])
        stateView.isHidden = true
        stateView.onAction = { [weak self] in
            self?.seedStarted = false
            self?.seedFromHome()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(appBackgrounded),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { [weak self] _ in
            self?.tickProgress()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let t = timeObserver { player.removeTimeObserver(t) }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        var top: CGFloat = 0
        if #available(iOS 11.0, *) { top = view.safeAreaInsets.top }
        collection.frame = view.bounds
        let size = view.bounds.size
        if layout.itemSize != size {
            layout.itemSize = size
            layout.invalidateLayout()
        }
        titleLabel.frame = CGRect(x: 16, y: top + 10, width: 200, height: 30)
        searchButton.frame = CGRect(x: view.bounds.width - 52, y: top + 4, width: 44, height: 44)
        stateView.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        PlayerManager.shared.pause()
        if videos.isEmpty { seedFromHome() } else if !pausedByUser { playShort() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        player.pause()
    }

    func scrollToTop() {
        if !videos.isEmpty {
            collection.scrollToItem(at: IndexPath(item: 0, section: 0), at: .top, animated: true)
        }
    }

    @objc private func searchTapped() { Router.shared.root?.openSearchScreen() }

    @objc private func appBackgrounded() { player.pause() }

    private func playShort() {
        PlayerManager.shared.activateSession()
        player.play()
    }

    // MARK: Data

    /// Any video id works as a seed for YouTube's Shorts sequence, so the first home-feed video is used.
    private func seedFromHome() {
        if seedStarted { return }
        seedStarted = true
        stateView.showLoading()
        InnerTube.shared.home { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let page):
                    let shorts = page.videos.filter { $0.isShort }
                    if !shorts.isEmpty {
                        self.setVideos(shorts, start: 0)
                    }
                    let seed = shorts.last?.id ?? page.videos.first?.id
                    if let s = seed {
                        self.fetchSequence(seed: s, replaceIfEmpty: shorts.isEmpty)
                    } else if shorts.isEmpty {
                        self.showError("")
                    }
                case .failure(let e):
                    self.showError(e.localizedDescription)
                }
            }
        }
    }

    private func showError(_ text: String) {
        seedStarted = false
        stateView.show(icon: "cloud_off", title: L10n.t("common.error"), detail: text, button: L10n.t("common.retry"))
    }

    private func fetchSequence(seed: String, replaceIfEmpty: Bool) {
        if loadingSequence { return }
        loadingSequence = true
        InnerTube.shared.reelSequence(seed: seed) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.loadingSequence = false
                switch result {
                case .success(let ids):
                    let known = Set(self.videos.map { $0.id })
                    let fresh = ids.filter { !known.contains($0) }.map { id -> VideoItem in
                        var v = VideoItem(id: id)
                        v.isShort = true
                        return v
                    }
                    if self.videos.isEmpty {
                        self.setVideos(fresh, start: 0)
                    } else if !fresh.isEmpty {
                        let start = self.videos.count
                        self.videos.append(contentsOf: fresh)
                        self.collection.insertItems(at: (start..<self.videos.count).map { IndexPath(item: $0, section: 0) })
                    }
                    if self.videos.isEmpty { self.showError("") }
                case .failure(let e):
                    if self.videos.isEmpty { self.showError(e.localizedDescription) }
                }
            }
        }
    }

    func open(videos list: [VideoItem], startIndex: Int) {
        loadViewIfNeeded()
        seedStarted = true
        setVideos(list, start: startIndex)
        if let last = list.last { fetchSequence(seed: last.id, replaceIfEmpty: false) }
    }

    private func setVideos(_ list: [VideoItem], start: Int) {
        generation += 1
        videos = list
        entries = [:]
        current = -1
        collection.reloadData()
        stateView.isHidden = list.isEmpty ? stateView.isHidden : true
        if list.isEmpty { return }
        collection.layoutIfNeeded()
        let idx = max(0, min(start, list.count - 1))
        collection.scrollToItem(at: IndexPath(item: idx, section: 0), at: .top, animated: false)
        DispatchQueue.main.async { self.activate(idx) }
    }

    // MARK: Playback

    private func activate(_ index: Int) {
        guard index >= 0, index < videos.count, index != current else { return }
        current = index
        let v = videos[index]
        pausedByUser = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        detachObservers()
        if let cell = collection.cellForItem(at: IndexPath(item: index, section: 0)) as? ShortCell {
            cell.attach(player: nil)
            cell.setLoading(true)
            cell.hidePoster(false)
            cell.setPaused(false)
        }
        let gen = generation
        let vid = v.id
        loadDetails(for: v)
        loadInfo(for: vid) { [weak self] info in
            guard let self = self, gen == self.generation, self.current == index, let info = info else { return }
            PlayerManager.makeItem(for: info) { item in
                guard let item = item, self.current == index, gen == self.generation else { return }
                self.endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                    self?.player.seek(to: .zero)
                    self?.playShort()
                }
                self.player.replaceCurrentItem(with: item)
                if let cell = self.collection.cellForItem(at: IndexPath(item: index, section: 0)) as? ShortCell {
                    cell.attach(player: self.player)
                    cell.setLoading(false)
                }
                self.playShort()
                self.waitForFirstFrame(index: index, gen: gen)
            }
        }
        // warm the next one
        if index + 1 < videos.count { loadInfo(for: videos[index + 1].id) { _ in } }
        if index >= videos.count - 3, let last = videos.last { fetchSequence(seed: last.id, replaceIfEmpty: false) }
    }

    private func waitForFirstFrame(index: Int, gen: Int) {
        func check(_ tries: Int) {
            guard gen == generation, current == index else { return }
            if player.currentItem?.status == .readyToPlay && player.rate > 0 && player.currentTime().seconds > 0.05 {
                (collection.cellForItem(at: IndexPath(item: index, section: 0)) as? ShortCell)?.hidePoster(true)
                return
            }
            if tries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { check(tries - 1) }
            } else {
                (collection.cellForItem(at: IndexPath(item: index, section: 0)) as? ShortCell)?.hidePoster(true)
            }
        }
        check(40)
    }

    private func detachObservers() {
        if let o = endObserver {
            NotificationCenter.default.removeObserver(o)
            endObserver = nil
        }
    }

    private func loadInfo(for id: String, completion: @escaping (PlaybackInfo?) -> Void) {
        if let i = infos[id], Date().timeIntervalSince(i.fetchedAt) < 3600 {
            completion(i)
            return
        }
        InnerTube.shared.playback(videoId: id) { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let info) = result {
                    self?.infos[id] = info
                    completion(info)
                } else {
                    completion(nil)
                }
            }
        }
    }

    private func loadDetails(for v: VideoItem) {
        if entries[v.id] != nil || requested.contains(v.id) { return }
        requested.insert(v.id)
        InnerTube.shared.reelItem(videoId: v.id) { [weak self] result in
            guard case .success(let entry) = result else { return }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.entries[v.id] = entry
                if let i = self.videos.firstIndex(where: { $0.id == v.id }) {
                    var merged = self.videos[i]
                    if !entry.video.title.isEmpty { merged.title = entry.video.title }
                    if !entry.video.channelName.isEmpty { merged.channelName = entry.video.channelName }
                    if !entry.video.channelId.isEmpty { merged.channelId = entry.video.channelId }
                    if !entry.video.channelAvatar.isEmpty { merged.channelAvatar = entry.video.channelAvatar }
                    self.videos[i] = merged
                    if let cell = self.collection.cellForItem(at: IndexPath(item: i, section: 0)) as? ShortCell {
                        cell.configure(video: merged, entry: entry)
                    }
                }
            }
        }
    }

    private func tickProgress() {
        guard current >= 0, let cell = collection.cellForItem(at: IndexPath(item: current, section: 0)) as? ShortCell else { return }
        let d = player.currentItem?.duration.seconds ?? 0
        let t = player.currentTime().seconds
        if d.isFinite && d > 0 && t.isFinite { cell.setProgress(CGFloat(t / d)) }
    }

    // MARK: Paging

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let h = max(1, scrollView.bounds.height)
        activate(Int((scrollView.contentOffset.y / h).rounded()))
    }

    // MARK: Collection

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { return videos.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ShortCell.reuseId, for: indexPath) as! ShortCell
        let v = videos[indexPath.item]
        cell.configure(video: v, entry: entries[v.id])
        cell.onTap = { [weak self] in
            guard let self = self else { return }
            if self.player.rate > 0 {
                self.player.pause()
                self.pausedByUser = true
                cell.setPaused(true)
            } else {
                self.playShort()
                self.pausedByUser = false
                cell.setPaused(false)
            }
        }
        cell.onChannel = { Router.shared.openChannel(id: self.entries[v.id]?.video.channelId ?? v.channelId, name: v.channelName) }
        cell.onComments = { Router.shared.play(v) }
        cell.onShare = {
            if let url = URL(string: "https://youtube.com/shorts/\(v.id)") { Router.shared.share(items: [v.title, url]) }
        }
        cell.onMore = { Router.shared.showVideoMenu(v) }
        cell.onLike = { Store.shared.toggleLike(v) }
        if indexPath.item == current, player.currentItem != nil {
            cell.attach(player: player)
            cell.hidePoster(player.currentTime().seconds > 0.05)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if let c = cell as? ShortCell, indexPath.item != current { c.attach(player: nil) }
    }
}
