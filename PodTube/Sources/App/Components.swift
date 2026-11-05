import UIKit

// MARK: - Small helpers

enum TextMetrics {
    private static var cache: [String: CGFloat] = [:]

    /// Height of `text` wrapped to `width`, limited to `maxLines` (0 = unlimited). Main thread only.
    static func height(_ text: String, font: UIFont, width: CGFloat, maxLines: Int) -> CGFloat {
        let key = "\(text)|\(font.pointSize)|\(Int(width))|\(maxLines)"
        if let h = cache[key] { return h }
        let lineH = ceil(font.lineHeight)
        let rect = (text as NSString).boundingRect(with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
                                                   options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                   attributes: [.font: font], context: nil)
        var lines = Int(ceil(rect.height / lineH - 0.01))
        if maxLines > 0 { lines = min(lines, maxLines) }
        lines = max(lines, 1)
        let h = CGFloat(lines) * lineH
        if cache.count > 3000 { cache.removeAll() }
        cache[key] = h
        return h
    }
}

final class PaddedLabel: UILabel {
    var insets = UIEdgeInsets(top: 2, left: 5, bottom: 2, right: 5)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let s = super.sizeThatFits(CGSize(width: size.width - insets.left - insets.right,
                                          height: size.height - insets.top - insets.bottom))
        return CGSize(width: ceil(s.width) + insets.left + insets.right,
                      height: ceil(s.height) + insets.top + insets.bottom)
    }

    override var intrinsicContentSize: CGSize {
        return sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
    }
}

final class IconButton: UIButton {
    private let iconName: String
    private let iconSize: CGFloat
    var useThemeTint = true

    init(icon: String, size: CGFloat = 24, frame: CGRect = CGRect(x: 0, y: 0, width: 44, height: 44)) {
        iconName = icon
        iconSize = size
        super.init(frame: frame)
        setImage(Icons.image(icon, size: size), for: .normal)
        imageView?.contentMode = .center
        tintColor = Theme.text
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .themeChanged, object: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func themeChanged() {
        if useThemeTint { tintColor = Theme.text }
    }

    func setIcon(_ name: String) {
        setImage(Icons.image(name, size: iconSize), for: .normal)
    }
}

extension UIView {
    func addSubviews(_ views: [UIView]) {
        for v in views { addSubview(v) }
    }
}

extension UIColor {
    func withBrightness(_ f: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: min(1, r * f), green: min(1, g * f), blue: min(1, b * f), alpha: a)
    }
}

// MARK: - Video cell (Android style: full-width 16:9 thumbnail, avatar + title + meta)

final class VideoCell: UITableViewCell {
    static let reuseId = "VideoCell"

    private let thumb = UIImageView()
    private let durationLabel = PaddedLabel()
    private let progressBar = UIView()
    private let avatar = UIImageView()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let moreButton = IconButton(icon: "more_vert", size: 20)

    var onMore: (() -> Void)?
    var onAvatar: (() -> Void)?
    private var fraction: CGFloat = 0
    private var showsAvatar = true

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

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

