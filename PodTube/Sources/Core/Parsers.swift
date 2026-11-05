import Foundation

/// Turns raw InnerTube JSON (visionOS client / classic renderers) into model objects.
/// Everything is lenient: unknown or missing fields are skipped rather than failing the page.
enum Parse {

    // MARK: - Small helpers

    static func absolute(_ url: String) -> String {
        if url.hasPrefix("//") { return "https:" + url }
        return url
    }

    /// Smallest thumbnail that is at least `minWidth` wide, else the largest one.
    static func thumb(_ node: JSON, minWidth: Int) -> String {
        let list = node["thumbnails"].array
        if list.isEmpty { return "" }
        var best: String?
        var bestWidth = Int.max
        var largest = ""
        var largestWidth = -1
        for t in list {
            let url = t["url"].stringValue
            let w = t["width"].int ?? 0
            if w > largestWidth { largestWidth = w; largest = url }
            if w >= minWidth && w < bestWidth { bestWidth = w; best = url }
        }
        return absolute(best ?? largest)
    }

    private static func firstText(_ nodes: JSON...) -> String {
        for n in nodes {
            if let t = n.text, !t.isEmpty { return t }
        }
        return ""
    }

    // MARK: - Single renderers

    /// compactVideoRenderer / videoWithContextRenderer / playlistVideoRenderer / reelItemRenderer
    static func video(_ r: JSON) -> VideoItem? {
        let nav = r["navigationEndpoint"]
        var id = r["videoId"].stringValue
        if id.isEmpty { id = nav["watchEndpoint"]["videoId"].stringValue }
        if id.isEmpty { id = nav["reelWatchEndpoint"]["videoId"].stringValue }
        if id.isEmpty { return nil }

        var v = VideoItem(id: id)
        if nav["reelWatchEndpoint"].exists { v.isShort = true }
        v.title = firstText(r["title"], r["headline"])

        var byline = r["longBylineText"]
        if !byline.exists { byline = r["shortBylineText"] }
        if !byline.exists { byline = r["ownerText"] }
        v.channelName = byline["runs"][0]["text"].string ?? byline.textValue
        v.channelId = byline["runs"][0]["navigationEndpoint"]["browseEndpoint"]["browseId"].stringValue
        v.channelAvatar = thumb(r["channelThumbnail"], minWidth: 48)
        v.thumbnail = thumb(r["thumbnail"], minWidth: 480)
        v.views = firstText(r["shortViewCountText"], r["viewCountText"])
        v.published = r["publishedTimeText"].textValue
        v.duration = r["lengthText"].textValue

        for o in r["thumbnailOverlays"].array {
            let ts = o["thumbnailOverlayTimeStatusRenderer"]
            if !ts.exists { continue }
            let style = ts["style"].stringValue
            if style == "LIVE" { v.isLive = true }
            if style == "UPCOMING" { v.isUpcoming = true }
            if style == "SHORTS" { v.isShort = true }
            if v.duration.isEmpty && (style == "DEFAULT" || style == "SHORTS") {
                v.duration = ts["text"].textValue
            }
        }
        if v.isLive || v.isUpcoming { v.duration = "" }
        return v
    }

    static func channel(_ r: JSON) -> ChannelItem? {
        var id = r["channelId"].stringValue
        if id.isEmpty { id = r["navigationEndpoint"]["browseEndpoint"]["browseId"].stringValue }
        if id.isEmpty { return nil }
        var c = ChannelItem(id: id)
        c.name = firstText(r["displayName"], r["title"])
        c.avatar = thumb(r["thumbnail"], minWidth: 88)
        // The renderer mislabels these: videoCountText holds the subscriber count, subscriberCountText the @handle.
        let a = r["videoCountText"].textValue
        let b = r["subscriberCountText"].textValue
        if b.hasPrefix("@") {
            c.handle = b
            c.subscribers = a
        } else {
            c.subscribers = b
            c.videoCount = a
        }
        return c
    }

