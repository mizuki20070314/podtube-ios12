import UIKit

// MARK: - Stored lists (history, watch later, liked, user playlists)

enum StoredKind {
    case history
    case watchLater
    case liked
    case playlist(String)
}

final class StoredListViewController: FeedViewController {
    private let kind: StoredKind

    init(kind: StoredKind) {
        self.kind = kind
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var showsRefreshControl: Bool { return false }

    override var showsChannelAvatars: Bool {
        if case .history = kind { return true }
        return false
    }

    override var emptyTitle: String {
        switch kind {
        case .history: return L10n.t("library.emptyHistory")
        default: return L10n.t("common.empty")
        }
    }

    private var videos: [VideoItem] {
        switch kind {
        case .history: return Store.shared.history.map { $0.video }
        case .watchLater: return Store.shared.watchLater
        case .liked: return Store.shared.liked
        case .playlist(let id): return Store.shared.playlists.first(where: { $0.id == id })?.videos ?? []
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        switch kind {
        case .history: title = L10n.t("library.history")
        case .watchLater: title = L10n.t("library.watchLater")
        case .liked: title = L10n.t("library.liked")
        case .playlist(let id): title = Store.shared.playlists.first(where: { $0.id == id })?.name
        }
        if case .history = kind {
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: L10n.t("common.delete"), style: .plain, target: self, action: #selector(clearTapped))
        }
        rebuild()
    }

    @objc private func clearTapped() {
        let alert = UIAlertController(title: L10n.t("library.confirmClear"), message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.t("common.cancel"), style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: L10n.t("common.delete"), style: .destructive) { _ in Store.shared.clearHistory() })
        present(alert, animated: true, completion: nil)
    }

    private func rebuild() {
        var page = FeedPage()
        page.items = videos.map { FeedItem.video($0) }
        setPage(page)
    }

    override func storeChanged() {
        if isViewLoaded { rebuild() }
    }

    override func play(_ video: VideoItem) {
        switch kind {
        case .playlist, .watchLater, .liked:
            Router.shared.play(video, queue: allVideos, playlistId: nil)
        case .history:
            Router.shared.play(video)
        }
    }

    override func extraActions(for video: VideoItem) -> [SheetAction] {
        switch kind {
        case .history:
            return [SheetAction(title: L10n.t("video.notInterested"), icon: "delete") { Store.shared.removeHistory(video.id) }]
        case .playlist(let id):
            return [SheetAction(title: L10n.t("common.delete"), icon: "delete") { Store.shared.remove(videoId: video.id, fromPlaylist: id) }]
        case .liked:
            return [SheetAction(title: L10n.t("common.delete"), icon: "delete") { Store.shared.toggleLike(video) }]
        case .watchLater:
            return []
        }
    }
}

/// The user's own (local) playlists.
final class UserPlaylistsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let table = UITableView(frame: .zero, style: .plain)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.t("library.playlists")
        view.backgroundColor = Theme.background
        table.dataSource = self
        table.delegate = self
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.rowHeight = 64
        view.addSubview(table)
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addTapped))
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .storeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .themeChanged, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        table.frame = view.bounds
    }

    @objc private func refresh() {
        view.backgroundColor = Theme.background
        table.reloadData()
    }

    @objc private func addTapped() { Router.shared.promptNewPlaylist(video: nil) }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { return Store.shared.playlists.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let id = "PL"
        let cell = tableView.dequeueReusableCell(withIdentifier: id) ?? UITableViewCell(style: .subtitle, reuseIdentifier: id)
        let p = Store.shared.playlists[indexPath.row]
        cell.backgroundColor = .clear
        cell.textLabel?.text = p.name
        cell.textLabel?.textColor = Theme.text
        cell.textLabel?.font = Theme.font(16, .medium)
        cell.detailTextLabel?.text = "\(p.videos.count)"
        cell.detailTextLabel?.textColor = Theme.secondaryText
        cell.imageView?.image = Icons.image("playlist_play", size: 28)
        cell.imageView?.tintColor = Theme.text
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(StoredListViewController(kind: .playlist(Store.shared.playlists[indexPath.row].id)), animated: true)
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool { return true }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            Store.shared.deletePlaylist(Store.shared.playlists[indexPath.row].id)
        }
    }
}

// MARK: - Library ("You") tab

