import UIKit

/// Home tab: app bar, topic chips and the recommendation feed.
final class HomeViewController: FeedViewController, HidesNavigationBar {
    override var showsChannelAvatars: Bool { return true }
    private let appBar = AppBarView()
    private let chipBar = ChipBar()

    private struct ChipDef {
        let title: String
        let query: String?
        let filter: SearchFilter
    }

    private var defs: [ChipDef] = []
    private var selected = 0
    private let chipHeight: CGFloat = 48

    private var appBarHeight: CGFloat {
        var top: CGFloat = 0
        if #available(iOS 11.0, *) { top = view.safeAreaInsets.top }
        return top + AppBarView.contentHeight
    }

    override var listFrame: CGRect {
        let top = appBarHeight + chipHeight
        return CGRect(x: 0, y: top, width: view.bounds.width, height: max(0, view.bounds.height - top))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildChips()
        view.addSubview(chipBar)
        view.addSubview(appBar)
        appBar.onSearch = { Router.shared.root?.openSearchScreen() }
        chipBar.onSelect = { [weak self] i in self?.selectChip(i) }
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: .settingsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(accountChanged), name: .accountChanged, object: nil)
        reload()
    }

    @objc private func settingsChanged() {
        buildChips()
        clearList()
        reload()
    }

    /// Signed in or out: the "All" chip switches between the personal and the anonymous feed.
    @objc private func accountChanged() {
        clearList()
        reload()
    }

    /// Personal recommendations; falls back to the anonymous feed when the account page cannot be read.
    private func accountHomeOrAnonymous(_ done: @escaping (Result<FeedPage, Error>) -> Void) {
        InnerTube.shared.accountHome { [weak self] r in
            if case .success(let page) = r, !page.items.isEmpty {
                done(r)
                return
            }
            DispatchQueue.main.async { self?.continuationEndpoint = "browse" }
            InnerTube.shared.home(done)
        }
    }

    private func buildChips() {
        var video = SearchFilter()
        video.kind = .video
        var live = video
        live.live = true
        var today = video
        today.date = .week
        defs = [
            ChipDef(title: L10n.t("chip.all"), query: nil, filter: video),
            ChipDef(title: L10n.t("chip.music"), query: nil, filter: video),
            ChipDef(title: L10n.t("chip.gaming"), query: nil, filter: video),
            ChipDef(title: L10n.t("chip.live"), query: nil, filter: live),
            ChipDef(title: L10n.t("chip.news"), query: nil, filter: today),
            ChipDef(title: L10n.t("chip.anime"), query: nil, filter: video),
            ChipDef(title: L10n.t("chip.sports"), query: nil, filter: video),
            ChipDef(title: L10n.t("chip.cooking"), query: nil, filter: video),
            ChipDef(title: L10n.t("chip.comedy"), query: nil, filter: video),
            ChipDef(title: L10n.t("chip.tech"), query: nil, filter: video),
            ChipDef(title: L10n.t("chip.travel"), query: nil, filter: video),
            ChipDef(title: L10n.t("chip.pets"), query: nil, filter: video)
        ]
        selected = 0
        chipBar.setTitles(defs.map { $0.title }, selected: 0)
    }

    private func selectChip(_ i: Int) {
        if i == selected { return }
        selected = i
        clearList()
        reload()
    }

    override func fetchFirstPage(_ done: @escaping (Result<FeedPage, Error>) -> Void) {
        if selected == 0 {
            if Account.shared.isSignedIn {
                continuationEndpoint = "tv"
                accountHomeOrAnonymous(done)
            } else {
                continuationEndpoint = "browse"
                InnerTube.shared.home(done)
            }
        } else {
            let d = defs[selected]
            continuationEndpoint = "search"
            InnerTube.shared.search(d.query ?? d.title, filter: d.filter, done)
        }
    }

    override func viewDidLayoutSubviews() {
        let ah = appBarHeight
        appBar.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: ah)
        chipBar.frame = CGRect(x: 0, y: ah, width: view.bounds.width, height: chipHeight)
        super.viewDidLayoutSubviews()
    }
}