    static func playlist(_ r: JSON) -> PlaylistItem? {
        var id = r["playlistId"].stringValue
        if id.isEmpty {
            let b = r["navigationEndpoint"]["browseEndpoint"]["browseId"].stringValue
            id = b.hasPrefix("VL") ? String(b.dropFirst(2)) : b
        }
        if id.isEmpty { return nil }
        var p = PlaylistItem(id: id)
        p.title = r["title"].textValue
        p.channelName = firstText(r["shortBylineText"], r["longBylineText"])
        var t = thumb(r["thumbnail"], minWidth: 320)
        if t.isEmpty {
            t = thumb(r["thumbnailRenderer"]["playlistVideoThumbnailRenderer"]["thumbnail"], minWidth: 320)
        }
        if t.isEmpty {
            t = thumb(r["thumbnailRenderer"]["playlistCustomThumbnailRenderer"]["thumbnail"], minWidth: 320)
        }
        p.thumbnail = t
        p.videoCount = firstText(r["videoCountText"], r["videoCountShortText"], r["numVideosText"])
        return p
    }

    // MARK: - Feeds

    private final class FeedWalker {
        var items: [FeedItem] = []
        var sections: [FeedSection] = []
        var tokens: [String] = []
        var seen = Set<String>()
        var currentSection: Int?

        func add(_ item: FeedItem) {
            items.append(item)
            if let i = currentSection { sections[i].items.append(item) }
        }

        func visit(_ node: Any?, depth: Int) {
            if depth > 60 { return }
            if let arr = node as? [Any] {
                for x in arr { visit(x, depth: depth + 1) }
                return
            }
            guard let d = node as? [String: Any] else { return }

            for key in ["compactVideoRenderer", "videoWithContextRenderer", "playlistVideoRenderer",
                        "gridVideoRenderer", "reelItemRenderer", "playlistPanelVideoRenderer"] {
                if let r = d[key] {
                    if let v = Parse.video(JSON(r)), !seen.contains(v.id) {
                        seen.insert(v.id)
                        add(.video(v))
                    }
                    return
                }
            }
            for key in ["compactChannelRenderer", "gridChannelRenderer", "channelRenderer"] {
                if let r = d[key] {
                    if let c = Parse.channel(JSON(r)), !seen.contains("c:" + c.id) {
                        seen.insert("c:" + c.id)
                        add(.channel(c))
                    }
                    return
                }
            }
            for key in ["compactPlaylistRenderer", "gridPlaylistRenderer", "playlistRenderer"] {
                if let r = d[key] {
                    if let p = Parse.playlist(JSON(r)), !seen.contains("p:" + p.id) {
                        seen.insert("p:" + p.id)
                        add(.playlist(p))
                    }
                    return
                }
            }
            if let shelf = d["shelfRenderer"] {
                let s = JSON(shelf)
                let title = s["title"].textValue
                sections.append(FeedSection(title: title, items: []))
                let saved = currentSection
                currentSection = sections.count - 1
                visit(s["content"].raw, depth: depth + 1)
                currentSection = saved
                if let last = sections.last, last.items.isEmpty { sections.removeLast() }
                return
            }
            if let n = d["nextContinuationData"] as? [String: Any], let t = n["continuation"] as? String {
                tokens.append(t)
                return
            }
            if let c = d["continuationItemRenderer"] {
                let t = JSON(c)["continuationEndpoint"]["continuationCommand"]["token"].stringValue
                if !t.isEmpty { tokens.append(t) }
                return
            }
            for k in d.keys.sorted() {
                if k == "menu" || k == "thumbnailOverlays" || k == "trackingParams" { continue }
                visit(d[k], depth: depth + 1)
            }
        }
    }

    /// Generic list parser: walks the whole response and collects every recognised item in document order.
    static func feed(_ root: JSON) -> FeedPage {
        let w = FeedWalker()
        w.visit(root.raw, depth: 0)
        var page = FeedPage()
        page.items = groupShorts(w.items)
        page.sections = w.sections
        page.continuation = w.tokens.last
        return page
    }

