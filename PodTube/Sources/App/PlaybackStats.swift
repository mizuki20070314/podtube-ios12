import UIKit
import AVFoundation
import CoreMedia

extension PlayerManager {
    /// The lines of the stats overlay ("stats for nerds"): what the player is doing right now.
    func statsLines() -> [String] {
        let item = player.currentItem
        let videoTrack = item.flatMap { PlayerManager.enabledTrack($0, .video) }
        let audioTrack = item.flatMap { PlayerManager.enabledTrack($0, .audio) }
        // the access log is what AVFoundation records about the network side of the item
        let events = item?.accessLog()?.events ?? []
        var out: [String] = []

        var head = "ID    " + (video?.id ?? "-") + "  " + sourceName
        if isLive { head += "  LIVE" }
        out.append(head)

        var res = "-"
        if let it = item, it.presentationSize.width > 0 {
            res = "\(Int(it.presentationSize.width))x\(Int(it.presentationSize.height))"
            if let fps = videoTrack?.currentVideoFrameRate, fps > 0 { res += String(format: " @%.0f", fps) }
        }
        let cap = maxHeight == 0 ? "auto" : "\(maxHeight)p"
        out.append("Res   \(res)  max \(cap)")

        let codecs = [PlayerManager.codecName(videoTrack), PlayerManager.codecName(audioTrack)].compactMap { $0 }
        out.append("Codec " + (codecs.isEmpty ? "-" : codecs.joined(separator: " / ")))

        let indicated = Format.bitrate(events.last?.indicatedBitrate ?? 0)
        let observed = Format.bitrate(events.last?.observedBitrate ?? 0)
        out.append("Rate  \(indicated)  net \(observed)")

        let dropped = events.reduce(0) { $0 + max(0, $1.numberOfDroppedVideoFrames) }
        let stalls = events.reduce(0) { $0 + max(0, $1.numberOfStalls) }
        out.append("Buf   " + String(format: "%.1f s", bufferAhead) + "  drop \(dropped)  stall \(stalls)")

        let bytes = events.reduce(Int64(0)) { $0 + max(0, $1.numberOfBytesTransferred) }
        let transferred = events.isEmpty ? "-" : Format.bytes(bytes)
        let volume = Int((AVAudioSession.sharedInstance().outputVolume * 100).rounded())
        out.append("Data  \(transferred)  speed " + String(format: "%g", speed) + "x  vol \(volume)%")

        // the name of the track only when there is a choice (a single track is listed as "unknown")
        let options = audioOptions
        let trackTitle = options.count > 1 ? options.first(where: { $0.isSelected })?.title : nil
        let format = PlayerManager.audioFormatText(audioTrack)
        let audioText = [trackTitle, format].compactMap { $0 }.joined(separator: "  ")
        out.append("Audio " + (audioText.isEmpty ? "-" : audioText))

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        out.append("App   \(version)  iOS " + UIDevice.current.systemVersion + "  " + PlayerManager.deviceModel)
        return out
    }

    /// Seconds of media that are loaded ahead of the playhead.
    private var bufferAhead: TimeInterval {
        guard let item = player.currentItem else { return 0 }
        let now = player.currentTime().seconds
        guard now.isFinite else { return 0 }
        for v in item.loadedTimeRanges {
            let r = v.timeRangeValue
            let start = r.start.seconds
            let end = start + r.duration.seconds
            if now >= start - 0.5 && now <= end { return max(0, end - now) }
        }
        return 0
    }

    fileprivate static func enabledTrack(_ item: AVPlayerItem, _ type: AVMediaType) -> AVPlayerItemTrack? {
        return item.tracks.first(where: { $0.isEnabled && $0.assetTrack?.mediaType == type })
    }

    /// "avc1.4D401F" (profile and level read from the stream) / "mp4a.40.2"; the four characters of the format otherwise.
    fileprivate static func codecName(_ track: AVPlayerItemTrack?) -> String? {
        guard let asset = track?.assetTrack, let first = asset.formatDescriptions.first else { return nil }
        let desc = first as! CMFormatDescription
        let code = fourCC(CMFormatDescriptionGetMediaSubType(desc))
        if asset.mediaType == .video {
            if code == "avc1" {
                var parameterSet: UnsafePointer<UInt8>?
                var size = 0
                let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(desc, parameterSetIndex: 0,
                                                                                 parameterSetPointerOut: &parameterSet,
                                                                                 parameterSetSizeOut: &size,
                                                                                 parameterSetCountOut: nil,
                                                                                 nalUnitHeaderLengthOut: nil)
                if status == noErr, let p = parameterSet, size >= 4 {
                    return String(format: "avc1.%02X%02X%02X", p[1], p[2], p[3])
                }
            }
            return code
        }
        switch code {
        case "aac ": return "mp4a.40.2"
        case "aach": return "mp4a.40.5"
        case "aacp": return "mp4a.40.29"
        default: return code
        }
    }

    /// "44.1 kHz 2ch" of the audio that plays.
    fileprivate static func audioFormatText(_ track: AVPlayerItemTrack?) -> String? {
        guard let first = track?.assetTrack?.formatDescriptions.first else { return nil }
        let desc = first as! CMFormatDescription
        guard let basic = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee, basic.mSampleRate > 0 else { return nil }
        return String(format: "%g kHz %dch", basic.mSampleRate / 1000, Int32(basic.mChannelsPerFrame))
    }

    fileprivate static func fourCC(_ value: FourCharCode) -> String {
        let bytes = [UInt8((value >> 24) & 255), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)]
        return String(bytes: bytes, encoding: .ascii) ?? "?"
    }

    /// "iPod9,1" (the simulator names the device it pretends to be).
    fileprivate static var deviceModel: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var system = utsname()
        uname(&system)
        return Mirror(reflecting: system.machine).children.reduce("") { text, element in
            guard let c = element.value as? Int8, c != 0 else { return text }
            return text + String(UnicodeScalar(UInt8(bitPattern: c)))
        }
    }
}

/// The panel of the stats: monospaced text on a translucent plate. Touches pass through to the player controls.
final class StatsOverlayView: UIView {
    private let label = UILabel()
    private let inset: CGFloat = 6

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = UIColor(white: 0, alpha: 0.68)
        layer.cornerRadius = 6
        clipsToBounds = true
        label.font = UIFont(name: "Menlo-Regular", size: 10) ?? UIFont.systemFont(ofSize: 10)
        label.textColor = .white
        label.numberOfLines = 0
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setLines(_ lines: [String]) {
        label.text = lines.joined(separator: "\n")
    }

    /// The size of the plate for the current text, at most `maxWidth` wide.
    func fittingSize(maxWidth: CGFloat) -> CGSize {
        let s = label.sizeThatFits(CGSize(width: max(0, maxWidth - inset * 2), height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: min(maxWidth, ceil(s.width) + inset * 2), height: ceil(s.height) + inset * 2)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: inset, dy: inset)
    }
}
