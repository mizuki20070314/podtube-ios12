import UIKit

/// How a list screen lays out its video rows. A phone gets one edge-to-edge row per video; an iPad gets rounded cards,
/// several to a row (like the YouTube app on an iPad: 2 across when held upright, 3 sideways).
struct GridLayout: Equatable {
    var columns: Int
    var card: Bool
    var margin: CGFloat
    var gap: CGFloat

    static let list = GridLayout(columns: 1, card: false, margin: 0, gap: 0)

    /// True where the screen is wide enough for the iPad layouts (never on a phone, even sideways).
    static func isRegular(width: CGFloat) -> Bool {
        return UIDevice.current.userInterfaceIdiom == .pad && width >= 600
    }

    /// Cards of at least 300 pt each, 16 pt from the edges and 12 pt apart.
    static func standard(width: CGFloat) -> GridLayout {
        guard isRegular(width: width) else { return .list }
        let margin: CGFloat = 16
        let gap: CGFloat = 12
        let columns = max(1, Int((width - margin * 2 + gap) / (300 + gap)))
        return GridLayout(columns: columns, card: true, margin: margin, gap: gap)
    }

    func cardWidth(_ width: CGFloat) -> CGFloat {
        return floor((width - margin * 2 - gap * CGFloat(columns - 1)) / CGFloat(columns))
    }
}

/// One video (or playlist) as a card: rounded 16:9 picture, channel icon on the left of the title, details below.
/// The unit of a grid row; the whole card is a button (the icon and the "…" are buttons of their own).
final class VideoCardView: UIControl {
    private let thumbBox = UIView()
    private let thumb = UIImageView()
    private let durationLabel = PaddedLabel()
    private let progressBar = UIView()
    private let avatar = UIImageView()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let moreButton = IconButton(icon: "more_horiz", size: 22)

    var onTap: (() -> Void)?
    var onMore: (() -> Void)?
    var onAvatar: (() -> Void)?
    private var fraction: CGFloat = 0
    private var showsAvatar = false
    private var titleLines = 2

