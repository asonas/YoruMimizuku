# Structured Filters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** フィルターを「型付き条件行（キーワード/ユーザー/ハッシュタグ/メンション）+ AND/OR」へ正規化する。OR は `searchPosts` が非対応なので条件ごとに検索してクライアント側で時系列マージする。

**Architecture:** `YoruMimizukuKit` の `SavedFilter` を `terms: [FilterTerm]` + `combinator` に構造化（旧 `{query}` を移行デコード）。`SavedFilter.subqueries` で AND は1本・OR は複数のクエリへ変換。OR マージと複合カーソルは Kit の純粋関数。app の `LiveSearchLoader` をサブクエリ配列対応にし、`WorkspaceModel`/`FilterEditorView` を新モデルへ。`SearchService` に `sort` 引数を追加。

**Tech Stack:** Swift 6 / SwiftUI / XcodeGen / macOS 26.0。コア=`BlueskyCore`、表示ロジック=`YoruMimizukuKit`、ビュー=app ターゲット `YoruMimizuku`。テストは `swift test`。

**設計書:** `docs/superpowers/specs/2026-06-05-yorumimizuku-structured-filters-design.md`

---

## 共通ルール

- 作業ディレクトリ: worktree `.worktrees/feature/structured-filters`。Kit/Core テストは `core/` で `swift test`、app ビルドはルートで `xcodegen generate && xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj -destination 'platform=macOS' -quiet`。
- コミットは `git ai-commit`（`git commit` 直接実行は禁止）。英語・先頭大文字・Conventional Commits 不可。
- TDD: 失敗するテスト → 失敗確認 → 最小実装 → 成功確認 → コミット。
- app ターゲットに XCTest は無い。app 層タスク（6〜8）はビルドで検証し、相互参照のため**まとめて1コミット**でよい。

## File Structure

- Modify: `core/Sources/YoruMimizukuKit/SavedFilter.swift` — 構造化モデル + 移行デコード + `subqueries`
- Create: `core/Sources/YoruMimizukuKit/FilterSearchMerge.swift` — OR マージ純粋関数 + `CompositeCursor`
- Modify: `core/Sources/YoruMimizukuKit/SavedFilterStore.swift` — `add` を terms/combinator ベースへ
- Modify: `core/Sources/BlueskyCore/XRPC/SearchService.swift` — `sort` 引数
- Modify: `apps/macos/Timeline/LiveSearchLoader.swift` — サブクエリ配列対応（単発 + 複合）
- Modify: `apps/macos/Workspace/WorkspaceModel.swift` — `FilterTab`/CRUD/`makeFilterModel` を `SavedFilter` ベースへ
- Modify: `apps/macos/Views/RootView.swift` — `makeFilterModel` 配線
- Modify: `apps/macos/Views/FilterEditorView.swift` — 型付き行 + AND/OR の作り直し
- Modify: `apps/macos/Views/SidebarView.swift` — フィルター行メタを条件要約に
- Test: `core/Tests/YoruMimizukuKitTests/SavedFilterStoreTests.swift`（改修）, `SavedFilterQueryTests.swift`（新規）, `FilterSearchMergeTests.swift`（新規）
- Test: `core/Tests/BlueskyCoreTests/SearchServiceTests.swift`（1ケース追加）

（テスト新規ファイルは `SavedFilterTests.swift`（モデル移行 + subqueries）と `FilterSearchMergeTests.swift`（マージ + cursor）。）

---

## Task 1: `SavedFilter` 構造化 + 移行デコード（Kit）

**Files:**
- Modify (全置換): `core/Sources/YoruMimizukuKit/SavedFilter.swift`
- Test (新規): `core/Tests/YoruMimizukuKitTests/SavedFilterTests.swift`

- [ ] **Step 1: 失敗するテストを書く**

`core/Tests/YoruMimizukuKitTests/SavedFilterTests.swift`:

```swift
import XCTest
@testable import YoruMimizukuKit

final class SavedFilterTests: XCTestCase {
    // MARK: - Migration / Codable

    func testLegacyQueryDecodesToSingleKeywordTermAnd() throws {
        let legacy = Data(##"""
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "name": "Swift",
          "query": "#swift from:alice.bsky.social",
          "createdAt": 1000
        }
        """##.utf8)
        let decoder = JSONDecoder()
        let filter = try decoder.decode(SavedFilter.self, from: legacy)

        XCTAssertEqual(filter.name, "Swift")
        XCTAssertEqual(filter.combinator, .and)
        XCTAssertEqual(filter.terms.count, 1)
        XCTAssertEqual(filter.terms[0].kind, .keyword)
        XCTAssertEqual(filter.terms[0].value, "#swift from:alice.bsky.social")
    }

    func testNewShapeRoundTrips() throws {
        let filter = SavedFilter(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "Two users",
            terms: [
                FilterTerm(id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, kind: .user, value: "alice.bsky.social"),
                FilterTerm(id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!, kind: .user, value: "bob.bsky.social")
            ],
            combinator: .or,
            createdAt: Date(timeIntervalSince1970: 2000)
        )
        let data = try JSONEncoder().encode(filter)
        let decoded = try JSONDecoder().decode(SavedFilter.self, from: data)
        XCTAssertEqual(decoded, filter)
    }

    func testEncodedShapeOmitsLegacyQueryKey() throws {
        let filter = SavedFilter(name: "x", terms: [FilterTerm(kind: .keyword, value: "y")], combinator: .and)
        let data = try JSONEncoder().encode(filter)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(object?["terms"])
        XCTAssertNil(object?["query"], "legacy query key must not be written")
    }
}
```

