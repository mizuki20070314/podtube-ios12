import Foundation

// MARK: - Feed items

struct VideoItem: Codable, Equatable {
    var id: String
    var title: String = ""
    var channelName: String = ""
    var channelId: String = ""
    var channelAvatar: String = ""
    var thumbnail: String = ""
    var duration: String = ""
    var views: String = ""
    var published: String = ""
    var isLive: Bool = false
    var isUpcoming: Bool = false
    var isShort: Bool = false

    init(id: String) { self.id = id }

    enum CodingKeys: String, CodingKey {
        case id, title, channelName, channelId, channelAvatar, thumbnail, duration, views, published
        case isLive, isUpcoming, isShort
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        channelName = try c.decodeIfPresent(String.self, forKey: .channelName) ?? ""
        channelId = try c.decodeIfPresent(String.self, forKey: .channelId) ?? ""
        channelAvatar = try c.decodeIfPresent(String.self, forKey: .channelAvatar) ?? ""
        thumbnail = try c.decodeIfPresent(String.self, forKey: .thumbnail) ?? ""
        duration = try c.decodeIfPresent(String.self, forKey: .duration) ?? ""
        views = try c.decodeIfPresent(String.self, forKey: .views) ?? ""
        published = try c.decodeIfPresent(String.self, forKey: .published) ?? ""
        isLive = try c.decodeIfPresent(Bool.self, forKey: .isLive) ?? false
        isUpcoming = try c.decodeIfPresent(Bool.self, forKey: .isUpcoming) ?? false
        isShort = try c.decodeIfPresent(Bool.self, forKey: .isShort) ?? false
    }

    /// Always usable thumbnail URL (falls back to the public i.ytimg.com pattern).
    var thumbnailURL: URL? {
        if !thumbnail.isEmpty { return URL(string: thumbnail) }
        return URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg")
    }

    var durationSeconds: Int? { return Format.parseDuration(duration) }
}

struct ChannelItem: Codable, Equatable {
    var id: String
    var name: String = ""
    var handle: String = ""
    var avatar: String = ""
    var subscribers: String = ""
    var videoCount: String = ""

    init(id: String) { self.id = id }

    enum CodingKeys: String, CodingKey { case id, name, handle, avatar, subscribers, videoCount }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        handle = try c.decodeIfPresent(String.self, forKey: .handle) ?? ""
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar) ?? ""
        subscribers = try c.decodeIfPresent(String.self, forKey: .subscribers) ?? ""
        videoCount = try c.decodeIfPresent(String.self, forKey: .videoCount) ?? ""
    }
}

struct PlaylistItem: Codable, Equatable {
    var id: String
    var title: String = ""
    var channelName: String = ""
    var thumbnail: String = ""
    var videoCount: String = ""

    init(id: String) { self.id = id }

    enum CodingKeys: String, CodingKey { case id, title, channelName, thumbnail, videoCount }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        channelName = try c.decodeIfPresent(String.self, forKey: .channelName) ?? ""
        thumbnail = try c.decodeIfPresent(String.self, forKey: .thumbnail) ?? ""
        videoCount = try c.decodeIfPresent(String.self, forKey: .videoCount) ?? ""
    }
}

enum FeedItem {
    case video(VideoItem)
    case channel(ChannelItem)
    case playlist(PlaylistItem)
    case shorts([VideoItem])
}

struct FeedSection {
    var title: String
    var items: [FeedItem]
}

struct FeedPage {
    var items: [FeedItem] = []
    var sections: [FeedSection] = []
    var continuation: String?

    var videos: [VideoItem] {
        var out: [VideoItem] = []
        for it in items {
            switch it {
            case .video(let v): out.append(v)
            case .shorts(let list): out.append(contentsOf: list)
            default: break
            }
        }
        return out
    }
}

// MARK: - Pages

struct ChannelTab {
    var title: String
    var params: String
    var selected: Bool
}

struct ChannelInfo {
    var id: String
    var name: String = ""
    var handle: String = ""
    var avatar: String = ""
    var banner: String = ""
    var subscribers: String = ""
    var videoCount: String = ""
    var verified: Bool = false
    var tabs: [ChannelTab] = []
    var firstPage: FeedPage = FeedPage()

    init(id: String) { self.id = id }

    var asItem: ChannelItem {
        var c = ChannelItem(id: id)
        c.name = name
        c.handle = handle
        c.avatar = avatar
        c.subscribers = subscribers
        c.videoCount = videoCount
        return c
    }
}

struct PlaylistInfo {
    var id: String
    var title: String = ""
    var owner: String = ""
    var ownerId: String = ""
    var stats: [String] = []
    var thumbnail: String = ""
    var firstPage: FeedPage = FeedPage()

    init(id: String) { self.id = id }
}

struct Comment {
    var id: String
    var author: String = ""
    var authorId: String = ""
    var avatar: String = ""
    var text: String = ""
    var likes: String = ""
    var published: String = ""
    var replyCount: Int = 0
    var repliesToken: String?
    var isOwner: Bool = false
    var isPinned: Bool = false
    var isReply: Bool = false

    init(id: String) { self.id = id }
}

struct CommentPage {
    var comments: [Comment] = []
    var continuation: String?
    var totalText: String = ""
    var sortTokens: [(title: String, token: String)] = []
}

struct WatchInfo {
    var videoId: String
    var title: String = ""
    var views: String = ""
    var viewsShort: String = ""
    var date: String = ""
    var description: String = ""
    var likeText: String = ""
    var likeCount: Int?
    var channel: ChannelItem?
    var related: FeedPage = FeedPage()
    var commentsToken: String?
    var commentCount: String = ""
    var commentSortTokens: [(title: String, token: String)] = []
    var autoplay: VideoItem?
    var queue: [VideoItem] = []
    var queueTitle: String = ""
    var queueIndex: Int = 0

    init(videoId: String) { self.videoId = videoId }
}

// MARK: - Playback

struct CaptionTrack {
    var languageCode: String
    var name: String
    var url: String
    var isAuto: Bool
}

struct AdaptiveFormat {
    var height: Int
    var url: URL
    var bitrate: Int
    var contentLength: Int64
}

struct PlaybackInfo {
    var videoId: String
    var title: String = ""
    var author: String = ""
    var channelId: String = ""
    var thumbnail: String = ""
    var duration: Double = 0
    var isLive: Bool = false
    var hlsURL: URL?
    var videoURL: URL?
    var audioURL: URL?
    var progressiveURL: URL?
    var captions: [CaptionTrack] = []
    var videoFormats: [AdaptiveFormat] = []
    var audioFormats: [AdaptiveFormat] = []
    var maxHeight: Int = 0
    var fetchedAt: Date = Date()

    init(videoId: String) { self.videoId = videoId }

    var isPlayable: Bool { return hlsURL != nil || progressiveURL != nil || (videoURL != nil && audioURL != nil) }
}

struct ShortEntry {
    var video: VideoItem
    var likes: String = ""
    var comments: String = ""
}

enum InnerTubeError: Error {
    case parse(String)
    case unplayable(String)
    /// "Sign in to confirm you're not a bot" – retried with a fresh visitor id.
    case botCheck(String)
    case http(Int)
    case empty
}

extension InnerTubeError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .parse(let s): return s
        case .unplayable(let s): return s
        case .botCheck(let s): return s
        case .http(let c): return "HTTP \(c)"
        case .empty: return "No results"
        }
    }
}
