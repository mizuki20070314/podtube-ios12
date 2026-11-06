import UIKit
import AVFoundation

/// Settings > Diagnostics: runs the whole playback chain once and prints what worked.
/// Meant for reports from real devices (the author could only test in the simulator).
final class DiagnosticsViewController: UIViewController {
    private let textView = UITextView()
    private let runButton = UIButton(type: .system)
    private var lines: [String] = []
    private var running = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.t("diag.title")
        view.backgroundColor = Theme.background
        textView.isEditable = false
        textView.backgroundColor = .clear
        textView.font = UIFont(name: "Menlo", size: 12) ?? Theme.font(12)
        textView.textColor = Theme.text
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        runButton.setTitle(L10n.t("diag.run"), for: .normal)
        runButton.titleLabel?.font = Theme.font(16, .medium)
        runButton.backgroundColor = Theme.chipSelectedBackground
        runButton.setTitleColor(Theme.chipSelectedText, for: .normal)
        runButton.layer.cornerRadius = 22
        runButton.addTarget(self, action: #selector(runTapped), for: .touchUpInside)
        view.addSubview(textView)
        view.addSubview(runButton)
        append("PodTube " + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"))
        append("iOS \(UIDevice.current.systemVersion) / \(UIDevice.current.model)")
        append("hl=\(InnerTube.shared.language) gl=\(InnerTube.shared.region)")
        append("")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds
        var bottom: CGFloat = 0
        if #available(iOS 11.0, *) { bottom = view.safeAreaInsets.bottom }
        runButton.frame = CGRect(x: 16, y: b.height - bottom - 60, width: b.width - 32, height: 44)
        textView.frame = CGRect(x: 0, y: 0, width: b.width, height: runButton.frame.minY - 8)
    }

    private func append(_ s: String) {
        lines.append(s)
        textView.text = lines.joined(separator: "\n")
        let end = NSRange(location: max(0, textView.text.count - 1), length: 1)
        textView.scrollRangeToVisible(end)
    }

    func runForDebug() {
        loadViewIfNeeded()
        runTapped()
    }

    @objc private func runTapped() {
        if running { return }
        running = true
        runButton.alpha = 0.5
        append("--- " + DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))
        InnerTube.shared.refreshVisitor { [weak self] in
            DispatchQueue.main.async { self?.step1() }
        }
    }

    private func report(_ label: String, _ start: Date, _ ok: Bool, _ detail: String = "") {
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        append("\(ok ? "OK " : "NG ") \(label) \(ms)ms \(detail)")
    }

    /// The last step of the chain: when signed in, checks that the statistics URLs of the account (what records a play
    /// in the watch history) can still be obtained. Only asks for them; nothing is sent to the history.
    private func done() {
        guard AuthSession.shared.isSignedIn, AccountDemo.responder == nil else {
            finish()
            return
        }
        let t = Date()
        InnerTube.shared.accountPlaybackTracking(videoId: "dQw4w9WgXcQ") { [weak self] r in
            DispatchQueue.main.async {
                switch r {
                case .success(let tracking):
                    self?.report("account history tracking", t, true, "uga=\(tracking.playbackURL.absoluteString.contains("uga="))")
                case .failure(let e):
                    self?.report("account history tracking", t, false, e.localizedDescription)
                }
                self?.finish()
            }
        }
    }

    private func finish() {
        running = false
        runButton.alpha = 1
        append("")
    }

    private func step1() {
        let t = Date()
        report("visitor id", t, InnerTube.shared.visitorData != nil, String((InnerTube.shared.visitorData ?? "").prefix(12)))
        let t2 = Date()
        InnerTube.shared.home { [weak self] r in
            DispatchQueue.main.async {
                switch r {
                case .success(let p): self?.report("home feed", t2, !p.items.isEmpty, "\(p.videos.count) videos")
                case .failure(let e): self?.report("home feed", t2, false, e.localizedDescription)
                }
                self?.step2()
            }
        }
    }

    private func step2() {
        let t = Date()
        InnerTube.shared.playback(videoId: "dQw4w9WgXcQ") { [weak self] r in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch r {
                case .success(let info):
                    self.report("player", t, true, "hls=\(info.hlsURL != nil) adaptive=\(info.videoFormats.count)+\(info.audioFormats.count)")
                    self.step3(info)
                case .failure(let e):
                    self.report("player", t, false, e.localizedDescription)
                    self.done()
                }
            }
        }
    }

    private func step3(_ info: PlaybackInfo) {
        let t = Date()
        guard let hls = info.hlsURL else {
            append("-- no HLS manifest for this video")
            step4(info)
            return
        }
        let asset = AVURLAsset(url: hls)
        asset.loadValuesAsynchronously(forKeys: ["playable", "tracks"]) { [weak self] in
            var err: NSError?
            let status = asset.statusOfValue(forKey: "playable", error: &err)
            DispatchQueue.main.async {
                let ok = status == .loaded && asset.isPlayable
                self?.report("AVAsset (HLS) playable", t, ok, err.map { "\($0.domain) \($0.code)" } ?? "")
                self?.step4(info)
            }
        }
    }

    private func step4(_ info: PlaybackInfo) {
        let t = Date()
        guard let v = info.videoURL, let a = info.audioURL else {
            append("-- no adaptive streams")
            done()
            return
        }
        let va = AVURLAsset(url: v)
        let aa = AVURLAsset(url: a)
        let group = DispatchGroup()
        group.enter()
        va.loadValuesAsynchronously(forKeys: ["playable", "tracks", "duration"]) { group.leave() }
        group.enter()
        aa.loadValuesAsynchronously(forKeys: ["playable", "tracks", "duration"]) { group.leave() }
        group.notify(queue: .main) { [weak self] in
            let vOK = va.isPlayable && !va.tracks(withMediaType: .video).isEmpty
            let aOK = aa.isPlayable && !aa.tracks(withMediaType: .audio).isEmpty
            self?.report("AVAsset (H.264 video)", t, vOK, "\(Int(va.duration.seconds))s")
            self?.report("AVAsset (AAC audio)", t, aOK, "\(Int(aa.duration.seconds))s")
            self?.done()
        }
    }
}
