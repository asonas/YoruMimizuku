# Filter Tabs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS 版に「フィルタータブ」を追加する。保存した `searchPosts` クエリ（ハッシュタグ/ユーザー名等）をサイドバーのタブとして購読し、ホーム同様に定期更新で読めるようにする。

**Architecture:** `BlueskyCore` に `searchPosts`（`SearchService` + `SearchResponse`）を追加。`YoruMimizukuKit` に値型 `SavedFilter` と CRUD/永続化を担う `SavedFilterStore`（ポート `SavedFilterStoring` 経由）を追加。app 側はクエリを捕捉した `LiveSearchLoader`（`TimelineLoading` 準拠）を `TimelineViewModel` に注入して再利用し、`WorkspaceModel` に `filter` タブを足し、サイドバーにフィルターセクションと `FilterEditorView` を追加する。

**Tech Stack:** Swift 6 / SwiftUI / XcodeGen / 対象 macOS 26.0。コアは `BlueskyCore`・表示ロジックは `YoruMimizukuKit`・ビューは app ターゲット `YoruMimizuku`。テストは `swift test`（`BlueskyCoreTests` / `YoruMimizukuKitTests`）。

**設計書:** `docs/superpowers/specs/2026-06-05-yorumimizuku-filter-tabs-design.md`

---

## File Structure

**BlueskyCore（コア）**
- Create: `core/Sources/BlueskyCore/Models/Search.swift` — `SearchResponse`（`posts: [PostView]` / `cursor?` / `hitsTotal?`）
- Create: `core/Sources/BlueskyCore/XRPC/SearchService.swift` — `app.bsky.feed.searchPosts` を叩く（401→refresh→1回リトライ）
- Test: `core/Tests/BlueskyCoreTests/SearchResponseTests.swift`
- Test: `core/Tests/BlueskyCoreTests/SearchServiceTests.swift`

**YoruMimizukuKit（表示ロジック）**
- Create: `core/Sources/YoruMimizukuKit/SavedFilter.swift` — 値型 `SavedFilter`
- Create: `core/Sources/YoruMimizukuKit/SavedFilterStore.swift` — `SavedFilterStoring` ポート + `@MainActor` `SavedFilterStore`（CRUD/永続化/バリデーション）
- Test: `core/Tests/YoruMimizukuKitTests/SavedFilterStoreTests.swift`

**apps/macos（SwiftUI 配線）**
- Create: `apps/macos/Timeline/LiveSearchLoader.swift` — `query` を捕捉した `TimelineLoading`
- Create: `apps/macos/Persistence/FilterFileStore.swift` — `SavedFilterStoring` の Codable ファイル実装（DID 単位）
- Create: `apps/macos/Views/FilterEditorView.swift` — 名前 + クエリのシート（新規/編集兼用）
- Modify: `apps/macos/Workspace/WorkspaceModel.swift` — `WorkspaceTab.filter` / `FilterTab` / フィルター反映・選択・削除フォールバック・巡回
- Modify: `apps/macos/Views/SidebarView.swift` — フィルターセクション + `+` + 行の編集/削除
- Modify: `apps/macos/Views/MainWindowView.swift` — `homeFeed` を汎用 `feedView(model:title:)` 化し `.home`/`.filter` で共用
- Modify: `apps/macos/Views/RootView.swift` — `SavedFilterStore`/`FilterFileStore`/`makeSearchModel` を配線

> **テスト方針の補足:** app ターゲットには XCTest ターゲットが無い。CRUD/バリデーション等の純ロジックは `SavedFilterStore`（Kit、テスト対象）に集約し、`WorkspaceModel` はそれを `FilterTab` に反映する薄い層とする。app 層（Task 5〜10）は `swift test` の自動テスト対象外なので、各タスクは `xcodegen generate` + `xcodebuild build` の成功で検証する。

> **作業ディレクトリ:** すべてのコマンドは worktree `.worktrees/feature/filter-tabs` 内で実行する。コア系コマンドは `core/` で `swift test`、app ビルドはリポジトリルートで `xcodebuild`。コミットは `git ai-commit`（`git commit` 直接実行は禁止）。コミット本文末尾に `Co-authored-by: Cursor Agent <cursoragent@cursor.com>` を付ける（`git ai-commit` が付けない場合は `--context` で補足）。

---

## Task 1: `SearchResponse` モデル

**Files:**
- Create: `core/Sources/BlueskyCore/Models/Search.swift`
- Test: `core/Tests/BlueskyCoreTests/SearchResponseTests.swift`

`app.bsky.feed.searchPosts` のレスポンスは `posts: [postView]` / `cursor?` / `hitsTotal?`。既存 `PostView`（`Models/Timeline.swift`）をそのまま再利用する。

- [ ] **Step 1: 失敗するテストを書く**

`core/Tests/BlueskyCoreTests/SearchResponseTests.swift`:

```swift
import XCTest
@testable import BlueskyCore

final class SearchResponseTests: XCTestCase {
    private let fixture = Data(##"""
    {
      "cursor": "next-page",
      "hitsTotal": 42,
      "posts": [
        {
          "uri": "at://did:plc:alice/app.bsky.feed.post/aaa",
          "cid": "bafyreialice",
          "author": {
            "did": "did:plc:alice",
            "handle": "alice.bsky.social",
            "displayName": "Alice",
            "avatar": "https://cdn.example/alice.jpg"
          },
          "record": {
            "$type": "app.bsky.feed.post",
            "text": "hello #swift",
            "createdAt": "2026-06-04T12:00:00.000Z",
            "facets": [
              {
                "index": { "byteStart": 6, "byteEnd": 12 },
                "features": [ { "$type": "app.bsky.richtext.facet#tag", "tag": "swift" } ]
              }
            ]
          },
          "replyCount": 1,
          "repostCount": 2,
          "likeCount": 3,
          "indexedAt": "2026-06-04T12:00:01.000Z"
        }
      ]
    }
    """##.utf8)

    func testDecodesPostsCursorAndHitsTotal() throws {
        let response = try JSONDecoder().decode(SearchResponse.self, from: fixture)

        XCTAssertEqual(response.cursor, "next-page")
        XCTAssertEqual(response.hitsTotal, 42)
        XCTAssertEqual(response.posts.count, 1)
        XCTAssertEqual(response.posts[0].author.handle, "alice.bsky.social")
        XCTAssertEqual(response.posts[0].record.facets.first?.features, [.tag(tag: "swift")])
    }

    func testDecodesWithoutOptionalFields() throws {
        let json = Data(##"{ "posts": [] }"##.utf8)
        let response = try JSONDecoder().decode(SearchResponse.self, from: json)

        XCTAssertTrue(response.posts.isEmpty)
        XCTAssertNil(response.cursor)
        XCTAssertNil(response.hitsTotal)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `cd core && swift test --filter SearchResponseTests`
Expected: コンパイルエラー（`SearchResponse` 未定義）。

- [ ] **Step 3: 最小実装を書く**

`core/Sources/BlueskyCore/Models/Search.swift`:

```swift
import Foundation

/// Response of `app.bsky.feed.searchPosts`: a page of hydrated posts plus an
/// optional pagination cursor and total hit count. Only the fields YoruMimizuku
/// renders are modeled; unknown keys are ignored by `Decodable`. `PostView` is
/// shared with the timeline so the same `PostDisplay` mapper applies.
public struct SearchResponse: Decodable, Equatable, Sendable {
    public let posts: [PostView]
    public let cursor: String?
    public let hitsTotal: Int?

