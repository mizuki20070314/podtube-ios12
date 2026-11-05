import UIKit

/// Horizontal strip of subscribed channel avatars.
final class ChannelStripView: UIView {
    private let scroll = UIScrollView()
    private let divider = UIView()
    private var channels: [ChannelItem] = []
    var onChannel: ((ChannelItem) -> Void)?
    var onAll: (() -> Void)?

    static let height: CGFloat = 96

    override init(frame: CGRect) {
        super.init(frame: frame)
        scroll.showsHorizontalScrollIndicator = false
        addSubview(scroll)
        addSubview(divider)
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeChanged, object: nil)
        applyTheme()
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func applyTheme() {
        backgroundColor = Theme.background
        divider.backgroundColor = Theme.divider
        rebuild()
    }

    func setChannels(_ list: [ChannelItem]) {
        channels = list
        rebuild()
    }

    private func rebuild() {
        scroll.subviews.forEach { $0.removeFromSuperview() }
        var x: CGFloat = 8
        for (i, c) in channels.enumerated() {
            let item = UIControl(frame: CGRect(x: x, y: 0, width: 72, height: ChannelStripView.height - 1))
            item.tag = i
            item.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            let iv = UIImageView(frame: CGRect(x: 8, y: 10, width: 56, height: 56))
            iv.layer.cornerRadius = 28
            iv.clipsToBounds = true
            iv.contentMode = .scaleAspectFill
            iv.backgroundColor = Theme.surface
            iv.isUserInteractionEnabled = false
            iv.setRemote(c.avatar, maxPixel: 120, fade: false)
            let l = UILabel(frame: CGRect(x: 2, y: 70, width: 68, height: 16))
            l.font = Theme.font(11)
            l.textColor = Theme.text
            l.textAlignment = .center
            l.text = c.name
            l.isUserInteractionEnabled = false
            item.addSubview(iv)
            item.addSubview(l)
            scroll.addSubview(item)
            x += 72
        }
        let all = UIControl(frame: CGRect(x: x, y: 0, width: 72, height: ChannelStripView.height - 1))
        all.addTarget(self, action: #selector(allTapped), for: .touchUpInside)
        let label = UILabel(frame: CGRect(x: 8, y: 10, width: 56, height: 56))
        label.text = L10n.t("subs.all")
        label.font = Theme.font(13, .medium)
        label.textColor = Theme.link
        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        all.addSubview(label)
        scroll.addSubview(all)
        x += 72
        scroll.contentSize = CGSize(width: x + 8, height: ChannelStripView.height)
        setNeedsLayout()
    }

    @objc private func tapped(_ c: UIControl) {
        if c.tag < channels.count { onChannel?(channels[c.tag]) }
    }

    @objc private func allTapped() { onAll?() }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        divider.frame = CGRect(x: 0, y: bounds.height - 0.5, width: bounds.width, height: 0.5)
    }
}

/// Subscriptions tab. Subscriptions are stored on the device; the feed is built from each channel's Videos tab.
final class SubscriptionsViewController: FeedViewController, HidesNavigationBar, ScrollsToTop {
    private let appBar = AppBarView()
    private let strip = ChannelStripView()
    private var shownIds: [String] = []
    private var lastLoad = Date.distantPast
    private static let videosTab = "EgZ2aWRlb3PyBgQKAjoA"

    private var appBarHeight: CGFloat {
        var top: CGFloat = 0
        if #available(iOS 11.0, *) { top = view.safeAreaInsets.top }
        return top + AppBarView.contentHeight
    }

    private var stripHeight: CGFloat { return Store.shared.subscriptions.isEmpty ? 0 : ChannelStripView.height }

    override var listFrame: CGRect {
        let top = appBarHeight + stripHeight
        return CGRect(x: 0, y: top, width: view.bounds.width, height: max(0, view.bounds.height - top))
    }

    override var emptyTitle: String { return L10n.t("subs.empty") }
    override var emptyIcon: String { return "subscriptions" }
    override var emptyDetail: String? { return L10n.t("subs.emptyHint") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(strip)
        view.addSubview(appBar)
        appBar.onSearch = { Router.shared.root?.openSearchScreen() }
        strip.onChannel = { c in Router.shared.openChannel(id: c.id, name: c.name) }
        strip.onAll = { Router.shared.push(ChannelsManagerViewController()) }
        shownIds = Store.shared.subscriptions.map { $0.id }
        strip.setChannels(Store.shared.subscriptions)
        reload()
    }

    func scrollToTop() { tableView.setContentOffset(CGPoint(x: 0, y: -tableView.contentInset.top), animated: true) }

    override func viewDidLayoutSubviews() {
        let ah = appBarHeight
        appBar.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: ah)
        strip.frame = CGRect(x: 0, y: ah, width: view.bounds.width, height: stripHeight)
        strip.isHidden = stripHeight == 0
        super.viewDidLayoutSubviews()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let ids = Store.shared.subscriptions.map { $0.id }
        if ids != shownIds || Date().timeIntervalSince(lastLoad) > 600 {
            refreshAll()
        }
    }

    override func storeChanged() {
        let ids = Store.shared.subscriptions.map { $0.id }
        if ids != shownIds && view.window == nil { refreshAll() }
    }

    private func refreshAll() {
        shownIds = Store.shared.subscriptions.map { $0.id }
        strip.setChannels(Store.shared.subscriptions)
        view.setNeedsLayout()
        clearList()
        reload()
    }

    override func fetchFirstPage(_ done: @escaping (Result<FeedPage, Error>) -> Void) {
        let subs = Store.shared.subscriptions
        lastLoad = Date()
        if subs.isEmpty {
            done(.success(FeedPage()))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let sem = DispatchSemaphore(value: 4)
            let group = DispatchGroup()
            let lock = NSLock()
            var collected: [(order: Int, video: VideoItem, age: Double)] = []
            for (idx, ch) in subs.enumerated() {
                sem.wait()
                group.enter()
                InnerTube.shared.channelTab(id: ch.id, params: SubscriptionsViewController.videosTab) { result in
                    if case .success(let page) = result {
                        var n = 0
                        for var v in page.videos where !v.isShort {
                            if n >= 12 { break }
                            v.channelId = ch.id
                            v.channelName = ch.name
                            v.channelAvatar = ch.avatar
                            lock.lock()
                            collected.append((order: idx * 100 + n, video: v, age: Format.approximateAge(v.published)))
                            lock.unlock()
                            n += 1
                        }
                    }
                    sem.signal()
                    group.leave()
                }
            }
            group.notify(queue: .global(qos: .userInitiated)) {
                let sorted = collected.sorted { a, b in
                    if a.age != b.age { return a.age < b.age }
                    return a.order < b.order
                }
                var page = FeedPage()
                page.items = sorted.prefix(150).map { FeedItem.video($0.video) }
                done(.success(page))
            }
        }
    }
}

/// "All channels" list with unsubscribe buttons.
final class ChannelsManagerViewController: FeedViewController {
    override var showsRefreshControl: Bool { return false }
    override var emptyTitle: String { return L10n.t("subs.empty") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.t("subs.manage")
        rebuild()
    }

    private func rebuild() {
        var page = FeedPage()
        page.items = Store.shared.subscriptions.map { FeedItem.channel($0) }
        setPage(page)
    }

    override func storeChanged() {}
}
