import UIKit

extension Notification.Name {
    static let downloadsChanged = Notification.Name("PodTubeDownloadsChanged")
}

struct DownloadRecord: Codable {
    var video: VideoItem
    var height: Int
    var bytes: Int64
    var addedAt: Date
}

struct PendingDownload: Codable {
    var video: VideoItem
    var height: Int
    var expectedBytes: Int64
    var videoDone: Bool
    var audioDone: Bool
    var bytes: Int64
}

/// Offline downloads. A video is stored as two files (H.264 video + AAC audio) that are
/// recombined with AVMutableComposition at playback time. Uses a background URLSession so
/// transfers continue while the app is suspended.
///
/// googlevideo throttles requests without a Range header to ~80 KB/s, so every task asks for `bytes=0-`.
final class DownloadManager: NSObject, URLSessionDownloadDelegate {
    static let shared = DownloadManager()

    private(set) var records: [DownloadRecord] = []
    private(set) var pending: [String: PendingDownload] = [:]
    private var written: [String: [String: Int64]] = [:]
    var backgroundCompletionHandler: (() -> Void)?

    private var session: URLSession!
    private let dir: URL
    private let lock = NSLock()
    private var lastNotify = Date.distantPast
    private let ioQueue = DispatchQueue(label: "podtube.downloads.io", qos: .utility)

    override init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        dir = base.appendingPathComponent("PodTube/Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        super.init()
        if let d = try? Data(contentsOf: dir.appendingPathComponent("records.json")),
           let r = try? JSONDecoder().decode([DownloadRecord].self, from: d) { records = r }
        if let d = try? Data(contentsOf: dir.appendingPathComponent("pending.json")),
           let p = try? JSONDecoder().decode([String: PendingDownload].self, from: d) { pending = p }
        let cfg = URLSessionConfiguration.background(withIdentifier: "com.podtube.ios12.downloads")
        cfg.sessionSendsLaunchEvents = true
        cfg.isDiscretionary = false
        cfg.timeoutIntervalForResource = 6 * 3600
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }

    // MARK: Persistence

    private func saveState() {
        let r = records
        let p = pending
        let rURL = dir.appendingPathComponent("records.json")
        let pURL = dir.appendingPathComponent("pending.json")
        ioQueue.async {
            if let d = try? JSONEncoder().encode(r) { try? d.write(to: rURL, options: .atomic) }
            if let d = try? JSONEncoder().encode(p) { try? d.write(to: pURL, options: .atomic) }
        }
    }

    private func notify(force: Bool = true) {
        let now = Date()
        if !force && now.timeIntervalSince(lastNotify) < 0.3 { return }
        lastNotify = now
        DispatchQueue.main.async { NotificationCenter.default.post(name: .downloadsChanged, object: nil) }
    }

    // MARK: Queries

    func record(for id: String) -> DownloadRecord? {
        return records.first(where: { $0.video.id == id })
    }

    func isDownloading(_ id: String) -> Bool { return pending[id] != nil }

    func localURLs(for id: String) -> (video: URL, audio: URL)? {
        let folder = dir.appendingPathComponent(id, isDirectory: true)
        let v = folder.appendingPathComponent("video.mp4")
        let a = folder.appendingPathComponent("audio.m4a")
        if FileManager.default.fileExists(atPath: v.path) && FileManager.default.fileExists(atPath: a.path) { return (v, a) }
        return nil
    }

