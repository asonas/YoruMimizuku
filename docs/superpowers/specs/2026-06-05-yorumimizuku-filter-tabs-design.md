# YoruMimizuku フィルタータブ設計書

- 日付: 2026-06-05
- ステータス: 設計合意済み（実装計画はこの後 `writing-plans` で作成）
- 作業ブランチ: `feature/filter-tabs`
- 関連: `docs/superpowers/specs/2026-06-04-yorumimizuku-design.md`（全体設計、7情報源の1つ「検索（searchPosts）」に対応）

## 1. 概要

macOS 版に「フィルタータブ」を追加する。ユーザーが保存した検索条件（ハッシュタグやユーザー名を含む生クエリ）をサイドバーのタブとして購読し、ホームタイムラインと同様に定期更新で読み続けられるようにする。データ源は AT Protocol の `app.bsky.feed.searchPosts` を新規実装する。フィルターはローカルに永続化し、将来 iCloud 経由で同一アカウント間共有できる設計とする。

「フィルター」は実質的に**保存された検索（saved search）の購読**であり、フォロー外の投稿も含めて条件にマッチする投稿を一覧する。

## 2. ゴール / 非ゴール

### v1 のゴール
- `searchPosts`（`app.bsky.feed.searchPosts`）を `BlueskyCore` に実装（401→refresh→1回リトライの既存パターン踏襲）。
- サイドバーに「フィルター」セクションを追加（ホーム/通知の下、会話の上）。見出しに `+` 追加ボタン。
- フィルターの完全 CRUD: 作成・編集・削除（v1 で全対応）。
- 各フィルタータブは保存クエリで `searchPosts` を取得し、ホーム同様に **30 秒ポーリング + 上マージ + 無限スクロール**で更新。
- フィルターのローカル永続化（アカウント DID ごと）。次回起動時にサイドバーへ復元。
- 永続化を**ポート（プロトコル）化**し、将来 iCloud 同期実装を差し替え可能にする。

### 非ゴール（後続 / 将来）
- iCloud 同期の実装そのもの（v1 はポートを用意するのみ。ローカル Codable ファイル実装で動かす）。
- 構造化フィルターフォーム（キーワード/タグ/ユーザーを個別入力）。v1 は生クエリ1本。
- 検索のソート種別切替（top/latest）やファセット絞り込み UI。
- ホームタイムラインのクライアント側フィルタリング（別方式。本 spec では扱わない）。
- Jetstream によるフィルターのリアルタイム更新（ポーリングで割り切る）。

## 3. 意思決定ログ

| 項目 | 決定 |
|---|---|
| データ源 | `searchPosts`（サーバ検索）。フォロー外も対象。クライアント側フィルタは不採用 |
| クエリ指定 | 生クエリ1本（例: `#swift from:asonas.bsky.social`）。構造化フォームは将来 |
| 永続化 | ローカル Codable ファイル（アカウント DID ごと）。将来 iCloud 共有を視野にポート化 |
| 更新方式 | ホーム同様の 30 秒ポーリング + 上マージ + 無限スクロール |
| ViewModel | 既存 `TimelineViewModel` を再利用（クエリを捕捉した `TimelineLoading` 実装を注入） |
| サイドバー配置 | ホーム/通知の下、会話の上に「フィルター」セクション。見出しに `+` |
| CRUD 範囲 | 作成・編集・削除すべて v1 対応。タブの × は削除 |

### `TimelineViewModel` を再利用する根拠
`TimelineLoading` は `loadPage(cursor:) async throws -> TimelinePage` だけの薄い境界であり、ポーリング・上マージ・無限スクロール・状態機械（idle/loading/loaded/failed）はすべて `TimelineViewModel` に実装済み。`searchPosts` は `posts: [PostView]` を返し、既存の `PostDisplay(postView:)` でそのまま UI 化できる。よってクエリをクロージャ／構造体に閉じ込めた `SearchTimelineLoader` を `TimelineLoading` に準拠させれば、`TimelineViewModel` を一切変更せず再利用できる。専用 `FilterViewModel` を新設すると状態機械を二重実装することになり、v1 のスコープでは過剰。

## 4. アーキテクチャ

### 4.1 BlueskyCore（UI 非依存コア）

**新規 `Models/Search.swift`**
```swift
public struct SearchResponse: Decodable, Equatable, Sendable {
    public let posts: [PostView]   // 既存 PostView を再利用
    public let cursor: String?
    public let hitsTotal: Int?
}
```
- `app.bsky.feed.searchPosts` のレスポンスは `posts: [postView]` / `cursor?` / `hitsTotal?`。未知キーは `Decodable` が無視。

