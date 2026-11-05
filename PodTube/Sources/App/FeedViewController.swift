import UIKit

/// Base class for every screen that is a (paginated) list of videos / channels / playlists.
class FeedViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    let tableView = UITableView(frame: .zero, style: .plain)
    let stateView = StateView()
    private let refresher = UIRefreshControl()

    private(set) var items: [FeedItem] = []
    private(set) var continuation: String?
    /// Endpoint that produced the continuation tokens ("browse", "search", "next", or "tv" for the signed-in account).
    var continuationEndpoint = "browse"
    private var seen = Set<String>()
    private var loadingMore = false
    private var generation = 0
    private(set) var hasLoadedOnce = false

    // MARK: Subclass hooks

    var emptyTitle: String { return L10n.t("common.empty") }
    var emptyIcon: String { return "search" }
    var emptyDetail: String? { return nil }
    /// Optional button shown in the empty state (e.g. "Import").
    var emptyButton: String? { return nil }
    func emptyAction() {}
    private var stateIsError = false
    var showsRefreshControl: Bool { return true }
    /// Home / Subscriptions: every video row shows its channel icon (looked up when the feed does not carry it).
    var showsChannelAvatars: Bool { return false }
    private var avatarRefreshQueued = false
    /// Area (inside `view`) that the list occupies; subclasses reserve space for their own bars.
    var listFrame: CGRect { return view.bounds }
    /// Area used for the loading / empty / error state (defaults to the list area).
    var stateFrame: CGRect { return listFrame }

    func fetchFirstPage(_ done: @escaping (Result<FeedPage, Error>) -> Void) {
        done(.success(FeedPage()))
    }

    func didReceiveFirstPage(_ page: FeedPage) {}

    /// Extra entries for the "⋮" menu of a video row.
    func extraActions(for video: VideoItem) -> [SheetAction] { return [] }

    func play(_ video: VideoItem) {
        Router.shared.play(video)
    }

    func headerView(width: CGFloat) -> UIView? { return nil }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.estimatedRowHeight = 0
        tableView.estimatedSectionHeaderHeight = 0
        tableView.estimatedSectionFooterHeight = 0
        tableView.cellLayoutMarginsFollowReadableWidth = false
        tableView.register(VideoCell.self, forCellReuseIdentifier: VideoCell.reuseId)
        tableView.register(ChannelCell.self, forCellReuseIdentifier: ChannelCell.reuseId)
        tableView.register(PlaylistCell.self, forCellReuseIdentifier: PlaylistCell.reuseId)
        tableView.register(ShortsShelfCell.self, forCellReuseIdentifier: ShortsShelfCell.reuseId)
        tableView.register(LoadingCell.self, forCellReuseIdentifier: LoadingCell.reuseId)
        tableView.register(TextBlockCell.self, forCellReuseIdentifier: TextBlockCell.reuseId)
        view.addSubview(tableView)
        view.addSubview(stateView)
        stateView.isHidden = true
        if showsChannelAvatars {
            NotificationCenter.default.addObserver(self, selector: #selector(channelDirectoryChanged),
                                                   name: .channelDirectoryChanged, object: nil)
        }
        if #available(iOS 11.0, *) { tableView.contentInsetAdjustmentBehavior = .never }
        if showsRefreshControl {
            refresher.addTarget(self, action: #selector(pulled), for: .valueChanged)
            tableView.refreshControl = refresher
        }
        stateView.onAction = { [weak self] in
            guard let self = self else { return }
            if self.stateIsError { self.reload() } else { self.emptyAction() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .themeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .storeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(miniPlayerChanged), name: .miniPlayerChanged, object: nil)
        miniPlayerChanged()
    }

    @objc private func miniPlayerChanged() {
        var inset = Router.shared.root?.miniPlayerInset ?? 0
        inset += extraBottomInset
        tableView.contentInset.bottom = inset
        tableView.scrollIndicatorInsets.bottom = inset
    }

    /// Subclasses that sit under other bars can reserve additional space.
    var extraBottomInset: CGFloat { return 0 }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let f = listFrame
        if tableView.frame != f {
            tableView.frame = f
            tableView.reloadData()
        }
        stateView.frame = stateFrame
        if let h = tableView.tableHeaderView, h.frame.width != f.width {
            if let nh = headerView(width: f.width) { tableView.tableHeaderView = nh }
        }
    }

    @objc private func themeChanged() {
        view.backgroundColor = Theme.background
        tableView.reloadData()
    }

    @objc func storeChanged() {}

    @objc private func channelDirectoryChanged() {
        if avatarRefreshQueued { return }
        avatarRefreshQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.avatarRefreshQueued = false
            for ip in self.tableView.indexPathsForVisibleRows ?? [] where ip.row < self.items.count {
                if case .video(let v) = self.items[ip.row], let cell = self.tableView.cellForRow(at: ip) as? VideoCell {
                    cell.setAvatar(ChannelDirectory.shared.filled(v).channelAvatar)
                }
            }
        }
    }

    private func openChannel(of v: VideoItem) {
        ChannelDirectory.shared.owner(of: v) { ch in
            if let c = ch { Router.shared.openChannel(id: c.id, name: c.name) }
        }
    }

    @objc private func pulled() { reload() }

    // MARK: Loading

    func reload() {
        generation += 1
        let gen = generation
        loadingMore = false
        if items.isEmpty { stateView.showLoading() }
        fetchFirstPage { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, gen == self.generation else { return }
                self.refresher.endRefreshing()
                switch result {
                case .success(let page):
                    self.items = []
                    self.seen = []
                    self.continuation = nil
                    self.append(page)
                    self.hasLoadedOnce = true
                    self.didReceiveFirstPage(page)
                    if self.items.isEmpty {
                        self.stateIsError = false
                        self.stateView.show(icon: self.emptyIcon, title: self.emptyTitle, detail: self.emptyDetail, button: self.emptyButton)
                    } else {
                        self.stateView.hide()
                    }
                    self.tableView.reloadData()
                case .failure(let error):
                    if self.items.isEmpty {
                        self.stateIsError = true
                        self.stateView.show(icon: "cloud_off", title: L10n.t("common.error"),
                                            detail: error.localizedDescription, button: L10n.t("common.retry"))
                    }
                }
            }
        }
    }

    /// Empties the list (e.g. before switching to another chip / query) without touching the network.
    func clearList() {
        generation += 1
        items = []
        seen = []
        continuation = nil
        loadingMore = false
        tableView.reloadData()
        tableView.setContentOffset(.zero, animated: false)
    }

    /// Replace the content with an already available page (library screens etc.).
    func setPage(_ page: FeedPage) {
        generation += 1
        items = []
        seen = []
        continuation = nil
        append(page)
        hasLoadedOnce = true
        if items.isEmpty {
            stateIsError = false
            stateView.show(icon: emptyIcon, title: emptyTitle, detail: emptyDetail, button: emptyButton)
        } else {
            stateView.hide()
        }
        tableView.reloadData()
    }

    private func append(_ page: FeedPage) {
        for it in page.items {
            switch it {
            case .video(let v):
                if seen.contains(v.id) { continue }
                seen.insert(v.id)
                items.append(it)
            case .channel(let c):
                if seen.contains("c:" + c.id) { continue }
                seen.insert("c:" + c.id)
                items.append(it)
            case .playlist(let p):
                if seen.contains("p:" + p.id) { continue }
                seen.insert("p:" + p.id)
                items.append(it)
            case .shorts(let list):
                let fresh = list.filter { !seen.contains($0.id) }
                if fresh.isEmpty { continue }
                for v in fresh { seen.insert(v.id) }
                items.append(.shorts(fresh))
            case .text:
                items.append(it)
            }
        }
        continuation = page.continuation
    }

    /// Drops a video from the list (e.g. after it was removed from the account's Watch later list).
    func removeVideo(id: String) {
        items.removeAll {
            if case .video(let v) = $0 { return v.id == id }
            return false
        }
        seen.remove(id)
        tableView.reloadData()
    }

    func loadMore() {
        guard let token = continuation, !loadingMore else { return }
        loadingMore = true
        let gen = generation
        let handle: Done<FeedPage> = { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, gen == self.generation else { return }
                self.loadingMore = false
                switch result {
                case .success(let page):
                    let before = self.items.count
                    self.append(page)
                    // A page that adds nothing new would otherwise loop forever.
                    if self.items.count == before && page.continuation == token { self.continuation = nil }
                case .failure:
                    self.continuation = nil
                }
                self.tableView.reloadData()
            }
        }
        if continuationEndpoint == "tv" {
            InnerTube.shared.accountContinuation(token, handle)
        } else {
            InnerTube.shared.continuation(token, endpoint: continuationEndpoint, handle)
        }
    }

    // MARK: Data source

    var allVideos: [VideoItem] {
        var out: [VideoItem] = []
        for it in items { if case .video(let v) = it { out.append(v) } }
        return out
    }

    func numberOfSections(in tableView: UITableView) -> Int { return 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count + (continuation != nil ? 1 : 0)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let w = tableView.bounds.width
        if indexPath.row >= items.count { return 56 }
        switch items[indexPath.row] {
        case .video(let v): return VideoCell.height(for: v, width: w, reserveAvatar: showsChannelAvatars)
        case .channel: return ChannelCell.rowHeight
        case .playlist: return PlaylistCell.height(width: w)
        case .shorts: return ShortsShelfCell.height(width: w)
        case .text(let t): return TextBlockCell.height(t, width: w)
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.row >= items.count {
            let cell = tableView.dequeueReusableCell(withIdentifier: LoadingCell.reuseId, for: indexPath) as! LoadingCell
            cell.start()
            DispatchQueue.main.async { self.loadMore() }
            return cell
        }
        switch items[indexPath.row] {
        case .video(let item):
            let cell = tableView.dequeueReusableCell(withIdentifier: VideoCell.reuseId, for: indexPath) as! VideoCell
            let v = showsChannelAvatars ? ChannelDirectory.shared.filled(item) : item
            if showsChannelAvatars && v.channelAvatar.isEmpty { ChannelDirectory.shared.resolve(v) }
            cell.configure(v, reserveAvatar: showsChannelAvatars)
            cell.onMore = { [weak self] in
                guard let self = self else { return }
                Router.shared.showVideoMenu(v, extra: self.extraActions(for: v))
            }
            cell.onAvatar = { [weak self] in self?.openChannel(of: v) }
            return cell
        case .channel(let c):
            let cell = tableView.dequeueReusableCell(withIdentifier: ChannelCell.reuseId, for: indexPath) as! ChannelCell
            cell.configure(c)
            cell.onSubscribe = { [weak cell] in
                Account.shared.toggleSubscribe(c)
                cell?.subscribeButton.setSubscribed(Store.shared.isSubscribed(c.id))
            }
            return cell
        case .playlist(let p):
            let cell = tableView.dequeueReusableCell(withIdentifier: PlaylistCell.reuseId, for: indexPath) as! PlaylistCell
            cell.configure(p)
            return cell
        case .shorts(let list):
            let cell = tableView.dequeueReusableCell(withIdentifier: ShortsShelfCell.reuseId, for: indexPath) as! ShortsShelfCell
            cell.configure(list)
            cell.onSelect = { videos, index in Router.shared.openShorts(videos, index: index) }
            return cell
        case .text(let t):
            let cell = tableView.dequeueReusableCell(withIdentifier: TextBlockCell.reuseId, for: indexPath) as! TextBlockCell
            cell.configure(t)
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        if indexPath.row >= items.count { return }
        switch items[indexPath.row] {
        case .video(let v): play(v)
        case .channel(let c): Router.shared.openChannel(id: c.id, name: c.name)
        case .playlist(let p):
            if p.id.hasPrefix("RD") && p.id.count == 13 {
                // A Mix ("RD" + video id) cannot be browsed; play its seed video and let autoplay follow the related list.
                var seed = VideoItem(id: String(p.id.dropFirst(2)))
                seed.title = p.title
                seed.thumbnail = p.thumbnail
                Router.shared.play(seed)
            } else {
                Router.shared.openPlaylist(id: p.id, title: p.title)
            }
        case .shorts, .text: break
        }
    }
}
