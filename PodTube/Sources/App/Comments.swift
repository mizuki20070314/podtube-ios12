import UIKit

final class CommentCell: UITableViewCell {
    static let reuseId = "CommentCell"

    private let avatar = UIImageView()
    private let nameLabel = UILabel()
    private let textLabelView = UILabel()
    private let likeIcon = UIImageView(image: Icons.image("thumb_up_outline", size: 16))
    private let likesLabel = UILabel()
    private let repliesLabel = UILabel()
    private var comment: Comment?

    static func textWidth(_ cellWidth: CGFloat) -> CGFloat { return cellWidth - 16 - 36 - 12 - 16 }

    static func height(for c: Comment, width: CGFloat) -> CGFloat {
        let th = TextMetrics.height(c.text, font: Theme.font(14), width: textWidth(width), maxLines: 0)
        return 12 + 16 + 4 + th + 8 + 22 + (c.replyCount > 0 ? 24 : 0) + 8
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = 18
        nameLabel.font = Theme.font(12, .medium)
        textLabelView.font = Theme.font(14)
        textLabelView.numberOfLines = 0
        likesLabel.font = Theme.font(12)
        repliesLabel.font = Theme.font(13, .medium)
        contentView.addSubviews([avatar, nameLabel, textLabelView, likeIcon, likesLabel, repliesLabel])
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ c: Comment) {
        comment = c
        avatar.backgroundColor = Theme.surface
        avatar.setRemote(c.avatar, maxPixel: 96, fade: false)
        var head = c.author
        if !c.published.isEmpty { head += " · " + c.published }
        nameLabel.text = head
        nameLabel.textColor = Theme.secondaryText
        textLabelView.text = c.text
        textLabelView.textColor = Theme.text
        likeIcon.tintColor = Theme.secondaryText
        likesLabel.text = c.likes
        likesLabel.textColor = Theme.secondaryText
        repliesLabel.text = c.replyCount > 0 ? L10n.t("comments.replies", "\(c.replyCount)") : nil
        repliesLabel.textColor = Theme.link
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = contentView.bounds.width
        let tx: CGFloat = 16 + 36 + 12
        let tw = CommentCell.textWidth(w)
        avatar.frame = CGRect(x: 16, y: 12, width: 36, height: 36)
        nameLabel.frame = CGRect(x: tx, y: 12, width: tw, height: 16)
        let th = TextMetrics.height(comment?.text ?? "", font: Theme.font(14), width: tw, maxLines: 0)
        textLabelView.frame = CGRect(x: tx, y: 32, width: tw, height: th)
        let y = textLabelView.frame.maxY + 8
        likeIcon.frame = CGRect(x: tx, y: y + 2, width: 16, height: 16)
        likesLabel.frame = CGRect(x: tx + 22, y: y, width: 100, height: 20)
        repliesLabel.frame = CGRect(x: tx, y: y + 24, width: tw, height: 20)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatar.image = nil
    }
}

