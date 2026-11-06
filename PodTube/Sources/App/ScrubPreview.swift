import UIKit

extension Notification.Name {
    static let storyboardSheetLoaded = Notification.Name("PodTubeStoryboardSheetLoaded")
}

/// Loads the sheets of a video's storyboard and cuts single frames out of them.
final class StoryboardImages {
    static let shared = StoryboardImages()

    /// Larger than any sheet YouTube makes (at most 960 px wide), so that no sheet is scaled down on decoding.
    private static let maxPixel: CGFloat = 1024
    private var inFlight = Set<URL>()
    private var failedAt: [URL: Date] = [:]

    /// Frame `cell` of `level`, or nil while its sheet is still on the way (the request is started).
    func frame(_ sb: Storyboard, level: Storyboard.Level, cell: Storyboard.Cell) -> UIImage? {
        guard let url = sb.sheetURL(level, sheet: cell.sheet) else { return nil }
        if let sheet = ImageLoader.shared.cached(url, maxPixel: StoryboardImages.maxPixel) {
            return StoryboardImages.cut(sheet, level: level, cell: cell)
        }
        request(url)
        return nil
    }

    /// Starts loading the smallest frames (a sheet or two for the whole video) so that something shows right away.
    func prefetch(_ sb: Storyboard) {
        let level = sb.levels[0]
        for sheet in 0..<min(level.sheetCount, 2) {
            if let u = sb.sheetURL(level, sheet: sheet) { request(u) }
        }
    }

    /// Starts loading the sheet that holds the frame at `time` (and the next one, which a slide sideways reaches soon).
    func warm(_ sb: Storyboard, level: Storyboard.Level, at time: Double) {
        let first = sb.cell(level, at: time).sheet
        for sheet in first...min(level.sheetCount - 1, first + 1) {
            if let u = sb.sheetURL(level, sheet: sheet) { request(u) }
        }
    }

    private func request(_ url: URL) {
        if inFlight.contains(url) { return }
        if let t = failedAt[url], Date().timeIntervalSince(t) < 20 { return }
        inFlight.insert(url)
        ImageLoader.shared.load(url, maxPixel: StoryboardImages.maxPixel) { [weak self] image in
            guard let self = self else { return }
            self.inFlight.remove(url)
            if image != nil {
                self.failedAt[url] = nil
                NotificationCenter.default.post(name: .storyboardSheetLoaded, object: nil)
            } else {
                self.failedAt[url] = Date()
            }
        }
    }

    static func cut(_ sheet: UIImage, level: Storyboard.Level, cell: Storyboard.Cell) -> UIImage? {
        guard let cg = sheet.cgImage, level.columns > 0, level.width > 0 else { return nil }
        // the same factor on both axes: the last sheet of a video may have fewer rows than the others
        let scale = CGFloat(cg.width) / CGFloat(level.columns * level.width)
        let rect = CGRect(x: CGFloat(cell.column * level.width) * scale, y: CGFloat(cell.row * level.height) * scale,
                          width: CGFloat(level.width) * scale, height: CGFloat(level.height) * scale).integral
        guard let part = cg.cropping(to: rect) else { return nil }
        return UIImage(cgImage: part)
    }
}

/// A row of preview frames that slides under a fixed white line (the current position). Shown while the finger holds
/// the seek bar from above: one frame is `spacing` seconds, so moving the finger by one frame width moves the position
/// by that long. The frames are cut square, from the middle of the picture, so that a good few fit on the screen.
final class FilmStripView: UIView {
    /// Frames of at least this width (in the sheet) are used where the video has them.
    static let preferredFrameWidth = 160