- [ ] **Step 2: 失敗確認**

Run: `cd core && swift test --filter SavedFilterTests`
Expected: コンパイルエラー（`FilterTerm`/`FilterCombinator`/新 `SavedFilter` 未定義）。

- [ ] **Step 3: 最小実装（`SavedFilter.swift` を全置換）**

```swift
import Foundation

/// The kind of a single filter condition, which determines how its value is
/// rendered into a `searchPosts` query fragment.
public enum FilterTermKind: String, Codable, Sendable, CaseIterable {
    case keyword   // value verbatim
    case user      // from:<handle>
    case hashtag   // #<tag>
    case mention   // mentions:<handle>
}

/// One condition row in a structured filter.
public struct FilterTerm: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var kind: FilterTermKind
    public var value: String

    public init(id: UUID = UUID(), kind: FilterTermKind, value: String) {
        self.id = id
        self.kind = kind
        self.value = value
    }
}

/// How a filter's condition rows are combined. `and` joins them into one query;
/// `or` runs each as its own search and merges the results client-side (the
/// Bluesky search API has no boolean OR).
public enum FilterCombinator: String, Codable, Sendable {
    case and
    case or
}

/// A saved search subscribed as a sidebar tab: a list of typed condition rows
/// combined by `combinator`. A pure value type so it can later be synced verbatim
/// (e.g. via iCloud). Decoding migrates the legacy single-`query` shape to one
/// keyword term so older persisted filters keep working.
public struct SavedFilter: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var terms: [FilterTerm]
    public var combinator: FilterCombinator
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        terms: [FilterTerm],
        combinator: FilterCombinator = .and,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.terms = terms
        self.combinator = combinator
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, terms, combinator, createdAt, query
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
            ?? Date(timeIntervalSince1970: 0)
        if let terms = try c.decodeIfPresent([FilterTerm].self, forKey: .terms) {
            self.terms = terms
            self.combinator = try c.decodeIfPresent(FilterCombinator.self, forKey: .combinator) ?? .and
        } else {
            // Legacy migration: a single raw `query` becomes one keyword term.
            let query = try c.decodeIfPresent(String.self, forKey: .query) ?? ""
            self.terms = [FilterTerm(kind: .keyword, value: query)]
            self.combinator = .and
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(terms, forKey: .terms)
        try c.encode(combinator, forKey: .combinator)
        try c.encode(createdAt, forKey: .createdAt)
    }
}
```

- [ ] **Step 4: 成功確認**

Run: `cd core && swift test --filter SavedFilterTests`
Expected: PASS（3 テスト）。`SavedFilterStore` を参照する既存テストはこの時点でコンパイルエラーになる場合があるが、それは Task 4 で解消する。まず `--filter SavedFilterTests` で本タスクのテストだけ通すこと。フルビルドは Task 4 まで保留。

- [ ] **Step 5: コミット**

```bash
git add core/Sources/YoruMimizukuKit/SavedFilter.swift core/Tests/YoruMimizukuKitTests/SavedFilterTests.swift
git ai-commit --context "Restructure SavedFilter into typed terms plus combinator with legacy query migration"
```

> 注: この変更で `SavedFilterStore.add(name:query:)`（旧）と app 側参照がコンパイル不能になる。Task 4（store）・Task 6〜8（app）で追従する。`swift test` 全体は Task 4 完了後に緑化する。

---

## Task 2: `SavedFilter.subqueries`（Kit）

**Files:**
- Modify: `core/Sources/YoruMimizukuKit/SavedFilter.swift`（拡張を追記）
- Test: `core/Tests/YoruMimizukuKitTests/SavedFilterTests.swift`（追記）

- [ ] **Step 1: 失敗するテストを追記**

`SavedFilterTests.swift` のクラス内に追記:

```swift
    // MARK: - subqueries

    private func filter(_ combinator: FilterCombinator, _ terms: [FilterTerm]) -> SavedFilter {
        SavedFilter(name: "n", terms: terms, combinator: combinator)
    }

    func testFragmentRenderingPerKind() {
        XCTAssertEqual(
            filter(.or, [
                FilterTerm(kind: .keyword, value: "  hello world "),
                FilterTerm(kind: .user, value: "@alice.bsky.social"),
                FilterTerm(kind: .hashtag, value: "#swift"),
                FilterTerm(kind: .mention, value: "bob.bsky.social")
            ]).subqueries,
            ["hello world", "from:alice.bsky.social", "#swift", "mentions:bob.bsky.social"]
        )
    }

    func testAndJoinsFragmentsIntoOneQuery() {
        XCTAssertEqual(
            filter(.and, [
                FilterTerm(kind: .hashtag, value: "swift"),
                FilterTerm(kind: .user, value: "alice.bsky.social")
            ]).subqueries,
            ["#swift from:alice.bsky.social"]
        )
    }

    func testOrSplitsFragments() {
        XCTAssertEqual(
            filter(.or, [
                FilterTerm(kind: .user, value: "alice.bsky.social"),
                FilterTerm(kind: .user, value: "bob.bsky.social")
            ]).subqueries,
            ["from:alice.bsky.social", "from:bob.bsky.social"]
        )
    }

    func testBlankTermsAreDropped() {
        XCTAssertEqual(
            filter(.and, [
                FilterTerm(kind: .keyword, value: "   "),
                FilterTerm(kind: .hashtag, value: "swift")
            ]).subqueries,
            ["#swift"]
        )
    }

    func testAllBlankYieldsEmpty() {
        XCTAssertTrue(filter(.or, [FilterTerm(kind: .keyword, value: "  ")]).subqueries.isEmpty)
        XCTAssertTrue(filter(.and, []).subqueries.isEmpty)
    }
```