final class VideoShelfCell: UITableViewCell, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    static let reuseId = "VideoShelfCell"
    static let cardWidth: CGFloat = 160
    static let height: CGFloat = 44 + 90 + 6 + 36 + 18 + 12

    private let header = UILabel()
    private let action = UIButton(type: .system)
    private let layout = UICollectionViewFlowLayout()
    private lazy var collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private var videos: [VideoItem] = []
    var onSelect: ((VideoItem) -> Void)?
    var onAction: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        header.font = Theme.font(18, .bold)
        action.titleLabel?.font = Theme.font(14, .medium)
        action.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 10
        layout.sectionInset = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        collection.backgroundColor = .clear
        collection.showsHorizontalScrollIndicator = false
        collection.dataSource = self
        collection.delegate = self
        collection.register(HistoryCardCell.self, forCellWithReuseIdentifier: HistoryCardCell.reuseId)
        contentView.addSubviews([header, action, collection])
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func actionTapped() { onAction?() }

    func configure(title: String, actionTitle: String, videos list: [VideoItem]) {
        header.text = title
        header.textColor = Theme.text
        action.setTitle(actionTitle, for: .normal)
        action.setTitleColor(Theme.link, for: .normal)
        videos = list
        collection.reloadData()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = contentView.bounds.width
        let bw = action.sizeThatFits(CGSize(width: 200, height: 30)).width + 12
        action.frame = CGRect(x: w - bw - 8, y: 4, width: bw, height: 36)
        header.frame = CGRect(x: 12, y: 4, width: w - bw - 24, height: 36)
        collection.frame = CGRect(x: 0, y: 44, width: w, height: VideoShelfCell.height - 44 - 4)
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { return videos.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: HistoryCardCell.reuseId, for: indexPath) as! HistoryCardCell
        cell.configure(videos[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: VideoShelfCell.cardWidth, height: collectionView.bounds.height)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect?(videos[indexPath.item])
    }
}

final class HistoryCardCell: UICollectionViewCell {
    static let reuseId = "HistoryCardCell"
    private let thumb = UIImageView()
    private let duration = PaddedLabel()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let progress = UIView()
    private var fraction: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        thumb.contentMode = .scaleAspectFill
        thumb.clipsToBounds = true
        thumb.layer.cornerRadius = 8
        duration.font = Theme.font(11, .semibold)
        duration.textColor = .white
        duration.backgroundColor = UIColor(white: 0, alpha: 0.8)
        duration.layer.cornerRadius = 3
        duration.clipsToBounds = true
        duration.insets = UIEdgeInsets(top: 1, left: 4, bottom: 1, right: 4)
        titleLabel.font = Theme.font(13, .medium)
        titleLabel.numberOfLines = 2
        metaLabel.font = Theme.font(11)
        progress.backgroundColor = Theme.red
        contentView.addSubviews([thumb, duration, progress, titleLabel, metaLabel])
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ v: VideoItem) {
        thumb.backgroundColor = Theme.thumbPlaceholder
        thumb.setRemote(v.thumbnail.isEmpty ? v.thumbnailURL?.absoluteString : v.thumbnail, maxPixel: 400)
        duration.text = v.duration
        duration.isHidden = v.duration.isEmpty
        titleLabel.text = v.title
        titleLabel.textColor = Theme.text
        metaLabel.text = v.channelName
        metaLabel.textColor = Theme.secondaryText
        if let pct = v.watchedPercent {
            fraction = CGFloat(pct) / 100
        } else {
            fraction = CGFloat(Store.shared.progress(for: v.id) ?? 0)
        }
        progress.isHidden = fraction <= 0.01
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = contentView.bounds.width
        thumb.frame = CGRect(x: 0, y: 0, width: w, height: 90)
        let ds = duration.sizeThatFits(CGSize(width: w, height: 20))
        duration.frame = CGRect(x: w - ds.width - 6, y: 90 - ds.height - 6, width: ds.width, height: ds.height)
        progress.frame = CGRect(x: 0, y: 88, width: w * fraction, height: 2)
        titleLabel.frame = CGRect(x: 0, y: 96, width: w, height: 34)
        metaLabel.frame = CGRect(x: 0, y: 132, width: w, height: 14)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumb.image = nil
    }
}

final class LibraryRowCell: UITableViewCell {
    static let reuseId = "LibraryRowCell"
    private let icon = UIImageView()
    private let titleLabel = UILabel()
    private let countLabel = UILabel()
    private let chevron = UIImageView(image: Icons.image("chevron_right", size: 22))

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        icon.contentMode = .center
        titleLabel.font = Theme.font(16)
        countLabel.font = Theme.font(14)
        countLabel.textAlignment = .right
        contentView.addSubviews([icon, titleLabel, countLabel, chevron])
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(icon name: String, title: String, count: String?) {
        icon.image = Icons.image(name, size: 24)
        icon.tintColor = Theme.text
        titleLabel.text = title
        titleLabel.textColor = Theme.text
        countLabel.text = count
        countLabel.textColor = Theme.secondaryText
        chevron.tintColor = Theme.secondaryText
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = contentView.bounds.width
        let h = contentView.bounds.height
        icon.frame = CGRect(x: 12, y: (h - 28) / 2, width: 28, height: 28)
        chevron.frame = CGRect(x: w - 36, y: (h - 22) / 2, width: 22, height: 22)
        countLabel.frame = CGRect(x: w - 36 - 80, y: 0, width: 76, height: h)
        titleLabel.frame = CGRect(x: 60, y: 0, width: w - 60 - 120, height: h)
    }
}

