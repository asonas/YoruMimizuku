# YoruMimizuku タイムライン UX 強化 設計書

- 日付: 2026-06-08
- ステータス: 設計合意済み（実装計画はこの後 `writing-plans` で作成）
- 作業ブランチ: `feature/timeline-ux-enhancements`
- 関連: `docs/superpowers/specs/2026-06-05-yorumimizuku-filter-tabs-design.md`（フィルタータブ）、`2026-06-05-yorumimizuku-structured-filters-design.md`（構造化フィルター）

## 1. 概要

縦タブ（home / notifications / filter / conversation）で動く既存の macOS クライアントに、日常運用で効く 6 つの UX 機能を追加する。

1. **新着バッジ（通知）** — 通知タブに未読件数をバッジ表示。
2. **新着バッジ（フィルター）** — フィルタータブにも新着投稿件数をバッジ表示。
3. **`f` でいいね** — focused post をキー一発でいいね（既存のいいね機構を流用）。
4. **permalink コピー + `o` でブラウザ** — アクション行のコピーアイコンで permalink をクリップボードへ、`o` キーでブラウザ起動。
5. **ユーザー専用タブ** — アバタークリックでそのユーザーの投稿を眺める新種別タブ（会話タブとは別区切り）。
6. **会話ビューの子返信ツリー** — 親チェーンに加え、アンカー投稿への返信（B→C,D…）も会話ビュー内に再帰表示。

機能 1・2 を成立させる前提として、**ポーリングのライフサイクルを View 駆動から ViewModel / WorkspaceModel 駆動へ移す**（後述のアーキテクチャ変更 A）。これが本設計の土台となる。

## 2. ゴール / 非ゴール

### ゴール
- 通知・フィルター（および home）タブが、非アクティブでもバックグラウンドでポーリングを継続し、新着件数を `unreadCount` として公開する。
- バッジは「前回そのタブをアクティブにした時点で既知だった最新アイテム以降の新着件数」。タブをアクティブにした瞬間に 0 リセット。上限表示は `99+`。
- `f` キーで focused post のいいねをトグル（フィード・会話・ユーザータブ共通）。
- 投稿の permalink（`https://bsky.app/profile/{handle}/post/{rkey}`）を組み立て、アクション行のコピーアイコンでクリップボードへコピー。`o` キーで focused post をブラウザ起動。
- アバタークリックでユーザー専用タブ（新種別 `.author`）を開く。`getAuthorFeed` filter=`posts_and_author_threads`。タイムライン・通知・会話の全アバターが対象。
- 会話ビューを `getPostThread` ベースに切り替え、親チェーン＋子返信ツリーを浅いインデント＋接続線で表示。

### 非ゴール（将来 / 対象外）
- サーバー側の既読同期（`updateSeen` / `getUnreadCount`）。バッジは完全にローカル基準で算出する。
- macOS の Dock アイコンバッジ・OS 通知（NSUserNotification）への反映。今回はアプリ内サイドバーのバッジのみ。
- プロフィールの編集・フォロー/アンフォロー操作。ユーザータブは閲覧専用。
- 会話ビューのネスト深さを無制限にすること（深さ上限を設け、超過分は再アンカーで辿る）。
- conversation / author タブへのバッジ表示（明示的に開く一時タブのため新着概念を持たせない）。

## 3. 意思決定ログ

| 項目 | 決定 |
|---|---|
| ポーリング駆動 | View 駆動 → ViewModel / WorkspaceModel 駆動へ移行（アプローチ A）。home/notifications/filter は裏でも継続、conversation/author はアクティブ時のみ |
| バッジ基準 | サーバー `isRead` ではなくローカル基準で統一。「タブをアクティブにしたらリセット」 |
| バッジ算出 | 「前回アクティブ時に既知だった最新アイテム」を境界に、それより新しいアイテム数をカウント |
| `f` の適用範囲 | フィード・会話・ユーザータブの focused post すべてで有効 |
| permalink handle | `authorHandle` を使用。`handle.invalid` 等で無効な場合は `did` でフォールバック |
| コピー UI | いいね・リポストのアクション行にコピーアイコンを追加。クリックで `NSPasteboard` |
| `o` キー | focused post の permalink を `NSWorkspace.open` でブラウザ起動 |
| ユーザータブ種別 | 新 `WorkspaceTab.author(UUID)`。`.conversation` とは独立した区切り |
| ユーザータブ feed | `getAuthorFeed` filter=`posts_and_author_threads`（公式 Posts タブ相当） |
| ユーザータブ重複 | 同じ did のタブが既にあれば既存にフォーカス（重複生成しない） |
| プロフィールヘッダ | あり（アバター / 表示名 / handle / bio）。ユーザータブ上部に表示 |
| 会話取得 API | `replyParent` 手動辿り → `app.bsky.feed.getPostThread` に切替 |
| 子ツリー表示 | 浅いインデント（1 段）＋左の接続線。深さ上限超過は「さらに表示」で再アンカー |