- [ ] **Step 2: 失敗確認**

Run: `cd core && swift test --filter SavedFilterTests`
Expected: コンパイルエラー（`subqueries` 未定義）。

- [ ] **Step 3: 実装を `SavedFilter.swift` 末尾に追記**

```swift
extension FilterTerm {
    /// The `searchPosts` query fragment for this term, or nil when the value is
    /// blank after trimming. Strips a leading `@`/`#` so users can type either form.
    public var fragment: String? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return nil }
        switch kind {
        case .keyword: return v
        case .user: return "from:" + Self.stripLeading("@", v)
        case .hashtag: return "#" + Self.stripLeading("#", v)
        case .mention: return "mentions:" + Self.stripLeading("@", v)
        }
    }

    private static func stripLeading(_ ch: Character, _ s: String) -> String {
        s.hasPrefix(String(ch)) ? String(s.dropFirst()) : s
    }
}

extension SavedFilter {
    /// The `searchPosts` queries this filter expands to. `and` joins every
    /// non-blank fragment into a single query; `or` yields one query per fragment
    /// (merged client-side by the loader). Empty when there are no usable terms.
    public var subqueries: [String] {
        let fragments = terms.compactMap(\.fragment)
        guard !fragments.isEmpty else { return [] }
        switch combinator {
        case .and: return [fragments.joined(separator: " ")]
        case .or: return fragments
        }
    }
}
```

- [ ] **Step 4: 成功確認**

Run: `cd core && swift test --filter SavedFilterTests`
Expected: PASS（8 テスト）。

- [ ] **Step 5: コミット**

```bash
git add core/Sources/YoruMimizukuKit/SavedFilter.swift core/Tests/YoruMimizukuKitTests/SavedFilterTests.swift
git ai-commit --context "Add SavedFilter.subqueries expanding typed terms into AND/OR searchPosts queries"
```

---

## Task 3: OR マージ + `CompositeCursor`（Kit）

**Files:**
- Create: `core/Sources/YoruMimizukuKit/FilterSearchMerge.swift`
- Test (新規): `core/Tests/YoruMimizukuKitTests/FilterSearchMergeTests.swift`

- [ ] **Step 1: 失敗するテストを書く**

`core/Tests/YoruMimizukuKitTests/FilterSearchMergeTests.swift`:

```swift
import XCTest
@testable import YoruMimizukuKit

final class FilterSearchMergeTests: XCTestCase {
    private func post(_ id: String, _ ageSeconds: TimeInterval) -> PostDisplay {
        PostDisplay(
            id: id, authorDisplayName: id, authorHandle: "\(id).bsky.social",
            body: id, createdAt: Date(timeIntervalSince1970: 10_000 - ageSeconds)
        )
    }

    func testMergeSortsNewestFirstAndDedupesById() {
        let a = [post("p1", 10), post("p3", 30)]
        let b = [post("p2", 20), post("p1", 10)] // p1 duplicated across subqueries
        let merged = FilterSearchMerge.merge([a, b])
        XCTAssertEqual(merged.map(\.id), ["p1", "p2", "p3"])
    }

    func testMergeEmpty() {
        XCTAssertTrue(FilterSearchMerge.merge([]).isEmpty)
        XCTAssertTrue(FilterSearchMerge.merge([[], []]).isEmpty)
    }

    func testCompositeCursorRoundTrips() throws {
        let cursor = CompositeCursor(cursors: ["a", nil, "c"])
        let encoded = try XCTUnwrap(cursor.encoded())
        XCTAssertEqual(CompositeCursor.decode(encoded), cursor)
    }

    func testCompositeCursorEncodesNilWhenAllExhausted() {
        XCTAssertNil(CompositeCursor(cursors: [nil, nil]).encoded())
    }

    func testCompositeCursorDecodeNilStringIsNil() {
        XCTAssertNil(CompositeCursor.decode(nil))
    }
}
```

- [ ] **Step 2: 失敗確認**

Run: `cd core && swift test --filter FilterSearchMergeTests`
Expected: コンパイルエラー（`FilterSearchMerge`/`CompositeCursor` 未定義）。

- [ ] **Step 3: 実装**

`core/Sources/YoruMimizukuKit/FilterSearchMerge.swift`:

```swift
import Foundation

/// An opaque pagination cursor for an OR filter, holding one sub-cursor per
/// subquery (aligned by position). A nil entry means that subquery is exhausted
/// or not yet fetched. Serialized to a single string to fit the `TimelineLoading`
/// single-cursor interface.
public struct CompositeCursor: Codable, Equatable, Sendable {
    public var cursors: [String?]

    public init(cursors: [String?]) {
        self.cursors = cursors
    }

    /// JSON-encode to one opaque cursor string, or nil when every sub-cursor is
    /// nil (nothing more to load anywhere).
    public func encoded() -> String? {
        guard cursors.contains(where: { $0 != nil }) else { return nil }
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Decode from an opaque cursor string; a nil string (first page) yields nil.
    public static func decode(_ string: String?) -> CompositeCursor? {
        guard let string, let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CompositeCursor.self, from: data)
    }
}