        titleLabel.numberOfLines = 2
        titleLabel.font = Theme.title
        metaLabel.font = Theme.meta
        moreButton.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)

        contentView.addSubviews([thumb, durationLabel, progressBar, avatar, titleLabel, metaLabel, moreButton])
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

    @objc private func moreTapped() { onMore?() }
    @objc private func avatarTapped() { onAvatar?() }

    static func metaText(_ v: VideoItem) -> String {
        var parts: [String] = []
        if !v.channelName.isEmpty { parts.append(v.channelName) }
        if !v.views.isEmpty { parts.append(v.views) }
        if !v.published.isEmpty { parts.append(v.published) }
        return parts.joined(separator: " · ")
    }

    /// `reserveAvatar`: keep the icon column (a grey disc until the icon is known) so the row does not change its
    /// layout when the icon arrives later (Home / Subscriptions, where the account feed has no icons).
    func configure(_ v: VideoItem, reserveAvatar: Bool = false) {
        titleLabel.text = v.title
        metaLabel.text = VideoCell.metaText(v)
        thumb.setRemote(v.thumbnail.isEmpty ? v.thumbnailURL?.absoluteString : v.thumbnail, maxPixel: 800)
        showsAvatar = !v.channelAvatar.isEmpty || reserveAvatar
        avatar.isHidden = !showsAvatar
        // also with an empty url: invalidates a load that is still running for the row's previous video
        avatar.setRemote(v.channelAvatar, maxPixel: 96, fade: false)

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

    static func thumbHeight(_ width: CGFloat) -> CGFloat { return (width * 9 / 16).rounded() }

    static func textMetrics(width: CGFloat, hasAvatar: Bool) -> (x: CGFloat, w: CGFloat) {
        let x: CGFloat = hasAvatar ? 60 : 12
        return (x, width - x - 44)
    }

    /// An icon that was not known when the row was configured (see `ChannelDirectory`).
    func setAvatar(_ url: String) {
        if url.isEmpty || !showsAvatar { return }
        avatar.setRemote(url, maxPixel: 96, fade: false)
    }

    static func height(for v: VideoItem, width: CGFloat, reserveAvatar: Bool = false) -> CGFloat {
        let m = textMetrics(width: width, hasAvatar: !v.channelAvatar.isEmpty || reserveAvatar)
        let th = TextMetrics.height(v.title, font: Theme.title, width: m.w, maxLines: 2)
        return thumbHeight(width) + 10 + th + 3 + 16 + 14
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = contentView.bounds.width
        let th = VideoCell.thumbHeight(w)
        thumb.frame = CGRect(x: 0, y: 0, width: w, height: th)
        let ds = durationLabel.sizeThatFits(CGSize(width: w, height: 30))
        durationLabel.frame = CGRect(x: w - ds.width - 8, y: th - ds.height - 8, width: ds.width, height: ds.height)
        progressBar.frame = CGRect(x: 0, y: th - 3, width: w * fraction, height: 3)
        avatar.frame = CGRect(x: 12, y: th + 12, width: 36, height: 36)
        let m = VideoCell.textMetrics(width: w, hasAvatar: showsAvatar)
        let titleH = TextMetrics.height(titleLabel.text ?? "", font: Theme.title, width: m.w, maxLines: 2)
        titleLabel.frame = CGRect(x: m.x, y: th + 10, width: m.w, height: titleH)
        metaLabel.frame = CGRect(x: m.x, y: titleLabel.frame.maxY + 3, width: m.w, height: 16)
        moreButton.frame = CGRect(x: w - 40, y: th + 6, width: 40, height: 40)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onMore = nil
        onAvatar = nil
        thumb.image = nil
        avatar.image = nil
    }
}

// MARK: - Channel row (search results, subscriptions manager)

final class ChannelCell: UITableViewCell {
    static let reuseId = "ChannelCell"
    static let rowHeight: CGFloat = 84

    private let avatar = UIImageView()
    private let nameLabel = UILabel()
    private let subLabel = UILabel()
    let subscribeButton = SubscribeButton()
    var onSubscribe: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = 30
        nameLabel.font = Theme.font(15, .medium)
        subLabel.font = Theme.meta
        subscribeButton.addTarget(self, action: #selector(subTapped), for: .touchUpInside)
        contentView.addSubviews([avatar, nameLabel, subLabel, subscribeButton])
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeChanged, object: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func applyTheme() {
        avatar.backgroundColor = Theme.surface
        nameLabel.textColor = Theme.text
        subLabel.textColor = Theme.secondaryText
    }

    @objc private func subTapped() { onSubscribe?() }

    func configure(_ c: ChannelItem) {
        nameLabel.text = c.name
        var parts: [String] = []
        if !c.handle.isEmpty { parts.append(c.handle) }
        if !c.subscribers.isEmpty { parts.append(c.subscribers) }
        subLabel.text = parts.joined(separator: " · ")
        avatar.setRemote(c.avatar, maxPixel: 160, fade: false)
        subscribeButton.setSubscribed(Store.shared.isSubscribed(c.id))
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = contentView.bounds.width
        avatar.frame = CGRect(x: 16, y: 12, width: 60, height: 60)
        let bs = subscribeButton.sizeThatFits(CGSize(width: 140, height: 36))
        subscribeButton.frame = CGRect(x: w - bs.width - 12, y: (ChannelCell.rowHeight - 34) / 2, width: bs.width, height: 34)
        let tx: CGFloat = 92
        let tw = max(40, subscribeButton.frame.minX - tx - 8)
        nameLabel.frame = CGRect(x: tx, y: 24, width: tw, height: 20)
        subLabel.frame = CGRect(x: tx, y: 46, width: tw, height: 16)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatar.image = nil
        onSubscribe = nil
    }
}

final class SubscribeButton: UIButton {
    private var subscribed = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel?.font = Theme.font(14, .medium)
        layer.cornerRadius = 17
        contentEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        setSubscribed(false)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .themeChanged, object: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func refresh() { setSubscribed(subscribed) }