    private var tiles: [UIImageView] = []
    private let playhead = UIView()
    private var storyboard: Storyboard?
    private var level: Storyboard.Level?
    private var coarse: Storyboard.Level?
    private var time: Double = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isUserInteractionEnabled = false
        backgroundColor = UIColor(white: 0, alpha: 0.6)
        playhead.backgroundColor = .white
        addSubview(playhead)
        NotificationCenter.default.addObserver(self, selector: #selector(sheetLoaded), name: .storyboardSheetLoaded, object: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// Width of one frame when the strip is `height` high.
    static func tileWidth(height: CGFloat) -> CGFloat {
        return height.rounded()
    }

    func configure(_ sb: Storyboard?) {
        storyboard = sb
        level = sb?.level(minWidth: FilmStripView.preferredFrameWidth)
        coarse = sb?.levels.first
        setNeedsLayout()
    }

    func setTime(_ t: Double) {
        time = t
        setNeedsLayout()
    }

    @objc private func sheetLoaded() {
        if alpha > 0.01 { setNeedsLayout() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height
        playhead.frame = CGRect(x: bounds.midX - 1, y: 0, width: 2, height: h)
        guard let sb = storyboard, let level = level, h > 0 else {
            tiles.forEach { $0.isHidden = true }
            return
        }
        let tileW = FilmStripView.tileWidth(height: h)
        let spacing = sb.spacing(of: level)
        let pointsPerSecond = tileW / CGFloat(spacing)
        let mid = bounds.midX
        let t = CGFloat(time)
        let origin = (mid - t * pointsPerSecond).rounded() // x of frame 0; a whole number of tiles further on for the others
        let firstSeen = Int(((t - mid / pointsPerSecond) / CGFloat(spacing)).rounded(.down))
        let lastSeen = Int(((t + mid / pointsPerSecond) / CGFloat(spacing)).rounded(.up))
        let first = max(0, firstSeen)
        let last = min(level.count - 1, lastSeen)
        var used = 0
        if first <= last {
            for f in first...last {
                while tiles.count <= used {
                    let v = UIImageView()
                    v.contentMode = .scaleAspectFill
                    v.clipsToBounds = true
                    v.backgroundColor = UIColor(white: 0.12, alpha: 1)
                    insertSubview(v, belowSubview: playhead)
                    tiles.append(v)
                }
                let v = tiles[used]
                used += 1
                v.isHidden = false
                v.frame = CGRect(x: origin + CGFloat(f) * tileW, y: 0, width: tileW, height: h)
                var img = StoryboardImages.shared.frame(sb, level: level, cell: sb.cell(level, frame: f))
                if img == nil, let c = coarse, c.index != level.index {
                    // the small frames of the whole video are fetched first: a blurry stand-in until the real one arrives
                    let when = sb.time(level, frame: f) + spacing / 2
                    img = StoryboardImages.shared.frame(sb, level: c, cell: sb.cell(c, at: when))
                }
                v.image = img
            }
        }
        for i in used..<tiles.count { tiles[i].isHidden = true }
    }
}

/// A made-up storyboard for the screenshots (the CI cannot count on a video to take frames from): numbered, coloured
/// frames in sheets under the temporary directory, named the way `Storyboard.sheetURL` builds them.
enum DebugStoryboard {
    static func make(duration: Double) -> Storyboard? {
        let dir = NSTemporaryDirectory() + "podtube-debug-storyboard"
        for sub in ["L0", "L1"] {
            try? FileManager.default.createDirectory(atPath: dir + "/" + sub, withIntermediateDirectories: true, attributes: nil)
        }
        let perSheet = 25
        let count = max(2, Int((duration / 2).rounded(.up)))
        for sheet in 0..<((count + perSheet - 1) / perSheet) {
            writeSheet(dir + "/L1/M\(sheet).jpg&sigh=x", tile: CGSize(width: 160, height: 90), columns: 5, rows: 5,
                       first: sheet * perSheet, total: count, seconds: 2)
        }
        writeSheet(dir + "/L0/default.jpg&sigh=x", tile: CGSize(width: 48, height: 27), columns: 10, rows: 10,
                   first: 0, total: 100, seconds: duration / 100)
        return Storyboard(spec: "file://\(dir)/L$L/$N.jpg|48#27#100#10#10#0#default#x|160#90#\(count)#5#5#2000#M$M#x", duration: duration)
    }

    private static func writeSheet(_ path: String, tile: CGSize, columns: Int, rows: Int, first: Int, total: Int, seconds: Double) {
        if FileManager.default.fileExists(atPath: path) { return }
        let size = CGSize(width: tile.width * CGFloat(columns), height: tile.height * CGFloat(rows))
        UIGraphicsBeginImageContextWithOptions(size, true, 1)
        UIColor.black.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: tile.height * 0.34), .foregroundColor: UIColor.white]
        for i in 0..<(columns * rows) {
            let frame = first + i
            if frame >= total { break }
            let r = CGRect(x: CGFloat(i % columns) * tile.width, y: CGFloat(i / columns) * tile.height, width: tile.width, height: tile.height)
            UIColor(hue: CGFloat((frame * 7) % 100) / 100, saturation: 0.55, brightness: 0.8, alpha: 1).setFill()
            UIRectFill(r)
            UIColor.white.setFill()
            UIRectFill(CGRect(x: r.minX, y: r.minY, width: 1, height: r.height))
            let label = Format.duration(Double(frame) * seconds) as NSString
            let ts = label.size(withAttributes: attrs)
            label.draw(at: CGPoint(x: r.midX - ts.width / 2, y: r.midY - ts.height / 2), withAttributes: attrs)
        }
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        if let data = image?.jpegData(compressionQuality: 0.85) {
            FileManager.default.createFile(atPath: path, contents: data, attributes: nil)
        }
    }
}
