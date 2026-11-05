import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        DebugRoutes.applyEarlyArguments()
        Settings.applyToClient()
        ClientOverrides.refresh()
        _ = PlayerManager.shared
        _ = DownloadManager.shared

        let win = UIWindow(frame: UIScreen.main.bounds)
        win.backgroundColor = Theme.background
        let root = RootViewController()
        win.rootViewController = root
        win.makeKeyAndVisible()
        window = win
        Router.shared.window = win
        Router.shared.root = root
        return true
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        DownloadManager.shared.backgroundCompletionHandler = completionHandler
    }
}

/// Launch arguments used by the CI smoke test to drive the UI and take screenshots.
///   -pt-theme light|dark   -pt-region JP|US   -route "watch:ID;wait:6;comments"
enum DebugRoutes {
    private static func value(for key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
        return args[i + 1]
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
        case "comments": root.debugOpenComments()
        case "w": root.debugWatch(arg)
        case "minimize": root.minimizeWatchIfNeeded()
        case "landscape": root.setLandscape(true)
        case "portrait": root.setLandscape(false)
        case "sheet":
            var v = VideoItem(id: "dQw4w9WgXcQ")
            v.title = "Sample"
            v.channelId = "UCuAXFkgsw1L7xaCfnd5JJOw"
            Router.shared.showVideoMenu(v)
        default: break
        }
    }
}