/// Comments panel that slides over the related list of the watch page.
final class CommentsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let headerBar = UIView()
    private let titleLabel = UILabel()
    private let countLabel = UILabel()
    private let sortButton = IconButton(icon: "swap_vert", size: 22)
    private let closeButton = IconButton(icon: "close", size: 22)
    private let divider = UIView()
    private let table = UITableView(frame: .zero, style: .plain)
    private let stateView = StateView()

    private var comments: [Comment] = []
    private var continuation: String?
    private var loading = false
    private var generation = 0
    private let sortTokens: [(title: String, token: String)]
    private var currentSort = 0
    private let firstToken: String
    private let countText: String
    var onClose: (() -> Void)?

    init(token: String, sortTokens: [(title: String, token: String)], countText: String, firstPage: CommentPage?) {
        self.firstToken = token
        self.sortTokens = sortTokens
        self.countText = countText
        super.init(nibName: nil, bundle: nil)
        if let p = firstPage {
            comments = p.comments
            continuation = p.continuation
        }
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        titleLabel.text = L10n.t("comments.title")
        titleLabel.font = Theme.font(16, .bold)
        countLabel.text = countText
        countLabel.font = Theme.font(13)
        sortButton.addTarget(self, action: #selector(sortTapped), for: .touchUpInside)
        sortButton.isHidden = sortTokens.count < 2
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        table.dataSource = self
        table.delegate = self
        table.separatorStyle = .none
        table.backgroundColor = .clear
        table.estimatedRowHeight = 0
        table.register(CommentCell.self, forCellReuseIdentifier: CommentCell.reuseId)
        table.register(LoadingCell.self, forCellReuseIdentifier: LoadingCell.reuseId)
        if #available(iOS 11.0, *) { table.contentInsetAdjustmentBehavior = .never }
        headerBar.addSubviews([titleLabel, countLabel, sortButton, closeButton, divider])
        view.addSubviews([table, headerBar, stateView])
        stateView.isHidden = true
        stateView.onAction = { [weak self] in self?.loadFirst() }
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeChanged, object: nil)
        if comments.isEmpty { loadFirst() }
    }

    @objc private func applyTheme() {
        view.backgroundColor = Theme.background
        headerBar.backgroundColor = Theme.background
        titleLabel.textColor = Theme.text
        countLabel.textColor = Theme.secondaryText
        divider.backgroundColor = Theme.divider
        table.reloadData()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let w = view.bounds.width
        let barH: CGFloat = 52
        headerBar.frame = CGRect(x: 0, y: 0, width: w, height: barH)
        titleLabel.sizeToFit()
        titleLabel.frame = CGRect(x: 16, y: 0, width: titleLabel.frame.width, height: barH)
        countLabel.sizeToFit()
        countLabel.frame = CGRect(x: titleLabel.frame.maxX + 8, y: 0, width: countLabel.frame.width, height: barH)
        closeButton.frame = CGRect(x: w - 48, y: 4, width: 44, height: 44)
        sortButton.frame = CGRect(x: w - 96, y: 4, width: 44, height: 44)
        divider.frame = CGRect(x: 0, y: barH - 0.5, width: w, height: 0.5)
        table.frame = CGRect(x: 0, y: barH, width: w, height: view.bounds.height - barH)
        stateView.frame = table.frame
    }

    @objc private func closeTapped() { onClose?() }

    @objc private func sortTapped() {
        var acts: [SheetAction] = []
        for (i, s) in sortTokens.enumerated() {
            acts.append(SheetAction(title: s.title, checked: i == currentSort) { [weak self] in
                guard let self = self else { return }
                self.currentSort = i
                self.comments = []
                self.continuation = nil
                self.table.reloadData()
                self.fetch(token: s.token, reset: true)
            })
        }
        SheetView.show(actions: acts)
    }

    private func loadFirst() {
        comments = []
        continuation = nil
        table.reloadData()
        fetch(token: firstToken, reset: true)
    }

    private func fetch(token: String, reset: Bool) {
        if loading { return }
        loading = true
        generation += 1
        let gen = generation
        if comments.isEmpty { stateView.showLoading() }
        InnerTube.shared.comments(token: token) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, gen == self.generation else { return }
                self.loading = false
                switch result {
                case .success(let page):
                    self.comments.append(contentsOf: page.comments)
                    self.continuation = page.continuation
                    if self.comments.isEmpty {
                        self.stateView.show(icon: "info", title: L10n.t("comments.empty"))
                    } else {
                        self.stateView.hide()
                    }
                case .failure(let e):
                    if self.comments.isEmpty {
                        self.stateView.show(icon: "cloud_off", title: L10n.t("common.error"), detail: e.localizedDescription,
                                            button: L10n.t("common.retry"))
                    }
                    self.continuation = nil
                }
                self.table.reloadData()
            }
        }
    }

    // MARK: Table

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return comments.count + (continuation != nil ? 1 : 0)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.row >= comments.count { return 56 }
        return CommentCell.height(for: comments[indexPath.row], width: tableView.bounds.width)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.row >= comments.count {
            let cell = tableView.dequeueReusableCell(withIdentifier: LoadingCell.reuseId, for: indexPath) as! LoadingCell
            cell.start()
            if let t = continuation {
                DispatchQueue.main.async { self.fetch(token: t, reset: false) }
            }
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: CommentCell.reuseId, for: indexPath) as! CommentCell
        cell.configure(comments[indexPath.row])
        return cell
    }
}