/// Pure merge logic for OR filters.
public enum FilterSearchMerge {
    /// Merge per-subquery result pages into a single feed: keep the first
    /// occurrence of each post id, then sort newest-first by `createdAt`.
    public static func merge(_ pages: [[PostDisplay]]) -> [PostDisplay] {
        var seen = Set<String>()
        var all: [PostDisplay] = []
        for page in pages {
            for post in page where seen.insert(post.id).inserted {
                all.append(post)
            }
        }
        return all.sorted { $0.createdAt > $1.createdAt }
    }
}
```

- [ ] **Step 4: 成功確認**

Run: `cd core && swift test --filter FilterSearchMergeTests`
Expected: PASS（5 テスト）。

- [ ] **Step 5: コミット**

```bash
git add core/Sources/YoruMimizukuKit/FilterSearchMerge.swift core/Tests/YoruMimizukuKitTests/FilterSearchMergeTests.swift
git ai-commit --context "Add CompositeCursor and FilterSearchMerge for OR-filter client-side merge"
```

---

## Task 4: `SavedFilterStore` を新モデルへ（Kit）

**Files:**
- Modify: `core/Sources/YoruMimizukuKit/SavedFilterStore.swift`（`add` のみ差し替え）
- Test (全置換): `core/Tests/YoruMimizukuKitTests/SavedFilterStoreTests.swift`

`add(name:query:)` を `add(name:terms:combinator:)` に変更。`subqueries` が空なら拒否。名前空欄ならサブクエリ結合を表示名に使う。`update`/`remove`/`init`/`persist`/`SavedFilterStoring` は変更なし。

- [ ] **Step 1: テストを全置換（失敗させる）**

`core/Tests/YoruMimizukuKitTests/SavedFilterStoreTests.swift`:

```swift
import XCTest
@testable import YoruMimizukuKit

final class SavedFilterStoreTests: XCTestCase {
    @MainActor
    func testLoadsExistingFiltersFromPort() {
        let existing = SavedFilter(name: "Swift", terms: [FilterTerm(kind: .hashtag, value: "swift")], combinator: .and)
        let port = InMemoryFilterStoring(initial: [existing])
        let store = SavedFilterStore(port: port)
        XCTAssertEqual(store.filters, [existing])
    }

    @MainActor
    func testAddAppendsAndPersists() throws {
        let port = InMemoryFilterStoring()
        let store = SavedFilterStore(port: port)

        let added = try XCTUnwrap(store.add(
            name: "Cats", terms: [FilterTerm(kind: .keyword, value: "cats")], combinator: .and
        ))

        XCTAssertEqual(store.filters.map(\.id), [added.id])
        XCTAssertEqual(port.saved.last?.map(\.id), [added.id])
    }

    @MainActor
    func testAddRejectsWhenNoUsableTerms() {
        let port = InMemoryFilterStoring()
        let store = SavedFilterStore(port: port)

        XCTAssertNil(store.add(
            name: "Empty", terms: [FilterTerm(kind: .keyword, value: "   ")], combinator: .or
        ))
        XCTAssertTrue(store.filters.isEmpty)
        XCTAssertTrue(port.saved.isEmpty)
    }

    @MainActor
    func testAddUsesJoinedSubqueriesAsNameWhenBlank() throws {
        let port = InMemoryFilterStoring()
        let store = SavedFilterStore(port: port)

        let added = try XCTUnwrap(store.add(
            name: "  ",
            terms: [FilterTerm(kind: .user, value: "alice.bsky.social"),
                    FilterTerm(kind: .user, value: "bob.bsky.social")],
            combinator: .or
        ))
        XCTAssertEqual(added.name, "from:alice.bsky.social | from:bob.bsky.social")
    }

    @MainActor
    func testUpdateReplacesByIdAndPersists() throws {
        let original = SavedFilter(name: "Swift", terms: [FilterTerm(kind: .hashtag, value: "swift")], combinator: .and)
        let port = InMemoryFilterStoring(initial: [original])
        let store = SavedFilterStore(port: port)

        var edited = original
        edited.name = "Swift Lang"
        edited.combinator = .or
        store.update(edited)

        XCTAssertEqual(store.filters.first?.name, "Swift Lang")
        XCTAssertEqual(store.filters.first?.combinator, .or)
        XCTAssertEqual(port.saved.last?.first?.name, "Swift Lang")
    }

    @MainActor
    func testRemoveDeletesByIdAndPersists() {
        let a = SavedFilter(name: "A", terms: [FilterTerm(kind: .keyword, value: "a")], combinator: .and)
        let b = SavedFilter(name: "B", terms: [FilterTerm(kind: .keyword, value: "b")], combinator: .and)
        let port = InMemoryFilterStoring(initial: [a, b])
        let store = SavedFilterStore(port: port)

        store.remove(id: a.id)

        XCTAssertEqual(store.filters.map(\.id), [b.id])
        XCTAssertEqual(port.saved.last?.map(\.id), [b.id])
    }

    @MainActor
    func testStartsEmptyWhenPortLoadThrows() {
        let port = InMemoryFilterStoring(loadError: NSError(domain: "x", code: 1))
        let store = SavedFilterStore(port: port)
        XCTAssertTrue(store.filters.isEmpty)
    }
}

private final class InMemoryFilterStoring: SavedFilterStoring, @unchecked Sendable {
    private let initial: [SavedFilter]
    private let loadError: Error?
    private(set) var saved: [[SavedFilter]] = []

