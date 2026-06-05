# YoruMimizuku 構造化フィルター設計書

- 日付: 2026-06-05
- ステータス: 設計合意済み（実装計画はこの後 `writing-plans` で作成）
- 作業ブランチ: `feature/structured-filters`
- 前提: `docs/superpowers/specs/2026-06-05-yorumimizuku-filter-tabs-design.md`（フィルタータブの初版。本設計はそれを構造化検索へ拡張する）

## 1. 概要

既存のフィルタータブは「生クエリ1本」を `app.bsky.feed.searchPosts` に渡すだけだった。本拡張では、フィルターを **複数の条件行（型付き）+ AND/OR の結合子** に正規化する。

- `+` で条件行を追加し、各行は種別（キーワード / ユーザー / ハッシュタグ / メンション）と値を持つ。
- `AND` / `OR` をラジオ（セグメント）で選ぶ。
- 想定ユースケース:
  - **OR**: 複数ユーザーを並べて「その人たちの投稿一覧」を見る。
  - **AND**: 「`#swift` の中で特定ユーザー(`from:`)」のように絞り込む。

`searchPosts` は **OR（論理和）に未対応**（スペース区切りは暗黙 AND、`from:` は単一アカウント）。したがって **OR は条件ごとに `searchPosts` を実行し、結果をクライアント側で時系列マージ**して実現する。AND は従来どおりフラグメントをスペース結合した1本のクエリで実現する。

## 2. ゴール / 非ゴール

### v1 のゴール
- `SavedFilter` を構造化（`terms: [FilterTerm]` + `combinator`）。旧 `{ query }` 永続化ファイルを**自動移行**して既存フィルターを壊さない。
- 条件種別 4種: `keyword` / `user`(→`from:`) / `hashtag`(→`#`) / `mention`(→`mentions:`)。
- AND: 全フラグメントをスペース結合した1本の `searchPosts`。
- OR: 条件ごとに `searchPosts`（`sort=latest`）し、`createdAt` 降順でマージ・URI で重複排除。無限スクロール維持（複合カーソル）。
- エディタ UI: 名前 / AND・OR 切替 / 条件行（種別 Picker + 値）/ 行追加・削除 / 1件も有効条件が無ければ保存不可。
- 既定の結合子は `AND`。

### 非ゴール（後続 / 将来）
- ネスト（グループ化された AND/OR の入れ子）。v1 はフラット 1段。
- `since`/`until`/`lang`/`domain` などの追加オペレータ UI（生クエリ keyword 行で代用可能）。
- リスト（`getListFeed`）タブ。複数ユーザーまとめ読みの別解だが本 spec の対象外。
- 検索結果のソート種別切替 UI（内部的に `latest` 固定）。

## 3. 意思決定ログ

| 項目 | 決定 |
|---|---|
| 行の正規化 | 型付き行（種別セレクタ + 値）。`from:`/`#` は内部で自動付与 |
| 種別 | 4種: keyword / user / hashtag / mention |
| 結合子 | AND / OR をラジオで選択。既定 AND |
| OR の実現 | 条件ごとに `searchPosts` 実行 → クライアント側で時系列マージ・重複排除 |
| OR のスクロール | 無限スクロール維持。複合カーソルで各条件の続きを追加読み込み |
| ソート | フィルター検索は `sort=latest`（時系列マージのため） |
| 永続化 | 既存 `SavedFilterStore`/`FilterFileStore` を流用。`SavedFilter` の Codable を移行対応に |

## 4. アーキテクチャ

### 4.1 モデル（YoruMimizukuKit）

```swift
public enum FilterTermKind: String, Codable, Sendable, CaseIterable {
    case keyword   // 値をそのまま
    case user      // from:<handle>
    case hashtag   // #<tag>
    case mention   // mentions:<handle>
}

public struct FilterTerm: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var kind: FilterTermKind
    public var value: String
}

public enum FilterCombinator: String, Codable, Sendable { case and, or }

public struct SavedFilter: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var terms: [FilterTerm]
    public var combinator: FilterCombinator
    public let createdAt: Date
}
```

**移行（カスタム Decodable）**: JSON に `terms` があれば通常デコード。無く旧 `query: String` があれば `terms = [FilterTerm(kind: .keyword, value: query)]`、`combinator = .and` に変換。エンコードは新形（`query` は書かない）。これにより旧 `filters-<DID>.json` をそのまま読める。