## 4. アーキテクチャ変更 A: ポーリングの ViewModel / WorkspaceModel 駆動化

### 現状の問題
通知（`NotificationsView.runNotifications()` の 30 秒ループ）もフィルター（`FeedView.runFeed()` の 30 秒ループ）も、ポーリングは **View の `.task` 駆動**。縦タブでは非アクティブタブの View が破棄されるため、裏に回るとポーリングが止まり新着を検知できない。バッジ表示には非アクティブタブの取得継続が必須。

### 方針
ポーリングループの所有権を View から ViewModel へ移す。

- 各 ViewModel（`TimelineViewModel` / `NotificationsViewModel`）が `startPolling(interval:)` / `stopPolling()` を持ち、内部に保持した `Task` で `refresh()` を回す。`refresh()`・`load()` のロジックは現状を流用。
- `WorkspaceModel` が「常駐ポーリング対象」（home / notifications / filter タブの ViewModel）に対してアプリ起動中ポーリングを開始する。タブ追加時に開始、削除時に停止。
- `conversation` / `author` タブの ViewModel は、そのタブが **アクティブな間だけ** ポーリングする（リソース節約・バッジ不要）。`WorkspaceModel` の選択タブ変更で start/stop を切り替える。
- View は ViewModel を `@ObservedObject` として購読し描画するだけ。`.task` での起動責務を持たない。

### 新着件数（unreadCount）の算出
ViewModel に新着境界を持たせる。

- `lastSeenMarker`: 前回そのタブをアクティブにした時点での最新アイテム識別子（通知は最新 `indexedAt`、タイムラインは最新投稿の `indexedAt` または URI）。
- `unreadCount`: 現在保持しているアイテムのうち `lastSeenMarker` より新しいものの件数（純粋な計算。テスト容易）。
- `markSeen()`: `lastSeenMarker` を現在の最新へ更新し `unreadCount` を 0 にする。`WorkspaceModel` がタブをアクティブにしたとき呼ぶ。

`unreadCount` の算出は ViewModel から切り出した純関数（例: `UnreadCounter.count(items:after:)`）として実装し、ユニットテストする。

## 5. 機能別設計

### 5.1 / 5.2 新着バッジ（通知・フィルター・home）
- サイドバーのタブ行（`WorkspaceTab` を描画している箇所）に、対応 ViewModel の `unreadCount` をバッジ表示。`0` のときは非表示、`>99` は `99+`。
- バッジ対象は常駐ポーリングタブ（home / notifications / filter）。通知の集約（likes/reposts のグループ化）はバッジ件数では考慮せず、**生の新着通知件数**でカウント（グループ表示は UI 内のまま）。
- アクティブタブの `unreadCount` は常に 0（`markSeen()` 済みのため）。

### 5.3 `f` でいいね
- `FeedView` の `postNavShortcuts`（`j`/`k`/`n` がある箇所）に `.keyboardShortcut("f", modifiers: [])` を追加。
- focused post に対し既存の `TimelineViewModel.toggleLike()` / `ThreadViewModel.toggleLike()` を呼ぶ（楽観的更新は `PostInteractionController` 済み）。
- 会話ビュー・ユーザータブのフィードでも同じショートカットを有効化（focused post 機構を共有）。focused post が無いときは no-op。

### 5.4 permalink コピー + `o`
- **permalink 組立**（`YoruMimizukuKit` の純関数 / テスト対象）:
  - 入力: `PostDisplay`（`id` = AT-URI、`authorHandle`、`authorDID`）。
  - `rkey = ATURI.rkey(post.id)`、`handle` が有効なら handle、無効/欠落なら `did`。
  - 出力: `https://bsky.app/profile/{handle-or-did}/post/{rkey}`。
- **コピー UI**: いいね・リポストのアクション行にコピーアイコンを追加。タップで `NSPasteboard.general` にクリア後セット。視覚フィードバック（一時的なチェック表示など）は実装計画で詳細化。
- **`o` キー**: `postNavShortcuts` に `o` を追加。focused post の permalink を `NSWorkspace.shared.open(url)` でブラウザ起動。
- クリップボード・ブラウザ起動は macOS View 層の薄いアクションとして実装（permalink 組立だけが純ロジックでテスト対象）。

### 5.5 ユーザー専用タブ
- **タブ種別**: `WorkspaceTab` に `.author(UUID)` を追加。保持クラス `AuthorTab`（`id` / `did` / `handle` / `displayName` / `AuthorFeedViewModel`）。
- **ViewModel**: `AuthorFeedViewModel`（`TimelineViewModel` と同じ load/loadMore/refresh/cursor の枠組みを踏襲）。ローダーは `getAuthorFeed`（filter=`posts_and_author_threads`）を呼ぶ `LiveAuthorFeedLoader`。
- **プロフィールヘッダ**: `getProfile`（既存 `ProfileService.getProfile`）でアバター / 表示名 / handle / bio を取得し、フィード上部に表示。
- **開く操作**: `WorkspaceModel.openAuthor(did:handle:displayName:)`。同じ did の `.author` タブがあれば選択、無ければ追加。
- **アバタークリック**: `PostRowView` / `NotificationRowView` / `ConversationView` のアバターに tap ハンドラ（クロージャ注入）を追加し `openAuthor` を呼ぶ。
- ユーザータブはアクティブ時のみポーリング。

