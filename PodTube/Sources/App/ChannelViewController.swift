import UIKit

/// Header of a channel page: banner, avatar, name, stats, subscribe button and the tab strip.
final class ChannelHeaderView: UIView {
    private let banner = UIImageView()
    private let avatar = UIImageView()
    private let nameLabel = UILabel()
    private let metaLabel = UILabel()
    private let subscribeButton = SubscribeButton()
    private let tabScroll = UIScrollView()
    private let tabLine = UIView()
    private let divider = UIView()
    private var tabButtons: [UIButton] = []
    private var info: ChannelInfo?
    private(set) var selectedTab = 0
    var onTab: ((Int) -> Void)?
    var onSubscribe: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        banner.contentMode = .scaleAspectFill
        banner.clipsToBounds = true
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = 36
        nameLabel.font = Theme.font(22, .bold)
        metaLabel.font = Theme.font(12)
        metaLabel.numberOfLines = 2
        subscribeButton.addTarget(self, action: #selector(subTapped), for: .touchUpInside)
        tabScroll.showsHorizontalScrollIndicator = false
        addSubviews([banner, avatar, nameLabel, metaLabel, subscribeButton, tabScroll, divider])
        tabScroll.addSubview(tabLine)
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshSubscribe), name: .storeChanged, object: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func applyTheme() {
        backgroundColor = Theme.background
        banner.backgroundColor = Theme.surface
        avatar.backgroundColor = Theme.surface
        nameLabel.textColor = Theme.text
        metaLabel.textColor = Theme.secondaryText
        tabLine.backgroundColor = Theme.text
        divider.backgroundColor = Theme.divider
        restyleTabs()
    }

    @objc private func refreshSubscribe() {
        if let i = info { subscribeButton.setSubscribed(Store.shared.isSubscribed(i.id)) }
    }

    @objc private func subTapped() { onSubscribe?() }

    func configure(_ i: ChannelInfo, selected: Int) {
        info = i
        selectedTab = selected
        nameLabel.text = i.name
        var parts: [String] = []
        if !i.handle.isEmpty { parts.append(i.handle) }
        if !i.subscribers.isEmpty { parts.append(i.subscribers) }
        if !i.videoCount.isEmpty { parts.append(i.videoCount) }
        metaLabel.text = parts.joined(separator: " · ")
        avatar.setRemote(i.avatar, maxPixel: 200, fade: false)
        banner.setRemote(i.banner, maxPixel: 1200)
        subscribeButton.setSubscribed(Store.shared.isSubscribed(i.id))
        tabButtons.forEach { $0.removeFromSuperview() }
        tabButtons = []
        // The "About" tab has no list content, so it is not offered.
        let shownTabs = i.tabs.filter { !$0.params.hasPrefix("EgVhYm91d") }
        for (idx, t) in shownTabs.enumerated() {
            let b = UIButton(type: .custom)
            b.setTitle(t.title, for: .normal)
            b.titleLabel?.font = Theme.font(14, .medium)
            b.tag = idx
            b.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            tabScroll.addSubview(b)
            tabButtons.append(b)
        }
        restyleTabs()
        setNeedsLayout()
    }

    func select(tab: Int) {
        selectedTab = tab
        restyleTabs()
        setNeedsLayout()
    }

    @objc private func tabTapped(_ b: UIButton) {
        selectedTab = b.tag
        restyleTabs()
        setNeedsLayout()
        onTab?(b.tag)
    }

    private func restyleTabs() {
        for (i, b) in tabButtons.enumerated() {
            b.setTitleColor(i == selectedTab ? Theme.text : Theme.secondaryText, for: .normal)
        }
    }

    var hasBanner: Bool { return !(info?.banner ?? "").isEmpty }

