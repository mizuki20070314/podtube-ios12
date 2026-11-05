import UIKit

final class PlaylistHeaderView: UIView {
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let playButton = UIButton(type: .custom)
    private let shuffleButton = UIButton(type: .custom)
    private let divider = UIView()
    var onPlay: (() -> Void)?
    var onShuffle: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = Theme.font(22, .bold)
        titleLabel.numberOfLines = 3
        metaLabel.font = Theme.font(13)
        metaLabel.numberOfLines = 2
        for (b, key, icon) in [(playButton, "playlist.playAll", "play_arrow"), (shuffleButton, "playlist.shuffle", "shuffle")] {
            b.setTitle(L10n.t(key), for: .normal)
            b.setImage(Icons.image(icon, size: 22), for: .normal)
            b.titleLabel?.font = Theme.font(14, .medium)
            b.layer.cornerRadius = 20
            b.titleEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: -8)
            b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 20)
        }
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        shuffleButton.addTarget(self, action: #selector(shuffleTapped), for: .touchUpInside)
        addSubviews([titleLabel, metaLabel, playButton, shuffleButton, divider])
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeChanged, object: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func applyTheme() {
        backgroundColor = Theme.background
        titleLabel.textColor = Theme.text
        metaLabel.textColor = Theme.secondaryText
        playButton.backgroundColor = Theme.chipSelectedBackground
        playButton.setTitleColor(Theme.chipSelectedText, for: .normal)
        playButton.tintColor = Theme.chipSelectedText
        shuffleButton.backgroundColor = Theme.surface
        shuffleButton.setTitleColor(Theme.text, for: .normal)
        shuffleButton.tintColor = Theme.text
        divider.backgroundColor = Theme.divider
    }

    @objc private func playTapped() { onPlay?() }
    @objc private func shuffleTapped() { onShuffle?() }

    func configure(title: String, meta: String) {
        titleLabel.text = title
        metaLabel.text = meta
        setNeedsLayout()
    }

    func height(width w: CGFloat) -> CGFloat {
        let th = TextMetrics.height(titleLabel.text ?? "", font: Theme.font(22, .bold), width: w - 32, maxLines: 3)
        let mh = TextMetrics.height(metaLabel.text ?? "", font: Theme.font(13), width: w - 32, maxLines: 2)
        return 16 + th + 6 + mh + 14 + 40 + 16 + 1
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        let th = TextMetrics.height(titleLabel.text ?? "", font: Theme.font(22, .bold), width: w - 32, maxLines: 3)
        let mh = TextMetrics.height(metaLabel.text ?? "", font: Theme.font(13), width: w - 32, maxLines: 2)
        titleLabel.frame = CGRect(x: 16, y: 16, width: w - 32, height: th)
        metaLabel.frame = CGRect(x: 16, y: titleLabel.frame.maxY + 6, width: w - 32, height: mh)
        let y = metaLabel.frame.maxY + 14
        let bw = (w - 32 - 10) / 2
        playButton.frame = CGRect(x: 16, y: y, width: bw, height: 40)
        shuffleButton.frame = CGRect(x: 16 + bw + 10, y: y, width: bw, height: 40)
        divider.frame = CGRect(x: 0, y: bounds.height - 0.5, width: w, height: 0.5)
    }
}

/// A YouTube playlist page.
final class PlaylistViewController: FeedViewController {
    private let playlistId: String
    private var titleText: String?
    private var info: PlaylistInfo?
    private let header = PlaylistHeaderView()

    init(playlistId: String, title: String?) {
        self.playlistId = playlistId
        self.titleText = title
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var showsRefreshControl: Bool { return false }

    override var stateFrame: CGRect {
        let h = header.frame.height
        let f = listFrame
        return CGRect(x: 0, y: min(f.height - 100, h), width: f.width, height: max(100, f.height - h))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = titleText
        header.configure(title: titleText ?? "", meta: "")
        header.onPlay = { [weak self] in self?.playAll(shuffle: false) }
        header.onShuffle = { [weak self] in self?.playAll(shuffle: true) }
        updateHeader()
        tableView.tableHeaderView = header
        reload()
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
        InnerTube.shared.playlist(id: playlistId) { [weak self] result in
            switch result {
            case .success(let info):
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.info = info
                    self.title = info.title
                    var parts: [String] = []
                    if !info.owner.isEmpty { parts.append(info.owner) }
                    parts.append(contentsOf: info.stats)
                    self.header.configure(title: info.title, meta: parts.joined(separator: " · "))
                    self.updateHeader()
                }
                done(.success(info.firstPage))
            case .failure(let e):
                done(.failure(e))
            }
        }
    }

    override func play(_ video: VideoItem) {
        Router.shared.play(video, queue: allVideos, playlistId: playlistId)
    }

    private func playAll(shuffle: Bool) {
        var list = allVideos
        if list.isEmpty { return }
        if shuffle { list.shuffle() }
        Router.shared.play(list[0], queue: list, playlistId: shuffle ? nil : playlistId)
    }
}