    init(initial: [SavedFilter] = [], loadError: Error? = nil) {
        self.initial = initial
        self.loadError = loadError
    }

    func load() throws -> [SavedFilter] {
        if let loadError { throw loadError }
        return initial
    }

    func save(_ filters: [SavedFilter]) throws {
        saved.append(filters)
    }
}
```

- [ ] **Step 2: 失敗確認**

Run: `cd core && swift test --filter SavedFilterStoreTests`
Expected: コンパイルエラー（旧 `add(name:query:)` シグネチャ不一致）。

- [ ] **Step 3: `SavedFilterStore.add` を差し替え**

`core/Sources/YoruMimizukuKit/SavedFilterStore.swift` の既存 `add(name:query:)` メソッドを以下に置換:

```swift
    /// Append a new filter built from typed terms. Returns nil (and does nothing)
    /// when the terms expand to no usable query. A blank name falls back to the
    /// joined subqueries as the label.
    @discardableResult
    public func add(name: String, terms: [FilterTerm], combinator: FilterCombinator) -> SavedFilter? {
        let candidate = SavedFilter(name: "", terms: terms, combinator: combinator)
        guard !candidate.subqueries.isEmpty else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty
            ? candidate.subqueries.joined(separator: combinator == .or ? " | " : " ")
            : trimmedName
        let filter = SavedFilter(name: resolvedName, terms: terms, combinator: combinator)
        filters.append(filter)
        persist()
        return filter
    }
```

- [ ] **Step 4: 成功確認 + コア全テスト**

Run: `cd core && swift test`
Expected: すべて PASS（`SavedFilterTests` / `FilterSearchMergeTests` / `SavedFilterStoreTests` 含む。コアは app 非依存なのでここで全緑になる）。

- [ ] **Step 5: コミット**

```bash
git add core/Sources/YoruMimizukuKit/SavedFilterStore.swift core/Tests/YoruMimizukuKitTests/SavedFilterStoreTests.swift
git ai-commit --context "Update SavedFilterStore.add to take typed terms and combinator, rejecting empty queries"
```

---

## Task 5: `SearchService` に `sort` を追加（BlueskyCore）

**Files:**
- Modify: `core/Sources/BlueskyCore/XRPC/SearchService.swift`
- Test: `core/Tests/BlueskyCoreTests/SearchServiceTests.swift`（1ケース追加）

- [ ] **Step 1: 失敗するテストを追記**

`SearchServiceTests.swift` のクラス内に追記:

```swift
    func testSearchIncludesSortWhenProvided() async throws {
        let http = FakeHTTPClient(response: HTTPResponse(statusCode: 200, body: Self.searchBody))
        let service = makeService(http: http)

        _ = try await service.searchPosts(
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: nil,
            query: "cats", limit: 25, cursor: nil, sort: "latest"
        )

        let sent = try XCTUnwrap(http.sentRequests.last)
        XCTAssertEqual(sent.url.query?.contains("sort=latest"), true)
    }
```

- [ ] **Step 2: 失敗確認**

Run: `cd core && swift test --filter SearchServiceTests`
Expected: コンパイルエラー（`sort` 引数なし）。

- [ ] **Step 3: 実装**

`SearchService.searchPosts` のシグネチャに `sort` を追加（`cursor` の後）し、`Self.searchURL` 呼び出しへ渡す:

```swift
    public func searchPosts(
        pds: URL,
        issuer: URL,
        accessToken: String,
        refreshToken: String?,
        query: String,
        limit: Int = 25,
        cursor: String? = nil,
        sort: String? = nil
    ) async throws -> (response: SearchResponse, refreshed: TokenResponse?) {
        let url = try Self.searchURL(pds: pds, query: query, limit: limit, cursor: cursor, sort: sort)
        // ... 以降は既存のまま（fetch / 401 refresh / decode）
```

`searchURL` に `sort` を追加:

```swift
    static func searchURL(pds: URL, query: String, limit: Int, cursor: String?, sort: String? = nil) throws -> URL {
        let endpoint = pds.appendingPathComponent("xrpc/app.bsky.feed.searchPosts")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw XRPCError.invalidURL("app.bsky.feed.searchPosts")
        }
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let sort { items.append(URLQueryItem(name: "sort", value: sort)) }
        components.queryItems = items
        guard let url = components.url else {
            throw XRPCError.invalidURL("app.bsky.feed.searchPosts")
        }
        return url
    }
```

- [ ] **Step 4: 成功確認 + コア全テスト**

Run: `cd core && swift test`
Expected: すべて PASS（既存 SearchService テストは `sort` 既定 nil なので URL 不変）。

- [ ] **Step 5: コミット**

```bash
git add core/Sources/BlueskyCore/XRPC/SearchService.swift core/Tests/BlueskyCoreTests/SearchServiceTests.swift
git ai-commit --context "Add optional sort parameter to SearchService.searchPosts"
```

---

> **app 層（Task 6〜8）について:** 相互参照でまとめてしか compile できないため、3タスクを実装後に Task 8 末尾で一括ビルド・**1コミット**する。中間ビルド失敗は許容。

## Task 6: `LiveSearchLoader` をサブクエリ対応に（app）

**Files:**
- Modify (全置換): `apps/macos/Timeline/LiveSearchLoader.swift`

- [ ] **Step 1: 全置換**

```swift
import Foundation
import os
import BlueskyCore
import YoruMimizukuKit
import PlatformApple