### 4.2 クエリ生成（純粋・テスト対象）

`SavedFilter` の拡張として:

```swift
extension SavedFilter {
    /// 各 term を searchPosts のフラグメントへ変換（空はスキップ、trim 済み）。
    /// keyword→値 / user→"from:"+handle / hashtag→"#"+tag / mention→"mentions:"+handle
    /// handle は先頭 "@" を除去、tag は先頭 "#" を除去。
    /// AND → [全フラグメントをスペース結合した1要素]（空なら []）
    /// OR  → 非空フラグメントごとに1要素
    public var subqueries: [String] { ... }
}
```

- フラグメント変換規則:
  - `keyword`: `value.trimmed`
  - `user`: `"from:" + value.trimmed.drop(prefix: "@")`
  - `hashtag`: `"#" + value.trimmed.drop(prefix: "#")`
  - `mention`: `"mentions:" + value.trimmed.drop(prefix: "@")`
- 空文字フラグメントは除外。
- `subqueries.isEmpty` は「有効な条件なし」を意味する（保存不可の判定にも使用）。

### 4.3 OR マージとカーソル（純粋・テスト対象）

OR では各サブクエリが独立した `searchPosts` ページとカーソルを持つ。これらを1つの `TimelineLoading.loadPage(cursor:)` 境界に載せるため、複合カーソルを用いる。

```swift
/// サブクエリ並びに整列した各カーソル（nil = そのサブクエリは尽きた/未取得）。
public struct CompositeCursor: Codable, Equatable, Sendable {
    public var cursors: [String?]
}
```

- エンコード: `CompositeCursor` を JSON 文字列化して `TimelinePage.cursor` に格納。
- デコード: `loadPage(cursor:)` 受領時に JSON 復元（nil の場合は全条件の先頭から）。
- マージ純粋関数: 複数の `[PostDisplay]` を結合し、`createdAt` 降順、`id`(URI) で重複排除した配列を返す。
- 次カーソル: 各サブクエリの応答 cursor を並びに保持。すべて nil なら `TimelinePage.cursor = nil`（尽き）。

> マージ・複合カーソルの codec は Kit に純粋関数として置き、ユニットテストする。実ネットワークは app 側ローダーが担う。

### 4.4 検索サービス（BlueskyCore）

`SearchService.searchPosts` に `sort: String? = nil` 引数を追加し、指定時は `&sort=` を付与。後方互換（既定 nil で従来と同一 URL）。フィルターのローダーは `sort: "latest"` を渡す。

### 4.5 ローダー（app）

`LiveSearchLoader` を **サブクエリ配列**対応に変更（`TimelineLoading` 準拠は維持）。

```swift
init(accountManager:, subqueries: [String], config:)
func loadPage(cursor: String?) async throws -> TimelinePage
```

- `subqueries.isEmpty` → 空ページ（`posts: [], cursor: nil`）。
- 1本 → 単発 `searchPosts(sort: "latest", cursor: cursor)`。`cursor`/次カーソルはそのまま文字列。
- 複数（OR）→ `CompositeCursor` を復元（nil なら全条件先頭）。各「尽きていない」サブクエリを `searchPosts(sort:"latest", cursor: 各)` 実行 → 全件を `PostDisplay` 化 → Kit のマージ関数で結合 → 次の `CompositeCursor` をエンコードして返す。
- トークンリフレッシュは各 `searchPosts` 呼び出しで起こり得るため、呼び出しごとに `context.persist(refreshed)`。
- リクエストは順次でよい（条件数は通常少数）。

### 4.6 WorkspaceModel / FilterTab（app）

- `FilterTab` は `SavedFilter` を保持し、`model` は `subqueries` から構築（`LiveSearchLoader(subqueries:)`）。
- `.id` 用に、編集で確実に再ロードさせるため `terms + combinator` から決まる安定キー（例: `subqueries.joined(separator:"\u{1}") + "|" + combinator`）を `FilterTab` が公開し、`MainWindowView` の `.id` に使う。
- `WorkspaceModel.addFilter` / `updateFilter` は `SavedFilter`（terms/combinator）ベースに変更。`SavedFilterStore` も同様。
- `makeFilterModel` のシグネチャは「`SavedFilter` を受け取り `TimelineViewModel` を返す」に変更（app 側で `subqueries` を計算してローダーへ）。

