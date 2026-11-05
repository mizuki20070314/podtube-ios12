import Foundation

/// Minimal localisation: every key has a Japanese and an English string. Unknown keys fall back to the key.
enum L10n {
    static var isJapanese: Bool {
        switch Settings.uiLanguage {
        case "ja": return true
        case "en": return false
        default: return Format.isJapanese()
        }
    }

    static func t(_ key: String) -> String {
        guard let pair = table[key] else { return key }
        return isJapanese ? pair.0 : pair.1
    }

    static func t(_ key: String, _ arg: String) -> String {
        return t(key).replacingOccurrences(of: "%@", with: arg)
    }

    private static let table: [String: (String, String)] = [
        // tabs
        "tab.home": ("ホーム", "Home"),
        "tab.shorts": ("ショート", "Shorts"),
        "tab.subs": ("登録チャンネル", "Subscriptions"),
        "tab.you": ("マイページ", "You"),

        // common
        "common.cancel": ("キャンセル", "Cancel"),
        "common.ok": ("OK", "OK"),
        "common.close": ("閉じる", "Close"),
        "common.done": ("完了", "Done"),
        "common.delete": ("削除", "Delete"),
        "common.retry": ("再試行", "Retry"),
        "common.loading": ("読み込み中…", "Loading…"),
        "common.error": ("読み込めませんでした", "Couldn't load"),
        "common.empty": ("何も見つかりませんでした", "Nothing here yet"),
        "common.more": ("もっと見る", "Show more"),
        "common.less": ("一部を表示", "Show less"),
        "common.all": ("すべて", "All"),
        "common.create": ("作成", "Create"),
        "common.name": ("名前", "Name"),

        // home chips
        "chip.all": ("すべて", "All"),
        "chip.music": ("音楽", "Music"),
        "chip.gaming": ("ゲーム", "Gaming"),
        "chip.live": ("ライブ", "Live"),
        "chip.news": ("ニュース", "News"),
        "chip.anime": ("アニメ", "Anime"),
        "chip.sports": ("スポーツ", "Sports"),
        "chip.cooking": ("料理", "Cooking"),
        "chip.comedy": ("お笑い", "Comedy"),
        "chip.tech": ("テクノロジー", "Technology"),
        "chip.travel": ("旅行", "Travel"),
        "chip.pets": ("ペット", "Pets"),
        "chip.recent": ("最近アップロードされた動画", "Recently uploaded"),

        // video actions
        "video.watchLater": ("後で見る", "Watch later"),
        "video.removeWatchLater": ("「後で見る」から削除", "Remove from Watch later"),
        "video.saved": ("「後で見る」に保存しました", "Saved to Watch later"),
        "video.removed": ("「後で見る」から削除しました", "Removed from Watch later"),
        "video.addToPlaylist": ("再生リストに追加", "Save to playlist"),
        "video.share": ("共有", "Share"),
        "video.channel": ("チャンネルを表示", "Go to channel"),
        "video.notInterested": ("この履歴を削除", "Remove from history"),
        "video.like": ("高評価", "Like"),
        "video.dislike": ("低評価", "Dislike"),
        "video.save": ("保存", "Save"),
        "video.download": ("ダウンロード", "Download"),
        "video.subscribe": ("チャンネル登録", "Subscribe"),
        "video.subscribed": ("登録済み", "Subscribed"),
        "video.subscribeShort": ("登録", "Subscribe"),
        "video.comments": ("コメント", "Comments"),
        "video.related": ("関連動画", "Related videos"),
        "video.description": ("概要", "Description"),
        "video.live": ("ライブ", "LIVE"),
        "video.upcoming": ("公開予定", "Upcoming"),
        "video.unavailable": ("この動画は再生できません", "This video can't be played"),
        "video.nextUp": ("次の動画", "Up next"),
        "video.autoplay": ("自動再生", "Autoplay"),
        "video.playlists": ("再生リスト", "Playlists"),
        "video.newPlaylist": ("新しい再生リスト", "New playlist"),
        "video.playlistName": ("再生リスト名", "Playlist name"),
        "video.addedTo": ("「%@」に追加しました", "Added to \"%@\""),
        "video.removedFrom": ("「%@」から削除しました", "Removed from \"%@\""),

        // player
        "player.chapters": ("チャプター", "Chapters"),
        "player.quality": ("画質", "Quality"),
        "player.speed": ("再生速度", "Playback speed"),
        "player.captions": ("字幕", "Captions"),
        "player.captionsOff": ("オフ", "Off"),
        "player.auto": ("自動", "Auto"),
        "player.normal": ("標準", "Normal"),
        "player.loop": ("ループ再生", "Loop"),
        "player.sleep": ("スリープタイマー", "Sleep timer"),
        "player.sleepOff": ("オフ", "Off"),
        "player.sleepMinutes": ("%@ 分", "%@ min"),
        "player.sleepEnd": ("動画の終了時", "End of video"),
        "player.settings": ("設定", "Settings"),
        "player.autoTranslate": ("自動翻訳", "Auto-translate"),

        // search
        "search.placeholder": ("YouTube を検索", "Search YouTube"),
        "search.history": ("検索履歴", "Search history"),
        "search.clearHistory": ("検索履歴を消去", "Clear search history"),
        "search.filters": ("検索フィルタ", "Search filters"),
        "search.sort": ("並べ替え", "Sort by"),
        "search.uploadDate": ("アップロード日", "Upload date"),
        "search.type": ("タイプ", "Type"),
        "search.duration": ("長さ", "Duration"),
        "search.relevance": ("関連度順", "Relevance"),
        "search.dateSort": ("アップロード日順", "Upload date"),
        "search.viewSort": ("視聴回数順", "View count"),
        "search.ratingSort": ("評価順", "Rating"),
        "search.any": ("指定なし", "Any"),
        "search.hour": ("1 時間以内", "Last hour"),
        "search.today": ("今日", "Today"),
        "search.week": ("今週", "This week"),
        "search.month": ("今月", "This month"),
        "search.year": ("今年", "This year"),
        "search.video": ("動画", "Video"),
        "search.channel": ("チャンネル", "Channel"),
        "search.playlist": ("再生リスト", "Playlist"),
        "search.movie": ("映画", "Movie"),
        "search.short": ("4 分未満", "Under 4 minutes"),
        "search.medium": ("4～20 分", "4-20 minutes"),
        "search.long": ("20 分以上", "Over 20 minutes"),
        "search.apply": ("適用", "Apply"),
        "search.reset": ("リセット", "Reset"),

        // channel
        "channel.videos": ("動画", "Videos"),
        "channel.home": ("ホーム", "Home"),
        "channel.playlists": ("再生リスト", "Playlists"),
        "channel.about": ("概要", "About"),
        "channel.shorts": ("ショート", "Shorts"),
        "channel.live": ("ライブ", "Live"),
        "channel.subscribers": ("チャンネル登録者数", "subscribers"),

        // library
        "library.history": ("履歴", "History"),
        "library.playlists": ("再生リスト", "Playlists"),
        "library.watchLater": ("後で見る", "Watch later"),
        "library.liked": ("高く評価した動画", "Liked videos"),
        "library.downloads": ("ダウンロード", "Downloads"),
        "library.settings": ("設定", "Settings"),
        "library.viewAll": ("すべて表示", "View all"),
        "library.emptyHistory": ("視聴履歴はまだありません", "No watch history yet"),
        "library.emptyPlaylists": ("再生リストはまだありません", "No playlists yet"),
        "library.clearHistory": ("視聴履歴を消去", "Clear watch history"),
        "library.confirmClear": ("視聴履歴をすべて消去しますか？", "Clear all watch history?"),

        // subscriptions
        "subs.empty": ("登録チャンネルがありません", "No subscriptions yet"),
        "subs.emptyHint": ("チャンネルを登録すると、新着動画がここに表示されます", "Subscribe to channels to see their latest videos here"),
        "subs.manage": ("チャンネルを管理", "Manage channels"),
        "subs.import": ("インポート", "Import"),
        "subs.imported": ("%@ 件のチャンネルを追加しました", "Added %@ channels"),
        "subs.importFailed": ("ファイルからチャンネルを読み取れませんでした", "No channels found in that file"),
        "subs.all": ("すべて", "All"),

        "downloads.started": ("ダウンロードを開始しました", "Download started"),
        "downloads.done": ("ダウンロードが完了しました", "Download finished"),
        "downloads.failed": ("ダウンロードに失敗しました", "Download failed"),
        "downloads.empty": ("ダウンロードした動画はありません", "No downloaded videos"),
        "downloads.already": ("ダウンロード済み、またはダウンロード中です", "Already downloaded or downloading"),
        "downloads.unavailable": ("この動画はダウンロードできません", "This video can't be downloaded"),
        "downloads.saved": ("ダウンロード済み", "Downloaded"),

        "playlist.playAll": ("すべて再生", "Play all"),
        "playlist.shuffle": ("シャッフル", "Shuffle"),

        // shorts
        "shorts.title": ("ショート", "Shorts"),

        // comments
        "comments.title": ("コメント", "Comments"),
        "comments.top": ("人気順", "Top comments"),
        "comments.newest": ("新しい順", "Newest first"),
        "comments.empty": ("コメントはありません", "No comments"),
        "comments.replies": ("%@ 件の返信", "%@ replies"),

        // settings
        "settings.title": ("設定", "Settings"),
        "settings.general": ("全般", "General"),
        "settings.appearance": ("テーマ", "Appearance"),
        "settings.dark": ("ダーク", "Dark"),
        "settings.light": ("ライト", "Light"),
        "settings.language": ("アプリの言語", "App language"),
        "settings.languageAuto": ("端末の設定に従う", "Use device language"),
        "settings.region": ("コンテンツの地域", "Content region"),
        "settings.playback": ("再生", "Playback"),
        "settings.autoplay": ("次の動画を自動再生", "Autoplay next video"),
        "settings.backgroundPlay": ("バックグラウンド再生", "Background playback"),
        "settings.defaultQuality": ("最大画質", "Maximum quality"),
        "settings.defaultSpeed": ("既定の再生速度", "Default playback speed"),
        "settings.captionsAlways": ("常に字幕を表示", "Always show captions"),
        "settings.privacy": ("履歴とプライバシー", "History & privacy"),
        "settings.pauseHistory": ("履歴を保存しない", "Pause history"),
        "settings.clearHistory": ("視聴履歴を消去", "Clear watch history"),
        "settings.clearSearch": ("検索履歴を消去", "Clear search history"),
        "settings.clearCache": ("画像キャッシュを消去", "Clear image cache"),
        "settings.about": ("このアプリについて", "About"),
        "settings.version": ("バージョン", "Version"),
        "settings.disclaimer": ("非公式の YouTube クライアントです。YouTube / Google とは無関係です。", "An unofficial YouTube client. Not affiliated with YouTube or Google."),
        "settings.source": ("ソースコード", "Source code"),
        "settings.done": ("完了", "Done")
    ]
}
