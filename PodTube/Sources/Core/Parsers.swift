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
        var list = node["thumbnails"].array
        if list.isEmpty { list = node["sources"].array }   // view-model style images
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

    /// `lockupViewModel` (the newer web layout): videos and playlists.
    static func lockup(_ r: JSON) -> FeedItem? {
        let id = r["contentId"].stringValue
        if id.isEmpty { return nil }
        let type = r["contentType"].stringValue
        let meta = r["metadata"]["lockupMetadataViewModel"]
        let title = meta["title"]["content"].stringValue
        let thumbNode = r["contentImage"]["thumbnailViewModel"]

        if type == "LOCKUP_CONTENT_TYPE_PLAYLIST" || type == "LOCKUP_CONTENT_TYPE_PODCAST" {
            var p = PlaylistItem(id: id)
            p.title = title
            var t = thumb(thumbNode["image"], minWidth: 320)
            if t.isEmpty {
                t = thumb(r["contentImage"]["collectionThumbnailViewModel"]["primaryThumbnail"]["thumbnailViewModel"]["image"], minWidth: 320)
            }
            p.thumbnail = t
            let rows = meta["metadata"]["contentMetadataViewModel"]["metadataRows"].array
            p.channelName = rows.first?["metadataParts"][0]["text"]["content"].stringValue ?? ""
            return .playlist(p)
        }
        if type != "LOCKUP_CONTENT_TYPE_VIDEO" && !type.isEmpty { return nil }

        var v = VideoItem(id: id)
        v.title = title
        v.thumbnail = thumb(thumbNode["image"], minWidth: 480)
        for o in thumbNode["overlays"].array {
            for b in o["thumbnailBottomOverlayViewModel"]["badges"].array {
                let badge = b["thumbnailBadgeViewModel"]
                let text = badge["text"].stringValue
                let style = badge["badgeStyle"].stringValue
                if style.contains("LIVE") { v.isLive = true } else if text.contains(":") && v.duration.isEmpty { v.duration = text }
            }
        }
        let avatarNode = meta["image"]["decoratedAvatarViewModel"]
        v.channelAvatar = thumb(avatarNode["avatar"]["avatarViewModel"]["image"], minWidth: 48)
        v.channelId = avatarNode["rendererContext"]["commandContext"]["onTap"]["innertubeCommand"]["browseEndpoint"]["browseId"].stringValue
        let rows = meta["metadata"]["contentMetadataViewModel"]["metadataRows"].array
        if rows.count >= 2 {
            v.channelName = rows[0]["metadataParts"][0]["text"]["content"].stringValue
            v.views = rows[1]["metadataParts"][0]["text"]["content"].stringValue
            v.published = rows[1]["metadataParts"][1]["text"]["content"].stringValue
        } else if let only = rows.first {
            v.views = only["metadataParts"][0]["text"]["content"].stringValue
            v.published = only["metadataParts"][1]["text"]["content"].stringValue
        }
        return .video(v)
    }

    /// `shortsLockupViewModel`
    static func shortLockup(_ r: JSON) -> VideoItem? {
        var id = r["onTap"]["innertubeCommand"]["reelWatchEndpoint"]["videoId"].stringValue
        if id.isEmpty { id = r["entityId"].stringValue.replacingOccurrences(of: "shorts-shelf-item-", with: "") }
        if id.isEmpty { return nil }
        var v = VideoItem(id: id)
        v.isShort = true
        v.title = r["overlayMetadata"]["primaryText"]["content"].stringValue
        v.views = r["overlayMetadata"]["secondaryText"]["content"].stringValue
        v.thumbnail = thumb(r["onTap"]["innertubeCommand"]["reelWatchEndpoint"]["thumbnail"], minWidth: 300)
        if v.title.isEmpty { v.title = r["accessibilityText"].stringValue }
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

    // MARK: - TV client (tileRenderer) – used for everything that needs the signed-in account

    /// Text of the `lineRenderer` rows of a tile / playlist header, separators and badges dropped.
    private static func lineRows(_ lines: [JSON]) -> [[String]] {
        var rows: [[String]] = []
        for line in lines {
            var row: [String] = []
            for it in line["lineRenderer"]["items"].array {
                let li = it["lineItemRenderer"]
                if li["badge"].exists { continue }
                let t = li["text"].textValue.trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t == "•" || t == "·" { continue }
                row.append(t)
            }
            rows.append(row)
        }
        return rows
    }

    static func tile(_ r: JSON) -> FeedItem? {
        let type = r["contentType"].stringValue
        let id = r["contentId"].stringValue
        if id.isEmpty || type.isEmpty { return nil }
        let meta = r["metadata"]["tileMetadataRenderer"]
        let header = r["header"]["tileHeaderRenderer"]
        let title = meta["title"].textValue
        let rows = lineRows(meta["lines"].array)

        switch type {
        case "TILE_CONTENT_TYPE_VIDEO", "TILE_CONTENT_TYPE_SHORTS":
            var v = VideoItem(id: id)
            v.title = title
            v.isShort = type == "TILE_CONTENT_TYPE_SHORTS"
            v.thumbnail = thumb(header["thumbnail"], minWidth: 480)
            if let first = rows.first { v.channelName = first.joined(separator: " ") }
            if rows.count > 1 {
                v.views = rows[1].first ?? ""
                if rows[1].count > 1 { v.published = rows[1][1] }
            }
            for o in header["thumbnailOverlays"].array {
                let ts = o["thumbnailOverlayTimeStatusRenderer"]
                if ts.exists {
                    let style = ts["style"].stringValue
                    if style == "LIVE" { v.isLive = true }
                    if style == "UPCOMING" { v.isUpcoming = true }
                    if style == "SHORTS" { v.isShort = true }
                    if v.duration.isEmpty && (style == "DEFAULT" || style == "SHORTS") { v.duration = ts["text"].textValue }
                }
                if let pct = o["thumbnailOverlayResumePlaybackRenderer"]["percentDurationWatched"].int { v.watchedPercent = pct }
            }
            if v.isLive || v.isUpcoming { v.duration = "" }
            return .video(v)
        case "TILE_CONTENT_TYPE_PLAYLIST":
            var p = PlaylistItem(id: id)
            p.title = title
            p.thumbnail = thumb(header["thumbnail"], minWidth: 320)
            if let first = rows.first { p.channelName = first.joined(separator: " · ") }
            for o in header["thumbnailOverlays"].array {
                let t = o["thumbnailOverlayTimeStatusRenderer"]["text"].textValue
                if !t.isEmpty { p.videoCount = t }
            }
            return .playlist(p)
        case "TILE_CONTENT_TYPE_CHANNEL":
            // library shortcuts ("FEhistory", …) are typed as channels too
            if !id.hasPrefix("UC") { return nil }
            var c = ChannelItem(id: id)
            c.name = title
            c.avatar = thumb(header["thumbnail"], minWidth: 88)
            for row in rows {
                for s in row {
                    if s.hasPrefix("@") { c.handle = s } else if c.subscribers.isEmpty { c.subscribers = s }
                }
            }
            return .channel(c)
        default:
            return nil
        }
    }

    /// Channel id inside the url-encoded base64 `params` of a subscriptions tab.
    static func channelId(fromParams params: String) -> String? {
        var s = params.removingPercentEncoding ?? params
        s = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        guard let data = Data(base64Encoded: s) else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        guard let re = try? NSRegularExpression(pattern: "UC[0-9A-Za-z_-]{22}", options: []) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range)
    }

    /// The left-hand channel list of the TV subscriptions page (most recently active channels first).
    static func subscriptionTabs(_ root: JSON) -> [ChannelItem] {
        var out: [ChannelItem] = []
        var seen = Set<String>()
        for t in root.findAll("tabRenderer") {
            if !t["thumbnail"].exists { continue }
            let params = t["endpoint"]["browseEndpoint"]["params"].stringValue
            guard let id = channelId(fromParams: params), !seen.contains(id) else { continue }
            seen.insert(id)
            var c = ChannelItem(id: id)
            c.name = t["title"].textValue
            c.avatar = thumb(t["thumbnail"], minWidth: 88)
            out.append(c)
        }
        return out
    }

    static func accountProfile(_ root: JSON) -> AccountProfile? {
        let items = root.findAll("accountItem")
        let item = items.first(where: { $0["isSelected"].bool == true }) ?? items.first
        guard let it = item else { return nil }
        let name = it["accountName"].textValue
        if name.isEmpty { return nil }
        return AccountProfile(name: name, handle: it["channelHandle"].textValue, avatar: thumb(it["accountPhoto"], minWidth: 88))
    }

    /// A playlist page of the TV client: title / owner / counts live in `entityMetadataRenderer`.
    static func accountPlaylistInfo(_ root: JSON, id: String) -> PlaylistInfo {
        var info = PlaylistInfo(id: id)
        if let e = root.findFirst("entityMetadataRenderer") {
            info.title = e["title"].textValue
            let texts = lineRows(e["bylines"].array).flatMap { $0 }
            if let owner = texts.first { info.owner = owner }
            info.stats = Array(texts.dropFirst())
        }
        info.firstPage = feed(root)
        info.thumbnail = info.firstPage.videos.first?.thumbnail ?? ""
        return info
    }

    static func accountWatchState(_ root: JSON) -> AccountWatchState {
        var s = AccountWatchState()
        if let like = root.findFirst("likeButtonRenderer") { s.likeStatus = like["likeStatus"].stringValue }
        if let sub = root.findFirst("subscribeButtonRenderer") {
            s.subscribed = sub["subscribed"].bool
            s.channelId = sub["channelId"].stringValue
        }
        return s
    }

    // MARK: - Feeds

    private final class FeedWalker {
        var items: [FeedItem] = []
        var sections: [FeedSection] = []
        var tokens: [String] = []
        var seen = Set<String>()
        var currentSection: Int?
        /// > 0 while inside a shelf: horizontal "more in this shelf" tokens must not be used for paging the list.
        var shelfDepth = 0

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

            if d["adSlotRenderer"] != nil || d["adBreakServiceRenderer"] != nil { return }
            if let r = d["tileRenderer"] {
                if let item = Parse.tile(JSON(r)) {
                    switch item {
                    case .video(let v):
                        if !seen.contains(v.id) {
                            seen.insert(v.id)
                            add(.video(v))
                        }
                    case .channel(let c):
                        if !seen.contains("c:" + c.id) {
                            seen.insert("c:" + c.id)
                            add(.channel(c))
                        }
                    case .playlist(let p):
                        if !seen.contains("p:" + p.id) {
                            seen.insert("p:" + p.id)
                            add(.playlist(p))
                        }
                    default:
                        break
                    }
                }
                return
            }
            if let r = d["lockupViewModel"] {
                if let item = Parse.lockup(JSON(r)) {
                    switch item {
                    case .video(let v):
                        if !seen.contains(v.id) {
                            seen.insert(v.id)
                            add(.video(v))
                        }
                    case .playlist(let p):
                        if !seen.contains("p:" + p.id) {
                            seen.insert("p:" + p.id)
                            add(.playlist(p))
                        }
                    default:
                        break
                    }
                }
                return
            }
            if let r = d["shortsLockupViewModel"] {
                if let v = Parse.shortLockup(JSON(r)), !seen.contains(v.id) {
                    seen.insert(v.id)
                    add(.video(v))
                }
                return
            }
            for key in ["compactVideoRenderer", "videoWithContextRenderer", "playlistVideoRenderer", "videoRenderer",
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
                var title = s["title"].textValue
                if title.isEmpty {
                    title = s["headerRenderer"]["shelfHeaderRenderer"]["avatarLockup"]["avatarLockupRenderer"]["title"].textValue
                }
                sections.append(FeedSection(title: title, items: []))
                let saved = currentSection
                currentSection = sections.count - 1
                shelfDepth += 1
                visit(s["content"].raw, depth: depth + 1)
                shelfDepth -= 1
                currentSection = saved
                if let last = sections.last, last.items.isEmpty { sections.removeLast() }
                return
            }
            if let n = d["nextContinuationData"] as? [String: Any], let t = n["continuation"] as? String {
                if shelfDepth == 0 { tokens.append(t) }
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

    /// Channel "About" tab: description, stats and links as one text block.
    static func aboutText(_ root: JSON) -> String? {
        guard let a = root.findFirst("channelAboutMetadataRenderer") else { return nil }
        var blocks: [String] = []
        let desc = a["description"].textValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !desc.isEmpty { blocks.append(desc) }
        var stats: [String] = []
        for key in ["joinedDateText", "viewCountText", "country"] {
            let t = a[key].textValue
            if !t.isEmpty { stats.append(t) }
        }
        if !stats.isEmpty { blocks.append(stats.joined(separator: "\n")) }
        var links: [String] = []
        for l in a["primaryLinks"].array {
            let title = l["title"].textValue
            let url = l["navigationEndpoint"]["urlEndpoint"]["url"].stringValue
            if !url.isEmpty { links.append(title.isEmpty ? url : title + "\n" + url) }
        }
        if !links.isEmpty { blocks.append(links.joined(separator: "\n\n")) }
        let out = blocks.joined(separator: "\n\n")
        return out.isEmpty ? nil : out
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

    /// The channel that owns a video, from the `next` response (id, name, icon) — nothing else is read.
    static func videoOwner(_ root: JSON) -> ChannelItem? {
        guard let owner = root.findFirst("videoOwnerRenderer") else { return nil }
        var cid = owner["navigationEndpoint"]["browseEndpoint"]["browseId"].stringValue
        if cid.isEmpty { cid = owner["subscribeButton"]["subscribeButtonRenderer"]["channelId"].stringValue }
        if cid.isEmpty { return nil }
        var ch = ChannelItem(id: cid)
        ch.name = owner["title"].textValue
        ch.avatar = thumb(owner["thumbnail"], minWidth: 88)
        ch.handle = owner["navigationEndpoint"]["browseEndpoint"]["canonicalBaseUrl"].stringValue
        return ch
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
        if let stats = root["playbackTracking"]["videostatsPlaybackUrl"]["baseUrl"].string { info.statsURL = URL(string: stats) }

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
            let length = Int64(f["contentLength"].stringValue) ?? 0
            if mime.contains("video/mp4") && mime.contains("avc1") {
                let h = f["height"].int ?? 0
                if let url = URL(string: u) {
                    info.videoFormats.append(AdaptiveFormat(height: h, url: url, bitrate: f["bitrate"].int ?? 0, contentLength: length))
                }
                if h > bestVideoH && h <= 1080 { bestVideoH = h; info.videoURL = URL(string: u) }
            } else if mime.contains("audio/mp4") && mime.contains("mp4a") {
                let br = f["bitrate"].int ?? 0
                if let url = URL(string: u) {
                    info.audioFormats.append(AdaptiveFormat(height: 0, url: url, bitrate: br, contentLength: length))
                }
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
