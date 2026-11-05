import UIKit
import AVFoundation
import MediaPlayer

extension Notification.Name {
    static let playerChanged = Notification.Name("PodTubePlayerChanged")
    static let playerItemChanged = Notification.Name("PodTubePlayerItemChanged")
}

enum PlayerState {
    case idle, loading, playing, paused, buffering, ended, failed
}

/// One shared AVPlayer for the whole app (inline player, mini player, full screen, lock screen).
final class PlayerManager: NSObject {
    static let shared = PlayerManager()

    let player = AVPlayer()

    private(set) var video: VideoItem?
    private(set) var info: PlaybackInfo?
    private(set) var state: PlayerState = .idle {
        didSet { if oldValue != state { NotificationCenter.default.post(name: .playerChanged, object: nil) } }
    }
    private(set) var errorMessage: String?

    /// Explicit queue (playlist or Shorts); `queueIndex` points at the current entry.
    private(set) var queue: [VideoItem] = []
    private(set) var queueIndex = -1
    private(set) var playlistId: String?
    /// Candidates for "up next" when no queue is active (set from the related list).
    var upNext: [VideoItem] = []

    var loops = false
    private(set) var speed: Double = Settings.playbackSpeed
    private(set) var maxHeight: Int = Settings.maxQuality

    private var itemObservers: [NSKeyValueObservation] = []
    private var playerObservers: [NSKeyValueObservation] = []
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var generation = 0
    private var candidates: [PlayableSource] = []
    private var candidateIndex = 0
    private var lastSaved: TimeInterval = 0
    private var wantsPlay = true
    private var sleepTimer: Timer?
    private(set) var sleepEndsAt: Date?
    private(set) var sleepAtEnd = false

    enum PlayableSource {
        case hls(URL)
        case composite(video: URL, audio: URL)
        case progressive(URL)
    }

    override init() {
        super.init()
        configureAudioSession()
        installObservers()
        installRemoteCommands()
    }

    // MARK: Setup