    /// 0...1 for a running download.
    func fraction(for id: String) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        guard let p = pending[id], p.expectedBytes > 0 else { return pending[id] == nil ? nil : 0 }
        var sum: Int64 = 0
        if let w = written[id] { for (_, v) in w { sum += v } }
        return min(1, Double(sum) / Double(p.expectedBytes))
    }

    var totalBytes: Int64 { return records.reduce(0) { $0 + $1.bytes } }

    // MARK: Control

    func start(video: VideoItem, info: PlaybackInfo, height: Int) {
        let id = video.id
        if record(for: id) != nil || pending[id] != nil { return }
        let candidates = info.videoFormats.filter { $0.height <= height }
        guard let vf = candidates.max(by: { $0.height < $1.height }) ?? info.videoFormats.min(by: { $0.height < $1.height }),
              let af = info.audioFormats.max(by: { $0.bitrate < $1.bitrate }) else { return }
        lock.lock()
        pending[id] = PendingDownload(video: video, height: vf.height, expectedBytes: vf.contentLength + af.contentLength,
                                      videoDone: false, audioDone: false, bytes: 0)
        written[id] = [:]
        lock.unlock()
        saveState()
        schedule(id: id, kind: "video", url: vf.url)
        schedule(id: id, kind: "audio", url: af.url)
        notify()
    }

    private func schedule(id: String, kind: String, url: URL) {
        var req = URLRequest(url: url)
        req.setValue("bytes=0-", forHTTPHeaderField: "Range")
        let task = session.downloadTask(with: req)
        task.taskDescription = "\(id)|\(kind)"
        task.resume()
    }

    func cancel(_ id: String) {
        session.getAllTasks { tasks in
            for t in tasks where (t.taskDescription ?? "").hasPrefix(id + "|") { t.cancel() }
        }
        lock.lock()
        pending[id] = nil
        written[id] = nil
        lock.unlock()
        removeFolder(id)
        saveState()
        notify()
    }

    func delete(_ id: String) {
        records.removeAll { $0.video.id == id }
        removeFolder(id)
        saveState()
        notify()
    }

    private func removeFolder(_ id: String) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(id, isDirectory: true))
    }

    private func fail(_ id: String, _ message: String) {
        session.getAllTasks { tasks in
            for t in tasks where (t.taskDescription ?? "").hasPrefix(id + "|") { t.cancel() }
        }
        lock.lock()
        pending[id] = nil
        written[id] = nil
        lock.unlock()
        removeFolder(id)
        saveState()
        notify()
        DispatchQueue.main.async { Toast.show(L10n.t("downloads.failed")) }
    }

    // MARK: URLSessionDownloadDelegate

    private func parse(_ task: URLSessionTask) -> (id: String, kind: String)? {
        guard let d = task.taskDescription else { return nil }
        let parts = d.split(separator: "|").map { String($0) }
        if parts.count != 2 { return nil }
        return (parts[0], parts[1])
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let (id, kind) = parse(downloadTask) else { return }
        lock.lock()
        var w = written[id] ?? [:]
        w[kind] = totalBytesWritten
        written[id] = w
        lock.unlock()
        notify(force: false)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let (id, kind) = parse(downloadTask) else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            fail(id, "HTTP \(status)")
            return
        }
        let folder = dir.appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)
        let dest = folder.appendingPathComponent(kind == "video" ? "video.mp4" : "audio.m4a")
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: location, to: dest)
        } catch {
            fail(id, error.localizedDescription)
            return
        }
        let size = ((try? FileManager.default.attributesOfItem(atPath: dest.path))?[.size] as? NSNumber)?.int64Value ?? 0
        lock.lock()
        guard var p = pending[id] else {
            lock.unlock()
            return
        }
        if kind == "video" { p.videoDone = true } else { p.audioDone = true }
        p.bytes += size
        pending[id] = p
        let finished = p.videoDone && p.audioDone
        if finished {
            pending[id] = nil
            written[id] = nil
            records.insert(DownloadRecord(video: p.video, height: p.height, bytes: p.bytes, addedAt: Date()), at: 0)
        }
        lock.unlock()
        saveState()
        notify()
        if finished {
            DispatchQueue.main.async { Toast.show(L10n.t("downloads.done")) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error, let (id, _) = parse(task) else { return }
        if (error as NSError).code == NSURLErrorCancelled { return }
        fail(id, error.localizedDescription)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
}

// MARK: - Downloads screen

final class DownloadCell: UITableViewCell {
    static let reuseId = "DownloadCell"
    private let thumb = UIImageView()
    private let titleLabel = UILabel()
    private let subLabel = UILabel()
    private let progress = UIProgressView(progressViewStyle: .default)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        thumb.contentMode = .scaleAspectFill
        thumb.clipsToBounds = true
        thumb.layer.cornerRadius = 6
        titleLabel.font = Theme.font(14, .medium)
        titleLabel.numberOfLines = 2
        subLabel.font = Theme.font(12)
        progress.progressTintColor = Theme.red
        contentView.addSubviews([thumb, titleLabel, subLabel, progress])
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(video: VideoItem, detail: String, fraction: Double?) {
        thumb.backgroundColor = Theme.thumbPlaceholder
        thumb.setRemote(video.thumbnail.isEmpty ? video.thumbnailURL?.absoluteString : video.thumbnail, maxPixel: 320)
        titleLabel.text = video.title
        titleLabel.textColor = Theme.text
        subLabel.text = detail
        subLabel.textColor = Theme.secondaryText
        progress.trackTintColor = Theme.surfaceHigh
        progress.isHidden = fraction == nil
        progress.progress = Float(fraction ?? 0)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = contentView.bounds.width
        thumb.frame = CGRect(x: 12, y: 10, width: 120, height: 68)
        let tx: CGFloat = 144
        titleLabel.frame = CGRect(x: tx, y: 10, width: w - tx - 12, height: 36)
        subLabel.frame = CGRect(x: tx, y: 48, width: w - tx - 12, height: 16)
        progress.frame = CGRect(x: tx, y: 70, width: w - tx - 12, height: 4)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumb.image = nil
    }
}

final class DownloadsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let table = UITableView(frame: .zero, style: .plain)
    private let stateView = StateView()

    private enum Entry {
        case active(PendingDownload)
        case done(DownloadRecord)
    }

    private var entries: [Entry] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.t("library.downloads")
        view.backgroundColor = Theme.background
        table.dataSource = self
        table.delegate = self
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.rowHeight = 88
        table.register(DownloadCell.self, forCellReuseIdentifier: DownloadCell.reuseId)
        view.addSubview(table)
        view.addSubview(stateView)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .downloadsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .themeChanged, object: nil)
        rebuild()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        table.frame = view.bounds
        stateView.frame = view.bounds
    }

    @objc private func refresh() {
        view.backgroundColor = Theme.background
        rebuild()
    }

    private func rebuild() {
        let dm = DownloadManager.shared
        entries = dm.pending.values.map { Entry.active($0) } + dm.records.map { Entry.done($0) }
        table.reloadData()
        if entries.isEmpty {
            stateView.show(icon: "file_download", title: L10n.t("downloads.empty"))
        } else {
            stateView.hide()
        }
    }

    private func sizeText(_ bytes: Int64) -> String {
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { return entries.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DownloadCell.reuseId, for: indexPath) as! DownloadCell
        switch entries[indexPath.row] {
        case .active(let p):
            let f = DownloadManager.shared.fraction(for: p.video.id) ?? 0
            cell.configure(video: p.video, detail: "\(Int(f * 100))% · \(p.height)p", fraction: f)
        case .done(let r):
            cell.configure(video: r.video, detail: "\(r.height)p · \(sizeText(r.bytes))", fraction: nil)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        if case .done(let r) = entries[indexPath.row] { Router.shared.play(r.video) }
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool { return true }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        switch entries[indexPath.row] {
        case .active(let p): DownloadManager.shared.cancel(p.video.id)
        case .done(let r): DownloadManager.shared.delete(r.video.id)
        }
    }
}
