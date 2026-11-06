import UIKit
import AVFoundation
import AVKit

// MARK: - Video surface

final class PlayerView: UIView {
    override class var layerClass: AnyClass { return AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { return layer as! AVPlayerLayer }
    private let pipLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
        pipLabel.text = L10n.t("pip.active")
        pipLabel.font = Theme.font(13, .medium)
        pipLabel.textColor = UIColor(white: 1, alpha: 0.7)
        pipLabel.textAlignment = .center
        pipLabel.numberOfLines = 2
        pipLabel.isHidden = true
        addSubview(pipLabel)
        playerLayer.player = PlayerManager.shared.player
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pipChanged), name: .pipChanged, object: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// Audio keeps playing in the background only if the video layer lets go of the player.
    @objc private func didEnterBackground() {
        // the PiP window keeps drawing the video and playing its sound: leave the player alone
        if PictureInPicture.shared.isActive { return }
        if Settings.backgroundPlay && PlayerManager.shared.isPlaying {
            playerLayer.player = nil
        } else {
            PlayerManager.shared.pause()
        }
    }

    @objc private func pipChanged() { setNeedsLayout() }

    override func layoutSubviews() {
        super.layoutSubviews()
        // this layer stays blank while the PiP window has the picture; say where it went (not in the small mini-player thumbnail)
        pipLabel.isHidden = !(PictureInPicture.shared.isActive && bounds.width >= 200)
        pipLabel.frame = CGRect(x: 12, y: bounds.midY + 44, width: max(0, bounds.width - 24), height: 36)
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
    /// True while the finger is held well above the bar: the position then follows the finger's sideways movement at
    /// the pace of `fineValuePerPoint`, not the place on the bar the finger is over.
    private(set) var isFine = false
    /// What one point of sideways movement is worth (as a share of the whole video) while fine-adjusting; nil where
    /// there is nothing to show for it (no preview frames), so that the bar always follows the finger.
    var fineValuePerPoint: CGFloat?
    private var fineAnchorX: CGFloat = 0
    private var fineAnchorValue: CGFloat = 0
    /// How far above the middle of the bar the finger has to be to enter fine-adjusting, and to leave it again.
    private static let fineEnter: CGFloat = 36
    private static let fineLeave: CGFloat = 14

    var onBegin: (() -> Void)?
    var onChange: ((CGFloat) -> Void)?
    var onFineChanged: ((Bool) -> Void)?
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
        let p = touch.location(in: self)
        let lift = bounds.midY - p.y
        let wantsFine = fineValuePerPoint != nil && lift >= (isFine ? SeekBar.fineLeave : SeekBar.fineEnter)
        if wantsFine != isFine {
            isFine = wantsFine
            fineAnchorX = p.x
            fineAnchorValue = value
            onFineChanged?(wantsFine)
        }
        if isFine, let perPoint = fineValuePerPoint {
            value = min(1, max(0, fineAnchorValue + (p.x - fineAnchorX) * perPoint))
            return
        }
        let inset = thumbSize / 2
        let w = max(1, bounds.width - inset * 2)
        value = min(1, max(0, (p.x - inset) / w))
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        isScrubbing = true
        isFine = false
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
        isFine = false
        setNeedsLayout()
        onEnd?(value)
    }

