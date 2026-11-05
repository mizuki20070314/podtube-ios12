import UIKit

/// Pill-shaped action button (like / share / save …) used in the watch page.
final class PillButton: UIButton {
    private let iconView = UIImageView()
    private let label = UILabel()
    private var iconName: String?

    init(icon: String?, title: String?) {
        super.init(frame: .zero)
        iconName = icon
        layer.cornerRadius = 18
        label.font = Theme.font(14, .medium)
        iconView.contentMode = .center
        iconView.isUserInteractionEnabled = false
        label.isUserInteractionEnabled = false
        addSubview(iconView)
        addSubview(label)
        set(icon: icon, title: title)
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeChanged, object: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func applyTheme() {
        backgroundColor = Theme.surface
        label.textColor = Theme.text
        iconView.tintColor = Theme.text
    }

    func set(icon: String?, title: String?) {
        iconName = icon
        if let i = icon {
            iconView.image = Icons.image(i, size: 20)
            iconView.isHidden = false
        } else {
            iconView.isHidden = true
        }
        label.text = title
        label.isHidden = (title ?? "").isEmpty
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        var w: CGFloat = 14
        if !iconView.isHidden { w += 20 }
        if !label.isHidden {
            if !iconView.isHidden { w += 8 }
            w += ceil(label.sizeThatFits(CGSize(width: 300, height: 30)).width)
        }
        w += 14
        return CGSize(width: w, height: 36)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var x: CGFloat = 14
        if !iconView.isHidden {
            iconView.frame = CGRect(x: x, y: (bounds.height - 20) / 2, width: 20, height: 20)
            x += 28
        }
        if !label.isHidden {
            label.frame = CGRect(x: x, y: 0, width: bounds.width - x - 14, height: bounds.height)
        }
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }
}

/// Everything above the related-videos list: title, description, actions, channel row and comment teaser.
final class WatchHeaderView: UIView, UITextViewDelegate {
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let moreLabel = UILabel()
    private let descView = UITextView()
    private let actionScroll = UIScrollView()
    private let likePill = UIView()
    private let likeButton = UIButton(type: .custom)
    private let likeIcon = UIImageView()
    private let likeLabel = UILabel()
    private let likeDivider = UIView()
    private let dislikeButton = UIButton(type: .custom)
    private let dislikeIcon = UIImageView()
    private let shareButton = PillButton(icon: "share_outline", title: L10n.t("video.share"))
    private let saveButton = PillButton(icon: "playlist_add", title: L10n.t("video.save"))
    private let downloadButton = PillButton(icon: "file_download", title: L10n.t("video.download"))
    private let channelRow = UIView()
    private let avatar = UIImageView()
    private let channelName = UILabel()
    private let subsLabel = UILabel()
    private let subscribeButton = SubscribeButton()
    private let commentsCard = UIControl()
    private let commentsTitle = UILabel()
    private let commentsCount = UILabel()
    private let commentAvatar = UIImageView()
    private let commentText = UILabel()
    private let commentsChevron = UIImageView()
    private let divider = UIView()
    private let upNextLabel = UILabel()
    private let autoplayLabel = UILabel()
    private let autoplaySwitch = UISwitch()

    private(set) var video: VideoItem?
    private var info: WatchInfo?
    private var channel: ChannelItem?
    private var expanded = false
    private var disliked = false
    private var hasComments = false
    private var previewComment: Comment?

    var onChannel: (() -> Void)?
    var onOpenComments: (() -> Void)?
    var onSeek: ((Double) -> Void)?
    var onNeedsLayout: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = Theme.font(17, .semibold)
        titleLabel.numberOfLines = 2
        metaLabel.font = Theme.font(12)
        moreLabel.font = Theme.font(12, .semibold)
        moreLabel.text = L10n.t("common.more")

        descView.isEditable = false
        descView.isScrollEnabled = false
        descView.backgroundColor = .clear
        descView.textContainerInset = .zero
        descView.textContainer.lineFragmentPadding = 0
        descView.delegate = self
        descView.isHidden = true

