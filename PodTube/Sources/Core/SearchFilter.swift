import Foundation

/// Builds the protobuf `params` blob that YouTube search uses for filters / sorting.
struct SearchFilter: Equatable {
    enum Sort: Int { case relevance = 0, rating = 1, uploadDate = 2, viewCount = 3 }
    enum UploadDate: Int { case any = 0, hour = 1, today = 2, week = 3, month = 4, year = 5 }
    enum Kind: Int { case any = 0, video = 1, channel = 2, playlist = 3, movie = 4 }
    /// short = under 4 minutes, medium = 4-20 minutes, long = over 20 minutes
    enum Duration: Int { case any = 0, short = 1, long = 2, medium = 3 }

    var sort: Sort = .relevance
    var date: UploadDate = .any
    var kind: Kind = .any
    var duration: Duration = .any
    var live = false
    var hd = false
    var subtitles = false
    var fourK = false

    var isDefault: Bool { return self == SearchFilter() }

    var params: String? {
        var out = [UInt8]()
        if sort != .relevance { out += SearchFilter.varintField(1, sort.rawValue) }
        var f = [UInt8]()
        if date != .any { f += SearchFilter.varintField(1, date.rawValue) }
        if kind != .any { f += SearchFilter.varintField(2, kind.rawValue) }
        if duration != .any { f += SearchFilter.varintField(3, duration.rawValue) }
        if hd { f += SearchFilter.varintField(4, 1) }
        if subtitles { f += SearchFilter.varintField(5, 1) }
        if live { f += SearchFilter.varintField(8, 1) }
        if fourK { f += SearchFilter.varintField(14, 1) }
        if !f.isEmpty {
            out += SearchFilter.varint(UInt64((2 << 3) | 2))
            out += SearchFilter.varint(UInt64(f.count))
            out += f
        }
        if out.isEmpty { return nil }
        let b64 = Data(out).base64EncodedString()
        return b64.replacingOccurrences(of: "=", with: "%3D")
    }

    private static func varint(_ value: UInt64) -> [UInt8] {
        var v = value
        var bytes = [UInt8]()
        while v >= 0x80 {
            bytes.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        bytes.append(UInt8(v))
        return bytes
    }

    private static func varintField(_ field: Int, _ value: Int) -> [UInt8] {
        return varint(UInt64(field << 3)) + varint(UInt64(value))
    }
}