**新規 `XRPC/SearchService.swift`** — `TimelineService` と同型の構造体。
```swift
public func searchPosts(
    pds: URL, issuer: URL,
    accessToken: String, refreshToken: String?,
    query: String, limit: Int = 25, cursor: String? = nil
) async throws -> (response: SearchResponse, refreshed: TokenResponse?)
```
- URL: `xrpc/app.bsky.feed.searchPosts?q=<query>&limit=<n>[&cursor=<c>]`。`q` は `URLQueryItem` で適切にパーセントエンコード。
- `401` かつ nonce チャレンジでない場合、`refresh_token` で更新して1回リトライ（`TimelineService` と同一フロー）。
- 200 以外は `XRPCError.requestFailed`、デコード失敗は `XRPCError.decodingFailed`。

### 4.2 YoruMimizukuKit（表示ロジック）

**新規 `SavedFilter.swift`**
```swift
public struct SavedFilter: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var query: String
    public let createdAt: Date
}
```
- iCloud 同期を見据え純粋な値型。`name` は表示名、`query` は `searchPosts` の生クエリ。

**新規 `SavedFilterStoring`（永続化ポート）**
```swift
public protocol SavedFilterStoring: Sendable {
    func load() throws -> [SavedFilter]
    func save(_ filters: [SavedFilter]) throws
}
```
- アプリ側で「アカウント DID ごとの Codable JSON ファイル」実装を注入。将来 iCloud 実装に差し替え可能。

**新規 `SavedFilterStore`（`@MainActor ObservableObject`）**
- `@Published private(set) var filters: [SavedFilter]` を保持。
- CRUD: `add(name:query:) -> SavedFilter` / `update(_:)` / `remove(id:)` / `move(...)`。
- 各変更後にポートの `save` を呼ぶ。`load` 失敗時は空配列で開始（フィルターはユーザー設定であり致命的でない）。
- バリデーション: `query` 空白のみは保存不可。

`TimelineViewModel` は**変更なし**で再利用する。

### 4.3 apps/macos（SwiftUI 配線）

- **`Timeline/LiveSearchLoader.swift`** — `LiveTimelineLoader` と同型。`query: String` を捕捉して `TimelineLoading` に準拠。`LiveServiceContext` で `SearchService` を配線し、`PostDisplay(postView:)` で `[PostDisplay]` にマップ。`result.refreshed` を `context.persist`。
- **`Workspace/WorkspaceModel.swift`**:
  - `WorkspaceTab` に `case filter(UUID)` を追加。
  - 新型 `FilterTab`（`Identifiable`）: `SavedFilter` の `id`/表示用 `title`(=name)/`query` を持ち、`TimelineViewModel`（loader=`LiveSearchLoader(query:)`）を所有。
  - `@Published private(set) var filters: [FilterTab]` を保持。
  - `SavedFilterStore` と同期: 起動時に復元、CRUD 操作を委譲（追加→`FilterTab` 生成・選択、削除→タブ除去とフォールバック選択、編集→name/query 反映、query 変更時は `TimelineViewModel` を作り直して再読込）。
  - `orderedTabs` に filter を挿入（home, notifications, filters..., conversations...）。タブ巡回ショートカットに反映。
  - `makeThreadModel` と同様に `makeSearchModel: @MainActor (String) -> TimelineViewModel` を注入（テスト時はスタブ loader を渡せる）。
- **`Persistence/FilterFileStore.swift`** — `SavedFilterStoring` の Apple 実装。`~/Library/Application Support/<bundle>/filters-<DID>.json` を Codable で読み書き。ディレクトリ生成、原子的書き込み。
- **`Views/SidebarView.swift`** — 通知の下に「フィルター」セクション。`sectionLabel("フィルター")` の右に `+` ボタン（`ChromeIconButton`）。各行は `SidebarRow`（title=name、meta=query を monospaced）。hover で編集（鉛筆）と削除（×）。
- **`Views/FilterEditorView.swift`** — 名前 + クエリの2フィールドのシート。新規/編集兼用。保存時に空クエリをバリデーション。
- **`Views/MainWindowView.swift`** — `homeFeed` を `TimelineViewModel` を引数に取る汎用フィードビュー（仮称 `feedView(model:)`）に小リファクタし、`.home` と `.filter(id)` で共用。`.filter(id)` 選択時は当該 `FilterTab.model` を渡す。フィルター用のヘッダにフィルター名を表示。
- **`Views/RootView.swift`** — `SavedFilterStore`（`FilterFileStore` 注入）を生成し、`WorkspaceModel` に渡す。`makeSearchModel` を `LiveSearchLoader` で配線。