    func setSubscribed(_ s: Bool) {
        subscribed = s
        if s {
            setTitle(L10n.t("video.subscribed"), for: .normal)
            setTitleColor(Theme.text, for: .normal)
            backgroundColor = Theme.surface
        } else {
            setTitle(L10n.t("video.subscribe"), for: .normal)
            setTitleColor(Theme.chipSelectedText, for: .normal)
            backgroundColor = Theme.chipSelectedBackground
        }
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let t = (title(for: .normal) ?? "") as NSString
        let w = t.size(withAttributes: [.font: Theme.font(14, .medium)]).width
        return CGSize(width: ceil(w) + 28, height: 34)
    }
}

// MARK: - Playlist row

final class PlaylistCell: UITableViewCell {
    static let reuseId = "PlaylistCell"

    private let thumb = UIImageView()
    private let countBadge = PaddedLabel()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let moreButton = IconButton(icon: "more_vert", size: 20)
    var onMore: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        thumb.contentMode = .scaleAspectFill
        thumb.clipsToBounds = true
        countBadge.font = Theme.font(12, .semibold)
        countBadge.textColor = .white
        countBadge.backgroundColor = UIColor(white: 0, alpha: 0.8)
        countBadge.layer.cornerRadius = 4
        countBadge.clipsToBounds = true
        titleLabel.numberOfLines = 2
        titleLabel.font = Theme.title
        metaLabel.font = Theme.meta
        moreButton.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)
        contentView.addSubviews([thumb, countBadge, titleLabel, metaLabel, moreButton])
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeChanged, object: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func applyTheme() {
        thumb.backgroundColor = Theme.thumbPlaceholder
        titleLabel.textColor = Theme.text
        metaLabel.textColor = Theme.secondaryText
    }

    @objc private func moreTapped() { onMore?() }

    func configure(_ p: PlaylistItem) {
        titleLabel.text = p.title
        var parts: [String] = []
        if !p.channelName.isEmpty { parts.append(p.channelName) }
        parts.append(L10n.t("video.playlists"))
        metaLabel.text = parts.joined(separator: " · ")
        thumb.setRemote(p.thumbnail, maxPixel: 800)
        countBadge.text = "≡ " + p.videoCount
        countBadge.isHidden = p.videoCount.isEmpty
        setNeedsLayout()
    }

    static func height(width: CGFloat) -> CGFloat {
        return VideoCell.thumbHeight(width) + 10 + 40 + 3 + 16 + 14 - 20
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = contentView.bounds.width
        let th = VideoCell.thumbHeight(w)
        thumb.frame = CGRect(x: 0, y: 0, width: w, height: th)
        let bs = countBadge.sizeThatFits(CGSize(width: w, height: 30))
        countBadge.frame = CGRect(x: w - bs.width - 8, y: th - bs.height - 8, width: bs.width, height: bs.height)
        titleLabel.frame = CGRect(x: 12, y: th + 10, width: w - 12 - 44, height: 20)
        titleLabel.numberOfLines = 1
        metaLabel.frame = CGRect(x: 12, y: titleLabel.frame.maxY + 3, width: w - 12 - 44, height: 16)
        moreButton.frame = CGRect(x: w - 40, y: th + 6, width: 40, height: 40)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumb.image = nil
        onMore = nil
    }
}