    static func groupShorts(_ items: [FeedItem]) -> [FeedItem] {
        var out: [FeedItem] = []
        var run: [VideoItem] = []
        for it in items {
            if case .video(let v) = it, v.isShort {
                run.append(v)
            } else {
                if !run.isEmpty { out.append(.shorts(run)); run = [] }
                out.append(it)
            }
        }
        if !run.isEmpty { out.append(.shorts(run)) }
        return out
    }

    // MARK: - Watch page (`next`)

    static func watch(_ root: JSON, videoId: String) -> WatchInfo {
        var info = WatchInfo(videoId: videoId)

        if let m = root.findFirst("videoMetadataRenderer") {
            info.title = m["title"].textValue
            info.views = m["viewCountText"].textValue
            info.viewsShort = m["shortViewCountText"].textValue
            info.date = m["dateText"].textValue
            info.description = m["description"].textValue
            let like = m["likeButton"]["likeButtonRenderer"]
            info.likeText = like["likeCountText"].textValue
            info.likeCount = like["likeCount"].int

            let owner = m["owner"]["videoOwnerRenderer"]
            var cid = owner["navigationEndpoint"]["browseEndpoint"]["browseId"].stringValue
            if cid.isEmpty { cid = owner["subscribeButton"]["subscribeButtonRenderer"]["channelId"].stringValue }
            if !cid.isEmpty {
                var ch = ChannelItem(id: cid)
                ch.name = owner["title"].textValue
                ch.avatar = thumb(owner["thumbnail"], minWidth: 88)
                ch.subscribers = owner["subscriberCountText"].textValue
                ch.handle = owner["navigationEndpoint"]["browseEndpoint"]["canonicalBaseUrl"].stringValue
                info.channel = ch
            }
        }

        // Related videos live in the second tab of the tabbed results.
        let tabs = root.findFirst("watchNextTabbedResultsRenderer")?["tabs"].array ?? []
        if tabs.count >= 2 {
            info.related = feed(tabs[1])
        } else if let t = tabs.last, tabs.count == 1 {
            info.related = feed(t)
            info.related.items = info.related.items.filter {
                if case .video(let v) = $0 { return v.id != videoId }
                return true
            }
        }

        if let next = root["contents"]["singleColumnWatchNextResults"]["autoplay"]["autoplay"]["sets"][0]["autoplayVideoRenderer"]["compactVideoRenderer"].raw {
            info.autoplay = video(JSON(next))
        }

        // Comments panel: count + the continuation token that loads the first page.
        for p in root["engagementPanels"].array {
            let panel = p["engagementPanelSectionListRenderer"]
            if panel["panelIdentifier"].stringValue != "comment-item-section" { continue }
            let header = panel["header"]["engagementPanelTitleHeaderRenderer"]
            info.commentCount = header["contextualInfo"].textValue
            info.commentsToken = panel["content"]["sectionListRenderer"]["continuations"][0]["reloadContinuationData"]["continuation"].string
            for item in header["menu"]["sortFilterSubMenuRenderer"]["subMenuItems"].array {
                let tok = item["continuation"]["reloadContinuationData"]["continuation"].stringValue
                if !tok.isEmpty { info.commentSortTokens.append((title: item["title"].textValue, token: tok)) }
            }
        }

        // Playlist queue (only present when the request carried a playlistId).
        let pl = root["contents"]["singleColumnWatchNextResults"]["playlist"]["playlist"]
        if pl.exists {
            info.queueTitle = pl["title"].textValue
            info.queueIndex = pl["currentIndex"].int ?? 0
            for it in pl["contents"].array {
                if let v = video(it["playlistPanelVideoRenderer"]) { info.queue.append(v) }
            }
        }
        return info
    }

    // MARK: - Comments

