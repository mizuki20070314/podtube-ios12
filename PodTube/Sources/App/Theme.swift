import UIKit

extension Notification.Name {
    static let themeChanged = Notification.Name("PodTubeThemeChanged")
    static let settingsChanged = Notification.Name("PodTubeSettingsChanged")
    static let storeChanged = Notification.Name("PodTubeStoreChanged")
    static let miniPlayerChanged = Notification.Name("PodTubeMiniPlayerChanged")
}

/// App-wide colours and fonts. iOS 12 has no system dark mode, so the theme is chosen in Settings.
enum Theme {
    private static let key = "theme"

    /// 0 = dark, 1 = light
    static var isDark: Bool {
        get {
            if UserDefaults.standard.object(forKey: key) == nil { return true }
            return UserDefaults.standard.integer(forKey: key) == 0
        }
        set {
            UserDefaults.standard.set(newValue ? 0 : 1, forKey: key)
            NotificationCenter.default.post(name: .themeChanged, object: nil)
        }
    }

    static let red = UIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1)

    private static func c(_ hex: UInt32, _ a: CGFloat = 1) -> UIColor {
        return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                       green: CGFloat((hex >> 8) & 0xFF) / 255,
                       blue: CGFloat(hex & 0xFF) / 255, alpha: a)
    }

    static var background: UIColor { return isDark ? c(0x0F0F0F) : c(0xFFFFFF) }
    /// chips, input fields, cards
    static var surface: UIColor { return isDark ? c(0x272727) : c(0xF2F2F2) }
    static var surfaceHigh: UIColor { return isDark ? c(0x3F3F3F) : c(0xE5E5E5) }
    static var text: UIColor { return isDark ? c(0xF1F1F1) : c(0x0F0F0F) }
    static var secondaryText: UIColor { return isDark ? c(0xAAAAAA) : c(0x606060) }
    static var divider: UIColor { return isDark ? c(0x303030) : c(0xE5E5E5) }
    static var chipSelectedBackground: UIColor { return isDark ? c(0xF1F1F1) : c(0x0F0F0F) }
    static var chipSelectedText: UIColor { return isDark ? c(0x0F0F0F) : c(0xFFFFFF) }
    static var sheetBackground: UIColor { return isDark ? c(0x212121) : c(0xFFFFFF) }
    static var link: UIColor { return isDark ? c(0x3EA6FF) : c(0x065FD4) }
    static var thumbPlaceholder: UIColor { return isDark ? c(0x1F1F1F) : c(0xE9E9E9) }
    static var statusBarStyle: UIStatusBarStyle { return isDark ? .lightContent : .default }

    // MARK: Fonts

    static func font(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
        return UIFont.systemFont(ofSize: size, weight: weight)
    }

    static var title: UIFont { return font(15, .medium) }
    static var meta: UIFont { return font(12) }
    static var sectionTitle: UIFont { return font(18, .bold) }

    // MARK: Navigation bar

    static func style(_ bar: UINavigationBar) {
        bar.isTranslucent = false
        bar.barTintColor = background
        bar.tintColor = text
        bar.titleTextAttributes = [.foregroundColor: text, .font: font(18, .medium)]
        bar.shadowImage = UIImage()
        bar.setBackgroundImage(UIImage(), for: .default)
        bar.barStyle = isDark ? .black : .default
    }
}

/// Settings stored in UserDefaults.
enum Settings {
    private static let d = UserDefaults.standard

    static func bool(_ key: String, default def: Bool) -> Bool {
        if d.object(forKey: key) == nil { return def }
        return d.bool(forKey: key)
    }

    static var autoplay: Bool {
        get { return bool("autoplay", default: true) }
        set { d.set(newValue, forKey: "autoplay") }
    }
    static var backgroundPlay: Bool {
        get { return bool("backgroundPlay", default: true) }
        set { d.set(newValue, forKey: "backgroundPlay") }
    }
    static var pauseHistory: Bool {
        get { return bool("pauseHistory", default: false) }
        set { d.set(newValue, forKey: "pauseHistory") }
    }
    static var captionsAlways: Bool {
        get { return bool("captionsAlways", default: false) }
        set { d.set(newValue, forKey: "captionsAlways") }
    }
    /// 0 = automatic, otherwise the maximum height in pixels (1080, 720, 480, 360, 240, 144).
    static var maxQuality: Int {
        get { return d.integer(forKey: "maxQuality") }
        set { d.set(newValue, forKey: "maxQuality") }
    }
    static var playbackSpeed: Double {
        get { let v = d.double(forKey: "playbackSpeed"); return v == 0 ? 1.0 : v }
        set { d.set(newValue, forKey: "playbackSpeed") }
    }
    /// The audio track chosen on a video that has several: "" = automatic (the system language decides), "original",
    /// or a language tag ("ja", "en-us").
    static var preferredAudio: String {
        get { return d.string(forKey: "preferredAudio") ?? "" }
        set { d.set(newValue, forKey: "preferredAudio") }
    }
    /// "auto", "ja", "en"
    static var uiLanguage: String {
        get { return d.string(forKey: "uiLanguage") ?? "auto" }
        set {
            d.set(newValue, forKey: "uiLanguage")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }
    /// Content language / region sent to YouTube as hl / gl.
    static var contentRegion: String {
        get { return d.string(forKey: "contentRegion") ?? (Format.isJapanese() ? "JP" : "US") }
        set {
            d.set(newValue, forKey: "contentRegion")
            applyToClient()
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    static func applyToClient() {
        let region = contentRegion
        let lang: String
        switch region {
        case "JP": lang = "ja"
        case "KR": lang = "ko"
        case "DE": lang = "de"
        case "FR": lang = "fr"
        case "ES": lang = "es"
        case "BR": lang = "pt"
        default: lang = "en"
        }
        InnerTube.shared.language = lang
        InnerTube.shared.region = region
    }
}