### 4.7 エディタ UI（app）

`FilterEditorView` を作り直す:
- 名前 TextField。
- `AND` / `OR` の `Picker(.segmented)`。
- 条件行リスト: 各行に種別 `Picker`（keyword/user/hashtag/mention）+ 値 TextField + 行削除ボタン。
- `+ 条件を追加` ボタン。
- 保存は `SavedFilter.subqueries.isEmpty == false` の時のみ有効。
- 新規は空1行 + AND 既定。編集は既存 `terms`/`combinator` を反映。

### 4.8 サイドバー表示

行のメタ（monospaced）は条件要約: `OR` なら `OR: ` + 各フラグメントをカンマ連結、`AND` なら結合済みクエリ。長い場合は truncation。

## 5. エラー処理

- 検索失敗（単発・複合いずれも）は `TimelineViewModel.failed` → 既存の再試行 UI。
- OR で一部サブクエリのみ失敗した場合: v1 は **loadPage 全体を失敗扱い**にせず、失敗したサブクエリはそのページで空として扱い、取得できた分をマージして返す（堅牢性優先）。次カーソルでは失敗条件のカーソルを据え置き再試行。
  - 実装簡素化の代替として「いずれか失敗で throw（既存 retry UI）」でもよいが、v1 は前者（部分成功）を採用。
- 保存時、有効条件 0 は保存不可（UI で無効化）。
- 永続化失敗は従来どおりログのみ。

## 6. テスト戦略（TDD・Kit 中心）

- `SavedFilter.subqueries`:
  - keyword/user/hashtag/mention の各フラグメント化（`@`/`#` 除去、trim）。
  - AND: 複数フラグメントのスペース結合 / 空除外 / 全空で `[]`。
  - OR: フラグメントごとに分割 / 空除外。
- 移行デコード: 旧 `{ "query": "#swift from:a" }` → `terms=[.keyword "#swift from:a"]`, `.and`。新形のラウンドトリップ。
- OR マージ純粋関数: 複数配列の `createdAt` 降順マージ・URI 重複排除。
- `CompositeCursor` codec: エンコード/デコード往復、全 nil 判定。
- `SavedFilterStore`: 既存 CRUD テストを新モデルへ更新（add は terms/combinator を受ける形）。
- app 層（ローダー/エディタ/Workspace）は XCTest ターゲットが無いため**ビルド + 手動確認**で担保。`searchPosts` の `sort` 付与は `SearchServiceTests` に1ケース追加。

## 7. 影響範囲（破壊的変更）

- `SavedFilter`（構造変更・移行で吸収） / `SavedFilterStore.add`（引数変更） / `LiveSearchLoader`（subqueries 化） / `FilterEditorView`（作り直し） / `WorkspaceModel`（`FilterTab`・`makeFilterModel`・CRUD） / `RootView`(`makeFilterModel` 配線) / `SearchService`（`sort` 追加・後方互換）。

## 8. 実装フェーズ（詳細は writing-plans）

1. Kit: `FilterTermKind`/`FilterTerm`/`FilterCombinator` + `SavedFilter` 構造化 + 移行デコード（TDD）。
2. Kit: `SavedFilter.subqueries`（TDD）。
3. Kit: OR マージ純粋関数 + `CompositeCursor` codec（TDD）。
4. Kit: `SavedFilterStore` を新モデルへ更新（TDD、既存テスト改修）。
5. BlueskyCore: `SearchService` に `sort` 追加（TDD 1 ケース）。
6. app: `LiveSearchLoader` を subqueries 対応に（単発 + 複合）。
7. app: `WorkspaceModel`/`FilterTab`/`makeFilterModel`/`RootView` 配線更新。
8. app: `FilterEditorView` 作り直し + サイドバー要約表示。
9. `xcodegen generate` + ビルド + コア全テストで検証。

## 9. 未確定事項（実装着手時に確定）

- OR の各サブクエリの `limit`（既定 25 を流用 / 条件数が多い時の合計件数の上限を設けるか）。
- マージのソートキー: `createdAt`（投稿時刻）で確定。`indexedAt` は `PostDisplay` に無いため使わない。
- サイドバー要約の最終フォーマット。
- 部分失敗時の挙動（§5 は部分成功を採用、実装時に再確認）。