    static func comment(_ cr: JSON) -> Comment? {
        let id = cr["commentId"].stringValue
        if id.isEmpty { return nil }
        var c = Comment(id: id)
        c.author = cr["authorText"].textValue
        c.authorId = cr["authorEndpoint"]["browseEndpoint"]["browseId"].stringValue
        c.avatar = thumb(cr["authorThumbnail"], minWidth: 48)
        c.text = cr["contentText"].textValue
        c.published = cr["publishedTimeText"].textValue
        c.likes = cr["voteCount"].textValue
        c.isOwner = cr["authorIsChannelOwner"].bool ?? false
        c.isPinned = cr["pinnedCommentBadge"].exists
        c.replyCount = cr["replyCount"].int ?? 0
        return c
    }

    static func comments(_ root: JSON) -> CommentPage {
        var page = CommentPage()
        for t in root.findAll("commentThreadRenderer") {
            let cr = t["comment"]["commentRenderer"]
            guard var c = comment(cr) else { continue }
            c.replyCount = max(c.replyCount, cr["replyCount"].int ?? 0)
            page.comments.append(c)
        }
        var tokens: [String] = []
        for n in root.findAll("nextContinuationData") {
            let t = n["continuation"].stringValue
            if !t.isEmpty { tokens.append(t) }
        }
        page.continuation = tokens.last
        if let h = root.findFirst("commentsHeaderRenderer") {
            page.totalText = h["countText"].textValue
            for item in h["sortMenu"]["sortFilterSubMenuRenderer"]["subMenuItems"].array {
                let tok = item["continuation"]["reloadContinuationData"]["continuation"].stringValue
                if !tok.isEmpty { page.sortTokens.append((title: item["title"].textValue, token: tok)) }
            }
        }
        return page
    }

    // MARK: - Channel / playlist pages

    static func channelInfo(_ root: JSON, id: String) -> ChannelInfo {
        var info = ChannelInfo(id: id)
        let h = root["header"]["c4TabbedHeaderRenderer"]
        if let cid = h["channelId"].string { info.id = cid }
        info.name = h["title"].textValue
        info.avatar = thumb(h["avatar"], minWidth: 88)
        info.banner = thumb(h["banner"], minWidth: 640)
        info.subscribers = h["subscriberCountText"].textValue
        info.videoCount = h["videosCountText"].textValue
        info.handle = h["channelHandleText"].textValue
        info.verified = !h["badges"].array.isEmpty
        for t in root["contents"]["singleColumnBrowseResultsRenderer"]["tabs"].array {
            let tr = t["tabRenderer"]
            let title = tr["title"].textValue
            if title.isEmpty { continue }
            let params = tr["endpoint"]["browseEndpoint"]["params"].stringValue
            info.tabs.append(ChannelTab(title: title, params: params, selected: tr["selected"].bool ?? false))
        }
        info.firstPage = feed(root["contents"])
        return info
    }

    static func playlistInfo(_ root: JSON, id: String) -> PlaylistInfo {
        var info = PlaylistInfo(id: id)
        let h = root["header"]["playlistHeaderRenderer"]
        info.title = h["title"].textValue
        info.owner = h["ownerText"].textValue
        info.ownerId = h["ownerEndpoint"]["browseEndpoint"]["browseId"].stringValue
        var stats: [String] = []
        let n = h["numVideosText"].textValue
        if !n.isEmpty { stats.append(n) }
        let views = h["viewCountText"].textValue
        if !views.isEmpty { stats.append(views) }
        info.stats = stats
        info.firstPage = feed(root["contents"])
        info.thumbnail = info.firstPage.videos.first?.thumbnail ?? ""
        return info
    }

    // MARK: - Player