final class LibraryViewController: UIViewController, HidesNavigationBar, ScrollsToTop, UITableViewDataSource, UITableViewDelegate {
    private let titleLabel = UILabel()
    private let searchButton = IconButton(icon: "search")
    private let settingsButton = IconButton(icon: "settings_outline")
    private let bar = UIView()
    private let divider = UIView()
    private let table = UITableView(frame: .zero, style: .plain)

    private struct Row {
        let icon: String
        let title: String
        let count: String?
        let action: () -> Void
    }

    private var rows: [Row] = []
    private let accountHeader = AccountHeaderView()
    /// First page of the signed-in account's history, the list the full history screen starts from; the first shelf
    /// is made of it (kept between visits to avoid flicker).
    private var accountHistory: [FeedItem] = []
    private var accountHistoryLoaded = Date.distantPast

    private var signedIn: Bool { return Account.shared.isSignedIn }

    override func viewDidLoad() {
        super.viewDidLoad()
        titleLabel.text = L10n.t("tab.you")
        titleLabel.font = Theme.font(22, .bold)
        searchButton.addTarget(self, action: #selector(searchTapped), for: .touchUpInside)
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        table.dataSource = self
        table.delegate = self
        table.separatorStyle = .none
        table.backgroundColor = .clear
        table.estimatedRowHeight = 0
        table.register(VideoShelfCell.self, forCellReuseIdentifier: VideoShelfCell.reuseId)
        table.register(LibraryRowCell.self, forCellReuseIdentifier: LibraryRowCell.reuseId)
        if #available(iOS 11.0, *) { table.contentInsetAdjustmentBehavior = .never }
        accountHeader.frame = CGRect(x: 0, y: 0, width: 320, height: AccountHeaderView.height)
        accountHeader.addTarget(self, action: #selector(accountTapped), for: .touchUpInside)
        table.tableHeaderView = accountHeader
        view.addSubview(table)
        view.addSubview(bar)
        bar.addSubviews([titleLabel, searchButton, settingsButton, divider])
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(accountChanged), name: .accountChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .accountProfileChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .storeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .downloadsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .settingsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(miniChanged), name: .miniPlayerChanged, object: nil)
        rebuildRows()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func applyTheme() {
        view.backgroundColor = Theme.background
        bar.backgroundColor = Theme.background
        titleLabel.textColor = Theme.text
        titleLabel.text = L10n.t("tab.you")
        divider.backgroundColor = Theme.divider
        rebuildRows()
        table.reloadData()
    }

    @objc private func refresh() {
        accountHeader.refresh()
        rebuildRows()
        table.reloadData()
    }

    @objc private func accountChanged() {
        accountHistory = []
        accountHistoryLoaded = .distantPast
        refresh()
        loadAccountHistory()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadAccountHistory()
    }

    private func loadAccountHistory() {
        guard signedIn, Date().timeIntervalSince(accountHistoryLoaded) > 120 else { return }
        accountHistoryLoaded = Date()
        InnerTube.shared.accountBrowse("FEhistory") { [weak self] r in
            guard case .success(let page) = r else { return }
            DispatchQueue.main.async {
                guard let self = self, self.signedIn else { return }
                self.accountHistory = page.items
                self.table.reloadData()
            }
        }
    }

    @objc private func accountTapped() {
        if signedIn {
            let name = Account.shared.profile?.name ?? L10n.t("account.signedIn")
            SheetView.show(title: name, actions: [
                SheetAction(title: L10n.t("account.signOut"), icon: "logout", destructive: true) { Account.shared.signOut() }
            ])
        } else {
            Router.shared.push(SignInViewController())
        }
    }

    @objc private func miniChanged() {
        let inset = Router.shared.root?.miniPlayerInset ?? 0
        table.contentInset.bottom = inset
        table.scrollIndicatorInsets.bottom = inset
    }

    func scrollToTop() { table.setContentOffset(.zero, animated: true) }

    /// Same entries as below, but backed by the signed-in account instead of the device.
    private func accountRows() -> [Row] {
        let dm = DownloadManager.shared
        let downloads = dm.records.count + dm.pending.count
        return [
            Row(icon: "history", title: L10n.t("library.history"), count: nil) {
                Router.shared.push(AccountListViewController(kind: .history))
            },
            Row(icon: "file_download", title: L10n.t("library.downloads"), count: downloads == 0 ? nil : "\(downloads)") {
                Router.shared.push(DownloadsViewController())
            },
            Row(icon: "playlist_play", title: L10n.t("library.playlists"), count: nil) {
                Router.shared.push(AccountListViewController(kind: .playlists))
            },
            Row(icon: "watch_later_outline", title: L10n.t("library.watchLater"), count: nil) {
                Router.shared.push(AccountListViewController(kind: .watchLater))
            },
            Row(icon: "thumb_up_outline", title: L10n.t("library.liked"), count: nil) {
                Router.shared.push(AccountListViewController(kind: .liked))
            },
            Row(icon: "settings_outline", title: L10n.t("library.settings"), count: nil) {
                Router.shared.openSettings()
            }
        ]
    }

    private func rebuildRows() {
        if signedIn {
            rows = accountRows()
            return
        }
        let s = Store.shared
        rows = [
            Row(icon: "history", title: L10n.t("library.history"), count: s.history.isEmpty ? nil : "\(s.history.count)") {
                Router.shared.push(StoredListViewController(kind: .history))
            },
            Row(icon: "file_download", title: L10n.t("library.downloads"),
                count: (DownloadManager.shared.records.count + DownloadManager.shared.pending.count) == 0
                    ? nil : "\(DownloadManager.shared.records.count + DownloadManager.shared.pending.count)") {
                Router.shared.push(DownloadsViewController())
            },
            Row(icon: "playlist_play", title: L10n.t("library.playlists"), count: s.playlists.isEmpty ? nil : "\(s.playlists.count)") {
                Router.shared.push(UserPlaylistsViewController())
            },
            Row(icon: "watch_later_outline", title: L10n.t("library.watchLater"), count: s.watchLater.isEmpty ? nil : "\(s.watchLater.count)") {
                Router.shared.push(StoredListViewController(kind: .watchLater))
            },
            Row(icon: "thumb_up_outline", title: L10n.t("library.liked"), count: s.liked.isEmpty ? nil : "\(s.liked.count)") {
                Router.shared.push(StoredListViewController(kind: .liked))
            },
            Row(icon: "settings_outline", title: L10n.t("library.settings"), count: nil) {
                Router.shared.openSettings()
            }
        ]
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        var top: CGFloat = 0
        if #available(iOS 11.0, *) { top = view.safeAreaInsets.top }
        let h = top + AppBarView.contentHeight
        bar.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: h)
        titleLabel.frame = CGRect(x: 16, y: top, width: 200, height: AppBarView.contentHeight)
        settingsButton.frame = CGRect(x: view.bounds.width - 48, y: top + 6, width: 44, height: 44)
        searchButton.frame = CGRect(x: view.bounds.width - 96, y: top + 6, width: 44, height: 44)
        divider.frame = CGRect(x: 0, y: h - 0.5, width: view.bounds.width, height: 0.5)
        table.frame = CGRect(x: 0, y: h, width: view.bounds.width, height: view.bounds.height - h)
        if accountHeader.frame.width != view.bounds.width {
            accountHeader.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: AccountHeaderView.height)
            table.tableHeaderView = accountHeader
        }
    }

