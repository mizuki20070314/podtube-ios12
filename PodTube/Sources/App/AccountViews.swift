import UIKit

/// Top row of the "You" tab: the signed-in account, or a prompt to sign in.
final class AccountHeaderView: UIControl {
    static let height: CGFloat = 84

    private let avatar = UIImageView()
    private let nameLabel = UILabel()
    private let subLabel = UILabel()
    private let chevron = UIImageView()
    private let divider = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = 26
        nameLabel.font = Theme.font(17, .semibold)
        nameLabel.adjustsFontSizeToFitWidth = true // "Google アカウントでログイン" is wider than the 320 pt column
        nameLabel.minimumScaleFactor = 0.75
        subLabel.font = Theme.font(13)
        subLabel.numberOfLines = 2
        chevron.image = Icons.image("chevron_right", size: 22)
        chevron.contentMode = .center
        for v in [avatar, nameLabel, subLabel, chevron, divider] as [UIView] { v.isUserInteractionEnabled = false }
        addSubviews([avatar, nameLabel, subLabel, chevron, divider])
        refresh()
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refresh() {
        backgroundColor = Theme.background
        nameLabel.textColor = Theme.text
        subLabel.textColor = Theme.secondaryText
        chevron.tintColor = Theme.secondaryText
        divider.backgroundColor = Theme.divider
        avatar.tintColor = Theme.secondaryText
        if Account.shared.isSignedIn {
            let p = Account.shared.profile
            nameLabel.text = (p?.name.isEmpty == false ? p?.name : nil) ?? L10n.t("account.signedIn")
            subLabel.text = p?.handle ?? ""
            if let a = p?.avatar, !a.isEmpty {
                avatar.backgroundColor = Theme.surface
                avatar.contentMode = .scaleAspectFill
                avatar.setRemote(a, maxPixel: 120, fade: false)
            } else {
                avatar.backgroundColor = .clear
                avatar.contentMode = .center
                avatar.image = Icons.image("account_circle", size: 52)
            }
        } else {
            nameLabel.text = L10n.t("account.signIn")
            subLabel.text = L10n.t("account.signInHint")
            avatar.backgroundColor = .clear
            avatar.contentMode = .center
            avatar.image = Icons.image("account_circle_outline", size: 52)
        }
        setNeedsLayout()
    }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? Theme.surface : Theme.background }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        avatar.frame = CGRect(x: 16, y: (bounds.height - 52) / 2, width: 52, height: 52)
        chevron.frame = CGRect(x: w - 40, y: (bounds.height - 24) / 2, width: 24, height: 24)
        let tx: CGFloat = 16 + 52 + 14
        let tw = chevron.frame.minX - tx - 6
        let subText = subLabel.text ?? ""
        let subH = subText.isEmpty ? 0 : TextMetrics.height(subText, font: Theme.font(13), width: tw, maxLines: 2)
        let total = 22 + (subH > 0 ? subH + 2 : 0)
        let top = (bounds.height - total) / 2
        nameLabel.frame = CGRect(x: tx, y: top, width: tw, height: 22)
        subLabel.frame = CGRect(x: tx, y: top + 24, width: tw, height: subH)
        divider.frame = CGRect(x: 0, y: bounds.height - 0.5, width: w, height: 0.5)
    }
}

/// A list that lives in the signed-in account (history, Watch later, liked videos, playlists).
final class AccountListViewController: FeedViewController {
    enum Kind {
        case history
        case watchLater
        case liked
        case playlists

        var browseId: String {
            switch self {
            case .history: return "FEhistory"
            case .watchLater: return "VLWL"
            case .liked: return "VLLL"
            case .playlists: return "FEplaylist_aggregation"
            }
        }
    }

    private let kind: Kind

    init(kind: Kind) {
        self.kind = kind
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var emptyTitle: String {
        switch kind {
        case .history: return L10n.t("library.emptyHistory")
        default: return L10n.t("common.empty")
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        switch kind {
        case .history: title = L10n.t("library.history")
        case .watchLater: title = L10n.t("library.watchLater")
        case .liked: title = L10n.t("library.liked")
        case .playlists: title = L10n.t("library.playlists")
        }
        NotificationCenter.default.addObserver(self, selector: #selector(accountChanged), name: .accountChanged, object: nil)
        reload()
    }

    @objc private func accountChanged() {
        clearList()
        reload()
    }

    override func fetchFirstPage(_ done: @escaping (Result<FeedPage, Error>) -> Void) {
        continuationEndpoint = "tv"
        guard Account.shared.isSignedIn else {
            done(.failure(InnerTubeError.api(401, L10n.t("account.signInRequired"))))
            return
        }
        InnerTube.shared.accountBrowse(kind.browseId) { r in
            if case .failure(let e) = r, let ie = e as? InnerTubeError, case .authRequired = ie {
                done(.failure(InnerTubeError.api(401, L10n.t("account.signInRequired"))))
            } else {
                done(r)
            }
        }
    }

    override func play(_ video: VideoItem) {
        switch kind {
        case .history, .playlists: Router.shared.play(video)
        case .watchLater, .liked: Router.shared.play(video, queue: allVideos, playlistId: nil)
        }
    }

    override func extraActions(for video: VideoItem) -> [SheetAction] {
        switch kind {
        case .watchLater:
            return [SheetAction(title: L10n.t("video.removeWatchLater"), icon: "delete") { [weak self] in
                Account.shared.setWatchLater(video, false)
                self?.removeVideo(id: video.id)
            }]
        case .liked:
            return [SheetAction(title: L10n.t("video.unlike"), icon: "delete") { [weak self] in
                Account.shared.setLike(video, .none)
                self?.removeVideo(id: video.id)
            }]
        default:
            return []
        }
    }
}