    func height(width w: CGFloat) -> CGFloat {
        let bannerH: CGFloat = hasBanner ? (w * 0.28).rounded() : 0
        return bannerH + 16 + 72 + 12 + 40 + 12 + 46 + 1
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        let bannerH: CGFloat = hasBanner ? (w * 0.28).rounded() : 0
        banner.isHidden = !hasBanner
        banner.frame = CGRect(x: 0, y: 0, width: w, height: bannerH)
        var y = bannerH + 16
        avatar.frame = CGRect(x: 16, y: y, width: 72, height: 72)
        let tx: CGFloat = 16 + 72 + 16
        nameLabel.frame = CGRect(x: tx, y: y + 4, width: w - tx - 16, height: 28)
        metaLabel.frame = CGRect(x: tx, y: y + 36, width: w - tx - 16, height: 34)
        y += 72 + 12
        let bw = subscribeButton.sizeThatFits(.zero).width
        subscribeButton.frame = CGRect(x: 16, y: y, width: max(bw, 120), height: 40)
        subscribeButton.layer.cornerRadius = 20
        y += 40 + 12
        tabScroll.frame = CGRect(x: 0, y: y, width: w, height: 46)
        var x: CGFloat = 8
        var lineFrame = CGRect.zero
        for (i, b) in tabButtons.enumerated() {
            let titleText = (b.title(for: .normal) ?? "") as NSString
            let tw = ceil(titleText.size(withAttributes: [.font: Theme.font(14, .medium)]).width) + 24
            b.frame = CGRect(x: x, y: 0, width: tw, height: 46)
            if i == selectedTab { lineFrame = CGRect(x: x + 8, y: 43, width: tw - 16, height: 3) }
            x += tw
        }
        tabLine.frame = lineFrame
        tabScroll.contentSize = CGSize(width: x + 8, height: 46)
        divider.frame = CGRect(x: 0, y: bounds.height - 0.5, width: w, height: 0.5)
    }
}

final class ChannelViewController: FeedViewController, ScrollsToTop {
    private let channelId: String
    private var channelName: String?
    private var info: ChannelInfo?
    private var tabIndex = 0
    private let header = ChannelHeaderView()
    private var loadedInfo = false

    init(channelId: String, name: String?) {
        self.channelId = channelId
        self.channelName = name
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = channelName
        header.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 160)
        header.onTab = { [weak self] i in self?.selectTab(i) }
        header.onSubscribe = { [weak self] in
            guard let self = self, let i = self.info else { return }
            if Store.shared.isSubscribed(i.id) { Store.shared.unsubscribe(i.id) } else { Store.shared.subscribe(i.asItem) }
        }
        tableView.tableHeaderView = header
        reload()
    }

    func scrollToTop() { tableView.setContentOffset(.zero, animated: true) }

    override var showsRefreshControl: Bool { return false }

    override var stateFrame: CGRect {
        let h = header.frame.height
        let f = listFrame
        return CGRect(x: 0, y: min(f.height - 100, h), width: f.width, height: max(100, f.height - h))
    }

    override func headerView(width: CGFloat) -> UIView? {
        updateHeader()
        return header
    }

    private func updateHeader() {
        let w = view.bounds.width
        if w <= 0 { return }
        header.frame = CGRect(x: 0, y: 0, width: w, height: header.height(width: w))
        tableView.tableHeaderView = header
        view.setNeedsLayout()
    }

    override func fetchFirstPage(_ done: @escaping (Result<FeedPage, Error>) -> Void) {
        continuationEndpoint = "browse"
        if let i = info, tabIndex < i.tabs.count, !loadedInfo || tabIndex != 0 {
            // switching tabs after the header is known
            let tab = i.tabs[tabIndex]
            InnerTube.shared.channelTab(id: i.id, params: tab.params) { r in
                done(r.map { self.fillChannel($0, info: i) })
            }
            return
        }
        InnerTube.shared.channel(id: channelId) { [weak self] result in
            switch result {
            case .success(let info):
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.info = info
                    self.loadedInfo = true
                    self.title = info.name
                    self.header.configure(info, selected: self.tabIndex)
                    self.updateHeader()
                }
                // The Home tab is a set of shelves; show it as a flat list.
                var page = info.firstPage
                page.continuation = nil
                done(.success(self.fillChannel(page, info: info)))
            case .failure(let e):
                done(.failure(e))
            }
        }
    }

    /// Videos on channel tabs carry no byline of their own.
    private func fillChannel(_ page: FeedPage, info: ChannelInfo) -> FeedPage {
        var out = page
        out.items = page.items.map { item in
            switch item {
            case .video(var v):
                if v.channelName.isEmpty { v.channelName = info.name }
                if v.channelId.isEmpty { v.channelId = info.id }
                return .video(v)
            case .shorts(var list):
                for i in 0..<list.count {
                    if list[i].channelName.isEmpty { list[i].channelName = info.name }
                }
                return .shorts(list)
            default:
                return item
            }
        }
        return out
    }

    private func selectTab(_ i: Int) {
        guard let inf = info, i < inf.tabs.count, i != tabIndex else { return }
        tabIndex = i
        header.select(tab: i)
        clearList()
        if i == 0 {
            loadedInfo = false
            info = nil
            reload()
        } else {
            reload()
        }
    }
}