// MARK: - Shorts shelf (horizontal row of vertical cards)

final class ShortCardCell: UICollectionViewCell {
    static let reuseId = "ShortCardCell"

    private let image = UIImageView()
    private let gradient = CAGradientLayer()
    private let titleLabel = UILabel()
    private let viewsLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 10
        contentView.clipsToBounds = true
        image.contentMode = .scaleAspectFill
        image.clipsToBounds = true
        gradient.colors = [UIColor.clear.cgColor, UIColor(white: 0, alpha: 0.75).cgColor]
        gradient.locations = [0.45, 1]
        titleLabel.font = Theme.font(13, .medium)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        viewsLabel.font = Theme.font(11)
        viewsLabel.textColor = UIColor(white: 1, alpha: 0.85)
        contentView.addSubview(image)
        contentView.layer.addSublayer(gradient)
        contentView.addSubview(titleLabel)
        contentView.addSubview(viewsLabel)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ v: VideoItem) {
        contentView.backgroundColor = Theme.thumbPlaceholder
        image.setRemote(v.thumbnail.isEmpty ? v.thumbnailURL?.absoluteString : v.thumbnail, maxPixel: 480)
        titleLabel.text = v.title
        viewsLabel.text = v.views
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = contentView.bounds
        image.frame = b
        gradient.frame = b
        viewsLabel.frame = CGRect(x: 8, y: b.height - 22, width: b.width - 16, height: 14)
        titleLabel.frame = CGRect(x: 8, y: b.height - 22 - 36, width: b.width - 16, height: 34)
        titleLabel.sizeToFit()
        titleLabel.frame = CGRect(x: 8, y: viewsLabel.frame.minY - 4 - titleLabel.frame.height, width: b.width - 16,
                                  height: titleLabel.frame.height)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        image.image = nil
    }
}

