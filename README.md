# PodTube — iOS 12 / iPod touch 向け YouTube クライアント

iOS 12 の iPod touch（第6世代 / 第7世代）で動く、非公式の YouTube クライアントです。
Android 版 YouTube の UI と機能にできるだけ寄せて、UIKit だけで作っています
（SwiftUI・async/await・SF Symbols は iOS 13 以降なので使っていません）。

![PodTube の画面](docs/screens.jpg)

（GitHub Actions のシミュレータで自動撮影した画面。ホーム / 再生 / 操作パネル / コメント / ショート / マイページ）

> 非公式アプリです。YouTube / Google とは無関係です。内部 API を使うため、YouTube 側の変更で突然動かなくなることがあります。

## 主な機能

| | |
|---|---|
| ホーム | おすすめフィード、トピックのチップ（音楽 / ゲーム / ライブ …）、引っ張って更新、続きの自動読み込み |
| 検索 | 検索候補、検索履歴、動画・チャンネル・再生リスト、フィルタ（並べ替え / 期間 / 種類 / 長さ）。YouTube の URL（youtu.be、watch、shorts、playlist、チャンネル、@ハンドル）を貼り付けるとそのまま開きます。`podtube://` スキームにも対応（Safari のブックマークレットなどから） |
| 再生ページ | 画質自動切替（HLS、最大1080p）、画質上限・再生速度・字幕・チャプター・ループ・スリープタイマー、ダブルタップで ±10 秒、シークバー、全画面（横向き）、ミニプレーヤー（下スワイプ）、バックグラウンド再生、ロック画面操作、AirPlay |
| 動画情報 | 高評価数、概要（URL・ハッシュタグ・タイムスタンプがタップ可）、チャンネル行、コメント（並べ替え・続き読み込み）、関連動画、自動再生スイッチ、再生リストの連続再生 |
| ダウンロード | 動画を画質を選んで端末に保存し、オフラインで再生（バックグラウンドでも転送を継続） |
| ショート | 縦スワイプのフィード、ループ再生 |
| チャンネル | バナー、登録者数、ホーム / 動画 / 再生リスト / 概要のタブ、共有 |
| 登録チャンネル | 端末内で管理（アカウント不要）。各チャンネルの最新動画をまとめて表示。Google Takeout の CSV、NewPipe / Piped の JSON、OPML から取り込み可能 |
| マイページ | 視聴履歴（再開位置つき）、ダウンロード、再生リスト、後で見る、高く評価した動画 |
| 設定 | ダーク / ライト、アプリの言語、コンテンツの地域、最大画質、既定の再生速度、履歴の一時停止、接続診断 など |

Safari の YouTube ページから PodTube で開くには、次をブックマークの URL に登録しておきます。

```
javascript:location.href='podtube://'+encodeURIComponent(location.href)
```

できないこと:

- **ログイン（Google アカウント）**: 未対応です。登録・高評価・再生リストは端末内にだけ保存されます（視聴履歴も端末内）。ログイン用の Cookie 認証は VISIONOS クライアントが対応しておらず、ウェブ版クライアントは応答の形式が違うため、このアプリでは扱っていません。
- **コメントへの返信の表示 / コメント投稿 / ライブチャット / 低評価数の表示**: 未対応です。
- 動画の「高評価」「低評価」「登録」は YouTube には送られません。

## 動作確認の状況

作者の環境は Windows（ARM）だけで、**実機の iOS 12 端末ではまだ試せていません**。確認できているのは次の範囲です。

| 確認した | 方法 |
|---|---|
| ビルド（Xcode 16.4、iOS 12.0 ターゲット、arm64）と IPA の構造（最小 OS 12.0、iOS 13 以降専用のライブラリを使っていない） | GitHub Actions |
| 画面の表示と操作（ホーム、検索、再生、コメント、チャンネル、ショート、マイページ、設定 など約 30 画面） | GitHub Actions の iOS 18 シミュレータ。スクリーンショットは各実行の `screenshots` アーティファクト |
| YouTube API の解析（ホーム / 検索 / 関連動画 / コメント / チャンネル / 再生リスト / ショート / HLS / 字幕）と、別々の動画 14 本での再生 URL の解決 | `Tools/ptcli`（実際の YouTube に対して実行） |