/// Live `TimelineLoading` for a saved filter. Holds the filter's expanded
/// subqueries: a single subquery (AND, or a one-term OR) is a plain `searchPosts`;
/// multiple subqueries (OR) are each searched with `sort=latest` and merged
/// newest-first, paginated through a `CompositeCursor`.
struct LiveSearchLoader: TimelineLoading {
    let accountManager: AccountManager
    let subqueries: [String]
    let config: OAuthClientConfig

    init(accountManager: AccountManager, subqueries: [String], config: OAuthClientConfig = .yoruMimizuku) {
        self.accountManager = accountManager
        self.subqueries = subqueries
        self.config = config
    }

    func loadPage(cursor: String?) async throws -> TimelinePage {
        switch subqueries.count {
        case 0:
            return TimelinePage(posts: [], cursor: nil)
        case 1:
            let page = try await runQuery(subqueries[0], cursor: cursor)
            return TimelinePage(posts: page.posts, cursor: page.cursor)
        default:
            return try await loadComposite(cursor: cursor)
        }
    }

    /// Run one subquery and map to display rows, persisting any refreshed tokens.
    private func runQuery(_ query: String, cursor: String?) async throws -> (posts: [PostDisplay], cursor: String?) {
        let context = try LiveServiceContext(accountManager: accountManager, config: config)
        let service = SearchService(
            sender: context.sender, metadataResolver: context.metadataResolver, config: context.config
        )
        let result = try await service.searchPosts(
            pds: context.account.pds,
            issuer: context.issuer,
            accessToken: context.account.accessToken,
            refreshToken: context.account.refreshToken,
            query: query,
            cursor: cursor,
            sort: "latest"
        )
        try context.persist(result.refreshed)
        return (result.response.posts.map { PostDisplay(postView: $0) }, result.response.cursor)
    }

    /// OR: fetch each non-exhausted subquery, merge newest-first, and re-encode the
    /// per-subquery cursors. A failing subquery contributes no posts this page and
    /// keeps its cursor so a later page retries.
    private func loadComposite(cursor: String?) async throws -> TimelinePage {
        let decoded = CompositeCursor.decode(cursor)
        let isFirstPage = decoded == nil
        let composite = decoded ?? CompositeCursor(cursors: Array(repeating: nil, count: subqueries.count))

        var pages: [[PostDisplay]] = []
        var nextCursors: [String?] = []
        for (index, query) in subqueries.enumerated() {
            let sub = composite.cursors[index]
            // On follow-up pages a nil sub-cursor means that subquery is exhausted.
            if !isFirstPage && sub == nil {
                pages.append([])
                nextCursors.append(nil)
                continue
            }
            do {
                let page = try await runQuery(query, cursor: sub)
                pages.append(page.posts)
                nextCursors.append(page.cursor)
            } catch {
                pages.append([])
                nextCursors.append(sub)
            }
        }
        let merged = FilterSearchMerge.merge(pages)
        return TimelinePage(posts: merged, cursor: CompositeCursor(cursors: nextCursors).encoded())
    }
}
```

- [ ] **Step 2:** 中間ビルドは未配線のため失敗してよい（Task 8 で検証）。

---

## Task 7: `WorkspaceModel`/`FilterTab`/配線（app）

**Files:**
- Modify: `apps/macos/Workspace/WorkspaceModel.swift`（`FilterTab` と CRUD・`makeFilterModel` 型）
- Modify: `apps/macos/Views/RootView.swift`（`makeFilterModel` の中身）
- Modify: `apps/macos/Views/MainWindowView.swift`（filter の `.id`）

- [ ] **Step 1: `FilterTab` と `WorkspaceModel` の該当部を差し替え**

`WorkspaceModel.swift` の `FilterTab` クラス全体を以下に置換:

```swift
/// One filter tab: a saved structured search. `id` mirrors the backing
/// `SavedFilter.id`; it owns a `TimelineViewModel` whose loader runs the filter's
/// expanded subqueries, reusing the timeline machinery unchanged. Editing relabels
/// and, when the expanded queries change, rebuilds the model.
@MainActor
final class FilterTab: Identifiable {
    let id: UUID
    private(set) var title: String
    private(set) var filter: SavedFilter
    private(set) var model: TimelineViewModel
    private let makeModel: @MainActor (SavedFilter) -> TimelineViewModel

    init(filter: SavedFilter, makeModel: @escaping @MainActor (SavedFilter) -> TimelineViewModel) {
        self.id = filter.id
        self.title = filter.name
        self.filter = filter
        self.makeModel = makeModel
        self.model = makeModel(filter)
    }

    /// A stable key over the expanded query content, so the view reloads only when
    /// the actual search changes (not on a pure rename).
    var contentKey: String {
        filter.subqueries.joined(separator: "\u{1}") + "|" + filter.combinator.rawValue
    }

    /// One-line summary for the sidebar meta row.
    var summary: String {
        switch filter.combinator {
        case .and: return filter.subqueries.first ?? ""
        case .or: return "OR: " + filter.subqueries.joined(separator: ", ")
        }
    }

    /// Apply an edited filter: relabel, and if the expanded queries changed rebuild
    /// the model so the next appearance loads the new search.
    func apply(_ edited: SavedFilter) {
        let queriesChanged = edited.subqueries != filter.subqueries
        title = edited.name
        filter = edited
        if queriesChanged {
            model = makeModel(edited)
        }
    }
}
```

In `WorkspaceModel`, change the `makeFilterModel` property type and the `addFilter` method:

```swift
    private let makeFilterModel: @MainActor (SavedFilter) -> TimelineViewModel