    override init(frame: CGRect) {
        super.init(frame: frame)
        thumbBox.layer.cornerRadius = 12
        thumbBox.clipsToBounds = true
        thumbBox.isUserInteractionEnabled = false
        thumb.contentMode = .scaleAspectFill
        thumb.clipsToBounds = true

        durationLabel.font = Theme.font(12, .semibold)
        durationLabel.textColor = .white
        durationLabel.backgroundColor = UIColor(white: 0, alpha: 0.8)
        durationLabel.layer.cornerRadius = 4
        durationLabel.clipsToBounds = true

        progressBar.backgroundColor = Theme.red

        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = 18
        avatar.isUserInteractionEnabled = true
        avatar.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(avatarTapped)))

        titleLabel.font = Theme.title
        metaLabel.font = Theme.meta
        titleLabel.isUserInteractionEnabled = false
        metaLabel.isUserInteractionEnabled = false
        moreButton.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)

        thumbBox.addSubviews([thumb, progressBar, durationLabel])
        addSubviews([thumbBox, avatar, titleLabel, metaLabel, moreButton])
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeChanged, object: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func applyTheme() {
        thumb.backgroundColor = Theme.thumbPlaceholder
        avatar.backgroundColor = Theme.surface
        titleLabel.textColor = Theme.text
        metaLabel.textColor = Theme.secondaryText
    }

    @objc private func tapped() { onTap?() }
    @objc private func moreTapped() { onMore?() }
    @objc private func avatarTapped() { onAvatar?() }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.8 : 1 }
    }

    /// Back to the empty state before the card shows another item.
    func reset() {
        onTap = nil
        onMore = nil
        onAvatar = nil
        thumb.image = nil
        avatar.image = nil
        alpha = 1
    }

    func configure(video v: VideoItem, reserveAvatar: Bool) {
        titleLines = 2
        titleLabel.numberOfLines = 2
        titleLabel.text = v.title
        metaLabel.text = VideoCell.metaText(v)
        thumb.setRemote(v.thumbnail.isEmpty ? v.thumbnailURL?.absoluteString : v.thumbnail, maxPixel: 800)
        showsAvatar = !v.channelAvatar.isEmpty || reserveAvatar
        avatar.isHidden = !showsAvatar
        avatar.setRemote(v.channelAvatar, maxPixel: 96, fade: false)
        moreButton.isHidden = false

        if v.isLive {
            durationLabel.text = L10n.t("video.live")
            durationLabel.backgroundColor = Theme.red
        } else if v.isUpcoming {
            durationLabel.text = L10n.t("video.upcoming")
            durationLabel.backgroundColor = UIColor(white: 0, alpha: 0.8)
        } else {
            durationLabel.text = v.duration
            durationLabel.backgroundColor = UIColor(white: 0, alpha: 0.8)
        }
        durationLabel.isHidden = (durationLabel.text ?? "").isEmpty
        if let pct = v.watchedPercent {
            fraction = CGFloat(pct) / 100
        } else {
            fraction = CGFloat(Store.shared.progress(for: v.id) ?? 0)
        }
        progressBar.isHidden = fraction <= 0.01
        setNeedsLayout()
    }

    func configure(playlist p: PlaylistItem) {
        titleLines = 2
        titleLabel.numberOfLines = 2
        titleLabel.text = p.title
        var parts: [String] = []
        if !p.channelName.isEmpty { parts.append(p.channelName) }
        parts.append(L10n.t("video.playlists"))
        metaLabel.text = parts.joined(separator: " · ")
        thumb.setRemote(p.thumbnail, maxPixel: 800)
        showsAvatar = false
        avatar.isHidden = true
        moreButton.isHidden = true
        durationLabel.text = "≡ " + p.videoCount
        durationLabel.backgroundColor = UIColor(white: 0, alpha: 0.8)
        durationLabel.isHidden = p.videoCount.isEmpty
        fraction = 0
        progressBar.isHidden = true
        setNeedsLayout()
    }

    /// An icon that was not known when the card was configured (see `ChannelDirectory`).
    func setAvatar(_ url: String) {
        if url.isEmpty || !showsAvatar { return }
        avatar.setRemote(url, maxPixel: 96, fade: false)
    }

    static func thumbHeight(_ width: CGFloat) -> CGFloat { return (width * 9 / 16).rounded() }

    /// Where the title starts and how wide it is: next to the icon when there is one, and clear of the "…" button.
    static func textMetrics(width: CGFloat, hasAvatar: Bool) -> (x: CGFloat, w: CGFloat) {
        let x: CGFloat = hasAvatar ? 46 : 0
        return (x, width - x - 40)
    }

    static func height(video v: VideoItem, width: CGFloat, reserveAvatar: Bool) -> CGFloat {
        let m = textMetrics(width: width, hasAvatar: !v.channelAvatar.isEmpty || reserveAvatar)
        let th = TextMetrics.height(v.title, font: Theme.title, width: m.w, maxLines: 2)
        return thumbHeight(width) + 10 + th + 3 + 16 + 24
    }

    static func height(playlist p: PlaylistItem, width: CGFloat) -> CGFloat {
        let m = textMetrics(width: width, hasAvatar: false)
        let th = TextMetrics.height(p.title, font: Theme.title, width: m.w, maxLines: 2)
        return thumbHeight(width) + 10 + th + 3 + 16 + 24
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        let th = VideoCardView.thumbHeight(w)
        thumbBox.frame = CGRect(x: 0, y: 0, width: w, height: th)
        thumb.frame = thumbBox.bounds
        let ds = durationLabel.sizeThatFits(CGSize(width: w, height: 30))
        durationLabel.frame = CGRect(x: w - ds.width - 8, y: th - ds.height - 8, width: ds.width, height: ds.height)
        progressBar.frame = CGRect(x: 0, y: th - 3, width: w * fraction, height: 3)
        avatar.frame = CGRect(x: 0, y: th + 12, width: 36, height: 36)
        let m = VideoCardView.textMetrics(width: w, hasAvatar: showsAvatar)
        let titleH = TextMetrics.height(titleLabel.text ?? "", font: Theme.title, width: m.w, maxLines: titleLines)
        titleLabel.frame = CGRect(x: m.x, y: th + 10, width: m.w, height: titleH)
        metaLabel.frame = CGRect(x: m.x, y: titleLabel.frame.maxY + 3, width: m.w, height: 16)
        moreButton.frame = CGRect(x: w - 40, y: th + 6, width: 40, height: 40)
    }
}

/// A table row that holds several cards side by side (the last row of a feed may hold fewer than the others).
final class GridRowCell: UITableViewCell {
    static let reuseId = "GridRowCell"

    private var cards: [VideoCardView] = []
    private var used = 0
    private var layout = GridLayout.list

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Makes sure `count` cards exist, hides the others and returns the ones to fill in.
    func prepare(count: Int, layout: GridLayout) -> [VideoCardView] {
        while cards.count < count {
            let c = VideoCardView()
            contentView.addSubview(c)
            cards.append(c)
        }
        for (i, c) in cards.enumerated() {
            c.isHidden = i >= count
            c.reset()
        }
        used = count
        self.layout = layout
        setNeedsLayout()
        return Array(cards[0..<count])
    }

    func card(at index: Int) -> VideoCardView? {
        return index < used ? cards[index] : nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let cw = layout.cardWidth(contentView.bounds.width)
        for i in 0..<used {
            cards[i].frame = CGRect(x: layout.margin + CGFloat(i) * (cw + layout.gap), y: 0, width: cw, height: contentView.bounds.height)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cards.forEach { $0.reset() }
    }
}
