import Foundation

/// Demo / CI account (launch argument `-pt-demo-account`). It answers the signed-in requests with canned data in the
/// shape of the real TV responses, so the signed-in screens can be screenshotted without a Google account and
/// without any network access to the account endpoints. Nothing here is ever used for a real sign-in.
///
/// The literals are built in small, explicitly typed steps: deeply nested heterogeneous dictionary literals make the
/// Swift type checker very slow.
enum FakeAccount {
    private static let ids = [
        "dQw4w9WgXcQ", "jNQXAC9IVRw", "aircAruvnKk", "YE7VzlLtp-4", "9bZkp7q19f0", "kJQP7kiw5Fk",
        "fJ9rUzIMcZQ", "hT_nvWreIhg", "JGwWNGJdvx8", "RgKAFK5djSk", "OPf0YbXqDm0", "60ItHLz5WEA"
    ]

    typealias Dict = [String: Any]

    static func enable() {
        AuthSession.shared.storage = nil
        AccountDemo.responder = { endpoint, body in respond(endpoint, body) }
        let tokens = AuthTokens(accessToken: "demo", refreshToken: "demo", expiresAt: Date(timeIntervalSinceNow: 86_400 * 365))
        AuthSession.shared.adopt(tokens, profile: AccountProfile(name: "デモユーザー", handle: "@demo_user", avatar: ""))
    }

    // MARK: Builders

    private static func text(_ s: String) -> Dict { return ["simpleText": s] }

    private static func lineItem(_ s: String) -> Dict {
        let inner: Dict = ["text": text(s)]
        return ["lineItemRenderer": inner]
    }

    private static func row(_ parts: [String]) -> Dict {
        var items: [Dict] = []
        for (i, p) in parts.enumerated() {
            if i > 0 { items.append(lineItem("•")) }
            items.append(lineItem(p))
        }
        let inner: Dict = ["items": items]
        return ["lineRenderer": inner]
    }

    private static func thumb(_ url: String, _ w: Int, _ h: Int) -> Dict {
        let one: Dict = ["url": url, "width": w, "height": h]
        return ["thumbnails": [one]]
    }

    private static func header(thumbnail: Dict, overlays: [Dict]) -> Dict {
        let inner: Dict = ["thumbnail": thumbnail, "thumbnailOverlays": overlays]
        return ["tileHeaderRenderer": inner]
    }

    private static func metadata(title: String, lines: [Dict]) -> Dict {
        let inner: Dict = ["title": text(title), "lines": lines]
        return ["tileMetadataRenderer": inner]
    }

    private static func tile(type: String, id: String, header: Dict, metadata: Dict) -> Dict {
        let inner: Dict = ["style": "TILE_STYLE_YTLR_DEFAULT", "contentType": type, "contentId": id,
                           "header": header, "metadata": metadata]
        return ["tileRenderer": inner]
    }

    private static func video(_ n: Int, title: String, channel: String, views: String, age: String,
                              duration: String, percent: Int? = nil) -> Dict {
        let id = ids[n % ids.count]
        var overlays: [Dict] = []
        if let p = percent {
            let resume: Dict = ["percentDurationWatched": p]
            overlays.append(["thumbnailOverlayResumePlaybackRenderer": resume])
        }
        let status: Dict = ["text": text(duration), "style": "DEFAULT"]
        overlays.append(["thumbnailOverlayTimeStatusRenderer": status])
        let lines: [Dict] = [row([channel]), row(age.isEmpty ? [views] : [views, age])]
        return tile(type: "TILE_CONTENT_TYPE_VIDEO", id: id,
                    header: header(thumbnail: thumb("https://i.ytimg.com/vi/\(id)/mqdefault.jpg", 320, 180), overlays: overlays),
                    metadata: metadata(title: title, lines: lines))
    }