    public init(posts: [PostView], cursor: String? = nil, hitsTotal: Int? = nil) {
        self.posts = posts
        self.cursor = cursor
        self.hitsTotal = hitsTotal
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `cd core && swift test --filter SearchResponseTests`
Expected: PASS（2 テスト）。

- [ ] **Step 5: コミット**

```bash
git -C .worktrees/feature/filter-tabs add core/Sources/BlueskyCore/Models/Search.swift core/Tests/BlueskyCoreTests/SearchResponseTests.swift
git -C .worktrees/feature/filter-tabs ai-commit --context "Add SearchResponse model decoding posts/cursor/hitsTotal for app.bsky.feed.searchPosts"
```

---

## Task 2: `SearchService`

**Files:**
- Create: `core/Sources/BlueskyCore/XRPC/SearchService.swift`
- Test: `core/Tests/BlueskyCoreTests/SearchServiceTests.swift`

`TimelineService` と同型。`searchPosts` を DPoP-bound で取得し、`401`（nonce チャレンジでない）かつ `refreshToken` ありなら `refresh_token` で更新し1回リトライ、更新したトークンを返す。

- [ ] **Step 1: 失敗するテストを書く**

`core/Tests/BlueskyCoreTests/SearchServiceTests.swift`:

```swift
import XCTest
@testable import BlueskyCore

final class SearchServiceTests: XCTestCase {
    private let pds = URL(string: "https://pds.example")!
    private let issuer = URL(string: "https://bsky.social")!

    private static let searchBody = Data(##"""
    {
      "cursor": "next",
      "posts": [
        {
          "uri": "at://did:plc:alice/app.bsky.feed.post/aaa",
          "cid": "bafyreialice",
          "author": { "did": "did:plc:alice", "handle": "alice.bsky.social", "displayName": "Alice" },
          "record": { "$type": "app.bsky.feed.post", "text": "hi #swift", "createdAt": "2026-06-04T12:00:00.000Z" },
          "indexedAt": "2026-06-04T12:00:01.000Z"
        }
      ]
    }
    """##.utf8)

    private func makeService(http: HTTPClient) -> SearchService {
        let sender = DPoPRequestSender(http: http, proofBuilder: DPoPProofBuilder(crypto: FakeDPoPCryptoProvider()))
        return SearchService(sender: sender, metadataResolver: OAuthMetadataResolver(http: http), config: .yoruMimizuku)
    }

    func testSearchSendsAuthorizedGetWithQueryAndDecodes() async throws {
        let http = FakeHTTPClient(response: HTTPResponse(statusCode: 200, body: Self.searchBody))
        let service = makeService(http: http)

        let result = try await service.searchPosts(
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: "rtk",
            query: "#swift from:alice.bsky.social", limit: 25, cursor: nil
        )

        XCTAssertNil(result.refreshed)
        XCTAssertEqual(result.response.posts.count, 1)
        XCTAssertEqual(result.response.cursor, "next")

        let sent = try XCTUnwrap(http.sentRequests.last)
        XCTAssertEqual(sent.method, .get)
        XCTAssertTrue(
            sent.url.absoluteString.hasPrefix("https://pds.example/xrpc/app.bsky.feed.searchPosts"),
            "unexpected url: \(sent.url.absoluteString)"
        )
        // The raw query is percent-encoded into q (the '#' becomes %23).
        XCTAssertEqual(sent.url.query?.contains("q=%23swift%20from:alice.bsky.social"), true)
        XCTAssertEqual(sent.url.query?.contains("limit=25"), true)
        XCTAssertEqual(sent.headers["Authorization"], "DPoP atk")
    }

    func testSearchIncludesCursorWhenProvided() async throws {
        let http = FakeHTTPClient(response: HTTPResponse(statusCode: 200, body: Self.searchBody))
        let service = makeService(http: http)

        _ = try await service.searchPosts(
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: nil,
            query: "cats", limit: 25, cursor: "page-2"
        )

        let sent = try XCTUnwrap(http.sentRequests.last)
        XCTAssertEqual(sent.url.query?.contains("cursor=page-2"), true)
    }

    func testSearchRefreshesOnUnauthorizedAndRetries() async throws {
        let unauthorized = HTTPResponse(statusCode: 401, body: Data(##"{"error":"invalid_token"}"##.utf8))
        let metadata = HTTPResponse(statusCode: 200, body: Data(##"""
        {
          "issuer": "https://bsky.social",
          "authorization_endpoint": "https://bsky.social/oauth/authorize",
          "token_endpoint": "https://bsky.social/oauth/token"
        }
        """##.utf8))
        let tokens = HTTPResponse(statusCode: 200, body: Data(##"""
        {"access_token":"atk2","token_type":"DPoP","refresh_token":"rtk2","sub":"did:plc:alice"}
        """##.utf8))
        let search = HTTPResponse(statusCode: 200, body: Self.searchBody)
        let http = SequencedHTTPClient([unauthorized, metadata, tokens, search])
        let service = makeService(http: http)

        let result = try await service.searchPosts(
            pds: pds, issuer: issuer, accessToken: "old", refreshToken: "rtk", query: "cats"
        )

        XCTAssertEqual(result.refreshed?.accessToken, "atk2")
        XCTAssertEqual(result.response.posts.count, 1)
        XCTAssertEqual(http.sentRequests.last?.headers["Authorization"], "DPoP atk2")
    }

    func testSearchThrowsOnNonSuccessStatus() async {
        let http = FakeHTTPClient(response: HTTPResponse(statusCode: 500, body: Data("{}".utf8)))
        let service = makeService(http: http)
        do {
            _ = try await service.searchPosts(
                pds: pds, issuer: issuer, accessToken: "atk", refreshToken: nil, query: "cats"
            )
            XCTFail("expected error")
        } catch let error as XRPCError {
            XCTAssertEqual(error, .requestFailed(status: 500, body: nil))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `cd core && swift test --filter SearchServiceTests`
Expected: コンパイルエラー（`SearchService` 未定義）。

- [ ] **Step 3: 最小実装を書く**

`core/Sources/BlueskyCore/XRPC/SearchService.swift`（`TimelineService` を踏襲）:

```swift
import Foundation

/// Fetches search results (`app.bsky.feed.searchPosts`) from the account's PDS
/// over a DPoP-bound channel. Mirrors `TimelineService`: the injected
/// `DPoPRequestSender` carries the access token and handles the `use_dpop_nonce`
/// retry; on an expired access token (a 401 that is not a nonce challenge) it
/// refreshes via `refresh_token` and retries once, returning the freshly issued
/// tokens so the caller can persist them.
public struct SearchService: Sendable {
    private let sender: DPoPRequestSender
    private let metadataResolver: OAuthMetadataResolver
    private let config: OAuthClientConfig

    public init(
        sender: DPoPRequestSender,
        metadataResolver: OAuthMetadataResolver,
        config: OAuthClientConfig
    ) {
        self.sender = sender
        self.metadataResolver = metadataResolver
        self.config = config
    }

    /// Fetch a page of search results for `query`. Returns the decoded response
    /// and, when a refresh occurred, the freshly issued tokens (nil otherwise).
    public func searchPosts(
        pds: URL,
        issuer: URL,
        accessToken: String,
        refreshToken: String?,
        query: String,
        limit: Int = 25,
        cursor: String? = nil
    ) async throws -> (response: SearchResponse, refreshed: TokenResponse?) {
        let url = try Self.searchURL(pds: pds, query: query, limit: limit, cursor: cursor)
        let response = try await fetch(url: url, accessToken: accessToken)

        if response.statusCode == 401,
           !DPoPRequestSender.isNonceChallenge(response),
           let refreshToken {
            let tokens = try await refresh(issuer: issuer, refreshToken: refreshToken)
            let retried = try await fetch(url: url, accessToken: tokens.accessToken)
            return (try Self.decode(retried), tokens)
        }

        return (try Self.decode(response), nil)
    }

    private func fetch(url: URL, accessToken: String) async throws -> HTTPResponse {
        try await sender.send(
            method: .get, url: url, accessToken: accessToken,
            headers: ["Accept": "application/json"]
        )
    }

    private func refresh(issuer: URL, refreshToken: String) async throws -> TokenResponse {
        let metadata = try await metadataResolver.authorizationServer(issuer: issuer)
        return try await TokenService(sender: sender).requestToken(
            metadata: metadata, config: config, grant: .refresh(refreshToken: refreshToken)
        )
    }

    static func searchURL(pds: URL, query: String, limit: Int, cursor: String?) throws -> URL {
        let endpoint = pds.appendingPathComponent("xrpc/app.bsky.feed.searchPosts")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw XRPCError.invalidURL("app.bsky.feed.searchPosts")
        }
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        components.queryItems = items
        guard let url = components.url else {
            throw XRPCError.invalidURL("app.bsky.feed.searchPosts")
        }
        return url
    }

    static func decode(_ response: HTTPResponse) throws -> SearchResponse {
        guard response.statusCode == 200 else {
            let errorBody = try? JSONDecoder().decode(XRPCErrorResponse.self, from: response.body)
            throw XRPCError.requestFailed(status: response.statusCode, body: errorBody)
        }
        do {
            return try JSONDecoder().decode(SearchResponse.self, from: response.body)
        } catch {
            throw XRPCError.decodingFailed(String(describing: error))
        }
    }
}
```

> **注意:** `q` のエンコードは `URLQueryItem` が担う。`URLComponents` の既定では `+` がそのまま通るが、`searchPosts` のクエリ用途では実害がないため v1 は既定エンコードのままとする（テストの期待値 `q=%23swift%20from:...` は `URLComponents` の標準出力に一致）。

- [ ] **Step 4: テストが通ることを確認**

Run: `cd core && swift test --filter SearchServiceTests`
Expected: PASS（4 テスト）。

- [ ] **Step 5: 全コアテストが緑であることを確認**

Run: `cd core && swift test`
Expected: 既存テスト含めすべて PASS。

- [ ] **Step 6: コミット**

```bash
git -C .worktrees/feature/filter-tabs add core/Sources/BlueskyCore/XRPC/SearchService.swift core/Tests/BlueskyCoreTests/SearchServiceTests.swift
git -C .worktrees/feature/filter-tabs ai-commit --context "Add SearchService for app.bsky.feed.searchPosts with DPoP auth and refresh-retry, mirroring TimelineService"
```

---

## Task 3: `SavedFilter` 値型

**Files:**
- Create: `core/Sources/YoruMimizukuKit/SavedFilter.swift`
- Test: `core/Tests/YoruMimizukuKitTests/SavedFilterStoreTests.swift`（このタスクでファイルを作り、最初のテストだけ書く。Task 4 で追記）

- [ ] **Step 1: 失敗するテストを書く**

`core/Tests/YoruMimizukuKitTests/SavedFilterStoreTests.swift`:

```swift
import XCTest
@testable import YoruMimizukuKit

final class SavedFilterStoreTests: XCTestCase {
    func testSavedFilterIsCodableRoundTrips() throws {
        let filter = SavedFilter(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Swift",
            query: "#swift",
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        let data = try JSONEncoder().encode(filter)
        let decoded = try JSONDecoder().decode(SavedFilter.self, from: data)
        XCTAssertEqual(decoded, filter)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `cd core && swift test --filter SavedFilterStoreTests`
Expected: コンパイルエラー（`SavedFilter` 未定義）。

- [ ] **Step 3: 最小実装を書く**

`core/Sources/YoruMimizukuKit/SavedFilter.swift`:

```swift
import Foundation

/// A saved search subscribed as a sidebar tab. `query` is the raw
/// `app.bsky.feed.searchPosts` query (e.g. `#swift from:alice.bsky.social`);
/// `name` is the user-facing tab label. A pure value type so it can later be
/// synced verbatim (e.g. via iCloud) without UI/OS coupling.
public struct SavedFilter: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var query: String
    public let createdAt: Date

    public init(id: UUID = UUID(), name: String, query: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.query = query
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `cd core && swift test --filter SavedFilterStoreTests`
Expected: PASS（1 テスト）。

- [ ] **Step 5: コミット**

```bash
git -C .worktrees/feature/filter-tabs add core/Sources/YoruMimizukuKit/SavedFilter.swift core/Tests/YoruMimizukuKitTests/SavedFilterStoreTests.swift
git -C .worktrees/feature/filter-tabs ai-commit --context "Add SavedFilter value type for persisted search-filter tabs"
```

---

## Task 4: `SavedFilterStoring` ポート + `SavedFilterStore`

**Files:**
- Create: `core/Sources/YoruMimizukuKit/SavedFilterStore.swift`
- Test: `core/Tests/YoruMimizukuKitTests/SavedFilterStoreTests.swift`（追記）

`SavedFilterStore` は `@MainActor ObservableObject`。フィルター配列を保持し、CRUD のたびにポート `SavedFilterStoring.save` を呼ぶ。`add` は空白のみのクエリ/名前を拒否し、名前が空なら query を表示名に使う。`load` 失敗時は空で開始。

- [ ] **Step 1: 失敗するテストを追記**

`core/Tests/YoruMimizukuKitTests/SavedFilterStoreTests.swift` に以下を追記（先頭の `import` はそのまま、クラス内にメソッド追加 + ファイル末尾にフェイクを追加）:

```swift
    // MARK: - Store

    @MainActor
    func testLoadsExistingFiltersFromPort() {
        let existing = SavedFilter(name: "Swift", query: "#swift")
        let port = InMemoryFilterStoring(initial: [existing])
        let store = SavedFilterStore(port: port)
        XCTAssertEqual(store.filters, [existing])
    }

    @MainActor
    func testAddAppendsAndPersists() throws {
        let port = InMemoryFilterStoring()
        let store = SavedFilterStore(port: port)

        let added = try XCTUnwrap(store.add(name: "Cats", query: "cats"))

        XCTAssertEqual(store.filters.map(\.id), [added.id])
        XCTAssertEqual(port.saved.last?.map(\.id), [added.id])
    }

    @MainActor
    func testAddRejectsBlankQuery() {
        let port = InMemoryFilterStoring()
        let store = SavedFilterStore(port: port)

        XCTAssertNil(store.add(name: "Empty", query: "   "))
        XCTAssertTrue(store.filters.isEmpty)
        XCTAssertTrue(port.saved.isEmpty)
    }

    @MainActor
    func testAddUsesQueryAsNameWhenNameBlank() throws {
        let port = InMemoryFilterStoring()
        let store = SavedFilterStore(port: port)

        let added = try XCTUnwrap(store.add(name: "  ", query: "#swift"))
        XCTAssertEqual(added.name, "#swift")
    }

    @MainActor
    func testUpdateReplacesByIdAndPersists() throws {
        let original = SavedFilter(name: "Swift", query: "#swift")
        let port = InMemoryFilterStoring(initial: [original])
        let store = SavedFilterStore(port: port)

        var edited = original
        edited.name = "Swift Lang"
        edited.query = "#swiftlang"
        store.update(edited)

        XCTAssertEqual(store.filters.first?.name, "Swift Lang")
        XCTAssertEqual(store.filters.first?.query, "#swiftlang")
        XCTAssertEqual(port.saved.last?.first?.query, "#swiftlang")
    }

    @MainActor
    func testRemoveDeletesByIdAndPersists() {
        let a = SavedFilter(name: "A", query: "a")
        let b = SavedFilter(name: "B", query: "b")
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

/// In-memory `SavedFilterStoring` fake recording every `save` so tests can assert
/// that mutations persisted. `loadError` simulates a corrupt/missing store file.
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

> 注: Task 3 で書いた `testSavedFilterIsCodableRoundTrips` の閉じ `}`（クラス終端）は、この追記でメソッド群とフェイクを差し込むため**置き換える**こと。最終的にクラスは `}` で閉じ、その後に `private final class InMemoryFilterStoring` が続く。

- [ ] **Step 2: テストが失敗することを確認**

Run: `cd core && swift test --filter SavedFilterStoreTests`
Expected: コンパイルエラー（`SavedFilterStore` / `SavedFilterStoring` 未定義）。

- [ ] **Step 3: 最小実装を書く**

`core/Sources/YoruMimizukuKit/SavedFilterStore.swift`:

```swift
import Foundation

/// Persistence port for saved filters. The app injects a concrete store
/// (currently a per-account Codable file); a future iCloud-backed implementation
/// can be swapped in without touching `SavedFilterStore`. Synchronous because the
/// backing stores are local and small.
public protocol SavedFilterStoring: Sendable {
    func load() throws -> [SavedFilter]
    func save(_ filters: [SavedFilter]) throws
}

/// Holds the user's saved filters and persists every mutation through the
/// injected port. `@MainActor` because it is bound to SwiftUI. CRUD is small and
/// synchronous; persistence failures are swallowed (filters are user preferences,
/// not critical state) but logged via the returned value being unaffected.
@MainActor
public final class SavedFilterStore: ObservableObject {
    @Published public private(set) var filters: [SavedFilter]

    private let port: SavedFilterStoring

    public init(port: SavedFilterStoring) {
        self.port = port
        self.filters = (try? port.load()) ?? []
    }

    /// Append a new filter. Returns nil (and does nothing) when the query is blank
    /// after trimming. A blank name falls back to the query as the label.
    @discardableResult
    public func add(name: String, query: String) -> SavedFilter? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let filter = SavedFilter(
            name: trimmedName.isEmpty ? trimmedQuery : trimmedName,
            query: trimmedQuery
        )
        filters.append(filter)
        persist()
        return filter
    }

    /// Replace the filter sharing `edited.id` (no-op if absent), then persist.
    public func update(_ edited: SavedFilter) {
        guard let index = filters.firstIndex(where: { $0.id == edited.id }) else { return }
        filters[index] = edited
        persist()
    }

    /// Remove the filter with `id` (no-op if absent), then persist.
    public func remove(id: SavedFilter.ID) {
        let before = filters.count
        filters.removeAll { $0.id == id }
        if filters.count != before { persist() }
    }

    private func persist() {
        try? port.save(filters)
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `cd core && swift test --filter SavedFilterStoreTests`
Expected: PASS（8 テスト）。

- [ ] **Step 5: 全コアテストが緑であることを確認**

Run: `cd core && swift test`
Expected: すべて PASS。

- [ ] **Step 6: コミット**

```bash
git -C .worktrees/feature/filter-tabs add core/Sources/YoruMimizukuKit/SavedFilterStore.swift core/Tests/YoruMimizukuKitTests/SavedFilterStoreTests.swift
git -C .worktrees/feature/filter-tabs ai-commit --context "Add SavedFilterStore with CRUD, blank-query validation, and port-based persistence"
```

---

## Task 5: `LiveSearchLoader`（app）

**Files:**
- Create: `apps/macos/Timeline/LiveSearchLoader.swift`

`LiveTimelineLoader` と同型。`query` を捕捉し `TimelineLoading` に準拠。これを `TimelineViewModel` に注入すればフィルタータブのフィードが成立する。

- [ ] **Step 1: 実装を書く**

`apps/macos/Timeline/LiveSearchLoader.swift`:

```swift
import Foundation
import os
import BlueskyCore
import YoruMimizukuKit
import PlatformApple

/// Live `TimelineLoading` for a saved filter: wires the real `SearchService`
/// through a `LiveServiceContext`, fetches a page of search results for the
/// captured `query` (passing the cursor for infinite scroll), persists any
/// refreshed tokens, and maps the posts into `PostDisplay` rows. Lets each filter
/// tab reuse `TimelineViewModel` unchanged.
struct LiveSearchLoader: TimelineLoading {
    let accountManager: AccountManager
    let query: String
    let config: OAuthClientConfig

    init(accountManager: AccountManager, query: String, config: OAuthClientConfig = .yoruMimizuku) {
        self.accountManager = accountManager
        self.query = query
        self.config = config
    }

    func loadPage(cursor: String?) async throws -> TimelinePage {
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
            cursor: cursor
        )

        try context.persist(result.refreshed)

        let posts = result.response.posts.map { PostDisplay(postView: $0) }
        return TimelinePage(posts: posts, cursor: result.response.cursor)
    }
}
```

- [ ] **Step 2: ビルド確認（Task 6 までまとめて検証してもよいが、ここで型を固める）**

Run: `cd .worktrees/feature/filter-tabs && xcodegen generate && xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj -destination 'platform=macOS' -quiet`
Expected: ビルド成功（このファイルはまだ未参照だが、コンパイル対象に含まれる）。

- [ ] **Step 3: コミット**

```bash
git -C .worktrees/feature/filter-tabs add apps/macos/Timeline/LiveSearchLoader.swift
git -C .worktrees/feature/filter-tabs ai-commit --context "Add LiveSearchLoader wiring SearchService into TimelineLoading for filter tabs"
```

---

## Task 6: `FilterFileStore`（app）

**Files:**
- Create: `apps/macos/Persistence/FilterFileStore.swift`

`SavedFilterStoring` の Apple 実装。`~/Library/Application Support/<bundle>/filters-<DID>.json` に Codable で読み書き。

- [ ] **Step 1: 実装を書く**

`apps/macos/Persistence/FilterFileStore.swift`:

```swift
import Foundation
import YoruMimizukuKit

/// File-backed `SavedFilterStoring`: persists a single account's filters to
/// `~/Library/Application Support/<bundle>/filters-<DID>.json`. The DID-scoped
/// filename keeps each signed-in account's filters separate. A future iCloud
/// store can replace this without touching `SavedFilterStore`.
struct FilterFileStore: SavedFilterStoring {
    let did: String
    private let directory: URL

    init(did: String, fileManager: FileManager = .default) {
        self.did = did
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )) ?? fileManager.temporaryDirectory
        self.directory = base.appendingPathComponent("as.ason.YoruMimizuku", isDirectory: true)
    }

    private var fileURL: URL {
        // DIDs contain ':' which is fine in a path component on APFS, but encode
        // it defensively so the filename stays portable.
        let safe = did.replacingOccurrences(of: ":", with: "_")
        return directory.appendingPathComponent("filters-\(safe).json")
    }

    func load() throws -> [SavedFilter] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([SavedFilter].self, from: data)
    }

    func save(_ filters: [SavedFilter]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(filters)
        try data.write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 2: ビルド確認**

Run: `cd .worktrees/feature/filter-tabs && xcodegen generate && xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj -destination 'platform=macOS' -quiet`
Expected: ビルド成功。

- [ ] **Step 3: コミット**

```bash
git -C .worktrees/feature/filter-tabs add apps/macos/Persistence/FilterFileStore.swift
git -C .worktrees/feature/filter-tabs ai-commit --context "Add FilterFileStore persisting filters per account DID under Application Support"
```

---

## Task 7: `WorkspaceModel` にフィルタータブ機構を追加（app）

**Files:**
- Modify: `apps/macos/Workspace/WorkspaceModel.swift`

`WorkspaceTab` に `.filter(UUID)` を追加、`FilterTab`（`TimelineViewModel` 所有）を新設、`SavedFilterStore` を保持して CRUD を委譲、`orderedTabs`/巡回/削除フォールバックに反映する。

- [ ] **Step 1: ファイル全体を以下に置き換える**

`apps/macos/Workspace/WorkspaceModel.swift`:

```swift
import Foundation
import YoruMimizukuKit

/// Identifies a vertical tab in the sidebar. `home` and `notifications` are pinned
/// and always present; `filter` is a saved-search subscription; each
/// `conversation` is a closable reply-thread tab.
enum WorkspaceTab: Hashable {
    case home
    case notifications
    case filter(UUID)
    case conversation(UUID)
}

/// One conversation tab: anchored on a post URI, it owns the `ThreadViewModel`
/// that fetches that post and its immediate parent so the tree can be climbed.
@MainActor
final class ConversationTab: Identifiable {
    let id = UUID()
    let anchorID: String
    let title: String
    let handle: String
    let subtitle: String
    let model: ThreadViewModel

    init(anchor: PostDisplay, model: ThreadViewModel) {
        self.anchorID = anchor.id
        let trimmedName = anchor.authorDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = trimmedName.isEmpty ? "@\(anchor.authorHandle)" : trimmedName
        self.handle = "@\(anchor.authorHandle)"
        self.subtitle = anchor.body.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model
    }
}

/// One filter tab: a saved search subscription. `id` mirrors the backing
/// `SavedFilter.id`; it owns a `TimelineViewModel` whose loader runs the search
/// query, so the existing timeline machinery (polling, infinite scroll) is reused
/// unchanged. Editing relabels and, when the query changes, rebuilds the model.
@MainActor
final class FilterTab: Identifiable {
    let id: UUID
    private(set) var title: String
    private(set) var query: String
    private(set) var model: TimelineViewModel
    private let makeModel: @MainActor (String) -> TimelineViewModel

    init(filter: SavedFilter, makeModel: @escaping @MainActor (String) -> TimelineViewModel) {
        self.id = filter.id
        self.title = filter.name
        self.query = filter.query
        self.makeModel = makeModel
        self.model = makeModel(filter.query)
    }

    /// Apply an edited filter: relabel, and if the query changed rebuild the model
    /// so the next appearance loads the new search.
    func apply(_ filter: SavedFilter) {
        title = filter.name
        if filter.query != query {
            query = filter.query
            model = makeModel(filter.query)
        }
    }
}

/// Holds the sidebar's tab state: the pinned home/notifications tabs, the saved
/// filter tabs (persisted via `SavedFilterStore`), and an ordered list of
/// conversation tabs. Opening a post's parent appends a conversation; closing a
/// tab falls back to a neighbor of the same kind, otherwise home.
@MainActor
final class WorkspaceModel: ObservableObject {
    @Published private(set) var filters: [FilterTab] = []
    @Published private(set) var conversations: [ConversationTab] = []
    @Published var selection: WorkspaceTab = .home

    let filterStore: SavedFilterStore
    private let makeThreadModel: @MainActor (String) -> ThreadViewModel
    private let makeFilterModel: @MainActor (String) -> TimelineViewModel

    init(
        filterStore: SavedFilterStore,
        makeThreadModel: @escaping @MainActor (String) -> ThreadViewModel,
        makeFilterModel: @escaping @MainActor (String) -> TimelineViewModel
    ) {
        self.filterStore = filterStore
        self.makeThreadModel = makeThreadModel
        self.makeFilterModel = makeFilterModel
        self.filters = filterStore.filters.map { FilterTab(filter: $0, makeModel: makeFilterModel) }
    }

    // MARK: - Filters

    /// Create a filter from raw name/query, append its tab, and select it. No-op
    /// when the query is blank (the store rejects it).
    func addFilter(name: String, query: String) {
        guard let saved = filterStore.add(name: name, query: query) else { return }
        let tab = FilterTab(filter: saved, makeModel: makeFilterModel)
        filters.append(tab)
        selection = .filter(tab.id)
    }

    /// Persist an edited filter and reflect it in its tab (relabel / model swap).
    func updateFilter(_ edited: SavedFilter) {
        filterStore.update(edited)
        guard let tab = filters.first(where: { $0.id == edited.id }) else { return }
        tab.apply(edited)
        filters = filters  // republish so the sidebar picks up the relabel
    }

    /// Delete a filter tab. When the closed tab was selected, select the adjacent
    /// filter if any, otherwise fall back to home.
    func removeFilter(id: UUID) {
        let wasSelected = selection == .filter(id)
        let index = filters.firstIndex { $0.id == id }
        filterStore.remove(id: id)
        filters.removeAll { $0.id == id }

        guard wasSelected else { return }
        if let index, !filters.isEmpty {
            selection = .filter(filters[min(index, filters.count - 1)].id)
        } else {
            selection = .home
        }
    }

    func filter(id: UUID) -> FilterTab? { filters.first { $0.id == id } }

    /// The backing `SavedFilter` for an id (for the editor); nil if absent.
    func savedFilter(id: UUID) -> SavedFilter? { filterStore.filters.first { $0.id == id } }

    // MARK: - Conversations

    func openConversation(_ post: PostDisplay) {
        if let existing = conversations.first(where: { $0.anchorID == post.id }) {
            selection = .conversation(existing.id)
            return
        }
        let tab = ConversationTab(anchor: post, model: makeThreadModel(post.id))
        conversations.append(tab)
        selection = .conversation(tab.id)
    }

    func closeConversation(_ id: UUID) {
        let wasSelected = selection == .conversation(id)
        let index = conversations.firstIndex { $0.id == id }
        conversations.removeAll { $0.id == id }

        guard wasSelected else { return }
        if let index, !conversations.isEmpty {
            selection = .conversation(conversations[min(index, conversations.count - 1)].id)
        } else {
            selection = .home
        }
    }

    func conversation(id: UUID) -> ConversationTab? {
        conversations.first { $0.id == id }
    }

    // MARK: - Cycling

    /// All tabs in display order: the two pinned tabs, the filters, then the open
    /// conversations. Drives the Cmd-Shift-J/K cycling shortcuts.
    var orderedTabs: [WorkspaceTab] {
        [.home, .notifications]
            + filters.map { .filter($0.id) }
            + conversations.map { .conversation($0.id) }
    }

    func selectNextTab() { cycleSelection(by: 1) }
    func selectPreviousTab() { cycleSelection(by: -1) }

    private func cycleSelection(by offset: Int) {
        let tabs = orderedTabs
        guard let index = tabs.firstIndex(of: selection) else {
            selection = .home
            return
        }
        selection = tabs[(index + offset + tabs.count) % tabs.count]
    }
}
```

- [ ] **Step 2: ビルドはまだ通らない（`RootView` の `WorkspaceModel(...)` 呼び出しが旧シグネチャ）。Task 10 でまとめて配線・検証するため、ここでは型整合の確認に留める。**

このタスク単体ではコミットせず、Task 8〜10 と合わせて段階的にコミットする。`WorkspaceModel` は Task 8（Sidebar）/ Task 9（MainWindow）/ Task 10（RootView）から参照されるため、**Task 7〜10 を実装し終えてから** `xcodegen generate` + `xcodebuild build` で一括検証する。

> 実装順の指針: Task 7 → 8 → 9 → 10 をこの順に編集し、Task 10 末尾で初めてビルドが通る。各ファイル編集後の中間ビルドは失敗してよい（参照未解決）。

---

## Task 8: `FilterEditorView` + `SidebarView` フィルターセクション（app）

**Files:**
- Create: `apps/macos/Views/FilterEditorView.swift`
- Modify: `apps/macos/Views/SidebarView.swift`

- [ ] **Step 1: `FilterEditorView` を作成**

`apps/macos/Views/FilterEditorView.swift`:

```swift
import SwiftUI
import YoruMimizukuKit

/// Sheet for creating or editing a saved filter: a name field and a raw
/// `searchPosts` query field. Save is disabled until the query is non-blank; a
/// blank name falls back to the query. The caller decides whether the submitted
/// name/query create a new filter or update an existing one.
struct FilterEditorView: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss

    /// Title differs for create vs edit; `existing` is only used for the heading.
    let isEditing: Bool
    /// Called with the resolved (trimmed, name-fallback-applied) name and query.
    let onSubmit: (_ name: String, _ query: String) -> Void

    @State private var name: String
    @State private var query: String

    init(name: String, query: String, isEditing: Bool, onSubmit: @escaping (String, String) -> Void) {
        self.isEditing = isEditing
        self.onSubmit = onSubmit
        _name = State(initialValue: name)
        _query = State(initialValue: query)
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedQuery.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isEditing ? "フィルターを編集" : "フィルターを追加")
                .font(.headline)
                .foregroundStyle(theme.primaryText)

            VStack(alignment: .leading, spacing: 6) {
                Text("名前").font(.caption).foregroundStyle(theme.secondaryText)
                TextField("例: Swift", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("検索クエリ").font(.caption).foregroundStyle(theme.secondaryText)
                TextField("例: #swift from:alice.bsky.social", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Text("ハッシュタグ・from:ユーザー名・キーワードなどを指定できます")
                    .font(.caption2).foregroundStyle(theme.tertiaryText)
            }

            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                Button(isEditing ? "保存" : "追加") {
                    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSubmit(trimmedName.isEmpty ? trimmedQuery : trimmedName, trimmedQuery)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(theme.background)
    }
}
```

- [ ] **Step 2: `SidebarView.swift` を以下の全文に置き換える**

`apps/macos/Views/SidebarView.swift`:

```swift
import SwiftUI
import YoruMimizukuKit

/// The cmux-style vertical tab rail: a compact brand header, the pinned
/// home/notifications tabs, the saved filter tabs, the stack of closable
/// conversation tabs, and an account footer with the settings entry point.
struct SidebarView: View {
    @ObservedObject var workspace: WorkspaceModel
    @EnvironmentObject private var theme: ThemeStore
    var accountHandle: String
    var accountAvatarURL: URL?
    var onOpenSettings: () -> Void

    /// Drives the create/edit sheet. `.new` opens a blank editor; `.edit` prefills
    /// from an existing filter and preserves its id/createdAt on save.
    private enum EditorRequest: Identifiable {
        case new
        case edit(SavedFilter)

        var id: String {
            switch self {
            case .new: return "new"
            case let .edit(filter): return filter.id.uuidString
            }
        }
    }

    @State private var editorRequest: EditorRequest?

    var body: some View {
        VStack(spacing: 0) {
            trafficLightInset
            tabList
            Spacer(minLength: 0)
            accountFooter
        }
        .background(theme.background)
        .ignoresSafeArea(.container, edges: .top)
        .sheet(item: $editorRequest) { request in
            editor(for: request).environmentObject(theme)
        }
    }

    @ViewBuilder
    private func editor(for request: EditorRequest) -> some View {
        switch request {
        case .new:
            FilterEditorView(name: "", query: "", isEditing: false) { name, query in
                workspace.addFilter(name: name, query: query)
            }
        case let .edit(filter):
            FilterEditorView(name: filter.name, query: filter.query, isEditing: true) { name, query in
                workspace.updateFilter(
                    SavedFilter(id: filter.id, name: name, query: query, createdAt: filter.createdAt)
                )
            }
        }
    }

    private var trafficLightInset: some View {
        Color.clear.frame(height: 28)
    }

    private var tabList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                SidebarRow(
                    icon: "house",
                    title: "ホーム",
                    isSelected: workspace.selection == .home
                ) { workspace.selection = .home }

                SidebarRow(
                    icon: "bell",
                    title: "通知",
                    isSelected: workspace.selection == .notifications
                ) { workspace.selection = .notifications }

                filterSection

                if !workspace.conversations.isEmpty {
                    sectionLabel("会話")
                    ForEach(workspace.conversations) { tab in
                        SidebarRow(
                            title: tab.title,
                            subtitle: tab.subtitle,
                            meta: tab.handle,
                            isSelected: workspace.selection == .conversation(tab.id),
                            onClose: { workspace.closeConversation(tab.id) }
                        ) { workspace.selection = .conversation(tab.id) }
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
    }

    /// The "フィルター" section: a header with an add button, then one row per
    /// saved filter. Always shown so the user can add the first filter.
    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                sectionLabel("フィルター")
                Spacer(minLength: 0)
                Button { editorRequest = .new } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.tertiaryText)
                        .padding(.horizontal, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("フィルターを追加")
            }

            ForEach(workspace.filters) { tab in
                SidebarRow(
                    icon: "line.3.horizontal.decrease",
                    title: tab.title,
                    meta: tab.query,
                    isSelected: workspace.selection == .filter(tab.id),
                    onClose: { workspace.removeFilter(id: tab.id) },
                    onEdit: {
                        if let saved = workspace.savedFilter(id: tab.id) {
                            editorRequest = .edit(saved)
                        }
                    }
                ) { workspace.selection = .filter(tab.id) }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(1)
            .foregroundStyle(theme.tertiaryText)
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }

    private var accountFooter: some View {
        HStack(spacing: 8) {
            accountAvatar
            Text("@\(accountHandle)")
                .font(.caption.weight(.medium))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            ChromeIconButton(systemImage: "gearshape", help: "設定", action: onOpenSettings)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.hairline).frame(height: 1)
        }
    }

    private var accountAvatar: some View {
        RemoteImage(url: accountAvatarURL, maxPointSize: 20) { phase in
            if case let .success(image) = phase {
                image.resizable().scaledToFill()
            } else {
                theme.avatarPlaceholder
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(theme.hairline, lineWidth: 1))
    }
}

/// A single sidebar tab row in the cmux idiom. Navigation rows pass `icon`+`title`;
/// filter rows add `meta` (the query) plus `onClose`/`onEdit`; conversation rows
/// add `subtitle`+`meta`+`onClose`. Selection paints a solid accent fill and
/// switches the foreground to white; hover reveals the edit/close affordances.
private struct SidebarRow: View {
    @EnvironmentObject private var theme: ThemeStore
    @State private var isHovered = false

    var icon: String? = nil
    let title: String
    var subtitle: String? = nil
    var meta: String? = nil
    let isSelected: Bool
    var onClose: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    let action: () -> Void

    private static let cornerRadius: CGFloat = 6

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 16)
                        .foregroundStyle(iconColor)
                        .padding(.top, 1)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(subtitleColor)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)
                    }

                    if let meta, !meta.isEmpty {
                        Text(meta)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(metaColor)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Self.cornerRadius).fill(rowBackground)
            )
            .overlay(alignment: .topTrailing) { trailingControls }
            .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovered)
    }

    @ViewBuilder
    private var trailingControls: some View {
        if isHovered, onEdit != nil || onClose != nil {
            HStack(spacing: 2) {
                if let onEdit {
                    iconButton("pencil", help: "フィルターを編集", action: onEdit)
                }
                if let onClose {
                    iconButton("xmark", help: "タブを閉じる", action: onClose)
                }
            }
            .padding(2)
        }
    }

    private func iconButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isSelected ? Color.white.opacity(0.85) : theme.tertiaryText)
                .padding(4)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var rowBackground: Color {
        if isSelected { return theme.accent }
        return isHovered ? theme.rowHover : .clear
    }

    private var titleColor: Color { isSelected ? .white : theme.primaryText }
    private var subtitleColor: Color { isSelected ? Color.white.opacity(0.82) : theme.secondaryText }
    private var metaColor: Color { isSelected ? Color.white.opacity(0.7) : theme.tertiaryText }
    private var iconColor: Color { isSelected ? .white : theme.tertiaryText }
}
```

- [ ] **Step 3: 中間ビルドは未配線のため失敗してよい。Task 10 で検証する。**

---

## Task 9: 汎用 `FeedView` への抽出と `.filter` ルーティング（app）

**Files:**
- Create: `apps/macos/Views/FeedView.swift`
- Modify: `apps/macos/Views/MainWindowView.swift`

ホームフィードのスクロール/状態/ポーリング/`j`/`k` ナビを `TimelineViewModel` を引数に取る `FeedView` に切り出し、`.home` と `.filter` で共用する。各 `FeedView` が自前で `focusedPostID` を持つのでタブ間でフォーカスが混ざらない。

- [ ] **Step 1: `FeedView` を作成**

`apps/macos/Views/FeedView.swift`:

```swift
import SwiftUI
import YoruMimizukuKit