| まだ確認していない | 備考 |
|---|---|
| 実機の iOS 12 での起動と再生 | 設定 → **接続診断** で、端末上で何が通るかを確認できます |
| バックグラウンドでのダウンロード / 音声再生、ロック画面の操作、AirPlay、横向き全画面の実機での挙動 | シミュレータでは確認できない部分です |

## IPA の入手とインストール

GitHub Actions が **署名なし IPA** を作ります。

- 最新ビルド: リポジトリの **Actions** タブ → 最新の実行 → Artifacts の `PodTube-ipa`
- タグ `v*` を付けると **Releases** に `PodTube-unsigned.ipa` が公開されます

署名なしなので、インストール時に自分で署名します。

- **Sideloadly / AltStore**（Apple ID で署名）: IPA をドラッグして iPod touch に入れます。無料の Apple ID だと 7 日で失効します。
- **脱獄済みの端末**（checkra1n / unc0ver など）: AppSync Unified を入れた上で、Filza や `ipainstaller` で IPA をインストールします。

対応 OS は iOS 12.0 以降です（Swift ランタイムを同梱しているので 12.0 / 12.1 でも動きます）。

## 再生の仕組み（2026 年 11 月時点）

YouTube は 2025 年以降、ほとんどのクライアントで **PO トークン** や **SABR** を要求するようになりました。
このアプリは次の方法で、PO トークンも JavaScript プレーヤーも使わずに再生しています。

1. InnerTube API を **VISIONOS クライアント**（Apple Vision Pro 用）として呼びます。ログアウト状態でもホームフィード、検索、関連動画、チャンネル、コメントが取れ、`/player` が **HLS マニフェスト**（H.264 + AAC、最大 1080p、WebVTT 字幕つき）を返します。
2. リクエストには必ず **`visitorData`** を付けます。付けないと「ログインして bot ではないことを確認してください」が返ることがあります。取得は `visitor_id` エンドポイント（約 500 バイト）で、起動後の最初のリクエスト前に行います。
3. HLS は AVPlayer がそのまま再生します（画質は `preferredMaximumResolution` で制限）。HLS が無い動画は iOS クライアントの HLS → H.264 映像 + AAC 音声を `AVMutableComposition` で結合、の順にフォールバックします。
4. 字幕は `timedtext`（json3）を取得して、自前のオーバーレイで表示します（HLS 以外の再生でも使えます）。

壊れたとき（YouTube 側の仕様変更）にまず見る場所:

1. 設定 → **接続診断** で、どの段階（訪問者 ID / ホーム / プレーヤー / HLS の解析）が失敗しているかが分かります。
2. クライアントのバージョンだけなら、アプリを作り直さずに **`config/clients.json`**（このリポジトリの main ブランチ）を書き換えるだけで直せます。アプリは起動時にこのファイルを読みます。
3. それ以外は `PodTube/Sources/Core/InnerTube.swift` の `Clients` と、`Tools/ptcli`（下記）の実行結果を見ます。

## 開発

```
project.yml                  XcodeGen の定義（.xcodeproj は CI で生成）
PodTube/Sources/Core         Foundation だけに依存する層（InnerTube クライアント、パーサー、モデル）
PodTube/Sources/App          UIKit の画面
Tools/ptcli                  Core を実機の YouTube に当てる CLI（Linux / macOS）
Tools/ci_screenshots.sh      CI のシミュレータで画面を巡回してスクリーンショットを撮る
.github/workflows/build.yml  IPA のビルド + スクリーンショット
```

- Core は Linux でもビルドできます（`Tools/linux_build.sh home` など）。API の変化を手元ですぐ確認できます。
- CI では「署名なし IPA のビルド」と「シミュレータで 20 画面ほどのスクリーンショット」を毎回実行します（`screenshots` アーティファクト）。
- アイコンは `Tools/make_icons.py`、Material アイコンの取得は `Tools/fetch_icons.py` で生成します（Material Icons は Apache License 2.0）。

## ライセンス

MIT License（`LICENSE`）。Material Icons は Apache License 2.0 です。
