import UIKit

/// Screens that draw their own top bar (the navigation bar is hidden for them).
protocol HidesNavigationBar {}

final class RootViewController: UIViewController, UINavigationControllerDelegate {
    private let tabContainer = UIView()
    private let tabBar = TabBarView()
    private var navs: [NavController] = []
    private(set) var selectedIndex = 0
    private let watch = WatchViewController()
    private var forcedMask: UIInterfaceOrientationMask?
    private let shorts = ShortsViewController()

    /// Space that list screens must leave free when the mini player is showing.
    var miniPlayerInset: CGFloat {
        return (watch.isActive && watch.progress > 0.5) ? WatchViewController.miniHeight : 0
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        view.addSubview(tabContainer)
        view.addSubview(tabBar)

        let roots: [UIViewController] = [HomeViewController(), shorts, SubscriptionsViewController(), LibraryViewController()]
        for r in roots {
            let nav = NavController(rootViewController: r)
            nav.delegate = self
            nav.setNavigationBarHidden(true, animated: false)
            navs.append(nav)
        }
        tabBar.setItems([
            TabBarView.Item(title: L10n.t("tab.home"), icon: "home_outline", iconSelected: "home"),
            TabBarView.Item(title: L10n.t("tab.shorts"), icon: "shorts_outline", iconSelected: "shorts"),
            TabBarView.Item(title: L10n.t("tab.subs"), icon: "subscriptions_outline", iconSelected: "subscriptions"),
            TabBarView.Item(title: L10n.t("tab.you"), icon: "account_circle_outline", iconSelected: "account_circle")
        ])
        tabBar.onSelect = { [weak self] i in self?.selectTab(i) }
        showTab(0)

        addChild(watch)
        view.addSubview(watch.view)
        watch.didMove(toParent: self)
        watch.view.isHidden = true
        watch.onProgress = { [weak self] _ in self?.watchProgressChanged() }
        watch.onClose = { [weak self] in self?.watchProgressChanged() }
        watch.onRequestLandscape = { [weak self] on in self?.setLandscape(on) }

        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .themeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: .settingsChanged, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DebugRoutes.runIfRequested(root: self)
    }

    @objc private func themeChanged() {
        view.backgroundColor = Theme.background
        setNeedsStatusBarAppearanceUpdate()
    }

    @objc private func settingsChanged() {
        tabBar.setItems([
            TabBarView.Item(title: L10n.t("tab.home"), icon: "home_outline", iconSelected: "home"),
            TabBarView.Item(title: L10n.t("tab.shorts"), icon: "shorts_outline", iconSelected: "shorts"),
            TabBarView.Item(title: L10n.t("tab.subs"), icon: "subscriptions_outline", iconSelected: "subscriptions"),
            TabBarView.Item(title: L10n.t("tab.you"), icon: "account_circle_outline", iconSelected: "account_circle")
        ])
        tabBar.select(selectedIndex)
    }

    // MARK: Layout

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds
        var safeBottom: CGFloat = 0
        var safeTop: CGFloat = 0
        if #available(iOS 11.0, *) {
            safeBottom = view.safeAreaInsets.bottom
            safeTop = view.safeAreaInsets.top
        }
        let tabH = TabBarView.contentHeight + safeBottom
        tabBar.frame = CGRect(x: 0, y: b.height - tabH, width: b.width, height: tabH)
        tabContainer.frame = CGRect(x: 0, y: 0, width: b.width, height: b.height - tabH)
        for nav in navs { nav.view.frame = tabContainer.bounds }
        let mini = CGRect(x: 0, y: b.height - tabH - WatchViewController.miniHeight, width: b.width, height: WatchViewController.miniHeight)
        watch.updateGeometry(expanded: b, mini: mini, safeTop: safeTop)
    }

    // MARK: Tabs

    private func showTab(_ i: Int) {
        let old = navs[selectedIndex]
        if old.parent != nil && selectedIndex != i {
            old.willMove(toParent: nil)
            old.view.removeFromSuperview()
            old.removeFromParent()
        }
        selectedIndex = i
        let nav = navs[i]
        if nav.parent == nil {
            addChild(nav)
            tabContainer.addSubview(nav.view)
            nav.view.frame = tabContainer.bounds
            nav.didMove(toParent: self)
        }
        tabBar.select(i)
    }

    func selectTab(_ i: Int) {
        if i == selectedIndex {
            let nav = navs[i]
            if nav.viewControllers.count > 1 {
                nav.popToRootViewController(animated: true)
            } else if let t = nav.viewControllers.first as? ScrollsToTop {
                t.scrollToTop()
            }
        } else {
            showTab(i)
        }
        if watch.isActive && watch.progress < 0.5 { watch.setMinimized(true, animated: true) }
    }

    var currentNav: NavController { return navs[selectedIndex] }

    func pushOnCurrentTab(_ vc: UIViewController) {
        currentNav.pushViewController(vc, animated: true)
    }

    func openSearchScreen() {
        minimizeWatchIfNeeded()
        pushOnCurrentTab(SearchViewController())
    }

    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        let hide = viewController is HidesNavigationBar
        navigationController.setNavigationBarHidden(hide, animated: animated)
    }

    // MARK: Watch

    func openWatch(video: VideoItem, queue: [VideoItem]?, playlistId: String?) {
        watch.start(video: video, queue: queue, playlistId: playlistId)
        UIViewController.attemptRotationToDeviceOrientation()
        setNeedsStatusBarAppearanceUpdate()
    }

    func openShorts(videos: [VideoItem], index: Int) {
        minimizeWatchIfNeeded()
        PlayerManager.shared.pause()
        selectTab(1)
        shorts.open(videos: videos, startIndex: index)
    }

    func debugOpenComments() { watch.openComments() }

    func minimizeWatchIfNeeded() {
        if watch.isActive && watch.progress < 0.5 { watch.setMinimized(true, animated: true) }
    }

    private func watchProgressChanged() {
        UIViewController.attemptRotationToDeviceOrientation()
        setNeedsStatusBarAppearanceUpdate()
        NotificationCenter.default.post(name: .miniPlayerChanged, object: nil)
    }

    // MARK: Orientation / status bar

    override var shouldAutorotate: Bool { return true }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if let m = forcedMask { return m }
        if watch.isActive && watch.progress < 0.5 { return .allButUpsideDown }
        return .portrait
    }

    func setLandscape(_ landscape: Bool) {
        forcedMask = landscape ? .landscape : .portrait
        UIViewController.attemptRotationToDeviceOrientation()
        let target: UIInterfaceOrientation = landscape ? .landscapeRight : .portrait
        UIDevice.current.setValue(target.rawValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
        if !landscape {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.forcedMask = nil
                UIViewController.attemptRotationToDeviceOrientation()
            }
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.setNeedsStatusBarAppearanceUpdate()
        }
        // A manual landscape request is released once the device really is in landscape and the user rotates back.
        if size.width <= size.height && forcedMask == .landscape { forcedMask = nil }
    }

    override var prefersStatusBarHidden: Bool { return watch.isFullscreenLayout }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        if watch.isActive && watch.progress < 0.5 { return .lightContent }
        return Theme.statusBarStyle
    }
}

protocol ScrollsToTop: AnyObject {
    func scrollToTop()
}