    private static func playlist(_ id: String, title: String, owner: String, count: String, thumbId: String) -> Dict {
        let status: Dict = ["text": text(count)]
        let overlays: [Dict] = [["thumbnailOverlayTimeStatusRenderer": status]]
        return tile(type: "TILE_CONTENT_TYPE_PLAYLIST", id: id,
                    header: header(thumbnail: thumb("https://i.ytimg.com/vi/\(thumbId)/mqdefault.jpg", 320, 180), overlays: overlays),
                    metadata: metadata(title: title, lines: [row([owner])]))
    }

    private static func channel(_ id: String, name: String, handle: String, subs: String) -> Dict {
        return tile(type: "TILE_CONTENT_TYPE_CHANNEL", id: id,
                    header: header(thumbnail: thumb("", 88, 88), overlays: []),
                    metadata: metadata(title: name, lines: [row([handle]), row([subs])]))
    }

    private static func shelf(_ title: String, _ tiles: [Dict]) -> Dict {
        let lockup: Dict = ["title": text(title)]
        let avatarLockup: Dict = ["avatarLockupRenderer": lockup]
        let shelfHeader: Dict = ["avatarLockup": avatarLockup]
        let headerRenderer: Dict = ["shelfHeaderRenderer": shelfHeader]
        let list: Dict = ["items": tiles]
        let content: Dict = ["horizontalListRenderer": list]
        let inner: Dict = ["headerRenderer": headerRenderer, "content": content]
        return ["shelfRenderer": inner]
    }

    private static func sectionList(_ sections: [Dict]) -> Dict {
        let list: Dict = ["contents": sections]
        return ["sectionListRenderer": list]
    }

    private static func surface(_ content: Dict) -> JSON {
        let tv: Dict = ["content": content]
        let browse: Dict = ["tvBrowseRenderer": tv]
        return JSON(["contents": browse] as Dict)
    }

    private static func page(_ sections: [Dict]) -> JSON {
        let surfaceContent: Dict = ["content": sectionList(sections)]
        return surface(["tvSurfaceContentRenderer": surfaceContent])
    }

    /// "UC" + 22 characters, the shape of a real channel id.
    private static func demoChannelId(_ i: Int) -> String {
        return "UCDemoChannel" + String(format: "%011d", i)
    }

    private static func tabParams(_ channelId: String) -> String {
        return Data(("\u{0A}\u{18}" + channelId).utf8).base64EncodedString()
    }

    private static func videos(_ range: Range<Int>, prefix: String, percent: Bool = false) -> [Dict] {
        return range.map { i in
            video(i, title: "\(prefix) \(i + 1)", channel: "デモチャンネル \(i % 4 + 1)", views: "\(i + 2)万回視聴",
                  age: "\(i % 6 + 1) 日前", duration: "\(i % 9 + 3):\(10 + i % 40)", percent: percent ? (i * 17) % 100 : nil)
        }
    }

    // MARK: Responses

    private static func respond(_ endpoint: String, _ body: [String: Any]) -> JSON? {
        switch endpoint {
        case "browse":
            return browse(body["browseId"] as? String ?? "")
        case "account/accounts_list":
            let item: Dict = ["accountName": text("デモユーザー"), "accountPhoto": thumb("", 88, 88),
                              "isSelected": true, "channelHandle": text("@demo_user")]
            let wrapped: Dict = ["accountItem": item]
            return JSON(["contents": [wrapped]] as Dict)
        case "next":
            let like: Dict = ["likeStatus": "INDIFFERENT"]
            let subscribe: Dict = ["subscribed": false, "channelId": "UCdemo"]
            let contents: Dict = ["likeButtonRenderer": like, "subscribeButtonRenderer": subscribe]
            return JSON(["contents": contents] as Dict)
        case "like/like", "like/dislike", "like/removelike", "subscription/subscribe", "subscription/unsubscribe":
            return JSON(Dict())
        case "browse/edit_playlist":
            return JSON(["status": "STATUS_SUCCEEDED"] as Dict)
        default:
            return nil
        }
    }