    static func playback(_ root: JSON, videoId: String) throws -> PlaybackInfo {
        var info = PlaybackInfo(videoId: videoId)
        let vd = root["videoDetails"]
        info.title = vd["title"].stringValue
        info.author = vd["author"].stringValue
        info.channelId = vd["channelId"].stringValue
        info.duration = Double(vd["lengthSeconds"].stringValue) ?? 0
        info.isLive = (vd["isLive"].bool ?? false) || (vd["isLiveContent"].bool ?? false) && info.duration == 0
        info.thumbnail = thumb(vd["thumbnail"], minWidth: 480)

        let ps = root["playabilityStatus"]
        let status = ps["status"].stringValue
        let sd = root["streamingData"]
        if status != "OK" && !sd.exists {
            var reason = ps["reason"].textValue
            if reason.isEmpty { reason = ps["errorScreen"]["playerErrorMessageRenderer"]["reason"].textValue }
            if reason.isEmpty { reason = status.isEmpty ? "Playback error" : status }
            if status == "LOGIN_REQUIRED" { throw InnerTubeError.botCheck(reason) }
            throw InnerTubeError.unplayable(reason)
        }

        if let hls = sd["hlsManifestUrl"].string { info.hlsURL = URL(string: hls) }

        // Muxed progressive (rarely present for this client, kept as a fallback).
        var bestMuxed = 0
        for f in sd["formats"].array {
            let mime = f["mimeType"].stringValue
            guard mime.contains("video/mp4"), mime.contains("avc1"), let u = f["url"].string else { continue }
            let h = f["height"].int ?? 0
            if h >= bestMuxed { bestMuxed = h; info.progressiveURL = URL(string: u) }
        }

        // Adaptive H.264 + AAC (combined on the device with AVMutableComposition if HLS is unavailable).
        var bestVideoH = 0
        var bestAudioRate = 0
        for f in sd["adaptiveFormats"].array {
            let mime = f["mimeType"].stringValue
            guard let u = f["url"].string else { continue }
            if mime.contains("video/mp4") && mime.contains("avc1") {
                let h = f["height"].int ?? 0
                if h > bestVideoH && h <= 1080 { bestVideoH = h; info.videoURL = URL(string: u) }
            } else if mime.contains("audio/mp4") && mime.contains("mp4a") {
                let br = f["bitrate"].int ?? 0
                if br > bestAudioRate { bestAudioRate = br; info.audioURL = URL(string: u) }
            }
        }
        info.maxHeight = max(bestVideoH, bestMuxed)

        for t in root["captions"]["playerCaptionsTracklistRenderer"]["captionTracks"].array {
            let url = t["baseUrl"].stringValue
            if url.isEmpty { continue }
            info.captions.append(CaptionTrack(languageCode: t["languageCode"].stringValue,
                                              name: t["name"].textValue,
                                              url: url,
                                              isAuto: t["kind"].stringValue == "asr"))
        }

        if !info.isPlayable {
            throw InnerTubeError.unplayable(ps["reason"].string ?? "No playable stream")
        }
        return info
    }

    // MARK: - Shorts

    static func reelSequence(_ root: JSON) -> [String] {
        var ids: [String] = []
        for e in root["entries"].array {
            let id = e["command"]["reelWatchEndpoint"]["videoId"].stringValue
            if !id.isEmpty && !ids.contains(id) { ids.append(id) }
        }
        return ids
    }

    /// Details for one Short from `reel/reel_item_watch`.
    static func reelItem(_ root: JSON, videoId: String) -> ShortEntry {
        var v = VideoItem(id: videoId)
        v.isShort = true
        let ov = root["overlay"]["reelPlayerOverlayRenderer"]
        let header = ov["reelPlayerHeaderSupportedRenderers"]["reelPlayerHeaderRenderer"]
        v.title = header["reelTitleText"].textValue
        v.channelName = header["channelTitleText"].textValue
        v.channelId = header["channelNavigationEndpoint"]["browseEndpoint"]["browseId"].stringValue
        v.channelAvatar = thumb(header["channelThumbnail"], minWidth: 48)
        v.published = header["timestampText"].textValue
        var e = ShortEntry(video: v)
        e.likes = ov["likeButton"]["likeButtonRenderer"]["likeCountText"].textValue
        e.comments = ov["viewCommentsButton"]["buttonRenderer"]["text"].textValue
        return e
    }
}