    private func configureAudioSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .moviePlayback, options: [])
        try? s.setActive(true, options: [])
    }

    private func installObservers() {
        playerObservers.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.timeControlChanged() }
        })
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] t in
            self?.tick(t)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(interruption(_:)),
                                               name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(routeChanged(_:)),
                                               name: AVAudioSession.routeChangeNotification, object: nil)
    }

    @objc private func interruption(_ n: Notification) {
        guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .began {
            wantsPlay = false
        } else if let optRaw = n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt,
                  AVAudioSession.InterruptionOptions(rawValue: optRaw).contains(.shouldResume) {
            play()
        }
    }

    @objc private func routeChanged(_ n: Notification) {
        guard let raw = n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        if reason == .oldDeviceUnavailable { pause() }
    }

    // MARK: Public state

    var isPlaying: Bool { return player.rate > 0 || state == .playing }
    var currentTime: TimeInterval {
        let t = player.currentTime().seconds
        return t.isFinite ? max(0, t) : 0
    }
    var duration: TimeInterval {
        if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 { return d }
        if let i = info, i.duration > 0 { return i.duration }
        return 0
    }
    var isLive: Bool { return info?.isLive ?? false }
    var bufferedTime: TimeInterval {
        guard let r = player.currentItem?.loadedTimeRanges.first?.timeRangeValue else { return 0 }
        let end = r.start.seconds + r.duration.seconds
        return end.isFinite ? end : 0
    }

    // MARK: Playing

    func play(_ video: VideoItem, queue newQueue: [VideoItem]? = nil, playlistId: String? = nil) {
        if let q = newQueue {
            queue = q
            queueIndex = q.firstIndex(where: { $0.id == video.id }) ?? -1
        } else if self.video?.id != video.id {
            // opening a plain video ends any previous queue unless it contains the video
            if let idx = queue.firstIndex(where: { $0.id == video.id }) {
                queueIndex = idx
            } else {
                queue = []
                queueIndex = -1
            }
        }
        if let p = playlistId { self.playlistId = p } else if newQueue != nil { self.playlistId = nil }

        generation += 1
        let gen = generation
        self.video = video
        info = nil
        errorMessage = nil
        candidates = []
        candidateIndex = 0
        wantsPlay = true
        tearDownItem()
        player.replaceCurrentItem(with: nil)
        state = .loading
        NotificationCenter.default.post(name: .playerItemChanged, object: nil)

        if DownloadManager.shared.record(for: video.id) != nil, let urls = DownloadManager.shared.localURLs(for: video.id) {
            var local = PlaybackInfo(videoId: video.id)
            local.title = video.title
            local.author = video.channelName
            local.videoURL = urls.video
            local.audioURL = urls.audio
            info = local
            candidates = [.composite(video: urls.video, audio: urls.audio)]
            candidateIndex = 0
            NotificationCenter.default.post(name: .playerItemChanged, object: nil)
            startCandidate(gen)
            return
        }

        InnerTube.shared.playback(videoId: video.id) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, gen == self.generation else { return }
                switch result {
                case .success(let info):
                    self.info = info
                    self.candidates = self.sources(for: info)
                    self.candidateIndex = 0
                    NotificationCenter.default.post(name: .playerItemChanged, object: nil)
                    self.startCandidate(gen)
                case .failure(let error):
                    self.fail(error.localizedDescription)
                }
            }
        }
    }

    private func sources(for info: PlaybackInfo) -> [PlayableSource] {
        var out: [PlayableSource] = []
        if let u = info.hlsURL { out.append(.hls(u)) }
        if let v = info.videoURL, let a = info.audioURL { out.append(.composite(video: v, audio: a)) }
        if let p = info.progressiveURL { out.append(.progressive(p)) }
        return out
    }

    private func fail(_ message: String) {
        errorMessage = message
        state = .failed
    }

    private func startCandidate(_ gen: Int) {
        guard gen == generation else { return }
        guard candidateIndex < candidates.count else {
            fail(L10n.t("video.unavailable"))
            return
        }
        switch candidates[candidateIndex] {
        case .hls(let url):
            install(item: AVPlayerItem(asset: AVURLAsset(url: url)), gen: gen)
        case .progressive(let url):
            install(item: AVPlayerItem(url: url), gen: gen)
        case .composite(let v, let a):
            buildComposite(video: v, audio: a, gen: gen)
        }
    }

    private func tryNextCandidate(_ gen: Int) {
        guard gen == generation else { return }
        candidateIndex += 1
        startCandidate(gen)
    }

    private func buildComposite(video: URL, audio: URL, gen: Int) {
        let va = AVURLAsset(url: video)
        let aa = AVURLAsset(url: audio)
        let group = DispatchGroup()
        group.enter()
        va.loadValuesAsynchronously(forKeys: ["tracks", "duration"]) { group.leave() }
        group.enter()
        aa.loadValuesAsynchronously(forKeys: ["tracks", "duration"]) { group.leave() }
        group.notify(queue: .main) { [weak self] in
            guard let self = self, gen == self.generation else { return }
            guard let vt = va.tracks(withMediaType: .video).first, let at = aa.tracks(withMediaType: .audio).first else {
                self.tryNextCandidate(gen)
                return
            }
            let comp = AVMutableComposition()
            let range = CMTimeRange(start: .zero, duration: va.duration)
            if let ct = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
               let ca = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                do {
                    try ct.insertTimeRange(range, of: vt, at: .zero)
                    try ca.insertTimeRange(CMTimeRange(start: .zero, duration: min(aa.duration, va.duration)), of: at, at: .zero)
                } catch {
                    self.tryNextCandidate(gen)
                    return
                }
                ct.preferredTransform = vt.preferredTransform
                self.install(item: AVPlayerItem(asset: comp), gen: gen)
            } else {
                self.tryNextCandidate(gen)
            }
        }
    }

    private func install(item: AVPlayerItem, gen: Int) {
        guard gen == generation else { return }
        tearDownItem()
        item.audioTimePitchAlgorithm = .timeDomain
        applyQuality(to: item)
        itemObservers.append(item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async { self?.itemStatusChanged(item, gen: gen) }
        })
        itemObservers.append(item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.timeControlChanged() }
        })
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            self?.itemEnded(gen)
        }
        player.replaceCurrentItem(with: item)
        state = .loading
    }

    private func tearDownItem() {
        itemObservers.forEach { $0.invalidate() }
        itemObservers = []
        if let e = endObserver {
            NotificationCenter.default.removeObserver(e)
            endObserver = nil
        }
    }

    private func itemStatusChanged(_ item: AVPlayerItem, gen: Int) {
        guard gen == generation, item === player.currentItem else { return }
        switch item.status {
        case .readyToPlay:
            if let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
                item.select(nil, in: group)
            }
            if let v = video, let pos = Store.shared.resumePosition(for: v.id), !isLive, currentTime < 1 {
                player.seek(to: CMTime(seconds: pos, preferredTimescale: 600))
            }
            if let v = video { Store.shared.addHistory(v, position: currentTime, duration: duration) }
            if wantsPlay { play() }
            updateNowPlaying()
        case .failed:
            tryNextCandidate(gen)
        default:
            break
        }
    }

    private func itemEnded(_ gen: Int) {
        guard gen == generation else { return }
        if let v = video { Store.shared.updateProgress(videoId: v.id, position: 0, duration: duration) }
        if loops {
            player.seek(to: .zero)
            play()
            return
        }
        if sleepAtEnd {
            sleepAtEnd = false
            state = .ended
            return
        }
        state = .ended
        if Settings.autoplay { playNext(auto: true) }
    }

    // MARK: One-shot item builder (used by the Shorts pager)

    /// Builds a ready-to-use item for `info`: HLS first, then progressive, then video+audio composition.
    static func makeItem(for info: PlaybackInfo, completion: @escaping (AVPlayerItem?) -> Void) {
        if let u = info.hlsURL {
            completion(AVPlayerItem(asset: AVURLAsset(url: u)))
            return
        }
        if let v = info.videoURL, let a = info.audioURL {
            let va = AVURLAsset(url: v)
            let aa = AVURLAsset(url: a)
            let group = DispatchGroup()
            group.enter()
            va.loadValuesAsynchronously(forKeys: ["tracks", "duration"]) { group.leave() }
            group.enter()
            aa.loadValuesAsynchronously(forKeys: ["tracks", "duration"]) { group.leave() }
            group.notify(queue: .main) {
                guard let vt = va.tracks(withMediaType: .video).first, let at = aa.tracks(withMediaType: .audio).first else {
                    if let p = info.progressiveURL { completion(AVPlayerItem(url: p)) } else { completion(nil) }
                    return
                }
                let comp = AVMutableComposition()
                if let cv = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
                   let ca = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                    do {
                        try cv.insertTimeRange(CMTimeRange(start: .zero, duration: va.duration), of: vt, at: .zero)
                        try ca.insertTimeRange(CMTimeRange(start: .zero, duration: min(aa.duration, va.duration)), of: at, at: .zero)
                        cv.preferredTransform = vt.preferredTransform
                        completion(AVPlayerItem(asset: comp))
                        return
                    } catch {}
                }
                if let p = info.progressiveURL { completion(AVPlayerItem(url: p)) } else { completion(nil) }
            }
            return
        }
        if let p = info.progressiveURL {
            completion(AVPlayerItem(url: p))
            return
        }
        completion(nil)
    }

    // MARK: Transport

    func play() {
        wantsPlay = true
        if state == .ended { player.seek(to: .zero) }
        player.play()
        player.rate = Float(speed)
    }

    func pause() {
        wantsPlay = false
        player.pause()
    }

    func toggle() {
        if player.timeControlStatus == .paused { play() } else { pause() }
    }

    func seek(to seconds: TimeInterval, completion: (() -> Void)? = nil) {
        let t = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            completion?()
        }
    }

    func skip(by seconds: TimeInterval) {
        var target = currentTime + seconds
        if duration > 0 { target = min(target, duration - 0.5) }
        seek(to: target)
    }

    var hasNext: Bool { return nextCandidate() != nil }
    var hasPrevious: Bool { return queueIndex > 0 }

    private func nextCandidate() -> VideoItem? {
        if queueIndex >= 0 && queueIndex + 1 < queue.count { return queue[queueIndex + 1] }
        if queueIndex < 0 || queue.isEmpty {
            return upNext.first(where: { $0.id != video?.id })
        }
        return nil
    }

    /// Adopts the queue returned by the watch page (playlist playback) without restarting the current video.
    func adoptQueue(_ list: [VideoItem], currentId: String, playlistId: String?) {
        guard let idx = list.firstIndex(where: { $0.id == currentId }) else { return }
        queue = list
        queueIndex = idx
        if let p = playlistId { self.playlistId = p }
        NotificationCenter.default.post(name: .playerChanged, object: nil)
    }

    func playNext(auto: Bool = false) {
        guard let next = nextCandidate() else { return }
        if queueIndex >= 0 && queueIndex + 1 < queue.count {
            play(next, queue: queue, playlistId: playlistId)
        } else {
            play(next)
        }
    }

    func playPrevious() {
        if currentTime > 5 {
            seek(to: 0)
            return
        }
        if queueIndex > 0 {
            play(queue[queueIndex - 1], queue: queue, playlistId: playlistId)
        } else {
            seek(to: 0)
        }
    }

    func stop() {
        generation += 1
        tearDownItem()
        player.pause()
        player.replaceCurrentItem(with: nil)
        video = nil
        info = nil
        queue = []
        queueIndex = -1
        state = .idle
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        NotificationCenter.default.post(name: .playerItemChanged, object: nil)
    }

    func retry() {
        guard let v = video else { return }
        play(v, queue: queue.isEmpty ? nil : queue, playlistId: playlistId)
    }

    // MARK: Quality / speed

    func setMaxHeight(_ h: Int) {
        maxHeight = h
        if let item = player.currentItem { applyQuality(to: item) }
        NotificationCenter.default.post(name: .playerChanged, object: nil)
    }

    private func applyQuality(to item: AVPlayerItem) {
        if maxHeight > 0 {
            item.preferredMaximumResolution = CGSize(width: CGFloat(maxHeight) * 16 / 9, height: CGFloat(maxHeight))
        } else {
            item.preferredMaximumResolution = .zero
        }
    }

    func setSpeed(_ s: Double) {
        speed = s
        if player.timeControlStatus != .paused { player.rate = Float(s) }
        NotificationCenter.default.post(name: .playerChanged, object: nil)
    }

    // MARK: Sleep timer

    func setSleepTimer(minutes: Int?, atEnd: Bool = false) {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepEndsAt = nil
        sleepAtEnd = atEnd
        if let m = minutes {
            sleepEndsAt = Date().addingTimeInterval(TimeInterval(m * 60))
            sleepTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(m * 60), repeats: false) { [weak self] _ in
                self?.pause()
                self?.sleepEndsAt = nil
                NotificationCenter.default.post(name: .playerChanged, object: nil)
            }
        }
        NotificationCenter.default.post(name: .playerChanged, object: nil)
    }

    // MARK: State tracking

    private func timeControlChanged() {
        guard video != nil, state != .failed, state != .ended else { return }
        switch player.timeControlStatus {
        case .playing:
            state = .playing
        case .paused:
            if player.currentItem == nil { return }
            state = (state == .loading && player.currentItem?.status != .readyToPlay) ? .loading : .paused
        case .waitingToPlayAtSpecifiedRate:
            state = .buffering
        @unknown default:
            break
        }
        updateNowPlayingRate()
    }

    private func tick(_ time: CMTime) {
        guard let v = video, state == .playing || state == .paused else { return }
        let now = Date().timeIntervalSince1970
        if now - lastSaved > 5 {
            lastSaved = now
            Store.shared.updateProgress(videoId: v.id, position: currentTime, duration: duration)
            updateNowPlaying()
        }
    }

    // MARK: Lock screen

    private func installRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in self?.play(); return .success }
        c.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in self?.toggle(); return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self, self.hasNext else { return .noActionableNowPlayingItem }
            self.playNext()
            return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in self?.playPrevious(); return .success }
        c.skipForwardCommand.preferredIntervals = [10]
        c.skipBackwardCommand.preferredIntervals = [10]
        c.skipForwardCommand.addTarget { [weak self] _ in self?.skip(by: 10); return .success }
        c.skipBackwardCommand.addTarget { [weak self] _ in self?.skip(by: -10); return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let e = event as? MPChangePlaybackPositionCommandEvent { self?.seek(to: e.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let v = video else { return }
        var d: [String: Any] = [
            MPMediaItemPropertyTitle: v.title,
            MPMediaItemPropertyArtist: v.channelName,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: player.rate
        ]
        if duration > 0 && !isLive { d[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = d
        if let url = v.thumbnailURL {
            ImageLoader.shared.load(url, maxPixel: 600) { image in
                guard let image = image, self.video?.id == v.id else { return }
                var cur = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                cur[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                MPNowPlayingInfoCenter.default().nowPlayingInfo = cur
            }
        }
    }

    private func updateNowPlayingRate() {
        guard var d = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        d[MPNowPlayingInfoPropertyPlaybackRate] = player.rate
        d[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        MPNowPlayingInfoCenter.default().nowPlayingInfo = d
    }
}