    @objc private func searchTapped() { Router.shared.root?.openSearchScreen() }
    @objc private func settingsTapped() { Router.shared.openSettings() }

    // MARK: Table

    private var shelfVideos: [VideoItem] {
        if signedIn { return HistoryMerge.shelf(local: HistoryMerge.recent(), account: accountHistory, limit: 12) }
        return Array(Store.shared.history.prefix(12)).map { $0.video }
    }

    private var hasHistoryShelf: Bool { return !shelfVideos.isEmpty }

    func numberOfSections(in tableView: UITableView) -> Int { return 2 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 { return hasHistoryShelf ? 1 : 0 }
        return rows.count
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return indexPath.section == 0 ? VideoShelfCell.height : 56
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: VideoShelfCell.reuseId, for: indexPath) as! VideoShelfCell
            cell.configure(title: L10n.t("library.history"), actionTitle: L10n.t("library.viewAll"), videos: shelfVideos)
            cell.onSelect = { v in Router.shared.play(v) }
            cell.onAction = { [weak self] in
                if self?.signedIn == true {
                    Router.shared.push(AccountListViewController(kind: .history))
                } else {
                    Router.shared.push(StoredListViewController(kind: .history))
                }
            }
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: LibraryRowCell.reuseId, for: indexPath) as! LibraryRowCell
        let r = rows[indexPath.row]
        cell.configure(icon: r.icon, title: r.title, count: r.count)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        if indexPath.section == 1 { rows[indexPath.row].action() }
    }
}