### 5.6 会話ビューの子返信ツリー
- **取得**: `ThreadViewModel` を `app.bsky.feed.getPostThread`（新 `ThreadService`）ベースに変更。`uri`（アンカー）、`depth`（子の深さ）、`parentHeight`（親の高さ）を指定。
- **モデル**: スレッドノード木 `ThreadNode { post: PostDisplay, replies: [ThreadNode], depth: Int }`。`getPostThread` の `ThreadViewPost` 再帰構造をデコードして組み立てる（純ロジック・テスト対象）。`notFound` / `blocked` ノードは欠損として無視。
- **表示**: アンカー投稿を基準に、上に親チェーン（従来どおり）、下に子返信ツリー。子は浅いインデント（1 段）＋左の接続線で関係を示す。深さ上限（既定 `getPostThread` の範囲。例: 表示は 3 階層まで）を超える枝は「さらに表示」で当該投稿を新アンカーとして開き直す（既存の再アンカー挙動を踏襲）。
- アバタークリックは 5.5 の `openAuthor` へ。

## 6. データモデル / API 変更

| 種別 | 変更 |
|---|---|
| 新 XRPC | `ThreadService.getPostThread(uri, depth, parentHeight, ...)`（401 refresh-retry は既存サービスに倣う） |
| 新 XRPC | `AuthorFeedService.getAuthorFeed(actor, filter, cursor, ...)` |
| 既存 XRPC | `ProfileService.getProfile`（ヘッダで利用、変更なし想定） |
| モデル | `ThreadNode`（スレッド木）、permalink 組立関数、`UnreadCounter`（純関数） |
| WorkspaceTab | `.author(UUID)` 追加、`AuthorTab` 追加 |
| ViewModel | `TimelineViewModel` / `NotificationsViewModel` にポーリング所有 + `unreadCount` / `markSeen()` / `lastSeenMarker`、`AuthorFeedViewModel` 新規、`ThreadViewModel` を getPostThread 化 |
| ローダー | `LiveAuthorFeedLoader` 新規、会話は getPostThread ローダーへ |

## 7. テスト方針（TDD）
純ロジックを優先的にユニットテスト（Red→Green→Refactor を 1 ステップずつ）。

- `UnreadCounter`: 境界マーカー前後の件数算出、境界一致、空配列、全件新着。
- permalink 組立: handle 正常 / 無効 → did フォールバック / rkey 抽出。
- `ThreadNode` 組み立て: 親チェーン、複数子、欠損ノード（notFound/blocked）スキップ、深さ。
- `AuthorFeedViewModel`: load / refresh のマージ・重複排除（既存 TimelineViewModel テストに倣う）。
- ポーリング start/stop のライフサイクル（fake クロック / fake ローダーで）。
- 副作用（NSPasteboard / NSWorkspace / Keychain / ネットワーク）は protocol 注入で fake 化し、View 層の実物呼び出しはテスト対象外。

## 8. 影響が見込まれる主なファイル

- `core/Sources/YoruMimizukuKit/WorkspaceModel.swift`（タブ種別・openAuthor・ポーリング統括・markSeen）
- `core/Sources/YoruMimizukuKit/TimelineViewModel.swift` / `NotificationsViewModel.swift`（ポーリング所有・unreadCount）
- `core/Sources/YoruMimizukuKit/ThreadViewModel.swift`（getPostThread 化・ThreadNode）
- `core/Sources/YoruMimizukuKit/PostDisplay.swift`（permalink 用フィールド確認）
- `core/Sources/BlueskyCore/XRPC/`（`ThreadService` / `AuthorFeedService` 新規、`ATURI` 流用）
- `apps/macos/Views/MainWindowView.swift`（サイドバーのバッジ描画・ショートカット集約）
- `apps/macos/Views/FeedView.swift`（`f` / `o` ショートカット）
- `apps/macos/Views/PostRowView.swift` / `NotificationsView.swift` / `ConversationView.swift`（アバタータップ・コピーアイコン・子ツリー描画）
- `apps/macos/Timeline/`（`LiveAuthorFeedLoader` 新規、会話ローダー差し替え）

## 9. 段階実装の順序（想定）
1. アーキテクチャ A（ポーリングの ViewModel 化 + unreadCount 基盤）→ 通知・フィルターのバッジ。
2. `f` いいね、permalink コピー + `o`（既存機構の小拡張で独立性が高い）。
3. ユーザータブ（`.author` 種別 + AuthorFeedViewModel + アバタータップ）。
4. 会話ビューの getPostThread 化 + 子ツリー表示。

各段は独立して動作確認できる粒度。詳細な手順は `writing-plans` で別途。
