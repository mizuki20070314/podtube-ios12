import UIKit

final class SettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private enum Row {
        case toggle(String, () -> Bool, (Bool) -> Void)
        case choice(String, () -> String, () -> Void)
        case button(String, Bool, () -> Void)
        case info(String, String)
    }

    private struct Section {
        let title: String
        let rows: [Row]
    }

    private let table = UITableView(frame: .zero, style: .grouped)
    private var sections: [Section] = []

    private static let regions: [(code: String, name: String)] = [
        ("JP", "日本 / Japan"), ("US", "United States"), ("GB", "United Kingdom"), ("KR", "한국 / Korea"),
        ("DE", "Deutschland"), ("FR", "France"), ("ES", "España"), ("BR", "Brasil"), ("IN", "India"), ("AU", "Australia")
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.t("settings.title")
        view.backgroundColor = Theme.background
        table.dataSource = self
        table.delegate = self
        table.backgroundColor = .clear
        table.separatorColor = Theme.divider
        view.addSubview(table)
        build()
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .themeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .settingsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .accountChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .accountProfileChanged, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        table.frame = view.bounds
    }

    @objc private func refresh() {
        view.backgroundColor = Theme.background
        table.separatorColor = Theme.divider
        title = L10n.t("settings.title")
        build()
        table.reloadData()
    }

    // MARK: Model

    private func qualityText(_ h: Int) -> String { return h == 0 ? L10n.t("player.auto") : "\(h)p" }

    private func languageText() -> String {
        switch Settings.uiLanguage {
        case "ja": return "日本語"
        case "en": return "English"
        default: return L10n.t("settings.languageAuto")
        }
    }

    private func regionText() -> String {
        return SettingsViewController.regions.first(where: { $0.code == Settings.contentRegion })?.name ?? Settings.contentRegion
    }

    private func accountRows() -> [Row] {
        if Account.shared.isSignedIn {
            let p = Account.shared.profile
            return [
                .info(p?.name ?? L10n.t("account.signedIn"), p?.handle ?? ""),
                .button(L10n.t("account.signOut"), true, { Account.shared.signOut() }),
                .info("", L10n.t("account.signedInNote"))
            ]
        }
        return [
            .button(L10n.t("account.signIn"), false, { [weak self] in
                self?.navigationController?.pushViewController(SignInViewController(), animated: true)
            }),
            .info("", L10n.t("account.signedOutNote"))
        ]
    }

    private func build() {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            + " (" + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1") + ")"
        sections = [
            Section(title: L10n.t("settings.account"), rows: accountRows()),
            Section(title: L10n.t("settings.general"), rows: [
                .choice(L10n.t("settings.appearance"), { Theme.isDark ? L10n.t("settings.dark") : L10n.t("settings.light") }, { [weak self] in self?.pickTheme() }),
                .choice(L10n.t("settings.language"), { [weak self] in self?.languageText() ?? "" }, { [weak self] in self?.pickLanguage() }),
                .choice(L10n.t("settings.region"), { [weak self] in self?.regionText() ?? "" }, { [weak self] in self?.pickRegion() })
            ]),
            Section(title: L10n.t("settings.playback"), rows: [
                .toggle(L10n.t("settings.autoplay"), { Settings.autoplay }, { Settings.autoplay = $0 }),
                .toggle(L10n.t("settings.backgroundPlay"), { Settings.backgroundPlay }, { Settings.backgroundPlay = $0 }),
                .toggle(L10n.t("settings.captionsAlways"), { Settings.captionsAlways }, { Settings.captionsAlways = $0 }),
                .choice(L10n.t("settings.defaultQuality"), { [weak self] in self?.qualityText(Settings.maxQuality) ?? "" }, { [weak self] in self?.pickQuality() }),
                .choice(L10n.t("settings.defaultSpeed"), { Settings.playbackSpeed == 1 ? L10n.t("player.normal") : "\(Settings.playbackSpeed)x" }, { [weak self] in self?.pickSpeed() })
            ]),
            Section(title: L10n.t("settings.privacy"), rows: [
                .toggle(L10n.t("settings.pauseHistory"), { Settings.pauseHistory }, { Settings.pauseHistory = $0 }),
                .button(L10n.t("settings.clearHistory"), true, { [weak self] in self?.confirmClearHistory() }),
                .button(L10n.t("settings.clearSearch"), false, { Store.shared.clearSearches(); Toast.show(L10n.t("settings.clearSearch")) }),
                .button(L10n.t("settings.clearCache"), false, { ImageLoader.shared.clearCaches(); Toast.show(L10n.t("settings.clearCache")) })
            ]),
            Section(title: L10n.t("settings.about"), rows: [
                .info(L10n.t("settings.version"), version),
                .button(L10n.t("diag.title"), false, { [weak self] in
                    self?.navigationController?.pushViewController(DiagnosticsViewController(), animated: true)
                }),
                .info("", L10n.t("settings.disclaimer")),
                .button(L10n.t("settings.source"), false, {
                    if let u = URL(string: "https://github.com/mizuki20070314/podtube-ios12") {
                        UIApplication.shared.open(u, options: [:], completionHandler: nil)
                    }
                })
            ])
        ]
    }

    // MARK: Pickers

    private func pickTheme() {
        SheetView.show(title: L10n.t("settings.appearance"), actions: [
            SheetAction(title: L10n.t("settings.dark"), checked: Theme.isDark) { Theme.isDark = true },
            SheetAction(title: L10n.t("settings.light"), checked: !Theme.isDark) { Theme.isDark = false }
        ])
    }

    private func pickLanguage() {
        SheetView.show(title: L10n.t("settings.language"), actions: [
            SheetAction(title: L10n.t("settings.languageAuto"), checked: Settings.uiLanguage == "auto") { Settings.uiLanguage = "auto" },
            SheetAction(title: "日本語", checked: Settings.uiLanguage == "ja") { Settings.uiLanguage = "ja" },
            SheetAction(title: "English", checked: Settings.uiLanguage == "en") { Settings.uiLanguage = "en" }
        ])
    }

    private func pickRegion() {
        let acts = SettingsViewController.regions.map { r in
            SheetAction(title: r.name, checked: r.code == Settings.contentRegion) { Settings.contentRegion = r.code }
        }
        SheetView.show(title: L10n.t("settings.region"), actions: acts)
    }

    private func pickQuality() {
        let acts = [0, 1080, 720, 480, 360, 240, 144].map { h in
            SheetAction(title: qualityText(h), checked: h == Settings.maxQuality) { [weak self] in
                Settings.maxQuality = h
                PlayerManager.shared.setMaxHeight(h)
                self?.refresh()
            }
        }
        SheetView.show(title: L10n.t("settings.defaultQuality"), actions: acts)
    }

    private func pickSpeed() {
        let acts = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map { s in
            SheetAction(title: s == 1 ? L10n.t("player.normal") : "\(s)x", checked: s == Settings.playbackSpeed) { [weak self] in
                Settings.playbackSpeed = s
                PlayerManager.shared.setSpeed(s)
                self?.refresh()
            }
        }
        SheetView.show(title: L10n.t("settings.defaultSpeed"), actions: acts)
    }

    private func confirmClearHistory() {
        let alert = UIAlertController(title: L10n.t("library.confirmClear"), message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.t("common.cancel"), style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: L10n.t("common.delete"), style: .destructive) { _ in Store.shared.clearHistory() })
        present(alert, animated: true, completion: nil)
    }

    // MARK: Table

    func numberOfSections(in tableView: UITableView) -> Int { return sections.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { return sections[section].rows.count }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { return sections[section].title }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        if let h = view as? UITableViewHeaderFooterView {
            h.textLabel?.textColor = Theme.secondaryText
            h.textLabel?.font = Theme.font(13, .semibold)
            h.contentView.backgroundColor = Theme.background
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if case .info(let t, let d) = sections[indexPath.section].rows[indexPath.row], t.isEmpty {
            let h = TextMetrics.height(d, font: Theme.font(13), width: tableView.bounds.width - 32, maxLines: 0)
            return h + 24
        }
        return 52
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.backgroundColor = Theme.background
        cell.selectionStyle = .none
        cell.textLabel?.font = Theme.font(16)
        cell.textLabel?.textColor = Theme.text
        cell.detailTextLabel?.font = Theme.font(14)
        cell.detailTextLabel?.textColor = Theme.secondaryText
        switch sections[indexPath.section].rows[indexPath.row] {
        case .toggle(let title, let get, let set):
            cell.textLabel?.text = title
            let sw = UISwitch()
            sw.isOn = get()
            sw.onTintColor = Theme.red
            sw.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)
            sw.tag = indexPath.section * 100 + indexPath.row
            cell.accessoryView = sw
            _ = set
        case .choice(let title, let value, _):
            cell.textLabel?.text = title
            cell.detailTextLabel?.text = value()
            cell.selectionStyle = .default
            cell.accessoryType = .disclosureIndicator
        case .button(let title, let destructive, _):
            cell.textLabel?.text = title
            cell.textLabel?.textColor = destructive ? Theme.red : Theme.link
            cell.selectionStyle = .default
        case .info(let title, let detail):
            if title.isEmpty {
                cell.textLabel?.text = detail
                cell.textLabel?.numberOfLines = 0
                cell.textLabel?.font = Theme.font(13)
                cell.textLabel?.textColor = Theme.secondaryText
            } else {
                cell.textLabel?.text = title
                cell.detailTextLabel?.text = detail
            }
        }
        return cell
    }

    @objc private func switchChanged(_ sw: UISwitch) {
        let section = sw.tag / 100
        let row = sw.tag % 100
        if case .toggle(_, _, let set) = sections[section].rows[row] { set(sw.isOn) }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section].rows[indexPath.row] {
        case .choice(_, _, let action): action()
        case .button(_, _, let action): action()
        default: break
        }
    }
}