        let titleTap = UITapGestureRecognizer(target: self, action: #selector(toggleExpanded))
        titleLabel.isUserInteractionEnabled = true
        titleLabel.addGestureRecognizer(titleTap)
        let metaTap = UITapGestureRecognizer(target: self, action: #selector(toggleExpanded))
        metaLabel.isUserInteractionEnabled = true
        metaLabel.addGestureRecognizer(metaTap)
        let moreTap = UITapGestureRecognizer(target: self, action: #selector(toggleExpanded))
        moreLabel.isUserInteractionEnabled = true
        moreLabel.addGestureRecognizer(moreTap)

        // like / dislike pill
        likePill.layer.cornerRadius = 18
        likePill.clipsToBounds = true
        likeLabel.font = Theme.font(14, .medium)
        likeIcon.contentMode = .center
        dislikeIcon.contentMode = .center
        likeButton.addTarget(self, action: #selector(likeTapped), for: .touchUpInside)
        dislikeButton.addTarget(self, action: #selector(dislikeTapped), for: .touchUpInside)
        likePill.addSubviews([likeIcon, likeLabel, likeButton, likeDivider, dislikeIcon, dislikeButton])
        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        downloadButton.addTarget(self, action: #selector(downloadTapped), for: .touchUpInside)
        actionScroll.showsHorizontalScrollIndicator = false
        actionScroll.addSubviews([likePill, shareButton, downloadButton, saveButton])
        NotificationCenter.default.addObserver(self, selector: #selector(refreshDownload), name: .downloadsChanged, object: nil)

        // channel row
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = 20
        channelName.font = Theme.font(15, .medium)
        subsLabel.font = Theme.font(12)
        subscribeButton.addTarget(self, action: #selector(subscribeTapped), for: .touchUpInside)
        channelRow.addSubviews([avatar, channelName, subsLabel, subscribeButton])
        let rowTap = UITapGestureRecognizer(target: self, action: #selector(channelTapped))
        channelRow.addGestureRecognizer(rowTap)

        // comments teaser
        commentsCard.layer.cornerRadius = 12
        commentsCard.addTarget(self, action: #selector(commentsTapped), for: .touchUpInside)
        commentsTitle.font = Theme.font(14, .semibold)
        commentsTitle.text = L10n.t("video.comments")
        commentsCount.font = Theme.font(12)
        commentAvatar.contentMode = .scaleAspectFill
        commentAvatar.clipsToBounds = true
        commentAvatar.layer.cornerRadius = 12
        commentText.font = Theme.font(13)
        commentText.numberOfLines = 2
        commentsChevron.image = Icons.image("chevron_right", size: 20)
        commentsChevron.contentMode = .center
        for v in [commentsTitle, commentsCount, commentAvatar, commentText, commentsChevron] as [UIView] {
            v.isUserInteractionEnabled = false
        }
        commentsCard.addSubviews([commentsTitle, commentsCount, commentAvatar, commentText, commentsChevron])

        upNextLabel.font = Theme.font(16, .bold)
        upNextLabel.text = L10n.t("video.nextUp")
        autoplayLabel.font = Theme.font(12)
        autoplayLabel.text = L10n.t("video.autoplay")
        autoplaySwitch.onTintColor = Theme.red
        autoplaySwitch.isOn = Settings.autoplay
        autoplaySwitch.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        autoplaySwitch.addTarget(self, action: #selector(autoplayChanged), for: .valueChanged)
        addSubviews([titleLabel, metaLabel, moreLabel, descView, actionScroll, channelRow, commentsCard, divider,
                     upNextLabel, autoplayLabel, autoplaySwitch])
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .storeChanged, object: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func applyTheme() {
        backgroundColor = Theme.background
        titleLabel.textColor = Theme.text
        metaLabel.textColor = Theme.secondaryText
        moreLabel.textColor = Theme.text
        likePill.backgroundColor = Theme.surface
        likeLabel.textColor = Theme.text
        likeIcon.tintColor = Theme.text
        dislikeIcon.tintColor = Theme.text
        likeDivider.backgroundColor = Theme.surfaceHigh
        channelName.textColor = Theme.text
        subsLabel.textColor = Theme.secondaryText
        avatar.backgroundColor = Theme.surface
        commentsCard.backgroundColor = Theme.surface
        commentsTitle.textColor = Theme.text
        commentsCount.textColor = Theme.secondaryText
        commentText.textColor = Theme.text
        commentsChevron.tintColor = Theme.secondaryText
        commentAvatar.backgroundColor = Theme.surfaceHigh
        divider.backgroundColor = Theme.divider
        upNextLabel.textColor = Theme.text
        autoplayLabel.textColor = Theme.secondaryText
        autoplaySwitch.onTintColor = Theme.red
        refreshActions()
        if expanded { renderDescription() }
    }

    @objc private func storeChanged() {
        refreshActions()
        if let c = channel { subscribeButton.setSubscribed(Store.shared.isSubscribed(c.id)) }
    }

    // MARK: Configure

    /// Quick pass with the data that is already known from the list item.
    func configure(preview v: VideoItem) {
        video = v
        info = nil
        expanded = false
        disliked = false
        hasComments = false
        previewComment = nil
        var ch = ChannelItem(id: v.channelId)
        ch.name = v.channelName
        ch.avatar = v.channelAvatar
        channel = v.channelId.isEmpty ? nil : ch
        titleLabel.text = v.title
        metaLabel.text = [v.views, v.published].filter { !$0.isEmpty }.joined(separator: " · ")
        descView.isHidden = true
        moreLabel.text = L10n.t("common.more")
        applyChannel()
        refreshActions()
        commentAvatar.image = nil
        commentText.text = nil
        commentsCount.text = nil
        setNeedsLayout()
    }

    func configure(info i: WatchInfo) {
        info = i
        if var v = video {
            if !i.title.isEmpty { v.title = i.title }
            video = v
        }
        titleLabel.text = i.title.isEmpty ? video?.title : i.title
        let views = expanded ? i.views : (i.viewsShort.isEmpty ? i.views : i.viewsShort)
        metaLabel.text = [views, i.date].filter { !$0.isEmpty }.joined(separator: " · ")
        if let c = i.channel {
            channel = c
            if var v = video {
                v.channelId = c.id
                v.channelName = c.name
                v.channelAvatar = c.avatar
                video = v
            }
        }
        hasComments = i.commentsToken != nil
        commentsCount.text = i.commentCount
        applyChannel()
        refreshActions(likeText: i.likeText)
        if expanded { renderDescription() }
        setNeedsLayout()
    }

    func configure(previewComment c: Comment?) {
        previewComment = c
        if let c = c {
            commentAvatar.setRemote(c.avatar, maxPixel: 64, fade: false)
            commentText.text = c.text
        } else {
            commentAvatar.image = nil
            commentText.text = nil
        }
        setNeedsLayout()
    }

    private func applyChannel() {
        guard let c = channel else {
            channelRow.isHidden = true
            return
        }
        channelRow.isHidden = false
        channelName.text = c.name
        subsLabel.text = c.subscribers
        avatar.setRemote(c.avatar, maxPixel: 96, fade: false)
        subscribeButton.setSubscribed(Store.shared.isSubscribed(c.id))
    }

    private func refreshActions(likeText: String? = nil) {
        guard let v = video else { return }
        let liked = Store.shared.isLiked(v.id)
        likeIcon.image = Icons.image("thumb_up" + (liked ? "" : "_outline"), size: 20)
        dislikeIcon.image = Icons.image("thumb_down" + (disliked ? "" : "_outline"), size: 20)
        if let t = likeText { likeLabel.text = t.isEmpty ? L10n.t("video.like") : t }
        else if likeLabel.text == nil { likeLabel.text = L10n.t("video.like") }
        shareButton.set(icon: "share_outline", title: L10n.t("video.share"))
        saveButton.set(icon: Store.shared.isWatchLater(v.id) ? "bookmark" : "playlist_add", title: L10n.t("video.save"))
        let dm = DownloadManager.shared
        if dm.record(for: v.id) != nil {
            downloadButton.set(icon: "offline_pin", title: L10n.t("downloads.saved"))
        } else if let f = dm.fraction(for: v.id), dm.isDownloading(v.id) {
            downloadButton.set(icon: "file_download", title: "\(Int(f * 100))%")
        } else {
            downloadButton.set(icon: "file_download", title: L10n.t("video.download"))
        }
        setNeedsLayout()
    }

    // MARK: Actions

    func expandDescription() { if !expanded { toggleExpanded() } }

    @objc private func toggleExpanded() {
        expanded = !expanded
        if let i = info {
            let views = expanded ? i.views : (i.viewsShort.isEmpty ? i.views : i.viewsShort)
            metaLabel.text = [views, i.date].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        moreLabel.text = expanded ? L10n.t("common.less") : L10n.t("common.more")
        descView.isHidden = !expanded
        if expanded { renderDescription() }
        titleLabel.numberOfLines = expanded ? 0 : 2
        setNeedsLayout()
        onNeedsLayout?()
    }

    @objc private func likeTapped() {
        guard let v = video else { return }
        if disliked { disliked = false }
        Store.shared.toggleLike(v)
        if Store.shared.isLiked(v.id) { Toast.show(L10n.t("library.liked")) }
    }

    @objc private func dislikeTapped() {
        disliked = !disliked
        if disliked, let v = video, Store.shared.isLiked(v.id) { Store.shared.toggleLike(v) }
        refreshActions()
    }

    @objc private func shareTapped() {
        if let v = video { Router.shared.share(video: v) }
    }

    @objc private func downloadTapped() {
        guard let v = video else { return }
        let dm = DownloadManager.shared
        if dm.record(for: v.id) != nil {
            SheetView.show(title: L10n.t("video.download"), actions: [
                SheetAction(title: L10n.t("common.delete"), icon: "delete", destructive: true) { dm.delete(v.id) }
            ])
        } else if dm.isDownloading(v.id) {
            SheetView.show(title: L10n.t("video.download"), actions: [
                SheetAction(title: L10n.t("common.cancel"), icon: "close", destructive: true) { dm.cancel(v.id) }
            ])
        } else {
            Router.shared.startDownload(v)
        }
    }

    @objc private func refreshDownload() {
        refreshActions()
        setNeedsLayout()
        onNeedsLayout?()
    }

    @objc private func saveTapped() {
        if let v = video { Router.shared.showPlaylistPicker(for: v) }
    }

    @objc private func channelTapped() { onChannel?() }

    @objc private func subscribeTapped() {
        guard let c = channel else { return }
        if Store.shared.isSubscribed(c.id) { Store.shared.unsubscribe(c.id) } else { Store.shared.subscribe(c) }
        subscribeButton.setSubscribed(Store.shared.isSubscribed(c.id))
    }

    @objc private func commentsTapped() { onOpenComments?() }

    @objc private func autoplayChanged() { Settings.autoplay = autoplaySwitch.isOn }

    // MARK: Description

    private func renderDescription() {
        let text = info?.description ?? ""
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 2
        let attr = NSMutableAttributedString(string: text, attributes: [
            .font: Theme.font(14), .foregroundColor: Theme.text, .paragraphStyle: para
        ])
        let ns = text as NSString
        // links
        if let re = try? NSRegularExpression(pattern: "https?://[^\\s]+", options: []) {
            for m in re.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length)) {
                if let url = URL(string: ns.substring(with: m.range)) {
                    attr.addAttributes([.link: url, .foregroundColor: Theme.link], range: m.range)
                }
            }
        }
        // hashtags -> search
        if let re = try? NSRegularExpression(pattern: "#[^\\s#]+", options: []) {
            for m in re.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length)) {
                let tag = ns.substring(with: m.range)
                if let enc = tag.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
                   let url = URL(string: "podtube-search://\(enc)") {
                    attr.addAttributes([.link: url, .foregroundColor: Theme.link], range: m.range)
                }
            }
        }
        // timestamps -> seek links
        if let re = try? NSRegularExpression(pattern: "(?<![0-9:])([0-9]{1,2}:)?[0-5]?[0-9]:[0-5][0-9](?![0-9:])", options: []) {
            for m in re.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length)) {
                let s = ns.substring(with: m.range)
                if let secs = Format.parseDuration(s), let url = URL(string: "podtube-seek://\(secs)") {
                    attr.addAttributes([.link: url, .foregroundColor: Theme.link], range: m.range)
                }
            }
        }
        descView.linkTextAttributes = [.foregroundColor: Theme.link]
        descView.attributedText = attr
    }

    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange,
                  interaction: UITextItemInteraction) -> Bool {
        if URL.scheme == "podtube-seek", let host = URL.host, let secs = Double(host) {
            onSeek?(secs)
            return false
        }
        if URL.scheme == "podtube-search", let host = URL.host, let q = host.removingPercentEncoding {
            Router.shared.openSearch(query: q)
            return false
        }
        UIApplication.shared.open(URL, options: [:], completionHandler: nil)
        return false
    }

    // MARK: Layout

    /// Lays everything out for `width` and returns the total height.
    @discardableResult
    func layout(width w: CGFloat) -> CGFloat {
        var y: CGFloat = 12
        let pad: CGFloat = 12
        let tw = w - pad * 2
        let th = TextMetrics.height(titleLabel.text ?? "", font: Theme.font(17, .semibold), width: tw, maxLines: expanded ? 0 : 2)
        titleLabel.frame = CGRect(x: pad, y: y, width: tw, height: th)
        y += th + 4
        metaLabel.frame = CGRect(x: pad, y: y, width: tw, height: 16)
        let ms = metaLabel.text ?? ""
        let mw = (ms as NSString).size(withAttributes: [.font: Theme.font(12)]).width
        moreLabel.sizeToFit()
        if expanded {
            moreLabel.isHidden = true
        } else {
            moreLabel.isHidden = false
            moreLabel.frame = CGRect(x: pad + min(mw, tw - 70) + 6, y: y, width: 80, height: 16)
        }
        y += 22
        if expanded {
            let size = descView.sizeThatFits(CGSize(width: tw, height: CGFloat.greatestFiniteMagnitude))
            descView.frame = CGRect(x: pad, y: y, width: tw, height: ceil(size.height))
            y += ceil(size.height) + 8
            moreLabel.isHidden = false
            moreLabel.frame = CGRect(x: pad, y: y, width: tw, height: 18)
            y += 26
        }

        // actions
        let ah: CGFloat = 36
        var x: CGFloat = pad
        let likeTextWidth: CGFloat = ceil(((likeLabel.text ?? "") as NSString).size(withAttributes: [.font: Theme.font(14, .medium)]).width)
        let likeW: CGFloat = max(104, likeTextWidth + 100)
        likePill.frame = CGRect(x: x, y: 0, width: likeW, height: ah)
        likeIcon.frame = CGRect(x: 12, y: 8, width: 20, height: 20)
        likeLabel.frame = CGRect(x: 38, y: 0, width: likeTextWidth + 4, height: ah)
        likeButton.frame = CGRect(x: 0, y: 0, width: likeW - 48, height: ah)
        likeDivider.frame = CGRect(x: likeW - 48, y: 8, width: 1, height: 20)
        dislikeIcon.frame = CGRect(x: likeW - 34, y: 8, width: 20, height: 20)
        dislikeButton.frame = CGRect(x: likeW - 48, y: 0, width: 48, height: ah)
        x += likeW + 8
        let sw = shareButton.sizeThatFits(.zero)
        shareButton.frame = CGRect(x: x, y: 0, width: sw.width, height: ah)
        x += sw.width + 8
        let dw = downloadButton.sizeThatFits(.zero)
        downloadButton.frame = CGRect(x: x, y: 0, width: dw.width, height: ah)
        x += dw.width + 8
        let vw = saveButton.sizeThatFits(.zero)
        saveButton.frame = CGRect(x: x, y: 0, width: vw.width, height: ah)
        x += vw.width + pad
        actionScroll.frame = CGRect(x: 0, y: y, width: w, height: ah)
        actionScroll.contentSize = CGSize(width: x, height: ah)
        y += ah + 14

        divider.frame = CGRect(x: 0, y: y, width: w, height: 0.5)
        y += 0.5

        // channel
        if channelRow.isHidden {
            channelRow.frame = .zero
        } else {
            let rh: CGFloat = 68
            channelRow.frame = CGRect(x: 0, y: y, width: w, height: rh)
            avatar.frame = CGRect(x: pad, y: 14, width: 40, height: 40)
            let bw = subscribeButton.sizeThatFits(.zero).width
            subscribeButton.frame = CGRect(x: w - bw - pad, y: 17, width: bw, height: 34)
            let nx: CGFloat = pad + 40 + 12
            let nw = subscribeButton.frame.minX - nx - 8
            channelName.frame = CGRect(x: nx, y: 17, width: nw, height: 18)
            subsLabel.frame = CGRect(x: nx, y: 36, width: nw, height: 16)
            y += rh
        }

        // comments teaser
        if hasComments {
            let ch: CGFloat = (previewComment != nil) ? 86 : 44
            commentsCard.isHidden = false
            commentsCard.frame = CGRect(x: pad, y: y + 4, width: tw, height: ch)
            commentsTitle.sizeToFit()
            commentsTitle.frame = CGRect(x: 12, y: 12, width: commentsTitle.frame.width, height: 18)
            commentsCount.sizeToFit()
            commentsCount.frame = CGRect(x: commentsTitle.frame.maxX + 8, y: 14, width: min(commentsCount.frame.width, tw - 120), height: 16)
            commentsChevron.frame = CGRect(x: tw - 34, y: 10, width: 24, height: 24)
            if previewComment != nil {
                commentAvatar.isHidden = false
                commentText.isHidden = false
                commentAvatar.frame = CGRect(x: 12, y: 42, width: 24, height: 24)
                commentText.frame = CGRect(x: 46, y: 38, width: tw - 46 - 12, height: 38)
            } else {
                commentAvatar.isHidden = true
                commentText.isHidden = true
            }
            y += ch + 12
        } else {
            commentsCard.isHidden = true
            y += 6
        }
        // "Up next" row with the autoplay switch
        autoplaySwitch.isOn = Settings.autoplay
        upNextLabel.frame = CGRect(x: pad, y: y, width: w - 140, height: 40)
        autoplaySwitch.frame = CGRect(x: w - 51 * 0.8 - pad, y: y + (40 - 31 * 0.8) / 2, width: 51 * 0.8, height: 31 * 0.8)
        let alw: CGFloat = 60
        autoplayLabel.frame = CGRect(x: autoplaySwitch.frame.minX - alw - 4, y: y, width: alw, height: 40)
        autoplayLabel.textAlignment = .right
        y += 44
        return y
    }
}
