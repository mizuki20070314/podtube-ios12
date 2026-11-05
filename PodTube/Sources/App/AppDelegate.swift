import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        DebugRoutes.applyEarlyArguments()
        Settings.applyToClient()
        ClientOverrides.refresh()
        Account.shared.start()
        if DebugRoutes.flag("-pt-demo-account") { FakeAccount.enable() }
        _ = PlayerManager.shared
        _ = DownloadManager.shared

        // CI only: -pt-size 320x568 previews the iPod touch layout inside a larger simulator screen.
        var frame = UIScreen.main.bounds
        var previewSmall = false
        if let s = DebugRoutes.value(for: "-pt-size") {
            let p = s.split(separator: "x").compactMap { Double($0) }
            if p.count == 2 {
                let sw = Double(frame.width)
                let sh = Double(frame.height)
                frame = CGRect(x: (sw - p[0]) / 2, y: (sh - p[1]) / 2, width: p[0], height: p[1])
                previewSmall = true
            }
        }
        let win = UIWindow(frame: frame)
        win.backgroundColor = Theme.background
        let root = RootViewController()
        if previewSmall, #available(iOS 11.0, *) {
            root.additionalSafeAreaInsets = UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)
        }
        win.rootViewController = root
        win.makeKeyAndVisible()
        window = win
        Router.shared.window = win
        Router.shared.root = root
        return true
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { Router.shared.open(link: url.absoluteString) }
        return true
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        DownloadManager.shared.backgroundCompletionHandler = completionHandler
    }
}

/// Launch arguments used by the CI smoke test to drive the UI and take screenshots.
///   -pt-theme light|dark   -pt-region JP|US   -route "watch:ID;wait:6;comments"   -pt-demo-account
enum DebugRoutes {
    static func value(for key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func flag(_ key: String) -> Bool {
        return ProcessInfo.processInfo.arguments.contains(key)
    }

    static func applyEarlyArguments() {
        if let t = value(for: "-pt-theme") { UserDefaults.standard.set(t == "light" ? 1 : 0, forKey: "theme") }
        if let r = value(for: "-pt-region") { UserDefaults.standard.set(r, forKey: "contentRegion") }
        if let l = value(for: "-pt-lang") { UserDefaults.standard.set(l, forKey: "uiLanguage") }
    }

    static func runIfRequested(root: RootViewController) {
        guard let script = value(for: "-route") else { return }
        let steps = script.split(separator: ";").map { String($0) }
        var delay: Double = 1.0
        for step in steps {
            if step.hasPrefix("wait:"), let n = Double(step.dropFirst(5)) {
                delay += n
                continue
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { run(step, root: root) }
            delay += 0.4
        }
    }

    private static func run(_ step: String, root: RootViewController) {
        let parts = step.split(separator: ":", maxSplits: 1).map { String($0) }
        let name = parts.first ?? ""
        let arg = parts.count > 1 ? parts[1] : ""
        switch name {
        case "tab": root.selectTab(Int(arg) ?? 0)
        case "search": Router.shared.openSearch(query: arg)
        case "suggest": Router.shared.push(SearchViewController(prefill: arg))
        case "watch": Router.shared.play(VideoItem(id: arg))
        case "channel": Router.shared.openChannel(id: arg)
        case "playlist": Router.shared.openPlaylist(id: arg)
        case "settings": Router.shared.openSettings()
        case "downloads": Router.shared.push(DownloadsViewController())
        case "manage": Router.shared.push(ChannelsManagerViewController())
        case "diag":
            let vc = DiagnosticsViewController()
            Router.shared.push(vc)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { vc.runForDebug() }
        case "comments": root.debugOpenComments()
        case "w": root.debugWatch(arg)
        case "channeltab":
            if let nav = root.currentNav.topViewController as? ChannelViewController { nav.debugSelectTab(Int(arg) ?? 0) }
        case "minimize": root.minimizeWatchIfNeeded()
        case "landscape": root.setLandscape(true)
        case "portrait": root.setLandscape(false)
        case "sheet":
            var v = VideoItem(id: "dQw4w9WgXcQ")
            v.title = "Sample"
            v.channelId = "UCuAXFkgsw1L7xaCfnd5JJOw"
            Router.shared.showVideoMenu(v)
        case "savesheet":
            var v = VideoItem(id: "dQw4w9WgXcQ")
            v.title = "Sample"
            Router.shared.showPlaylistPicker(for: v)
        case "signin":
            // fixed code, no network: the real one is requested from Google when the screen opens normally
            let demo = DeviceCode(userCode: "ABC-DEF-GHIJ", verificationURL: "https://www.google.com/device",
                                  deviceCode: "demo", interval: 5, expiresAt: Date(timeIntervalSinceNow: 1800))
            Router.shared.push(SignInViewController(demoCode: demo))
        case "acctlist":
            switch arg {
            case "watchLater": Router.shared.push(AccountListViewController(kind: .watchLater))
            case "liked": Router.shared.push(AccountListViewController(kind: .liked))
            case "playlists": Router.shared.push(AccountListViewController(kind: .playlists))
            default: Router.shared.push(AccountListViewController(kind: .history))
            }
        case "localhistory":
            // demo entries (only when the list is empty) so that the screen has content on a fresh simulator
            if Store.shared.history.isEmpty {
                for (i, id) in ["dQw4w9WgXcQ", "jNQXAC9IVRw", "aircAruvnKk"].enumerated() {
                    var v = VideoItem(id: id)
                    v.title = "視聴履歴（デモ） \(i + 1)"
                    v.channelName = "デモチャンネル \(i + 1)"
                    Store.shared.addHistory(v)
                }
            }
            Router.shared.push(StoredListViewController(kind: .history))
        case "accountplaylist":
            Router.shared.openPlaylist(id: arg, title: nil)
        default: break
        }
    }
}