```

```swift
    init(
        filterStore: SavedFilterStore,
        makeThreadModel: @escaping @MainActor (String) -> ThreadViewModel,
        makeFilterModel: @escaping @MainActor (SavedFilter) -> TimelineViewModel
    ) {
        self.filterStore = filterStore
        self.makeThreadModel = makeThreadModel
        self.makeFilterModel = makeFilterModel
        self.filters = filterStore.filters.map { FilterTab(filter: $0, makeModel: makeFilterModel) }
    }
```

```swift
    /// Create a filter from typed terms, append its tab, and select it. No-op when
    /// the terms expand to no usable query (the store rejects it).
    func addFilter(name: String, terms: [FilterTerm], combinator: FilterCombinator) {
        guard let saved = filterStore.add(name: name, terms: terms, combinator: combinator) else { return }
        let tab = FilterTab(filter: saved, makeModel: makeFilterModel)
        filters.append(tab)
        selection = .filter(tab.id)
    }
```

(`updateFilter`/`removeFilter`/`filter(id:)`/`savedFilter(id:)` are unchanged — `apply` now takes the full edited filter, which `updateFilter` already passes.)

- [ ] **Step 2: `RootView` の `makeFilterModel` 差し替え**

In `apps/macos/Views/RootView.swift`, inside `AuthenticatedRootView.init`, change the `makeFilterModel` closure:

```swift
                makeFilterModel: { filter in
                    TimelineViewModel(loader: LiveSearchLoader(accountManager: accountManager, subqueries: filter.subqueries))
                }
```

- [ ] **Step 3: `MainWindowView` の filter `.id` 差し替え**

In `apps/macos/Views/MainWindowView.swift`, the `.filter(id)` case: replace `.id("\(id)-\(tab.query)")` with:

```swift
                .id("\(id)-\(tab.contentKey)")
```

- [ ] **Step 4:** 中間ビルドは未完のため失敗してよい（Task 8 で検証）。

---

## Task 8: `FilterEditorView` 作り直し + サイドバー要約 + 一括検証（app）

**Files:**
- Modify (全置換): `apps/macos/Views/FilterEditorView.swift`
- Modify: `apps/macos/Views/SidebarView.swift`（editor 呼び出しと filter 行の meta）

- [ ] **Step 1: `FilterEditorView.swift` を全置換**

```swift
import SwiftUI
import YoruMimizukuKit