### 4.4 データフロー

```
[作成] Sidebar + → FilterEditor 入力 → SavedFilterStore.add
   → WorkspaceModel が FilterTab(TimelineViewModel + LiveSearchLoader) 生成・選択
[表示] タブ選択 → TimelineViewModel.load → LiveSearchLoader.loadPage(cursor:)
   → SearchService.searchPosts → SearchResponse → [PostDisplay]
   → 30秒ごと refresh で上マージ / 末尾到達で loadMore（cursor）
[編集] FilterEditor 保存 → SavedFilterStore.update
   → name 変更のみ: タブ表示更新 / query 変更: model 作り直し再読込
[削除] 行の × → SavedFilterStore.remove → タブ除去 + 隣接/ホームへフォールバック
[復元] 起動時 → FilterFileStore.load(DID) → SavedFilter[] → FilterTab[] 復元
```

## 5. エラー処理

- 検索失敗は `TimelineViewModel.State.failed` に落ち、既存の「再試行」UI（`MainWindowView.failedState`）を流用。
- ポーリング中の失敗は握りつぶし、現行の表示を維持（`TimelineViewModel.refresh`/`loadMore` の既存挙動）。
- 空クエリはエディタで保存不可（バリデーションエラー表示）。
- 永続化（保存/読込）の失敗はログのみ。読込失敗時は空配列で起動。

## 6. テスト戦略（TDD）

Red → Green → Refactor を1テストずつ。コアは UI 非依存で実ネットワークを使わず `URLProtocolStub` / フェイクで検証する。

- **`SearchService`**: URL 構築（`q`/`cursor` のエンコード、limit）、200 デコード、`401`→refresh→リトライ、200 以外のエラーデコード、nonce チャレンジ時の挙動。
- **`SearchResponse`**: fixture JSON デコード（実レスポンス断片）。
- **`PostDisplay(postView:)`**: 検索結果（`PostView`）からのマッピング確認（既存ロジックの回帰確認）。
- **`SavedFilterStore`**: add/update/remove/move の状態遷移、各操作でポート `save` が呼ばれること、空クエリ拒否、`load` 失敗時に空で開始（インメモリフェイクポート）。
- **`TimelineViewModel` + スタブ loader**: 既存の `TimelineLoading` スタブで load/refresh/loadMore が機能すること（`searchPosts` 用に新しい ViewModel テストは不要。既存テストの回帰確認に留める）。
- UI（SidebarView/FilterEditor/MainWindowView）はロジックを Kit に寄せ、ビューは薄く保つ。WorkspaceModel のタブ操作（追加・選択・削除フォールバック・巡回順）は `@MainActor` ユニットテストで検証。

## 7. 永続化 & 機密

- フィルター（`name`/`query`）は機密ではない。`~/Library/Application Support/<bundle>/filters-<DID>.json` に Codable で保存。
- アカウント DID ごとにファイルを分け、アカウント切替で対応するフィルターを読む。
- 将来 iCloud: `SavedFilterStoring` の別実装（`NSUbiquitousKeyValueStore` 等）に差し替え。値型 `SavedFilter` がそのまま同期単位になる。
- 設計書全体方針（機密は Keychain、設定/状態は Codable ファイル、SwiftData 不採用）に整合。

## 8. 実装フェーズの見通し（詳細は writing-plans で確定）

1. `BlueskyCore`: `SearchResponse` モデル + fixture デコードテスト。
2. `BlueskyCore`: `SearchService`（URL 構築 → 200 デコード → 401 リトライ）を TDD。
3. `YoruMimizukuKit`: `SavedFilter` + `SavedFilterStoring` + `SavedFilterStore`（CRUD/永続化呼び出し/バリデーション）を TDD。
4. apps/macos: `LiveSearchLoader` + `FilterFileStore`。
5. apps/macos: `WorkspaceModel` に `filter` タブ機構（追加/選択/削除/巡回/復元）を追加、ユニットテスト。
6. apps/macos: `SidebarView` フィルターセクション + `FilterEditorView` + `MainWindowView` の汎用フィードビュー化。
7. `RootView` 配線、`xcodegen generate` → ビルド確認。

## 9. 未確定事項（実装着手時に確定）

- `searchPosts` の既定 `limit`（25 程度で開始）と、ポーリング間隔をホームと共有するか個別設定にするか。
- フィルター行の編集 UI（hover の鉛筆ボタン vs コンテキストメニュー）。
- フィルターのアイコン（サイドバーで `line.3.horizontal.decrease` 等を出すか）。
- 並べ替え（`move`）の v1 UI を出すか（ロジックは用意、UI は後続でも可）。
