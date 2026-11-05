import UIKit

/// Search entry screen: text field + history / live suggestions.
final class SearchViewController: UIViewController, HidesNavigationBar, UITextFieldDelegate, UITableViewDataSource, UITableViewDelegate {
    private let topBar = UIView()
    private let backButton = IconButton(icon: "arrow_back")
    private let fieldBackground = UIView()
    private let field = UITextField()
    private let clearButton = IconButton(icon: "close", size: 18, frame: CGRect(x: 0, y: 0, width: 36, height: 36))
    private let table = UITableView(frame: .zero, style: .plain)
    private let divider = UIView()

    private var suggestions: [String] = []
    private var pending: DispatchWorkItem?
    private let prefill: String?

    init(prefill: String? = nil) {
        self.prefill = prefill
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        topBar.backgroundColor = Theme.background
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        fieldBackground.layer.cornerRadius = 18
        field.font = Theme.font(16)
        field.returnKeyType = .search
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.clearButtonMode = .never
        field.delegate = self
        field.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
        table.dataSource = self
        table.delegate = self
        table.separatorStyle = .none
        table.backgroundColor = .clear
        table.keyboardDismissMode = .onDrag
        table.rowHeight = 52
        if #available(iOS 11.0, *) { table.contentInsetAdjustmentBehavior = .never }
        view.addSubview(table)
        view.addSubview(topBar)
        topBar.addSubviews([backButton, fieldBackground, divider])
        fieldBackground.addSubview(field)
        fieldBackground.addSubview(clearButton)
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeChanged, object: nil)
        field.text = prefill
        clearButton.isHidden = (prefill ?? "").isEmpty
        if let p = prefill, !p.isEmpty { fetchSuggestions(p) }
    }

    @objc private func applyTheme() {
        view.backgroundColor = Theme.background
        topBar.backgroundColor = Theme.background
        fieldBackground.backgroundColor = Theme.surface
        field.textColor = Theme.text
        field.keyboardAppearance = Theme.isDark ? .dark : .light
        field.attributedPlaceholder = NSAttributedString(string: L10n.t("search.placeholder"),
                                                         attributes: [.foregroundColor: Theme.secondaryText])
        divider.backgroundColor = Theme.divider
        table.reloadData()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        field.becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        field.resignFirstResponder()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        var top: CGFloat = 0
        if #available(iOS 11.0, *) { top = view.safeAreaInsets.top }
        let barH = top + 56
        topBar.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: barH)
        backButton.frame = CGRect(x: 4, y: top + 6, width: 44, height: 44)
        fieldBackground.frame = CGRect(x: 52, y: top + 10, width: view.bounds.width - 52 - 12, height: 36)
        clearButton.frame = CGRect(x: fieldBackground.bounds.width - 38, y: 0, width: 36, height: 36)
        field.frame = CGRect(x: 14, y: 0, width: fieldBackground.bounds.width - 14 - 40, height: 36)
        divider.frame = CGRect(x: 0, y: barH - 0.5, width: view.bounds.width, height: 0.5)
        table.frame = CGRect(x: 0, y: barH, width: view.bounds.width, height: view.bounds.height - barH)
    }

    // MARK: Actions

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func clearTapped() {
        field.text = ""
        clearButton.isHidden = true
        suggestions = []
        table.reloadData()
        field.becomeFirstResponder()
    }

    @objc private func textChanged() {
        let q = (field.text ?? "").trimmingCharacters(in: .whitespaces)
        clearButton.isHidden = q.isEmpty
        pending?.cancel()
        if q.isEmpty {
            suggestions = []
            table.reloadData()
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.fetchSuggestions(q) }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private func fetchSuggestions(_ q: String) {
        InnerTube.shared.suggestions(q) { [weak self] list in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let current = (self.field.text ?? "").trimmingCharacters(in: .whitespaces)
                if current != q { return }
                self.suggestions = list
                self.table.reloadData()
            }
        }
    }

    private func submit(_ q: String) {
        let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return }
        field.resignFirstResponder()
        if Router.shared.open(link: t) { return }
        Router.shared.openSearch(query: t)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        submit(textField.text ?? "")
        return true
    }

    // MARK: Table

    private var showsHistory: Bool { return (field.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    private var rows: [String] { return showsHistory ? Store.shared.searches : suggestions }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let id = "SuggestCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: id) as? SuggestionCell ?? SuggestionCell(style: .default, reuseIdentifier: id)
        let text = rows[indexPath.row]
        cell.configure(text: text, isHistory: showsHistory)
        cell.onFill = { [weak self] in
            guard let self = self else { return }
            self.field.text = text + " "
            self.clearButton.isHidden = false
            self.textChanged()
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        submit(rows[indexPath.row])
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool { return showsHistory }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete && showsHistory {
            Store.shared.removeSearch(rows[indexPath.row])
            tableView.reloadData()
        }
    }
}

final class SuggestionCell: UITableViewCell {
    private let icon = UIImageView()
    private let label = UILabel()
    private let fill = IconButton(icon: "north_west", size: 20)
    var onFill: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        label.font = Theme.font(16)
        fill.addTarget(self, action: #selector(fillTapped), for: .touchUpInside)
        contentView.addSubviews([icon, label, fill])
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func fillTapped() { onFill?() }

    func configure(text: String, isHistory: Bool) {
        label.text = text
        label.textColor = Theme.text
        icon.image = Icons.image(isHistory ? "history" : "search", size: 22)
        icon.tintColor = Theme.secondaryText
        fill.tintColor = Theme.secondaryText
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = contentView.bounds.width
        let h = contentView.bounds.height
        icon.frame = CGRect(x: 16, y: (h - 22) / 2, width: 22, height: 22)
        fill.frame = CGRect(x: w - 48, y: (h - 44) / 2, width: 44, height: 44)
        label.frame = CGRect(x: 56, y: 0, width: w - 56 - 52, height: h)
    }
}

// MARK: - Search results

final class SearchResultsViewController: FeedViewController, HidesNavigationBar {
    private let query: String
    private var filter = SearchFilter()
    private let topBar = UIView()
    private let backButton = IconButton(icon: "arrow_back")
    private let queryButton = UIButton(type: .custom)
    private let filterButton = IconButton(icon: "tune")
    private let divider = UIView()

    init(query: String) {
        self.query = query
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var barHeight: CGFloat {
        var top: CGFloat = 0
        if #available(iOS 11.0, *) { top = view.safeAreaInsets.top }
        return top + 56
    }

    override var listFrame: CGRect {
        let b = barHeight
        return CGRect(x: 0, y: b, width: view.bounds.width, height: max(0, view.bounds.height - b))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        topBar.backgroundColor = Theme.background
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        queryButton.setTitle(query, for: .normal)
        queryButton.titleLabel?.font = Theme.font(16)
        queryButton.contentHorizontalAlignment = .left
        queryButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        queryButton.layer.cornerRadius = 18
        queryButton.addTarget(self, action: #selector(editTapped), for: .touchUpInside)
        filterButton.addTarget(self, action: #selector(filterTapped), for: .touchUpInside)
        view.addSubview(topBar)
        topBar.addSubviews([backButton, queryButton, filterButton, divider])
        applyBarTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyBarTheme), name: .themeChanged, object: nil)
        reload()
    }

    @objc private func applyBarTheme() {
        topBar.backgroundColor = Theme.background
        queryButton.backgroundColor = Theme.surface
        queryButton.setTitleColor(Theme.text, for: .normal)
        divider.backgroundColor = Theme.divider
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = barHeight
        let top = b - 56
        topBar.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: b)
        backButton.frame = CGRect(x: 4, y: top + 6, width: 44, height: 44)
        filterButton.frame = CGRect(x: view.bounds.width - 48, y: top + 6, width: 44, height: 44)
        queryButton.frame = CGRect(x: 52, y: top + 10, width: view.bounds.width - 52 - 52, height: 36)
        divider.frame = CGRect(x: 0, y: b - 0.5, width: view.bounds.width, height: 0.5)
    }

    override func fetchFirstPage(_ done: @escaping (Result<FeedPage, Error>) -> Void) {
        continuationEndpoint = "search"
        InnerTube.shared.search(query, filter: filter.isDefault ? nil : filter, done)
    }

    @objc private func backTapped() { navigationController?.popViewController(animated: true) }

    @objc private func editTapped() {
        navigationController?.pushViewController(SearchViewController(prefill: query), animated: false)
    }

    @objc private func filterTapped() {
        let actions = [
            SheetAction(title: L10n.t("search.sort"), icon: "swap_vert", subtitle: sortName(filter.sort)) { [weak self] in self?.pickSort() },
            SheetAction(title: L10n.t("search.uploadDate"), icon: "schedule", subtitle: dateName(filter.date)) { [weak self] in self?.pickDate() },
            SheetAction(title: L10n.t("search.type"), icon: "video_library", subtitle: kindName(filter.kind)) { [weak self] in self?.pickKind() },
            SheetAction(title: L10n.t("search.duration"), icon: "timer", subtitle: durationName(filter.duration)) { [weak self] in self?.pickDuration() },
            SheetAction(title: L10n.t("search.reset"), icon: "refresh") { [weak self] in
                self?.filter = SearchFilter()
                self?.applyFilter()
            }
        ]
        SheetView.show(title: L10n.t("search.filters"), actions: actions)
    }

    private func applyFilter() {
        clearList()
        reload()
    }

    private func sortName(_ s: SearchFilter.Sort) -> String {
        switch s {
        case .relevance: return L10n.t("search.relevance")
        case .rating: return L10n.t("search.ratingSort")
        case .uploadDate: return L10n.t("search.dateSort")
        case .viewCount: return L10n.t("search.viewSort")
        }
    }

    private func dateName(_ d: SearchFilter.UploadDate) -> String {
        switch d {
        case .any: return L10n.t("search.any")
        case .hour: return L10n.t("search.hour")
        case .today: return L10n.t("search.today")
        case .week: return L10n.t("search.week")
        case .month: return L10n.t("search.month")
        case .year: return L10n.t("search.year")
        }
    }

    private func kindName(_ k: SearchFilter.Kind) -> String {
        switch k {
        case .any: return L10n.t("search.any")
        case .video: return L10n.t("search.video")
        case .channel: return L10n.t("search.channel")
        case .playlist: return L10n.t("search.playlist")
        case .movie: return L10n.t("search.movie")
        }
    }

    private func durationName(_ d: SearchFilter.Duration) -> String {
        switch d {
        case .any: return L10n.t("search.any")
        case .short: return L10n.t("search.short")
        case .medium: return L10n.t("search.medium")
        case .long: return L10n.t("search.long")
        }
    }

    private func pickSort() {
        let all: [SearchFilter.Sort] = [.relevance, .uploadDate, .viewCount, .rating]
        let acts = all.map { s in
            SheetAction(title: sortName(s), checked: s == filter.sort) { [weak self] in
                self?.filter.sort = s
                self?.applyFilter()
            }
        }
        SheetView.show(title: L10n.t("search.sort"), actions: acts)
    }

    private func pickDate() {
        let all: [SearchFilter.UploadDate] = [.any, .hour, .today, .week, .month, .year]
        let acts = all.map { d in
            SheetAction(title: dateName(d), checked: d == filter.date) { [weak self] in
                self?.filter.date = d
                self?.applyFilter()
            }
        }
        SheetView.show(title: L10n.t("search.uploadDate"), actions: acts)
    }

    private func pickKind() {
        let all: [SearchFilter.Kind] = [.any, .video, .channel, .playlist, .movie]
        let acts = all.map { k in
            SheetAction(title: kindName(k), checked: k == filter.kind) { [weak self] in
                self?.filter.kind = k
                self?.applyFilter()
            }
        }
        SheetView.show(title: L10n.t("search.type"), actions: acts)
    }

    private func pickDuration() {
        let all: [SearchFilter.Duration] = [.any, .short, .medium, .long]
        let acts = all.map { d in
            SheetAction(title: durationName(d), checked: d == filter.duration) { [weak self] in
                self?.filter.duration = d
                self?.applyFilter()
            }
        }
        SheetView.show(title: L10n.t("search.duration"), actions: acts)
    }
}