    override func cancelTracking(with event: UIEvent?) {
        isScrubbing = false
        isFine = false
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
    private let pipButton = IconButton(icon: "picture_in_picture_alt", size: 24)
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
    private let statsView = StatsOverlayView()
    private let scrubPill = PaddedLabel()
    private let filmStrip = FilmStripView()

    private var timer: Timer?
    private var hideTimer: Timer?
    private(set) var controlsVisible = true
    /// From the finger touching the seek bar until the seek it asked for has landed (the bar ignores the player meanwhile).
    private var scrubbing = false
    /// A finger holds the seek bar: the controls stand aside for the pill, and for the film strip once it slides up.
    private var fingerDown = false
    private var scrubFine = false
    private var scrubTime: Double = 0
    private var scrubStoryboard: Storyboard?
    private var statsTicks = 0
    private var chromeVisible: Bool { return controlsVisible && !fingerDown }
    /// The film strip: about a third of the player, but neither a sliver nor a wall.
    private var stripHeight: CGFloat { return min(120, max(56, (bounds.height * 0.3).rounded())) }

    var onCollapse: (() -> Void)?
    var onFullscreen: (() -> Void)?
    var onSettings: (() -> Void)?
    var onCaptions: (() -> Void)?
    var onPictureInPicture: (() -> Void)?
    var isFullscreen = false { didSet { updateFullscreenIcon(); setNeedsLayout() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        shade.backgroundColor = UIColor(white: 0, alpha: 0.4)
        shade.isUserInteractionEnabled = false

        for b in [collapseButton, captionButton, settingsButton, pipButton, prevButton, playButton, nextButton, fullscreenButton] {
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

        scrubPill.textAlignment = .center
        scrubPill.backgroundColor = UIColor(white: 0, alpha: 0.6)
        scrubPill.insets = UIEdgeInsets(top: 5, left: 14, bottom: 5, right: 14)
        scrubPill.clipsToBounds = true
        scrubPill.isUserInteractionEnabled = false
        scrubPill.alpha = 0
        filmStrip.alpha = 0

        addSubviews([shade, statsView, thinProgress, subtitleLabel, collapseButton, titleLabel, routePicker, pipButton, captionButton, settingsButton,
                     prevButton, playButton, nextButton, timeLabel, chapterLabel, seekBar, fullscreenButton,
                     spinner, errorLabel, retryButton, filmStrip, scrubPill, skipIndicator])

        collapseButton.addTarget(self, action: #selector(collapseTapped), for: .touchUpInside)
        captionButton.addTarget(self, action: #selector(captionsTapped), for: .touchUpInside)
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        pipButton.addTarget(self, action: #selector(pipTapped), for: .touchUpInside)
        fullscreenButton.addTarget(self, action: #selector(fullscreenTapped), for: .touchUpInside)
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        prevButton.addTarget(self, action: #selector(prevTapped), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        seekBar.onBegin = { [weak self] in self?.scrubBegan() }
        seekBar.onFineChanged = { [weak self] fine in self?.scrubFineChanged(fine) }
        seekBar.onChange = { [weak self] v in self?.scrubMoved(to: v) }
        seekBar.onEnd = { [weak self] v in self?.scrubEnded(at: v) }

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
        NotificationCenter.default.addObserver(self, selector: #selector(refreshPip), name: .pipChanged, object: nil)
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

    /// For the screenshots: what a finger holding the seek bar at `value` looks like (with a made-up storyboard where
    /// the video has none, which is all the CI can count on).
    func debugScrub(value: CGFloat, fine: Bool) {
        let pm = PlayerManager.shared
        let d = pm.duration > 0 ? pm.duration : 212
        cancelHide()
        scrubbing = true
        fingerDown = true
        scrubFine = fine
        scrubStoryboard = pm.storyboard ?? DebugStoryboard.make(duration: d)
        filmStrip.configure(scrubStoryboard)
        seekBar.value = value
        scrubTime = Double(value) * d
        filmStrip.setTime(scrubTime)
        updateScrubPill()
        updateScrubChrome(animated: false)
    }

    func debugScrubEnd() {
        scrubbing = false
        fingerDown = false
        scrubFine = false
        updateScrubChrome(animated: false)
    }

    // MARK: Scrubbing

    private func scrubBegan() {
        let pm = PlayerManager.shared
        scrubbing = true
        fingerDown = true
        scrubFine = false
        cancelHide()
        pm.beginScrub()
        scrubStoryboard = pm.storyboard
        filmStrip.configure(scrubStoryboard)
        seekBar.fineValuePerPoint = fineValuePerPoint()
        if let sb = scrubStoryboard {
            // the sheet for the place where the finger went down, ready for when it slides up
            StoryboardImages.shared.warm(sb, level: sb.level(minWidth: FilmStripView.preferredFrameWidth),
                                         at: Double(seekBar.value) * pm.duration)
        }
        updateScrubChrome(animated: true)
    }

    private func scrubFineChanged(_ fine: Bool) {
        scrubFine = fine
        updateScrubChrome(animated: true)
    }

    private func scrubMoved(to v: CGFloat) {
        let pm = PlayerManager.shared
        let d = pm.duration
        scrubTime = Double(v) * d
        timeLabel.text = Format.duration(scrubTime) + " / " + Format.duration(d)
        pm.scrub(to: scrubTime, fine: scrubFine)
        filmStrip.setTime(scrubTime)
        updateScrubPill()
    }

    private func scrubEnded(at v: CGFloat) {
        let d = PlayerManager.shared.duration
        fingerDown = false
        scrubFine = false
        updateScrubChrome(animated: true)
        PlayerManager.shared.endScrub(at: Double(v) * d) { [weak self] in self?.scrubbing = false }
        scheduleHide()
    }

    /// What one point of sideways movement of the finger is worth while the film strip is up: one frame width is one
    /// frame spacing. nil where the video has no frames to show.
    private func fineValuePerPoint() -> CGFloat? {
        let d = PlayerManager.shared.duration
        guard let sb = scrubStoryboard, d > 0 else { return nil }
        let level = sb.level(minWidth: FilmStripView.preferredFrameWidth)
        return CGFloat(sb.spacing(of: level)) / FilmStripView.tileWidth(height: stripHeight) / CGFloat(d)
    }

    /// The pill over the bar (over the strip when it is up): the time and, if the video has chapters, the chapter.
    private func updateScrubPill() {
        let text = NSMutableAttributedString(string: Format.duration(scrubTime),
                                             attributes: [.font: Theme.font(14, .bold), .foregroundColor: UIColor.white])
        if let ch = Chapters.current(PlayerManager.shared.chapters, at: scrubTime) {
            text.append(NSAttributedString(string: "  " + ch.title,
                                           attributes: [.font: Theme.font(14, .medium), .foregroundColor: UIColor(white: 1, alpha: 0.9)]))
        }
        scrubPill.attributedText = text
        layoutScrub()
    }

    /// The controls go out of the way of the finger; the pill comes in, and the film strip once the finger is above the bar.
    private func updateScrubChrome(animated: Bool) {
        layoutScrub()
        let changes = {
            self.applyVisibility()
            self.filmStrip.alpha = (self.fingerDown && self.scrubFine) ? 1 : 0
            self.scrubPill.alpha = self.fingerDown ? 1 : 0
        }
        if animated { UIView.animate(withDuration: 0.15, animations: changes) } else { changes() }
    }

    private func layoutScrub() {
        let w = bounds.width
        let h = bounds.height
        let sh = stripHeight
        filmStrip.frame = CGRect(x: 0, y: h - sh, width: w, height: sh)
        let maxW = max(0, w - 32)
        let size = scrubPill.sizeThatFits(CGSize(width: maxW, height: 40))
        let pw = min(maxW, size.width)
        let bottom = scrubFine ? h - sh - 12 : seekBar.frame.midY - 26
        scrubPill.frame = CGRect(x: ((w - pw) / 2).rounded(), y: bottom - size.height, width: pw, height: size.height)
        scrubPill.layer.cornerRadius = size.height / 2
    }

    // MARK: Actions

    @objc private func collapseTapped() { onCollapse?() }
    @objc private func captionsTapped() { onCaptions?(); scheduleHide() }
    @objc private func settingsTapped() { onSettings?(); scheduleHide() }
    @objc private func pipTapped() { onPictureInPicture?(); scheduleHide() }
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
        if animated { UIView.animate(withDuration: 0.2, animations: { self.applyVisibility() }) } else { applyVisibility() }
        if visible { scheduleHide() } else { cancelHide() }
    }

    /// Alphas of everything that comes and goes with the controls (which also stand aside while a finger scrubs).
    private func applyVisibility() {
        let alpha: CGFloat = chromeVisible ? 1 : 0
        shade.alpha = alpha
        for v in [collapseButton, captionButton, settingsButton, routePicker, timeLabel, chapterLabel, fullscreenButton, titleLabel] as [UIView] {
            v.alpha = alpha
        }
        refreshTransportAlpha()
        let barShown = controlsVisible || fingerDown
        seekBar.alpha = barShown ? 1 : 0
        thinProgress.alpha = barShown ? 0 : 1
        updatePlayButtonAlpha()
        refreshPip()
        layoutSubtitle()
    }

    /// Previous / next: dimmed where there is nothing to go to.
    private func refreshTransportAlpha() {
        let pm = PlayerManager.shared
        let a: CGFloat = chromeVisible ? 1 : 0
        prevButton.alpha = a * (pm.hasPrevious ? 1 : 0.35)
        nextButton.alpha = a * (pm.hasNext ? 1 : 0.35)
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
        // the big button stays (as a picture) while the film strip is up, the video being paused meanwhile; on a small
        // player the pill would land on it, and the pill wins
        let pictureOnly = fingerDown && scrubFine && scrubPill.frame.minY >= playButton.frame.maxY + 6
        playButton.alpha = ((chromeVisible || pictureOnly) && !busy && !failed) ? 1 : 0
        playButton.isUserInteractionEnabled = chromeVisible && !busy && !failed
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
        nextButton.isEnabled = pm.hasNext
        refreshTransportAlpha()
        titleLabel.text = pm.video?.title
        updatePlayButtonAlpha()
        if st == .playing { scheduleHide() } else if st != .playing { cancelHide(); if st != .loading && !controlsVisible { setControlsVisible(true, animated: true) } }
        refreshCaptionIcon()
        refreshPip()
        refreshStats()
        setNeedsLayout()
    }

    /// The stats panel: hidden unless switched on in the settings sheet; its text is renewed about once a second.
    private func refreshStats() {
        let pm = PlayerManager.shared
        statsView.isHidden = !pm.showsStats
        guard pm.showsStats else { return }
        statsView.setLines(pm.statsLines())
        setNeedsLayout()
    }

    /// No button at all where the OS does not offer PiP; dimmed until the video layer has a picture to hand over.
    @objc private func refreshPip() {
        let pip = PictureInPicture.shared
        let supported = PictureInPicture.isSupported
        if pipButton.isHidden == supported { pipButton.isHidden = !supported; setNeedsLayout() }
        let usable = pip.isPossible || pip.isActive
        pipButton.isEnabled = usable
        pipButton.alpha = (chromeVisible ? 1 : 0) * (usable ? 1 : 0.35)
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
        // captions (not while a finger scrubs: they would sit on the pill)
        if !fingerDown, SubtitleController.shared.isEnabled, let text = SubtitleController.shared.text(at: t) {
            if subtitleLabel.text != text {
                subtitleLabel.text = text
                layoutSubtitle()
            }
            subtitleLabel.isHidden = false
        } else {
            subtitleLabel.isHidden = true
        }
        statsTicks += 1
        if statsTicks % 4 == 0 { refreshStats() }
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
        pipButton.frame = CGRect(x: w - 192 - right, y: 2, width: 44, height: 44)
        titleLabel.frame = CGRect(x: 52 + left, y: 2, width: w - 52 - (pipButton.isHidden ? 150 : 198) - left - right, height: 44)
        if !statsView.isHidden {
            let size = statsView.fittingSize(maxWidth: min(320, w - 20 - left - right))
            statsView.frame = CGRect(x: 10 + left, y: 46, width: size.width, height: size.height)
        }
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
        layoutScrub()
    }
}
