import Foundation

/// The small preview pictures YouTube keeps for every video ("storyboards"): sheets of frames laid out in a grid,
/// in several sizes. The player response carries them as one string:
/// `baseURL|w#h#count#columns#rows#intervalMs#name#sigh|...` (`$L` in the base URL and `$N` / `$M` in the name are
/// filled in per level and per sheet).
struct Storyboard {
    struct Level {
        /// The `$L` of the sheet URL (0 = the smallest frames).
        var index: Int
        /// Size of one frame in pixels.
        var width: Int
        var height: Int
        /// Frames over the whole video (all sheets together).
        var count: Int
        var columns: Int
        var rows: Int
        /// Time between two frames; 0 = the frames are spread evenly over the video.
        var intervalMs: Int
        /// "default" or "M$M" (`$M` is the number of the sheet).
        var name: String
        var sigh: String

        var framesPerSheet: Int { return max(1, columns * rows) }
        var sheetCount: Int { return (count + framesPerSheet - 1) / framesPerSheet }
    }

    /// Where one frame sits: sheet number and its cell in that sheet.
    struct Cell: Equatable {
        var sheet: Int
        var column: Int
        var row: Int
        /// Position of the frame in the whole video (0-based).
        var frame: Int
    }

    let baseURL: String
    /// Smallest frames first.
    let levels: [Level]
    let duration: Double

    init?(spec: String, duration: Double) {
        let parts = spec.components(separatedBy: "|")
        guard parts.count >= 2, duration > 0, parts[0].contains("$L") || parts[0].contains("$N") else { return nil }
        var parsed: [Level] = []
        for p in parts.dropFirst() {
            let f = p.components(separatedBy: "#")
            guard f.count == 8, let w = Int(f[0]), let h = Int(f[1]), let n = Int(f[2]), let c = Int(f[3]), let r = Int(f[4]),
                  let iv = Int(f[5]), w > 0, h > 0, n > 0, c > 0, r > 0 else { continue }
            parsed.append(Level(index: 0, width: w, height: h, count: n, columns: c, rows: r, intervalMs: iv, name: f[6], sigh: f[7]))
        }
        // `$L` counts from the smallest frames, whatever the order of the list
        parsed.sort { $0.width != $1.width ? $0.width < $1.width : $0.height < $1.height }
        for i in parsed.indices { parsed[i].index = i }
        guard !parsed.isEmpty else { return nil }
        self.baseURL = parts[0]
        self.levels = parsed
        self.duration = duration
    }

    /// The smallest level whose frames are at least `width` pixels wide (the largest one if none is).
    func level(minWidth width: Int) -> Level {
        return levels.first(where: { $0.width >= width }) ?? levels[levels.count - 1]
    }

    /// Seconds between two frames of `level`.
    func spacing(of level: Level) -> Double {
        if level.intervalMs > 0 { return Double(level.intervalMs) / 1000 }
        return duration / Double(max(1, level.count))
    }

    func frameIndex(_ level: Level, at time: Double) -> Int {
        let idx = Int((max(0, time) / spacing(of: level)).rounded(.down))
        return min(max(0, idx), level.count - 1)
    }

    func cell(_ level: Level, frame: Int) -> Cell {
        let f = min(max(0, frame), level.count - 1)
        let sheet = f / level.framesPerSheet
        let j = f % level.framesPerSheet
        return Cell(sheet: sheet, column: j % level.columns, row: j / level.columns, frame: f)
    }

    func cell(_ level: Level, at time: Double) -> Cell {
        return cell(level, frame: frameIndex(level, at: time))
    }

    /// Time shown by frame number `frame` of `level`.
    func time(_ level: Level, frame: Int) -> Double {
        return min(duration, Double(frame) * spacing(of: level))
    }

    func sheetURL(_ level: Level, sheet: Int) -> URL? {
        let name = level.name.replacingOccurrences(of: "$M", with: String(sheet))
        let s = baseURL.replacingOccurrences(of: "$L", with: String(level.index))
            .replacingOccurrences(of: "$N", with: name) + "&sigh=" + level.sigh
        return URL(string: s)
    }
}