/// Sheet for creating or editing a structured filter: a name, an AND/OR selector,
/// and a list of typed condition rows (keyword / user / hashtag / mention). Save is
/// disabled until at least one row expands to a usable query. The caller decides
/// whether the submitted values create a new filter or update an existing one.
struct FilterEditorView: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss

    let isEditing: Bool
    let onSubmit: (_ name: String, _ terms: [FilterTerm], _ combinator: FilterCombinator) -> Void

    @State private var name: String
    @State private var combinator: FilterCombinator
    @State private var terms: [FilterTerm]

    init(
        name: String,
        terms: [FilterTerm],
        combinator: FilterCombinator,
        isEditing: Bool,
        onSubmit: @escaping (String, [FilterTerm], FilterCombinator) -> Void
    ) {
        self.isEditing = isEditing
        self.onSubmit = onSubmit
        _name = State(initialValue: name)
        _combinator = State(initialValue: combinator)
        // Always show at least one editable row.
        _terms = State(initialValue: terms.isEmpty ? [FilterTerm(kind: .keyword, value: "")] : terms)
    }

    private var canSave: Bool {
        !SavedFilter(name: "", terms: terms, combinator: combinator).subqueries.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isEditing ? "フィルターを編集" : "フィルターを追加")
                .font(.headline)
                .foregroundStyle(theme.primaryText)

            VStack(alignment: .leading, spacing: 6) {
                Text("名前").font(.caption).foregroundStyle(theme.secondaryText)
                TextField("例: Swift界隈", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            Picker("結合", selection: $combinator) {
                Text("すべて満たす（AND）").tag(FilterCombinator.and)
                Text("いずれか（OR）").tag(FilterCombinator.or)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 8) {
                Text("条件").font(.caption).foregroundStyle(theme.secondaryText)
                ForEach($terms) { $term in
                    HStack(spacing: 8) {
                        Picker("種別", selection: $term.kind) {
                            Text("キーワード").tag(FilterTermKind.keyword)
                            Text("ユーザー").tag(FilterTermKind.user)
                            Text("ハッシュタグ").tag(FilterTermKind.hashtag)
                            Text("メンション").tag(FilterTermKind.mention)
                        }
                        .labelsHidden()
                        .frame(width: 130)

                        TextField(placeholder(for: term.kind), text: $term.value)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            terms.removeAll { $0.id == term.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.tertiaryText)
                        .disabled(terms.count <= 1)
                    }
                }

                Button {
                    terms.append(FilterTerm(kind: .keyword, value: ""))
                } label: {
                    Label("条件を追加", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.accent)
                .padding(.top, 2)
            }

            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                Button(isEditing ? "保存" : "追加") {
                    onSubmit(name, terms, combinator)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 460)
        .background(theme.background)
    }

    private func placeholder(for kind: FilterTermKind) -> String {
        switch kind {
        case .keyword: return "キーワード"
        case .user: return "alice.bsky.social"
        case .hashtag: return "swift"
        case .mention: return "bob.bsky.social"
        }
    }
}
```

- [ ] **Step 2: `SidebarView.swift` の editor 呼び出しと meta を更新**

`editor(for:)` を以下に置換:

```swift
    @ViewBuilder
    private func editor(for request: EditorRequest) -> some View {
        switch request {
        case .new:
            FilterEditorView(name: "", terms: [], combinator: .and, isEditing: false) { name, terms, combinator in
                workspace.addFilter(name: name, terms: terms, combinator: combinator)
            }
        case let .edit(filter):
            FilterEditorView(name: filter.name, terms: filter.terms, combinator: filter.combinator, isEditing: true) { name, terms, combinator in
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let candidate = SavedFilter(id: filter.id, name: trimmed, terms: terms, combinator: combinator, createdAt: filter.createdAt)
                let resolvedName = trimmed.isEmpty
                    ? candidate.subqueries.joined(separator: combinator == .or ? " | " : " ")
                    : trimmed
                workspace.updateFilter(
                    SavedFilter(id: filter.id, name: resolvedName, terms: terms, combinator: combinator, createdAt: filter.createdAt)
                )
            }
        }
    }
```

In the filter-row `ForEach(workspace.filters)`, change the `SidebarRow`'s `meta:` argument from `tab.query` to `tab.summary`:

```swift
                SidebarRow(
                    icon: "line.3.horizontal.decrease",
                    title: tab.title,
                    meta: tab.summary,
                    isSelected: workspace.selection == .filter(tab.id),
                    onClose: { workspace.removeFilter(id: tab.id) },
                    onEdit: {
                        if let saved = workspace.savedFilter(id: tab.id) {
                            editorRequest = .edit(saved)
                        }
                    }
                ) { workspace.selection = .filter(tab.id) }
```

- [ ] **Step 3: プロジェクト再生成 + ビルド**

Run: `cd .worktrees/feature/structured-filters && xcodegen generate && xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj -destination 'platform=macOS' -quiet`
Expected: ビルド成功（エラーなし）。コンパイルエラーが出たら、`EditorRequest` の `SavedFilter` 参照や `FilterTerm` import（`SidebarView` は `import YoruMimizukuKit` 済み）を確認して最小修正。

- [ ] **Step 4: コア全テストの再確認**

Run: `cd .worktrees/feature/structured-filters/core && swift test`
Expected: すべて PASS。

- [ ] **Step 5: app 層（Task 6〜8）を 1 コミット**

```bash
git -C .worktrees/feature/structured-filters add \
  apps/macos/Timeline/LiveSearchLoader.swift \
  apps/macos/Workspace/WorkspaceModel.swift \
  apps/macos/Views/RootView.swift \
  apps/macos/Views/MainWindowView.swift \
  apps/macos/Views/FilterEditorView.swift \
  apps/macos/Views/SidebarView.swift
git -C .worktrees/feature/structured-filters ai-commit --context "Wire structured filter UI: typed condition rows with AND/OR editor, OR client-side merge loader, and sidebar summary"
```

- [ ] **Step 6: 動作確認（手動・GUI）**
  1. `+` → 名前・AND/OR・条件行（種別+値）を入力、`条件を追加` で行追加、`-` で削除。
  2. OR で複数ユーザーを入れて union が時系列で出る／末尾スクロールで各条件の続きが読める。
  3. AND で `#hashtag` + `from:user` の絞り込みが効く。
  4. 編集でクエリ変更→再ロード、名前のみ変更→再ロードされない（contentKey 据え置き）。
  5. 旧フィルター（単一クエリ）が起動時にそのまま keyword 1行の AND として復元される。

---

## Self-Review（spec 突き合わせ）

- 型付き条件行（keyword/user/hashtag/mention）→ Task 1 モデル + Task 8 エディタ。✓
- AND/OR ラジオ → Task 8 segmented Picker、`subqueries`（Task 2）で分岐。✓
- OR の client-side 時系列マージ + 無限スクロール（複合カーソル）→ Task 3 + Task 6。✓
- 旧 `{query}` 移行 → Task 1 カスタム Decodable。✓
- `sort=latest` → Task 5 + Task 6。✓
- 永続化（DID 単位・ポート）→ 既存 `SavedFilterStore`/`FilterFileStore` 流用、`add` のみ更新（Task 4）。✓
- 既定 AND → Task 8 初期値 `.and` / store fallback。✓

**型整合チェック:** `SavedFilter(id:name:terms:combinator:createdAt:)`（Task 1）/ `subqueries`（Task 2）/ `CompositeCursor` + `FilterSearchMerge.merge`（Task 3）/ `SavedFilterStore.add(name:terms:combinator:)`（Task 4）/ `searchPosts(...,sort:)`（Task 5）/ `LiveSearchLoader(accountManager:subqueries:)`（Task 6）/ `makeFilterModel: (SavedFilter)->TimelineViewModel`・`FilterTab.contentKey`/`summary`（Task 7）/ `FilterEditorView(name:terms:combinator:isEditing:onSubmit:)`・`addFilter(name:terms:combinator:)`（Task 8）— 定義と参照が一致。✓

**既知の制約:** OR の各サブクエリは `limit=25` で取得しマージするため、画面1ページ内の総件数は条件数×25 が上限の目安。部分失敗のサブクエリは初回ページで cursor を失い再試行されない（v1 割り切り）。

## Execution Handoff

**1. Subagent-Driven（推奨）** / **2. Inline Execution** のどちらで実装するか。