/// A scrollable post feed backed by a `TimelineViewModel`. Reused by the home tab
/// and every filter tab: it loads on appear, refreshes on an interval while
/// visible, appends older posts on scroll, and supports j/k focus movement.
/// Owning its own `focusedPostID` keeps each tab's focus independent.
struct FeedView: View {
    @ObservedObject var model: TimelineViewModel
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var displaySettings: DisplaySettingsStore

    /// Shown in the header. Home passes nil (the sidebar already names the pane);
    /// filter tabs pass the filter name.
    var title: String?
    let now: Date
    var onImageTap: (URL) -> Void
    var onOpenConversation: (PostDisplay) -> Void

    @State private var focusedPostID: String?

    private let refreshInterval: Duration = .seconds(30)

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(title) { EmptyView() }
            timeline
        }
        .background(theme.canvas)
        .ignoresSafeArea(.container, edges: .top)
        .background { postNavShortcuts }
        .task { await runFeed() }
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                switch model.state {
                case .idle, .loading:
                    loadingState
                case let .failed(message):
                    failedState(message)
                case let .loaded(posts):
                    if posts.isEmpty {
                        emptyState
                    } else {
                        postList(posts)
                    }
                }
            }
            .onChange(of: focusedPostID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func postList(_ posts: [PostDisplay]) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(posts) { post in
                PostRowView(
                    post: post, density: displaySettings.density, now: now,
                    onImageTap: onImageTap,
                    onReplyTap: { _ in onOpenConversation(post) }
                )
                .background(post.id == focusedPostID ? theme.rowHover : .clear)
                .overlay(alignment: .leading) {
                    if post.id == focusedPostID {
                        Rectangle().fill(theme.accent).frame(width: 3)
                    }
                }
                .id(post.id)
                .onAppear {
                    if post.id == posts.last?.id {
                        Task { await model.loadMore() }
                    }
                }
                Divider().overlay(theme.divider)
            }
            if model.isLoadingMore {
                loadMoreFooter
            }
        }
    }

    private var loadMoreFooter: some View {
        HStack {
            Spacer()
            ProgressView().controlSize(.small)
            Spacer()
        }
        .padding(.vertical, 14)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.regular)
            Text("夜空を眺めています…")
                .font(.callout)
                .foregroundStyle(theme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func failedState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 26))
                .foregroundStyle(theme.star)
            Text("読み込みに失敗しました")
                .font(.callout).foregroundStyle(theme.secondaryText)
            Text(message)
                .font(.caption).foregroundStyle(theme.tertiaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button("再試行") { Task { await model.load() } }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.stars")
                .font(.system(size: 28))
                .foregroundStyle(theme.tertiaryText)
            Text("まだ投稿がありません")
                .font(.callout).foregroundStyle(theme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    /// Load once, then refresh on an interval while on screen. SwiftUI cancels this
    /// on disappear; returning re-runs it (the initial load is skipped once loaded).
    private func runFeed() async {
        if case .idle = model.state { await model.load() }
        if focusedPostID == nil { focusedPostID = model.posts.first?.id }
        while !Task.isCancelled {
            try? await Task.sleep(for: refreshInterval)
            if Task.isCancelled { break }
            await model.refresh()
        }
    }

    private func focusAdjacentPost(_ offset: Int) {
        let posts = model.posts
        guard !posts.isEmpty else { return }
        if let id = focusedPostID, let index = posts.firstIndex(where: { $0.id == id }) {
            let target = max(0, min(posts.count - 1, index + offset))
            focusedPostID = posts[target].id
        } else {
            focusedPostID = posts.first?.id
        }
        if focusedPostID == posts.last?.id {
            Task { await model.loadMore() }
        }
    }

    private var postNavShortcuts: some View {
        ZStack {
            Button("") { focusAdjacentPost(1) }
                .keyboardShortcut("j", modifiers: [])
            Button("") { focusAdjacentPost(-1) }
                .keyboardShortcut("k", modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}
```

- [ ] **Step 2: `MainWindowView.swift` を以下の全文に置き換える**

`apps/macos/Views/MainWindowView.swift`:

```swift
import SwiftUI
import YoruMimizukuKit

/// The main window: a cmux-style vertical tab rail (home, notifications, filter,
/// and closable conversation tabs) on the left, with the selected tab's content
/// on the right. Home and filter tabs render a `FeedView`; Cmd-Shift-J/K cycle the
/// tabs. The lightbox and settings sheet float above everything.
struct MainWindowView: View {
    @ObservedObject var model: TimelineViewModel
    @ObservedObject var notifications: NotificationsViewModel
    @ObservedObject var workspace: WorkspaceModel
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var displaySettings: DisplaySettingsStore
    var accountHandle: String
    var accountAvatarURL: URL?

    @State private var lightboxURL: URL?
    @State private var showSettings = false

    private let now = Date()

    var body: some View {
        NavigationSplitView {
            SidebarView(
                workspace: workspace,
                accountHandle: accountHandle,
                accountAvatarURL: accountAvatarURL,
                onOpenSettings: { showSettings = true }
            )
            .overlay(alignment: .trailing) {
                Rectangle().fill(theme.divider).frame(width: 1).ignoresSafeArea()
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 232, max: 320)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 600, minHeight: 540)
        .background { tabShortcuts }
        .overlay {
            if let lightboxURL {
                ImageLightboxView(url: lightboxURL) { self.lightboxURL = nil }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(theme)
                .environmentObject(displaySettings)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch workspace.selection {
        case .home:
            FeedView(
                model: model, title: nil, now: now,
                onImageTap: { lightboxURL = $0 },
                onOpenConversation: { workspace.openConversation($0) }
            )
        case .notifications:
            NotificationsView(model: notifications, now: now)
        case let .filter(id):
            if let tab = workspace.filter(id: id) {
                FeedView(
                    model: tab.model, title: tab.title, now: now,
                    onImageTap: { lightboxURL = $0 },
                    onOpenConversation: { workspace.openConversation($0) }
                )
                .id(id)
            } else {
                Color.clear.background(theme.canvas)
            }
        case let .conversation(id):
            if let tab = workspace.conversation(id: id) {
                ConversationView(
                    model: tab.model,
                    title: tab.title,
                    now: now,
                    onImageTap: { lightboxURL = $0 },
                    onOpenConversation: { workspace.openConversation($0) },
                    onClose: { workspace.closeConversation(id) }
                )
                .id(id)
            } else {
                Color.clear.background(theme.canvas)
            }
        }
    }

    /// Zero-size, invisible buttons whose key equivalents drive tab cycling.
    private var tabShortcuts: some View {
        ZStack {
            Button("") { workspace.selectNextTab() }
                .keyboardShortcut("j", modifiers: [.command, .shift])
            Button("") { workspace.selectPreviousTab() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}
```

- [ ] **Step 3: 中間ビルドは `RootView` 未配線のため失敗してよい。Task 10 で検証する。**

---

## Task 10: `RootView` 配線とビルド検証（app）

**Files:**
- Modify: `apps/macos/Views/RootView.swift`

`SavedFilterStore`（`FilterFileStore` 注入）を生成し、`WorkspaceModel` に `filterStore` と `makeFilterModel`（`LiveSearchLoader` 配線）を渡す。これで Task 7〜9 の参照が解決しビルドが通る。

> **コミット方針（Tidy First の例外）:** app 層（Task 7〜10）は相互参照で**まとめてしか compile できない**。app ターゲットに XCTest が無く構造変更・挙動変更の分離コミットの恩恵が小さいこと、`FeedView` 抽出が `.filter` ルーティング追加と不可分であることから、Task 7〜10 を**1つの behavioral コミット**にまとめる。コア層（Task 1〜4）は従来どおりタスク単位でコミット済み。

- [ ] **Step 1: `RootView.swift` を以下の全文に置き換える**

`apps/macos/Views/RootView.swift`:

```swift
import SwiftUI
import BlueskyCore
import YoruMimizukuKit
import PlatformApple

/// Chooses the login screen or the main window based on whether an account is
/// currently stored. Builds the live login stack from the Keychain-backed store,
/// and wires the per-account filter store and search-backed filter tabs.
struct RootView: View {
    @State private var currentDID: String?
    @State private var accountAvatarURL: URL?
    @StateObject private var loginModel: LoginViewModel
    @StateObject private var timelineModel: TimelineViewModel
    @StateObject private var notificationsModel: NotificationsViewModel
    @StateObject private var workspace: WorkspaceModel
    @StateObject private var themeStore = ThemeStore()
    @StateObject private var displaySettings = DisplaySettingsStore()

    private let accountManager: AccountManager
    private let profileLoader: LiveProfileLoader

    init() {
        let storage = KeychainStorage(service: "as.ason.YoruMimizuku")
        let manager = AccountManager(store: AccountStore(storage: storage))
        self.accountManager = manager
        self.profileLoader = LiveProfileLoader(accountManager: manager)

        // current() returns PersistedAccount?; try? wraps it again, so flatten first.
        let existing = (try? manager.current()) ?? nil

        _loginModel = StateObject(
            wrappedValue: LoginViewModel(performer: LiveLoginPerformer(accountManager: manager))
        )
        _timelineModel = StateObject(
            wrappedValue: TimelineViewModel(loader: LiveTimelineLoader(accountManager: manager), tracer: OSSignpostTracing.timeline)
        )
        _notificationsModel = StateObject(
            wrappedValue: NotificationsViewModel(loader: LiveNotificationsLoader(accountManager: manager))
        )

        // Filters persist per account DID. A returning user's DID is known here; a
        // first login in this same launch falls back to an empty store until relaunch.
        let filterStore = SavedFilterStore(port: FilterFileStore(did: existing?.did ?? "anonymous"))
        _workspace = StateObject(
            wrappedValue: WorkspaceModel(
                filterStore: filterStore,
                makeThreadModel: { uri in
                    ThreadViewModel(loader: LiveThreadLoader(accountManager: manager), uri: uri)
                },
                makeFilterModel: { query in
                    TimelineViewModel(loader: LiveSearchLoader(accountManager: manager, query: query))
                }
            )
        )
        _currentDID = State(initialValue: existing?.did)
    }

    var body: some View {
        Group {
            if currentDID != nil {
                MainWindowView(
                    model: timelineModel,
                    notifications: notificationsModel,
                    workspace: workspace,
                    accountHandle: currentHandle,
                    accountAvatarURL: accountAvatarURL
                )
                .task(id: currentDID) { await loadAvatar() }
            } else {
                LoginView(model: loginModel) { did in
                    currentDID = did
                }
            }
        }
        .environmentObject(themeStore)
        .environmentObject(displaySettings)
    }

    private var currentHandle: String {
        let account = (try? accountManager.current()) ?? nil
        return account?.handle ?? account?.did ?? ""
    }

    private func loadAvatar() async {
        accountAvatarURL = try? await profileLoader.loadCurrentAvatar()
    }
}
```

- [ ] **Step 2: プロジェクト再生成 + ビルド**

Run: `cd .worktrees/feature/filter-tabs && xcodegen generate && xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj -destination 'platform=macOS' -quiet`
Expected: ビルド成功（警告・エラーなし）。

- [ ] **Step 3: コア全テストが緑であることを再確認**

Run: `cd .worktrees/feature/filter-tabs/core && swift test`
Expected: すべて PASS。

- [ ] **Step 4: app 層（Task 7〜10）を 1 コミット**

```bash
git -C .worktrees/feature/filter-tabs add \
  apps/macos/Workspace/WorkspaceModel.swift \
  apps/macos/Views/FilterEditorView.swift \
  apps/macos/Views/SidebarView.swift \
  apps/macos/Views/FeedView.swift \
  apps/macos/Views/MainWindowView.swift \
  apps/macos/Views/RootView.swift
git -C .worktrees/feature/filter-tabs ai-commit --context "Add filter tabs UI: sidebar filter section with create/edit/delete, FeedView reused for home and filter tabs backed by SearchService, wired through WorkspaceModel and per-account FilterFileStore"
```

- [ ] **Step 5: 動作確認（手動・GUI）**

`xcodebuild` で生成された app を起動し、以下を確認:
1. サイドバーに「フィルター」セクションと `+` が表示される。
2. `+` →名前/クエリ入力（例: 名前 `Swift`、クエリ `#swift`）→追加でタブが生まれ選択される。
3. フィルタータブに検索結果が表示され、30 秒で上に新着がマージされ、末尾スクロールで追加読み込みされる。
4. 行 hover で鉛筆（編集）と × （削除）が出る。編集でクエリ変更→再読込、削除でタブが消えてフォールバック選択。
5. アプリ再起動後もフィルターがサイドバーに復元される。
6. `Cmd-Shift-J/K` でフィルタータブを含むタブ巡回ができる。

---

## Self-Review（spec 突き合わせ）

- **searchPosts 実装** → Task 1（`SearchResponse`）+ Task 2（`SearchService`）。✓
- **サイドバーのフィルターセクション + `+`** → Task 8（`filterSection`）。✓
- **完全 CRUD** → 作成/編集（Task 8 `FilterEditorView` + `WorkspaceModel.addFilter/updateFilter`）、削除（`removeFilter` + 行 ×）。✓
- **30 秒ポーリング + 上マージ + 無限スクロール** → Task 9 `FeedView.runFeed` / `loadMore`（`TimelineViewModel` 再利用）。✓
- **ローカル永続化（DID 単位）+ iCloud 視野のポート化** → Task 3/4（`SavedFilter` 値型 + `SavedFilterStoring` ポート + `SavedFilterStore`）+ Task 6（`FilterFileStore`）。✓
- **生クエリ1本** → `FilterEditorView` のクエリ欄 + `SavedFilter.query`。✓
- **エラー処理（再試行 UI / ポーリング失敗握りつぶし / 空クエリ拒否 / 永続化失敗ログのみ）** → `FeedView.failedState`、`TimelineViewModel` 既存挙動、`SavedFilterStore.add` バリデーション、`SavedFilterStore.persist` の `try?`。✓
- **テスト戦略** → Task 1/2/3/4 に対応テスト。app 層はビルド + 手動確認（app に XCTest ターゲットが無い前提を明記）。✓

**型整合チェック:** `SavedFilter(id:name:query:createdAt:)` イニシャライザは Task 3 で定義し Task 8/10 で同シグネチャ使用。`SavedFilterStore.add(name:query:)` / `update(_:)` / `remove(id:)` は Task 4 定義と Task 7 呼び出しが一致。`WorkspaceModel(filterStore:makeThreadModel:makeFilterModel:)` は Task 7 定義と Task 10 呼び出しが一致。`FeedView(model:title:now:onImageTap:onOpenConversation:)` は Task 9 定義と Task 9 `MainWindowView` 呼び出しが一致。`LiveSearchLoader(accountManager:query:)` は Task 5 定義と Task 10 呼び出しが一致。✓

**既知の制約:** 同一起動中に新規ログインした場合、フィルターストアは init 時の DID（未ログイン時は `anonymous`）で構築されるため、当該アカウントのフィルターは再起動まで空になる。v1 の割り切り（設計書 §9 未確定事項に準ずる運用）。

## Execution Handoff

**実行方法は2つ:**

1. **Subagent-Driven（推奨）** — タスクごとに新しいサブエージェントを割り当て、タスク間でレビュー。高速反復。
2. **Inline Execution** — このセッション内で `executing-plans` によりチェックポイント付きで一括実行。

どちらで進めますか。

