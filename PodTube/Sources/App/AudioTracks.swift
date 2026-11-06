import AVFoundation

/// An audio track the viewer can pick: one rendition of the HLS manifest of a video that has several audio tracks
/// (the original, dubbed languages, audio description).
struct AudioOption {
    let option: AVMediaSelectionOption
    let title: String
    /// What the manifest says ("ja", "en-US").
    let languageTag: String
    let isOriginal: Bool
    let isSelected: Bool
}

extension PlayerManager {
    /// The audio tracks of the playing item, the original one first. Fewer than two: nothing to choose from.
    var audioOptions: [AudioOption] {
        // not before the item is ready: asking an asset that still loads its manifest would block the main thread
        guard let item = player.currentItem, item.status == .readyToPlay,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else { return [] }
        let selected = item.currentMediaSelection.selectedMediaOption(in: group)
        let tracks = info?.audioTracks ?? []
        var seen = Set<String>()
        var out: [AudioOption] = []
        for o in group.options {
            let tag = o.extendedLanguageTag ?? o.locale?.identifier ?? ""
            // a manifest lists every rendition once per audio group (one group per bitrate): show it once
            if !seen.insert(tag.lowercased() + "|" + o.displayName).inserted { continue }
            let match = PlayerManager.matchTrack(tag, in: tracks)
            var title = o.displayName
            if let m = match, !m.name.isEmpty { title = m.name }
            let original = match?.isDefault ?? o.displayName.lowercased().contains("original")
            var isSelected = false
            if let s = selected {
                isSelected = s == o || (s.displayName == o.displayName && s.extendedLanguageTag == o.extendedLanguageTag)
            }
            out.append(AudioOption(option: o, title: title, languageTag: tag, isOriginal: original, isSelected: isSelected))
        }
        return out.filter { $0.isOriginal } + out.filter { !$0.isOriginal }
    }

    /// Plays the chosen track and remembers the choice for the next videos ("original", or the language).
    func selectAudio(_ o: AudioOption) {
        guard let item = player.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else { return }
        item.select(o.option, in: group)
        Settings.preferredAudio = o.isOriginal ? "original" : o.languageTag.lowercased()
        NotificationCenter.default.post(name: .playerChanged, object: nil)
    }

    /// Back to "automatic": the system picks the track that fits its language setting, for this and the next videos.
    func selectAutomaticAudio() {
        Settings.preferredAudio = ""
        if let item = player.currentItem, let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) {
            item.selectMediaOptionAutomatically(in: group)
        }
        NotificationCenter.default.post(name: .playerChanged, object: nil)
    }

    /// Applies the viewer's earlier choice to a new item. No choice: the system picks (its language setting).
    func applyAudioPreference(to item: AVPlayerItem) {
        let pref = Settings.preferredAudio
        guard !pref.isEmpty, item === player.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible), group.options.count > 1 else { return }
        let options = audioOptions
        var target: AudioOption?
        if pref == "original" {
            target = options.first(where: { $0.isOriginal })
        } else {
            target = options.first(where: { $0.languageTag.lowercased() == pref })
            if target == nil {
                // "en" was chosen on a video whose English is "en-US" (or the other way round): the same language
                let same = options.filter { PlayerManager.primaryLanguage($0.languageTag) == PlayerManager.primaryLanguage(pref) }
                if same.count == 1 { target = same[0] }
            }
        }
        if let t = target, !t.isSelected { item.select(t.option, in: group) }
    }

    fileprivate static func primaryLanguage(_ tag: String) -> String {
        return String(tag.lowercased().split(separator: "-").first ?? "")
    }

    /// The track of YouTube's `adaptiveFormats` that a manifest language belongs to: "en-US" matches "en-US.4", "en"
    /// matches "en.4", and "en" also matches "en-US.4" when that is the only English track.
    fileprivate static func matchTrack(_ tag: String, in tracks: [AudioTrackInfo]) -> AudioTrackInfo? {
        let t = tag.lowercased()
        if t.isEmpty { return nil }
        let exact = tracks.filter { $0.languageTag.lowercased() == t }
        if exact.count == 1 { return exact[0] }
        if !exact.isEmpty { return nil }
        let loose = tracks.filter { primaryLanguage($0.languageTag) == primaryLanguage(t) }
        return loose.count == 1 ? loose[0] : nil
    }
}