    private static func subscriptionsPage() -> JSON {
        // the strip is read from the tabs (the channel id hides in their base64 params); the first tab is "All"
        var tabs: [Dict] = []
        let all: Dict = ["title": text("すべて")]
        tabs.append(["tabRenderer": all])
        for i in 1...6 {
            let endpoint: Dict = ["browseEndpoint": ["params": tabParams(demoChannelId(i))] as Dict]
            let tab: Dict = ["title": text("デモチャンネル \(i)"), "thumbnail": thumb("", 88, 88), "endpoint": endpoint]
            tabs.append(["tabRenderer": tab])
        }
        let feed: [Dict] = [
            shelf("関連が強い", videos(0..<6, prefix: "登録チャンネルの動画（デモ）")),
            shelf("", videos(6..<12, prefix: "登録チャンネルの動画（デモ）"))
        ]
        let section: Dict = ["tvSecondaryNavSectionRenderer": ["tabs": tabs] as Dict]
        let nav: Dict = ["sections": [section], "feed": sectionList(feed)]
        return surface(["tvSecondaryNavRenderer": nav])
    }

    private static func playlistPage(_ id: String) -> JSON {
        let list = videos(0..<6, prefix: "再生リストの動画（デモ）")
        let entity: Dict = ["title": text("作業用BGM（デモ）"),
                            "bylines": [row(["デモユーザー", "6 本の動画", "0 回視聴"])]]
        let right: Dict = ["contents": list, "playlistId": id]
        let columns: Dict = ["leftColumn": ["entityMetadataRenderer": entity] as Dict,
                             "rightColumn": ["playlistVideoListRenderer": right] as Dict]
        let surfaceContent: Dict = ["content": ["twoColumnRenderer": columns] as Dict]
        return surface(["tvSurfaceContentRenderer": surfaceContent])
    }

    private static func browse(_ id: String) -> JSON? {
        switch id {
        case "FEwhat_to_watch":
            return page([
                shelf("あなたへのおすすめ", videos(0..<5, prefix: "おすすめ動画（デモ）")),
                shelf("最近アップロードされた動画", videos(5..<8, prefix: "新着動画（デモ）")),
                shelf("ゲーム実況", videos(8..<12, prefix: "ゲーム実況（デモ）"))
            ])
        case "FEsubscriptions":
            return subscriptionsPage()
        case "FEhistory":
            return page([shelf("", videos(0..<8, prefix: "視聴履歴（デモ）", percent: true))])
        case "VLWL":
            return page([shelf("", videos(2..<9, prefix: "後で見る（デモ）", percent: true))])
        case "VLLL":
            return page([shelf("", videos(4..<11, prefix: "高く評価した動画（デモ）"))])
        case "FEplaylist_aggregation":
            let lists: [Dict] = [
                playlist("LL", title: "高く評価した動画", owner: "非公開", count: "42 本の動画", thumbId: ids[3]),
                playlist("WL", title: "後で見る", owner: "非公開", count: "7 本の動画", thumbId: ids[2]),
                playlist("PLdemo1", title: "作業用BGM（デモ）", owner: "デモユーザー", count: "18 本の動画", thumbId: ids[6]),
                playlist("PLdemo2", title: "あとで学ぶ（デモ）", owner: "デモユーザー", count: "5 本の動画", thumbId: ids[2])
            ]
            return page([shelf("", lists)])
        case "FEchannels":
            let channels: [Dict] = [
                channel("UCDemoChannel00000000001", name: "デモチャンネル 1", handle: "@demo_one", subs: "チャンネル登録者数 12.3万人"),
                channel("UCDemoChannel00000000002", name: "デモチャンネル 2", handle: "@demo_two", subs: "チャンネル登録者数 4560人")
            ]
            return page([shelf("", channels)])
        default:
            if id.hasPrefix("VL") { return playlistPage(String(id.dropFirst(2))) }
            return nil
        }
    }
}
