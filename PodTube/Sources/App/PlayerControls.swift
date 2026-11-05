import UIKit
import AVFoundation
import AVKit

// MARK: - Video surface

final class PlayerView: UIView {
    override class var layerClass: AnyClass { return AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { return layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
        playerLayer.player = PlayerManager.shared.player
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// Audio keeps playing in the background only if the video layer lets go of the player.
    @objc private func didEnterBackground() {
        if Settings.backgroundPlay && PlayerManager.shared.isPlaying {
            playerLayer.player = nil
        } else {
            PlayerManager.shared.pause()
        }
    }

    @objc private func willEnterForeground() {
        playerLayer.player = PlayerManager.shared.player
    }
}

// MARK: - Seek bar

final class SeekBar: UIControl {
    private let track = UIView()
    private let bufferView = UIView()
    private let playedView = UIView()
    private let thumb = UIView()
    private let thumbSize: CGFloat = 14

    var value: CGFloat = 0 { didSet { setNeedsLayout() } }
    var buffered: CGFloat = 0 { didSet { setNeedsLayout() } }
    var showsThumb = true { didSet { thumb.isHidden = !showsThumb } }
    private(set) var isScrubbing = false

    var onBegin: (() -> Void)?
    var onChange: ((CGFloat) -> Void)?
    var onEnd: ((CGFloat) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        track.backgroundColor = UIColor(white: 1, alpha: 0.3)
        bufferView.backgroundColor = UIColor(white: 1, alpha: 0.45)
        playedView.backgroundColor = Theme.red
        thumb.backgroundColor = Theme.red
        thumb.layer.cornerRadius = thumbSize / 2
        for v in [track, bufferView, playedView, thumb] {
            v.isUserInteractionEnabled = false
            addSubview(v)
        }
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = thumbSize / 2
        let w = bounds.width - inset * 2
        let h: CGFloat = isScrubbing ? 5 : 3
        let y = (bounds.height - h) / 2
        track.frame = CGRect(x: inset, y: y, width: w, height: h)
        bufferView.frame = CGRect(x: inset, y: y, width: w * min(1, max(0, buffered)), height: h)
        let pw = w * min(1, max(0, value))
        playedView.frame = CGRect(x: inset, y: y, width: pw, height: h)
        let ts = isScrubbing ? thumbSize + 6 : thumbSize
        thumb.layer.cornerRadius = ts / 2
        thumb.frame = CGRect(x: inset + pw - ts / 2, y: (bounds.height - ts) / 2, width: ts, height: ts)
    }

    private func update(_ touch: UITouch) {
        let inset = thumbSize / 2
        let w = max(1, bounds.width - inset * 2)
        let x = touch.location(in: self).x - inset
        value = min(1, max(0, x / w))
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        isScrubbing = true
        update(touch)
        onBegin?()
        onChange?(value)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        update(touch)
        onChange?(value)
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        if let t = touch { update(t) }
        isScrubbing = false
        setNeedsLayout()
        onEnd?(value)
    }

    override func cancelTracking(with event: UIEvent?) {
        isScrubbing = false
        setNeedsLayout()
        onEnd?(value)
    }
}

// MARK: - Controls overlay

final class PlayerControlsView: UIView, UIGestureRecognizerDelegate {
    private let shade = UIView()
    private let collapseButton = IconButton(icon: "keyboard_arrow_down", size: 30)
    private let captionButton = IconButton(icon: "closed_caption_off", size: 24)
    private let settingsButton = IconButton(icon: "settings", size: 24)
    private let routePicker = AVRoutePickerView()
    private let prevButton = IconButton(icon: "skip_previous", size: 34)
    private let playButton = IconButton(icon: "play_arrow", size: 44, frame: CGRect(x: 0, y: 0, width: 72, height: 72))
    private let nextButton = IconButton(icon: "skip_next", size: 34)
    private let timeLabel = UILabel()
    private let fullscreenButton = IconButton(icon: "fullscreen", size: 26)
    private let seekBar = SeekBar()
    private let thinProgress = UIView()
    private let spinner = UIActivityIndicatorView(style: .whiteLarge)
    private let errorLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private let subtitleLabel = PaddedLabel()
    private let skipIndicator = PaddedLabel()
    private let titleLabel = UILabel()
    private let chapterLabel = UILabel()

    private var timer: Timer?
    private var hideTimer: Timer?
    private(set) var controlsVisible = true
    private var scrubbing = false

    var onCollapse: (() -> Void)?
    var onFullscreen: (() -> Void)?
    var onSettings: (() -> Void)?
    var onCaptions: (() -> Void)?
    var isFullscreen = false { didSet { updateFullscreenIcon(); setNeedsLayout() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        shade.backgroundColor = UIColor(white: 0, alpha: 0.4)
        shade.isUserInteractionEnabled = false

        for b in [collapseButton, captionButton, settingsButton, prevButton, playButton, nextButton, fullscreenButton] {
            b.tintColor = .white
            b.useThemeTint = false
        }
        routePicker.tintColor = .white
        routePicker.activeTintColor = Theme.red

        timeLabel.font = Theme.font(12, .medium)
        timeLabel.textColor = .white
        chapterLabel.font = Theme.font(12)
        chapterLabel.textColor = UIColor(white: 1, alpha: 0.8)
        titleLabel.font = Theme.font(15, .medium)
        titleLabel.textColor = .white
        titleLabel.isHidden = true

        thinProgress.backgroundColor = Theme.red
        spinner.color = .white
        spinner.hidesWhenStopped = true

        errorLabel.font = Theme.font(14)
        errorLabel.textColor = .white
        errorLabel.numberOfLines = 3
        errorLabel.textAlignment = .center
        errorLabel.isHidden = true
        retryButton.setTitle(L10n.t("common.retry"), for: .normal)
        retryButton.titleLabel?.font = Theme.font(14, .medium)
        retryButton.tintColor = .white
        retryButton.layer.borderColor = UIColor.white.cgColor
        retryButton.layer.borderWidth = 1
        retryButton.layer.cornerRadius = 16
        retryButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 18, bottom: 0, right: 18)
        retryButton.isHidden = true

        subtitleLabel.font = Theme.font(15, .medium)
        subtitleLabel.textColor = .white
        subtitleLabel.backgroundColor = UIColor(white: 0, alpha: 0.7)
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 3
        subtitleLabel.insets = UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
        subtitleLabel.layer.cornerRadius = 4
        subtitleLabel.clipsToBounds = true
        subtitleLabel.isHidden = true

        skipIndicator.font = Theme.font(15, .bold)
        skipIndicator.textColor = .white
        skipIndicator.backgroundColor = UIColor(white: 0, alpha: 0.6)
        skipIndicator.layer.cornerRadius = 18
        skipIndicator.clipsToBounds = true
        skipIndicator.insets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        skipIndicator.alpha = 0

        addSubviews([shade, thinProgress, subtitleLabel, collapseButton, titleLabel, routePicker, captionButton, settingsButton,
                     prevButton, playButton, nextButton, timeLabel, chapterLabel, seekBar, fullscreenButton,
                     spinner, errorLabel, retryButton, skipIndicator])

        collapseButton.addTarget(self, action: #selector(collapseTapped), for: .touchUpInside)
        captionButton.addTarget(self, action: #selector(captionsTapped), for: .touchUpInside)
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        fullscreenButton.addTarget(self, action: #selector(fullscreenTapped), for: .touchUpInside)
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        prevButton.addTarget(self, action: #selector(prevTapped), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        seekBar.onBegin = { [weak self] in
            self?.scrubbing = true
            self?.cancelHide()
        }
        seekBar.onChange = { [weak self] v in
            guard let self = self else { return }
            let d = PlayerManager.shared.duration
            self.timeLabel.text = Format.duration(Double(v) * d) + " / " + Format.duration(d)
        }
        seekBar.onEnd = { [weak self] v in
            guard let self = self else { return }
            let d = PlayerManager.shared.duration
            PlayerManager.shared.seek(to: Double(v) * d) { self.scrubbing = false }
            self.scheduleHide()
        }

        let single = UITapGestureRecognizer(target: self, action: #selector(singleTapped(_:)))
        let double = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        double.numberOfTapsRequired = 2
        single.require(toFail: double)
        single.delegate = self
        double.delegate = self
        addGestureRecognizer(single)
        addGestureRecognizer(double)

        NotificationCenter.default.addObserver(self, selector: #selector(refreshState), name: .playerChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshState), name: .playerItemChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshCaptionIcon), name: .subtitlesChanged, object: nil)
        refreshState()
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        timer?.invalidate()
        hideTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        timer?.invalidate()
        if window != nil {
            timer = Timer.scheduledTimer(timeInterval: 0.25, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        }
    }

    func debugShow() { setControlsVisible(true, animated: false); cancelHide() }

    // MARK: Actions

    @objc private func collapseTapped() { onCollapse?() }
    @objc private func captionsTapped() { onCaptions?(); scheduleHide() }
    @objc private func settingsTapped() { onSettings?(); scheduleHide() }
    @objc private func fullscreenTapped() { onFullscreen?() }
    @objc private func prevTapped() { PlayerManager.shared.playPrevious(); scheduleHide() }
    @objc private func nextTapped() { PlayerManager.shared.playNext(); scheduleHide() }
    @objc private func retryTapped() { PlayerManager.shared.retry() }

    @objc private func playTapped() {
        PlayerManager.shared.toggle()
        scheduleHide()
    }

    @objc private func singleTapped(_ g: UITapGestureRecognizer) {
        setControlsVisible(!controlsVisible, animated: true)
    }

    @objc private func doubleTapped(_ g: UITapGestureRecognizer) {
        let x = g.location(in: self).x
        if x < bounds.width / 3 {
            PlayerManager.shared.skip(by: -10)
            flashSkip("« 10")
        } else if x > bounds.width * 2 / 3 {
            PlayerManager.shared.skip(by: 10)
            flashSkip("10 »")
        } else {
            PlayerManager.shared.toggle()
        }
    }

    private func flashSkip(_ text: String) {
        skipIndicator.text = text
        let s = skipIndicator.sizeThatFits(CGSize(width: 200, height: 60))
        let forward = text.hasSuffix("»")
        skipIndicator.frame = CGRect(x: forward ? bounds.width * 0.78 - s.width / 2 : bounds.width * 0.22 - s.width / 2,
                                     y: bounds.height / 2 - s.height / 2, width: s.width, height: s.height)
        skipIndicator.layer.removeAllAnimations()
        skipIndicator.alpha = 1
        UIView.animate(withDuration: 0.5, delay: 0.35, options: [], animations: { self.skipIndicator.alpha = 0 }, completion: nil)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var v: UIView? = touch.view
        while let cur = v, cur !== self {
            if cur is UIControl { return false }
            v = cur.superview
        }
        return true
    }

    // MARK: Visibility

    func setControlsVisible(_ visible: Bool, animated: Bool) {
        controlsVisible = visible
        let alpha: CGFloat = visible ? 1 : 0
        let changes = {
            self.shade.alpha = alpha
            for v in [self.collapseButton, self.captionButton, self.settingsButton, self.routePicker, self.prevButton,
                      self.nextButton, self.timeLabel, self.chapterLabel, self.fullscreenButton, self.titleLabel] as [UIView] {
                v.alpha = alpha
            }
            self.seekBar.alpha = alpha
            self.thinProgress.alpha = visible ? 0 : 1
            self.updatePlayButtonAlpha()
            self.layoutSubtitle()
        }
        if animated { UIView.animate(withDuration: 0.2, animations: changes) } else { changes() }
        if visible { scheduleHide() } else { cancelHide() }
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        guard PlayerManager.shared.state == .playing else { return }
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
            guard let self = self, !self.scrubbing else { return }
            self.setControlsVisible(false, animated: true)
        }
    }

    private func cancelHide() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    private func updatePlayButtonAlpha() {
        let st = PlayerManager.shared.state
        let busy = st == .loading || st == .buffering
        let failed = st == .failed
        playButton.alpha = (controlsVisible && !busy && !failed) ? 1 : 0
        playButton.isUserInteractionEnabled = controlsVisible && !busy && !failed
    }

    // MARK: State

    @objc private func refreshState() {
        let pm = PlayerManager.shared
        let st = pm.state
        switch st {
        case .playing: playButton.setIcon("pause")
        case .ended: playButton.setIcon("refresh")
        default: playButton.setIcon("play_arrow")
        }
        let busy = st == .loading || st == .buffering
        if busy { spinner.startAnimating() } else { spinner.stopAnimating() }
        errorLabel.isHidden = st != .failed
        retryButton.isHidden = st != .failed
        errorLabel.text = pm.errorMessage
        prevButton.isEnabled = pm.hasPrevious || pm.currentTime > 5
        prevButton.alpha = (controlsVisible ? 1 : 0) * (pm.hasPrevious ? 1 : 0.35)
        nextButton.isEnabled = pm.hasNext
        nextButton.alpha = (controlsVisible ? 1 : 0) * (pm.hasNext ? 1 : 0.35)
        titleLabel.text = pm.video?.title
        updatePlayButtonAlpha()
        if st == .playing { scheduleHide() } else if st != .playing { cancelHide(); if st != .loading && !controlsVisible { setControlsVisible(true, animated: true) } }
        refreshCaptionIcon()
        setNeedsLayout()
    }

    @objc private func refreshCaptionIcon() {
        let sc = SubtitleController.shared
        captionButton.isHidden = sc.tracks.isEmpty
        captionButton.setIcon(sc.isEnabled ? "closed_caption" : "closed_caption_off")
        if !sc.isEnabled { subtitleLabel.isHidden = true }
    }

    @objc private func tick() {
        let pm = PlayerManager.shared
        let d = pm.duration
        let t = pm.currentTime
        let live = pm.isLive
        seekBar.isHidden = live
        thinProgress.isHidden = live
        if !scrubbing {
            let v: CGFloat = d > 0 ? CGFloat(t / d) : 0
            seekBar.value = v
            seekBar.buffered = d > 0 ? CGFloat(pm.bufferedTime / d) : 0
            if live {
                timeLabel.text = "● " + L10n.t("video.live")
            } else {
                timeLabel.text = Format.duration(t) + " / " + Format.duration(d)
            }
            thinProgress.frame = CGRect(x: 0, y: bounds.height - 2, width: bounds.width * v, height: 2)
        }
        if let ch = Chapters.current(pm.chapters, at: t), !live {
            chapterLabel.text = "· " + ch.title
        } else {
            chapterLabel.text = nil
        }
        // captions
        if SubtitleController.shared.isEnabled, let text = SubtitleController.shared.text(at: t) {
            if subtitleLabel.text != text {
                subtitleLabel.text = text
                layoutSubtitle()
            }
            subtitleLabel.isHidden = false
        } else {
            subtitleLabel.isHidden = true
        }
    }

    private func updateFullscreenIcon() {
        fullscreenButton.setIcon(isFullscreen ? "fullscreen_exit" : "fullscreen")
        titleLabel.isHidden = !isFullscreen
    }

    // MARK: Layout

    private func layoutSubtitle() {
        let w = bounds.width
        let maxW = w - 32
        let s = subtitleLabel.sizeThatFits(CGSize(width: maxW, height: 100))
        let bottomGap: CGFloat = controlsVisible ? 52 : 14
        subtitleLabel.frame = CGRect(x: (w - min(maxW, s.width)) / 2, y: bounds.height - bottomGap - s.height,
                                     width: min(maxW, s.width), height: s.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        let h = bounds.height
        var left: CGFloat = 0
        var right: CGFloat = 0
        if #available(iOS 11.0, *) {
            left = safeAreaInsets.left
            right = safeAreaInsets.right
        }
        shade.frame = bounds
        collapseButton.frame = CGRect(x: 4 + left, y: 2, width: 44, height: 44)
        settingsButton.frame = CGRect(x: w - 48 - right, y: 2, width: 44, height: 44)
        captionButton.frame = CGRect(x: w - 96 - right, y: 2, width: 44, height: 44)
        routePicker.frame = CGRect(x: w - 144 - right, y: 2, width: 44, height: 44)
        titleLabel.frame = CGRect(x: 52 + left, y: 2, width: w - 52 - 150 - left - right, height: 44)
        let cx = w / 2
        let cy = h / 2
        playButton.frame = CGRect(x: cx - 36, y: cy - 36, width: 72, height: 72)
        prevButton.frame = CGRect(x: cx - 36 - 24 - 54, y: cy - 27, width: 54, height: 54)
        nextButton.frame = CGRect(x: cx + 36 + 24, y: cy - 27, width: 54, height: 54)
        spinner.center = CGPoint(x: cx, y: cy)
        timeLabel.frame = CGRect(x: 14 + left, y: h - 54, width: 100, height: 18)
        chapterLabel.frame = CGRect(x: 14 + left + 100, y: h - 54, width: max(0, w - 14 - left - 100 - 60 - right), height: 18)
        fullscreenButton.frame = CGRect(x: w - 48 - right, y: h - 56, width: 44, height: 44)
        seekBar.frame = CGRect(x: 6 + left, y: h - 30, width: w - 12 - left - right, height: 28)
        errorLabel.frame = CGRect(x: 24, y: cy - 44, width: w - 48, height: 50)
        retryButton.frame = CGRect(x: cx - 50, y: cy + 14, width: 100, height: 32)
        thinProgress.frame = CGRect(x: 0, y: h - 2, width: thinProgress.frame.width, height: 2)
        layoutSubtitle()
    }
}