final class ShortsShelfCell: UITableViewCell, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    static let reuseId = "ShortsShelfCell"

    private let header = UILabel()
    private let icon = UIImageView()
    private let layout = UICollectionViewFlowLayout()
    private lazy var collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private var videos: [VideoItem] = []
    var onSelect: (([VideoItem], Int) -> Void)?

    static func cardWidth(_ w: CGFloat) -> CGFloat { return floor((w - 12 * 2 - 8 * 2) / 2.6) }
    static func height(width: CGFloat) -> CGFloat {
        return 52 + (cardWidth(width) * 16 / 9).rounded() + 14
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        icon.image = Icons.image("shorts", size: 26)
        icon.tintColor = Theme.red
        header.font = Theme.font(20, .bold)
        header.text = L10n.t("shorts.title")
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        collection.backgroundColor = .clear
        collection.showsHorizontalScrollIndicator = false
        collection.dataSource = self
        collection.delegate = self
        collection.register(ShortCardCell.self, forCellWithReuseIdentifier: ShortCardCell.reuseId)
        contentView.addSubviews([icon, header, collection])
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeChanged, object: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func applyTheme() {
        header.textColor = Theme.text
        collection.reloadData()
    }

    func configure(_ list: [VideoItem]) {
        videos = list
        collection.reloadData()
        collection.contentOffset = .zero
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = contentView.bounds.width
        icon.frame = CGRect(x: 12, y: 13, width: 26, height: 26)
        header.frame = CGRect(x: 44, y: 12, width: w - 56, height: 28)
        let ch = (ShortsShelfCell.cardWidth(w) * 16 / 9).rounded()
        collection.frame = CGRect(x: 0, y: 48, width: w, height: ch)
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { return videos.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ShortCardCell.reuseId, for: indexPath) as! ShortCardCell
        cell.configure(videos[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let w = ShortsShelfCell.cardWidth(contentView.bounds.width)
        return CGSize(width: w, height: (w * 16 / 9).rounded())
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect?(videos, indexPath.item)
    }
}

// MARK: - Plain text block (channel About)

final class TextBlockCell: UITableViewCell, UITextViewDelegate {
    static let reuseId = "TextBlockCell"
    private let textView = UITextView()

    static func height(_ text: String, width: CGFloat) -> CGFloat {
        return TextMetrics.height(text, font: Theme.font(14), width: width - 32, maxLines: 0) + 40
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.dataDetectorTypes = .link
        textView.delegate = self
        contentView.addSubview(textView)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ text: String) {
        textView.font = Theme.font(14)
        textView.textColor = Theme.text
        textView.linkTextAttributes = [.foregroundColor: Theme.link]
        textView.text = text
        setNeedsLayout()
    }

    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange,
                  interaction: UITextItemInteraction) -> Bool {
        UIApplication.shared.open(URL, options: [:], completionHandler: nil)
        return false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        textView.frame = CGRect(x: 16, y: 16, width: contentView.bounds.width - 32, height: max(0, contentView.bounds.height - 32))
    }
}

// MARK: - Loading / error / empty

final class LoadingCell: UITableViewCell {
    static let reuseId = "LoadingCell"
    private let spinner = UIActivityIndicatorView(style: .white)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.addSubview(spinner)
        spinner.hidesWhenStopped = false
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func start() {
        spinner.color = Theme.secondaryText
        spinner.startAnimating()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        spinner.center = CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
    }
}

final class StateView: UIView {
    private let icon = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let button = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .whiteLarge)
    var onAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        icon.contentMode = .center
        titleLabel.font = Theme.font(16, .medium)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        detailLabel.font = Theme.font(13)
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0
        button.titleLabel?.font = Theme.font(14, .medium)
        button.layer.cornerRadius = 18
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        button.addTarget(self, action: #selector(tapped), for: .touchUpInside)
        addSubviews([icon, titleLabel, detailLabel, button, spinner])
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeChanged, object: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func applyTheme() {
        icon.tintColor = Theme.secondaryText
        titleLabel.textColor = Theme.text
        detailLabel.textColor = Theme.secondaryText
        spinner.color = Theme.secondaryText
        button.backgroundColor = Theme.chipSelectedBackground
        button.setTitleColor(Theme.chipSelectedText, for: .normal)
    }

    @objc private func tapped() { onAction?() }

    func showLoading() {
        isHidden = false
        icon.isHidden = true
        titleLabel.isHidden = true
        detailLabel.isHidden = true
        button.isHidden = true
        spinner.isHidden = false
        spinner.startAnimating()
        setNeedsLayout()
    }

    func show(icon name: String, title: String, detail: String? = nil, button text: String? = nil) {
        isHidden = false
        spinner.stopAnimating()
        spinner.isHidden = true
        icon.isHidden = false
        icon.image = Icons.image(name, size: 56)
        titleLabel.isHidden = false
        titleLabel.text = title
        detailLabel.text = detail
        detailLabel.isHidden = (detail ?? "").isEmpty
        button.isHidden = (text ?? "").isEmpty
        button.setTitle(text, for: .normal)
        setNeedsLayout()
    }

    func hide() {
        spinner.stopAnimating()
        isHidden = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        spinner.center = CGPoint(x: bounds.midX, y: bounds.midY)
        var blocks: [(UIView, CGFloat)] = []
        let tw = w - 48
        if !icon.isHidden { blocks.append((icon, 64)) }
        var th: CGFloat = 0
        if !titleLabel.isHidden {
            th = ceil(titleLabel.sizeThatFits(CGSize(width: tw, height: 400)).height)
            blocks.append((titleLabel, th))
        }
        var dh: CGFloat = 0
        if !detailLabel.isHidden {
            dh = ceil(detailLabel.sizeThatFits(CGSize(width: tw, height: 400)).height)
            blocks.append((detailLabel, dh))
        }
        if !button.isHidden { blocks.append((button, 36)) }
        var total: CGFloat = CGFloat(max(0, blocks.count - 1)) * 10
        for b in blocks { total += b.1 }
        var y = (bounds.height - total) / 2 - 20
        for (v, h) in blocks {
            if v === button {
                let bw = button.sizeThatFits(CGSize(width: 240, height: 36)).width + 40
                v.frame = CGRect(x: (w - bw) / 2, y: y, width: bw, height: h)
            } else {
                v.frame = CGRect(x: 24, y: y, width: tw, height: h)
            }
            y += h + 10
        }
    }
}

// MARK: - Chip bar

final class ChipBar: UIView {
    private let scroll = UIScrollView()
    private var buttons: [UIButton] = []
    private(set) var selectedIndex = 0
    var onSelect: ((Int) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        scroll.showsHorizontalScrollIndicator = false
        addSubview(scroll)
        NotificationCenter.default.addObserver(self, selector: #selector(restyle), name: .themeChanged, object: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    func setTitles(_ titles: [String], selected: Int = 0) {
        buttons.forEach { $0.removeFromSuperview() }
        buttons = []
        for (i, t) in titles.enumerated() {
            let b = UIButton(type: .custom)
            b.setTitle(t, for: .normal)
            b.titleLabel?.font = Theme.font(14, .medium)
            b.layer.cornerRadius = 8
            b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
            b.tag = i
            b.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            scroll.addSubview(b)
            buttons.append(b)
        }
        selectedIndex = min(selected, max(0, titles.count - 1))
        restyle()
        setNeedsLayout()
    }

    func select(_ index: Int, notify: Bool = false) {
        guard index >= 0, index < buttons.count else { return }
        selectedIndex = index
        restyle()
        if notify { onSelect?(index) }
        let f = buttons[index].frame
        scroll.scrollRectToVisible(f.insetBy(dx: -24, dy: 0), animated: true)
    }

    @objc private func tapped(_ b: UIButton) {
        selectedIndex = b.tag
        restyle()
        onSelect?(b.tag)
    }

    @objc private func restyle() {
        backgroundColor = Theme.background
        for (i, b) in buttons.enumerated() {
            let sel = i == selectedIndex
            b.backgroundColor = sel ? Theme.chipSelectedBackground : Theme.surface
            b.setTitleColor(sel ? Theme.chipSelectedText : Theme.text, for: .normal)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        var x: CGFloat = 12
        let h: CGFloat = 32
        let y = (bounds.height - h) / 2
        for b in buttons {
            let w = ceil(b.sizeThatFits(CGSize(width: 300, height: h)).width)
            b.frame = CGRect(x: x, y: y, width: w, height: h)
            x += w + 8
        }
        scroll.contentSize = CGSize(width: x + 4, height: bounds.height)
    }
}

// MARK: - Section header

final class SectionHeaderView: UITableViewHeaderFooterView {
    static let reuseId = "SectionHeaderView"
    let label = UILabel()
    let actionButton = UIButton(type: .system)
    var onAction: (() -> Void)?

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        label.font = Theme.sectionTitle
        actionButton.titleLabel?.font = Theme.font(14, .medium)
        actionButton.addTarget(self, action: #selector(tapped), for: .touchUpInside)
        contentView.addSubview(label)
        contentView.addSubview(actionButton)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func tapped() { onAction?() }

    func configure(title: String, action: String? = nil) {
        contentView.backgroundColor = Theme.background
        label.textColor = Theme.text
        label.text = title
        actionButton.setTitle(action, for: .normal)
        actionButton.setTitleColor(Theme.link, for: .normal)
        actionButton.isHidden = (action ?? "").isEmpty
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = contentView.bounds.width
        let bw: CGFloat = actionButton.isHidden ? 0 : actionButton.sizeThatFits(CGSize(width: 200, height: 30)).width + 12
        actionButton.frame = CGRect(x: w - bw - 8, y: 0, width: bw, height: contentView.bounds.height)
        label.frame = CGRect(x: 12, y: 0, width: w - 24 - bw, height: contentView.bounds.height)
    }
}

// MARK: - Bottom sheet

struct SheetAction {
    var title: String
    var icon: String?
    var subtitle: String?
    var checked: Bool
    var destructive: Bool
    var handler: () -> Void

    init(title: String, icon: String? = nil, subtitle: String? = nil, checked: Bool = false,
         destructive: Bool = false, handler: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.checked = checked
        self.destructive = destructive
        self.handler = handler
    }
}

/// Material-style modal bottom sheet. Added to the window so it covers tab bar and player.
final class SheetView: UIView {
    private let dim = UIView()
    private let panel = UIView()
    private let scroll = UIScrollView()
    private let titleLabel = UILabel()
    private var rows: [UIControl] = []
    private var actions: [SheetAction] = []
    private let rowHeight: CGFloat = 56
    private var titleHeight: CGFloat = 0
    private var bottomInset: CGFloat = 0
    private weak var hostWindow: UIWindow?

    static func show(title: String? = nil, actions: [SheetAction]) {
        guard let window = Router.shared.window else { return }
        let v = SheetView(frame: window.bounds)
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        v.build(title: title, actions: actions)
        window.addSubview(v)
        v.hostWindow = window
        v.layoutIfNeeded()
        v.animateIn()
    }

    private func build(title: String?, actions: [SheetAction]) {
        self.actions = actions
        dim.backgroundColor = UIColor(white: 0, alpha: 0.5)
        dim.alpha = 0
        dim.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissTapped)))
        addSubview(dim)

        panel.backgroundColor = Theme.sheetBackground
        panel.layer.cornerRadius = 16
        panel.clipsToBounds = true
        addSubview(panel)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        panel.addGestureRecognizer(pan)

        if let t = title, !t.isEmpty {
            titleLabel.text = t
            titleLabel.font = Theme.font(16, .bold)
            titleLabel.textColor = Theme.text
            titleHeight = 52
            panel.addSubview(titleLabel)
        }
        panel.addSubview(scroll)
        scroll.showsVerticalScrollIndicator = false

        for (i, a) in actions.enumerated() {
            let row = UIControl()
            row.tag = i
            row.addTarget(self, action: #selector(rowTapped(_:)), for: .touchUpInside)

            let color = a.destructive ? Theme.red : Theme.text
            if let ic = a.icon {
                let iv = UIImageView(image: Icons.image(ic, size: 24))
                iv.tintColor = color
                iv.frame = CGRect(x: 16, y: (rowHeight - 24) / 2, width: 24, height: 24)
                iv.isUserInteractionEnabled = false
                row.addSubview(iv)
            }
            let tl = UILabel()
            tl.text = a.title
            tl.font = Theme.font(16)
            tl.textColor = color
            tl.tag = 9001
            tl.isUserInteractionEnabled = false
            row.addSubview(tl)
            if let s = a.subtitle, !s.isEmpty {
                let sl = UILabel()
                sl.text = s
                sl.font = Theme.font(12)
                sl.textColor = Theme.secondaryText
                sl.tag = 9002
                sl.isUserInteractionEnabled = false
                row.addSubview(sl)
            }
            if a.checked {
                let c = UIImageView(image: Icons.image("check", size: 22))
                c.tintColor = Theme.text
                c.tag = 9003
                c.isUserInteractionEnabled = false
                row.addSubview(c)
            }
            scroll.addSubview(row)
            rows.append(row)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dim.frame = bounds
        let pw = min(bounds.width, 560) // on an iPad the sheet is a centred panel, not a full-width bar
        let px = ((bounds.width - pw) / 2).rounded()
        var safeBottom: CGFloat = 0
        if #available(iOS 11.0, *) { safeBottom = safeAreaInsets.bottom }
        bottomInset = safeBottom
        let contentH = CGFloat(rows.count) * rowHeight
        let maxH = bounds.height * 0.7 - titleHeight
        let scrollH = min(contentH, maxH)
        let panelH = titleHeight + scrollH + 8 + safeBottom
        let wasHidden = panel.transform != .identity
        panel.transform = .identity
        panel.frame = CGRect(x: px, y: bounds.height - panelH, width: pw, height: panelH)
        if wasHidden && dim.alpha == 0 { panel.transform = CGAffineTransform(translationX: 0, y: panelH) }
        titleLabel.frame = CGRect(x: 16, y: 0, width: pw - 32, height: titleHeight)
        scroll.frame = CGRect(x: 0, y: titleHeight, width: pw, height: scrollH)
        scroll.contentSize = CGSize(width: pw, height: contentH)
        for (i, row) in rows.enumerated() {
            row.frame = CGRect(x: 0, y: CGFloat(i) * rowHeight, width: pw, height: rowHeight)
            let hasIcon = actions[i].icon != nil
            let tx: CGFloat = hasIcon ? 60 : 16
            let tw = pw - tx - 52
            if let tl = row.viewWithTag(9001) as? UILabel {
                if let sl = row.viewWithTag(9002) as? UILabel {
                    tl.frame = CGRect(x: tx, y: 9, width: tw, height: 21)
                    sl.frame = CGRect(x: tx, y: 31, width: tw, height: 16)
                } else {
                    tl.frame = CGRect(x: tx, y: 0, width: tw, height: rowHeight)
                }
            }
            if let c = row.viewWithTag(9003) {
                c.frame = CGRect(x: pw - 16 - 22, y: (rowHeight - 22) / 2, width: 22, height: 22)
            }
        }
    }

    private func animateIn() {
        let h = panel.frame.height
        panel.transform = CGAffineTransform(translationX: 0, y: h)
        UIView.animate(withDuration: 0.26, delay: 0, options: [.curveEaseOut], animations: {
            self.panel.transform = .identity
            self.dim.alpha = 1
        }, completion: nil)
    }

    private func animateOut(then: (() -> Void)? = nil) {
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseIn], animations: {
            self.panel.transform = CGAffineTransform(translationX: 0, y: self.panel.frame.height)
            self.dim.alpha = 0
        }, completion: { _ in
            self.removeFromSuperview()
            then?()
        })
    }

    @objc private func dismissTapped() { animateOut() }

    @objc private func rowTapped(_ row: UIControl) {
        let a = actions[row.tag]
        animateOut { a.handler() }
    }

    @objc private func panned(_ g: UIPanGestureRecognizer) {
        let dy = max(0, g.translation(in: self).y)
        switch g.state {
        case .changed:
            panel.transform = CGAffineTransform(translationX: 0, y: dy)
            dim.alpha = max(0, 1 - dy / max(1, panel.frame.height))
        case .ended, .cancelled:
            let v = g.velocity(in: self).y
            if dy > panel.frame.height * 0.35 || v > 900 {
                animateOut()
            } else {
                UIView.animate(withDuration: 0.2) {
                    self.panel.transform = .identity
                    self.dim.alpha = 1
                }
            }
        default: break
        }
    }
}

// MARK: - Toast

enum Toast {
    static func show(_ text: String) {
        guard let window = Router.shared.window else { return }
        let label = PaddedLabel()
        label.insets = UIEdgeInsets(top: 12, left: 18, bottom: 12, right: 18)
        label.text = text
        label.font = Theme.font(14)
        label.textColor = Theme.isDark ? UIColor(white: 0.06, alpha: 1) : .white
        label.backgroundColor = Theme.isDark ? UIColor(white: 0.95, alpha: 0.96) : UIColor(white: 0.1, alpha: 0.95)
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.numberOfLines = 2
        let maxW = window.bounds.width - 32
        let size = label.sizeThatFits(CGSize(width: maxW, height: 100))
        let w = min(maxW, size.width)
        var bottomPad: CGFloat = 110
        if #available(iOS 11.0, *) { bottomPad += window.safeAreaInsets.bottom }
        label.frame = CGRect(x: (window.bounds.width - w) / 2, y: window.bounds.height - bottomPad - size.height,
                             width: w, height: size.height)
        label.autoresizingMask = [.flexibleTopMargin, .flexibleLeftMargin, .flexibleRightMargin]
        label.alpha = 0
        window.addSubview(label)
        UIView.animate(withDuration: 0.2, animations: { label.alpha = 1 }, completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 2.0, options: [], animations: { label.alpha = 0 }, completion: { _ in
                label.removeFromSuperview()
            })
        })
    }
}
