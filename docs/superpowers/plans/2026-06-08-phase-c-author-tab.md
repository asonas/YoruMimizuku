# Phase C: User (Author) Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tapping a user's avatar (from a timeline post, a notification row, or a conversation post) opens a deduplicated, view-only vertical-rail tab showing that user's profile header and their `getAuthorFeed` posts.

**Architecture:** A new `WorkspaceTab.author(UUID)` tab kind backed by an ephemeral `AuthorTab` that owns a reused `TimelineViewModel` (fed by a `LiveAuthorFeedLoader` over `app.bsky.feed.getAuthorFeed`) plus a small `ProfileHeaderViewModel` (fed by a `LiveAuthorProfileLoader` over `app.bsky.actor.getProfile`). `WorkspaceModel` dedupes author tabs by DID, and `MainWindowView` polls an author tab only while it is the active selection. Author tabs carry no unread badge and are not persisted.

**Tech Stack:** Swift 6.0, SwiftUI, XCTest, AT Protocol XRPC (app.bsky.feed.getAuthorFeed, app.bsky.actor.getProfile)

---

## Dependency on Phase B

This plan **assumes Phase B has been merged**, because the avatar-tap wiring derives a post author's DID from its AT-URI via `ATURI.repo(_:)`. As of this plan, `core/Sources/BlueskyCore/XRPC/ATURI.swift` only defines `ATURI.rkey(_:)`; Phase B adds `ATURI.repo(_:)` (the authority segment of `at://<authority>/<collection>/<rkey>`). Phase C also inherits the Phase B `f` / `o` / copy keyboard shortcuts and the avatar-tap affordance by reusing `FeedView`/`PostRowView`.

If Phase B is **not** merged when you start, add `ATURI.repo(_:)` as a prerequisite step in Task 10 (a one-line helper mirroring `rkey`, returning `parts[0]` when the URI is a valid `at://authority/collection/rkey` triple, with a unit test in `core/Tests/BlueskyCoreTests/`). Otherwise rely on Phase B's implementation and do not duplicate it.

## File Structure

### Created

| File | Responsibility |
| --- | --- |
| `core/Sources/YoruMimizukuKit/ProfileHeaderViewModel.swift` | `AuthorProfile` model, `AuthorProfileLoading` port, and the `ProfileHeaderViewModel` (`@MainActor ObservableObject`) that loads a profile failure-tolerantly. |
| `core/Sources/BlueskyCore/XRPC/AuthorFeedService.swift` | `AuthorFeedService.getAuthorFeed(...)`: DPoP-bound `app.bsky.feed.getAuthorFeed`, mirroring `TimelineService` (401→refresh→retry), decoding into the existing `TimelineResponse`. |
| `apps/macos/Timeline/LiveAuthorFeedLoader.swift` | Live `TimelineLoading` over `AuthorFeedService` for one actor (DID), persisting refreshed tokens and mapping the feed to `PostDisplay`. |
| `apps/macos/Timeline/LiveAuthorProfileLoader.swift` | Live `AuthorProfileLoading` over the existing `ProfileService`, mapping `ProfileViewBasic` → `AuthorProfile`. |
| `apps/macos/Views/AuthorView.swift` | The author tab's content: a profile header (avatar / displayName / @handle / bio) above a reused `FeedView`. |
| `core/Tests/YoruMimizukuKitTests/ProfileHeaderViewModelTests.swift` | TDD for the header VM (load success / load failure keeps initial). |
| `core/Tests/BlueskyCoreTests/AuthorFeedServiceTests.swift` | TDD for the URL query items (actor/filter/cursor) and decode/refresh. |

### Modified

| File | Change |
| --- | --- |
| `core/Sources/YoruMimizukuKit/WorkspaceModel.swift` | Add `WorkspaceTab.author(UUID)`, the `AuthorTab` class, `@Published authors`, `makeAuthorModel`/`makeAuthorHeader` closures, `openAuthor`/`closeAuthor`/`author(id:)`, and extend `orderedTabs`. |
| `core/Tests/YoruMimizukuKitTests/WorkspaceModelTests.swift` | TDD for author dedupe-by-DID, append+select, close fallback, ordering. |
| `apps/macos/Views/RootView.swift` | Pass `makeAuthorModel` and `makeAuthorHeader` into `WorkspaceModel`. |
| `apps/macos/Views/MainWindowView.swift` | Add the `.author` detail case; poll author tabs only while active in `syncActiveTab()`. |
| `apps/macos/Views/SidebarView.swift` | Add a "ユーザー" section listing author tabs (no badge). |
| `apps/macos/Views/FeedView.swift` | Thread an `onOpenAuthor: (PostDisplay) -> Void` to each `PostRowView`. |
| `apps/macos/Views/PostRowView.swift` | Add `onAvatarTap` and an avatar `.onTapGesture`. |
| `apps/macos/Views/NotificationsView.swift` | Make actor avatars tappable, calling an `onOpenAuthor` closure. |
| `apps/macos/Views/ConversationView.swift` | Thread `onOpenAuthor` to its `PostRowView`s. |
| `core/Sources/BlueskyCore/XRPC/ATURI.swift` | Only if Phase B is absent: add `ATURI.repo(_:)`. |

---

## Task 1: `AuthorProfile`, `AuthorProfileLoading`, and `ProfileHeaderViewModel`

**Files:**
- `core/Sources/YoruMimizukuKit/ProfileHeaderViewModel.swift` (create)
- `core/Tests/YoruMimizukuKitTests/ProfileHeaderViewModelTests.swift` (create)

- [ ] **Step 1: Write the failing test for load success.**

Create `core/Tests/YoruMimizukuKitTests/ProfileHeaderViewModelTests.swift`:

```swift
import XCTest
@testable import YoruMimizukuKit

@MainActor
final class ProfileHeaderViewModelTests: XCTestCase {
    private final class StubLoader: AuthorProfileLoading, @unchecked Sendable {
        let result: Result<AuthorProfile, Error>
        init(_ result: Result<AuthorProfile, Error>) { self.result = result }
        func loadProfile(actor: String) async throws -> AuthorProfile {
            try result.get()
        }
    }

    private struct LoadError: Error {}

    private func profile(did: String = "did:plc:alice") -> AuthorProfile {
        AuthorProfile(
            did: did, handle: "alice.bsky.social", displayName: "Alice",
            avatarURL: URL(string: "https://cdn.example/alice.jpg"), bio: "hello"
        )
    }

    func testLoadSuccessSetsProfile() async {
        let loaded = profile()
        let vm = ProfileHeaderViewModel(loader: StubLoader(.success(loaded)), actor: "did:plc:alice")

        await vm.load()

        XCTAssertEqual(vm.profile, loaded)
        XCTAssertFalse(vm.failed)
    }
}
```

- [ ] **Step 2: Run the test, see it fail.**

```bash
cd core && swift test --filter ProfileHeaderViewModelTests
```

Expected: compilation failure — `AuthorProfile`, `AuthorProfileLoading`, and `ProfileHeaderViewModel` are not defined.

- [ ] **Step 3: Implement the minimum to pass.**

Create `core/Sources/YoruMimizukuKit/ProfileHeaderViewModel.swift`:

```swift
import Foundation

/// A user's profile as the author tab header renders it. `displayName` and `bio`
/// are optional because the actor may not have set them; `bio` is currently always
/// nil from the basic profile view (see `LiveAuthorProfileLoader`).
public struct AuthorProfile: Equatable, Sendable {
    public let did: String
    public let handle: String
    public let displayName: String?
    public let avatarURL: URL?
    public let bio: String?

    public init(did: String, handle: String, displayName: String?, avatarURL: URL?, bio: String?) {
        self.did = did
        self.handle = handle
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.bio = bio
    }
}

/// Resolves an actor's profile for the author tab header. The app provides the live
/// implementation (authenticated XRPC + mapping); tests inject a stub.
public protocol AuthorProfileLoading: Sendable {
    func loadProfile(actor: String) async throws -> AuthorProfile
}

/// Drives the author tab's profile header. Holds the loaded profile (or an initial
/// snapshot captured from the tapped avatar so the header renders before the fetch
/// completes). The header is cosmetic, so a failed load keeps any initial snapshot
/// and flips `failed` rather than surfacing an error screen.
@MainActor
public final class ProfileHeaderViewModel: ObservableObject {
    @Published public private(set) var profile: AuthorProfile?
    @Published public private(set) var failed = false

    private let loader: AuthorProfileLoading
    private let actor: String

    public init(loader: AuthorProfileLoading, actor: String, initial: AuthorProfile? = nil) {
        self.loader = loader
        self.actor = actor
        self.profile = initial
    }

    /// Fetch the full profile. On success replaces `profile`; on failure keeps the
    /// initial snapshot (if any) and sets `failed`.
    public func load() async {
        do {
            profile = try await loader.loadProfile(actor: actor)
            failed = false
        } catch {
            failed = true
        }
    }
}
```

- [ ] **Step 4: Run the test, see it pass.**

```bash
cd core && swift test --filter ProfileHeaderViewModelTests
```

Expected: `Executed 1 test, with 0 failures`.

- [ ] **Step 5: Add the failure-tolerance test.**

Append to `ProfileHeaderViewModelTests`:

```swift
    func testLoadFailureKeepsInitialAndMarksFailed() async {
        let initial = profile()
        let vm = ProfileHeaderViewModel(
            loader: StubLoader(.failure(LoadError())), actor: "did:plc:alice", initial: initial
        )

        await vm.load()

        XCTAssertEqual(vm.profile, initial)
        XCTAssertTrue(vm.failed)
    }
```

- [ ] **Step 6: Run, see it pass (already covered by the impl).**

```bash
cd core && swift test --filter ProfileHeaderViewModelTests
```

Expected: `Executed 2 tests, with 0 failures`.

- [ ] **Step 7: Commit.**

```bash
git ai-commit
```

Message: `Add ProfileHeaderViewModel and AuthorProfile for the author tab header`

---

## Task 2: `AuthorFeedService.getAuthorFeed`

**Files:**
- `core/Sources/BlueskyCore/XRPC/AuthorFeedService.swift` (create)
- `core/Tests/BlueskyCoreTests/AuthorFeedServiceTests.swift` (create)

- [ ] **Step 1: Write the failing URL/decode test.**

Create `core/Tests/BlueskyCoreTests/AuthorFeedServiceTests.swift`:

```swift
import XCTest
@testable import BlueskyCore

final class AuthorFeedServiceTests: XCTestCase {
    private let pds = URL(string: "https://pds.example")!
    private let issuer = URL(string: "https://bsky.social")!

    private static let feedBody = Data(##"""
    {
      "cursor": "next-page",
      "feed": [
        {
          "post": {
            "uri": "at://did:plc:alice/app.bsky.feed.post/aaa",
            "cid": "bafyreialice",
            "author": { "did": "did:plc:alice", "handle": "alice.bsky.social", "displayName": "Alice" },
            "record": { "$type": "app.bsky.feed.post", "text": "hi", "createdAt": "2026-06-04T12:00:00.000Z" },
            "indexedAt": "2026-06-04T12:00:01.000Z"
          }
        }
      ]
    }
    """##.utf8)

    private func makeService(http: HTTPClient) -> AuthorFeedService {
        let sender = DPoPRequestSender(http: http, proofBuilder: DPoPProofBuilder(crypto: FakeDPoPCryptoProvider()))
        return AuthorFeedService(sender: sender, metadataResolver: OAuthMetadataResolver(http: http), config: .yoruMimizuku)
    }

    func testGetAuthorFeedSendsActorAndFilterAndDecodes() async throws {
        let http = FakeHTTPClient(response: HTTPResponse(statusCode: 200, body: Self.feedBody))
        let service = makeService(http: http)

        let result = try await service.getAuthorFeed(
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: "rtk",
            actor: "did:plc:alice", limit: 50, cursor: nil
        )

        XCTAssertNil(result.refreshed)
        XCTAssertEqual(result.response.feed.count, 1)
        XCTAssertEqual(result.response.cursor, "next-page")

        let sent = try XCTUnwrap(http.sentRequests.last)
        XCTAssertEqual(sent.method, .get)
        XCTAssertTrue(
            sent.url.absoluteString.hasPrefix("https://pds.example/xrpc/app.bsky.feed.getAuthorFeed"),
            "unexpected url: \(sent.url.absoluteString)"
        )
        let query = sent.url.query ?? ""
        XCTAssertTrue(query.contains("actor=did:plc:alice") || query.contains("actor=did%3Aplc%3Aalice"))
        XCTAssertTrue(query.contains("filter=posts_and_author_threads"))
        XCTAssertTrue(query.contains("limit=50"))
        XCTAssertFalse(query.contains("cursor="))
        XCTAssertEqual(sent.headers["Authorization"], "DPoP atk")
    }

    func testGetAuthorFeedIncludesCursorWhenProvided() async throws {
        let http = FakeHTTPClient(response: HTTPResponse(statusCode: 200, body: Self.feedBody))
        let service = makeService(http: http)

        _ = try await service.getAuthorFeed(
            pds: pds, issuer: issuer, accessToken: "atk", refreshToken: nil,
            actor: "did:plc:alice", limit: 20, cursor: "page-2"
        )

        let sent = try XCTUnwrap(http.sentRequests.last)
        XCTAssertEqual(sent.url.query?.contains("cursor=page-2"), true)
        XCTAssertEqual(sent.url.query?.contains("limit=20"), true)
    }
}
```

- [ ] **Step 2: Run the test, see it fail.**

```bash
cd core && swift test --filter AuthorFeedServiceTests
```

Expected: compilation failure — `AuthorFeedService` is not defined.

- [ ] **Step 3: Implement the service.**

Create `core/Sources/BlueskyCore/XRPC/AuthorFeedService.swift` (mirrors `TimelineService` exactly, adding `actor` and `filter` query items):

```swift
import Foundation

/// Fetches an actor's posts (`app.bsky.feed.getAuthorFeed`) from the account's PDS
/// over a DPoP-bound channel. Mirrors `TimelineService`'s auth handling: the
/// `use_dpop_nonce` retry lives in the sender, and an expired access token (401
/// that is not a nonce challenge) is refreshed via `refresh_token` and retried once,
/// returning the freshly issued tokens so the caller can persist them. The response
/// shape matches `getTimeline`, so it decodes into the existing `TimelineResponse`.
public struct AuthorFeedService: Sendable {
    private let sender: DPoPRequestSender
    private let metadataResolver: OAuthMetadataResolver
    private let config: OAuthClientConfig
    private let refreshGate: RefreshGate

    public init(
        sender: DPoPRequestSender,
        metadataResolver: OAuthMetadataResolver,
        config: OAuthClientConfig,
        refreshGate: RefreshGate = RefreshGate()
    ) {
        self.sender = sender
        self.metadataResolver = metadataResolver
        self.config = config
        self.refreshGate = refreshGate
    }

    /// Fetch a page of `actor`'s feed. `actor` is a DID or handle. Returns the
    /// decoded response and, when a refresh occurred, the freshly issued tokens;
    /// `refreshed` is nil when the original access token was still valid.
    public func getAuthorFeed(
        pds: URL,
        issuer: URL,
        accessToken: String,
        refreshToken: String?,
        actor: String,
        limit: Int = 50,
        cursor: String? = nil,
        filter: String = "posts_and_author_threads"
    ) async throws -> (response: TimelineResponse, refreshed: TokenResponse?) {
        let url = try Self.authorFeedURL(pds: pds, actor: actor, limit: limit, cursor: cursor, filter: filter)
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
        let metadataResolver = self.metadataResolver
        let sender = self.sender
        let config = self.config
        return try await refreshGate.refresh(using: refreshToken) {
            let metadata = try await metadataResolver.authorizationServer(issuer: issuer)
            return try await TokenService(sender: sender).requestToken(
                metadata: metadata, config: config, grant: .refresh(refreshToken: refreshToken)
            )
        }
    }

    static func authorFeedURL(pds: URL, actor: String, limit: Int, cursor: String?, filter: String) throws -> URL {
        let endpoint = pds.appendingPathComponent("xrpc/app.bsky.feed.getAuthorFeed")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw XRPCError.invalidURL("app.bsky.feed.getAuthorFeed")
        }
        var items = [
            URLQueryItem(name: "actor", value: actor),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "filter", value: filter)
        ]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        components.queryItems = items
        guard let url = components.url else {
            throw XRPCError.invalidURL("app.bsky.feed.getAuthorFeed")
        }
        return url
    }

    static func decode(_ response: HTTPResponse) throws -> TimelineResponse {
        guard response.statusCode == 200 else {
            let errorBody = try? JSONDecoder().decode(XRPCErrorResponse.self, from: response.body)
            throw XRPCError.requestFailed(status: response.statusCode, body: errorBody)
        }
        do {
            return try JSONDecoder().decode(TimelineResponse.self, from: response.body)
        } catch {
            throw XRPCError.decodingFailed(String(describing: error))
        }
    }
}
```

- [ ] **Step 4: Run the test, see it pass.**

```bash
cd core && swift test --filter AuthorFeedServiceTests
```

Expected: `Executed 2 tests, with 0 failures`.

- [ ] **Step 5: Add the refresh-on-401 test.**

Append to `AuthorFeedServiceTests` (mirrors `TimelineServiceTests.testGetTimelineRefreshesOnUnauthorizedAndRetries`):

```swift
    func testGetAuthorFeedRefreshesOnUnauthorizedAndRetries() async throws {
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
        let feed = HTTPResponse(statusCode: 200, body: Self.feedBody)
        let http = SequencedHTTPClient([unauthorized, metadata, tokens, feed])
        let service = makeService(http: http)

        let result = try await service.getAuthorFeed(
            pds: pds, issuer: issuer, accessToken: "old", refreshToken: "rtk", actor: "did:plc:alice"
        )

        XCTAssertEqual(result.refreshed?.accessToken, "atk2")
        XCTAssertEqual(result.response.feed.count, 1)
        XCTAssertEqual(http.sentRequests.last?.headers["Authorization"], "DPoP atk2")
    }
```

- [ ] **Step 6: Run, see it pass.**

```bash
cd core && swift test --filter AuthorFeedServiceTests
```

Expected: `Executed 3 tests, with 0 failures`.

- [ ] **Step 7: Commit.**

```bash
git ai-commit
```

Message: `Add AuthorFeedService for app.bsky.feed.getAuthorFeed`

---

## Task 3: `WorkspaceTab.author`, `AuthorTab`, and the workspace plumbing

**Files:**
- `core/Sources/YoruMimizukuKit/WorkspaceModel.swift` (modify)
- `core/Tests/YoruMimizukuKitTests/WorkspaceModelTests.swift` (modify)

- [ ] **Step 1: Write the failing test for `openAuthor` (append + select).**

Append to `WorkspaceModelTests`. First extend the `makeModel` helper to inject the two new closures and add an author-specific helper. Replace the existing `makeModel` body so it also passes `makeAuthorModel`/`makeAuthorHeader`:

```swift
    private final class StubAuthorProfileLoader: AuthorProfileLoading, @unchecked Sendable {
        func loadProfile(actor: String) async throws -> AuthorProfile {
            AuthorProfile(did: actor, handle: "x", displayName: "x", avatarURL: nil, bio: nil)
        }
    }

    private func makeModel(persistence: ConversationPersisting) -> WorkspaceModel {
        WorkspaceModel(
            filterStore: SavedFilterStore(port: InMemoryFilterPort()),
            persistence: persistence,
            makeThreadModel: { uri in ThreadViewModel(loader: StubThreadLoader(), uri: uri) },
            makeFilterModel: { _ in TimelineViewModel(loader: StubTimelineLoader()) },
            makeAuthorModel: { _ in TimelineViewModel(loader: StubTimelineLoader()) },
            makeAuthorHeader: { did, initial in
                ProfileHeaderViewModel(loader: StubAuthorProfileLoader(), actor: did, initial: initial)
            }
        )
    }
```

Then add the tests:

```swift
    func testOpenAuthorAppendsAndSelects() async {
        let model = makeModel(persistence: FakePersistence())

        model.openAuthor(did: "did:plc:alice", handle: "alice.bsky.social", displayName: "Alice", avatarURL: nil)

        XCTAssertEqual(model.authors.map(\.did), ["did:plc:alice"])
        XCTAssertEqual(model.authors[0].handle, "alice.bsky.social")
        XCTAssertEqual(model.authors[0].displayName, "Alice")
        guard case let .author(id) = model.selection else { return XCTFail("expected author selection") }
        XCTAssertEqual(model.author(id: id)?.did, "did:plc:alice")
    }

    func testOpenAuthorDedupesByDID() async {
        let model = makeModel(persistence: FakePersistence())

        model.openAuthor(did: "did:plc:alice", handle: "alice.bsky.social", displayName: "Alice", avatarURL: nil)
        let firstID = model.authors[0].id
        model.selection = .home
        model.openAuthor(did: "did:plc:alice", handle: "alice.bsky.social", displayName: "Alice (changed)", avatarURL: nil)

        XCTAssertEqual(model.authors.count, 1)
        XCTAssertEqual(model.selection, .author(firstID))
    }
```

- [ ] **Step 2: Run, see it fail.**

```bash
cd core && swift test --filter WorkspaceModelTests
```

Expected: compilation failure — `makeAuthorModel`/`makeAuthorHeader`, `openAuthor`, `authors`, `author(id:)`, and `WorkspaceTab.author` are not defined.

- [ ] **Step 3: Implement the enum case, `AuthorTab`, and the workspace API.**

In `core/Sources/YoruMimizukuKit/WorkspaceModel.swift`, add the enum case:

```swift
public enum WorkspaceTab: Hashable, Sendable {
    case home
    case notifications
    case filter(UUID)
    case conversation(UUID)
    case author(UUID)
}
```

Add the `AuthorTab` class (place it after `ConversationTab`):

```swift
/// One author tab: a view-only window onto a single user. Anchored on the user's
/// DID (the dedupe key), it owns a `TimelineViewModel` backed by the author feed and
/// a `ProfileHeaderViewModel` for the header. The tab captures the tapped avatar's
/// basics so its header and sidebar row render instantly; the feed and full profile
/// load lazily. Author tabs are ephemeral (never persisted).
@MainActor
public final class AuthorTab: Identifiable {
    public let id = UUID()
    /// The user's DID; used to de-duplicate tabs for the same user.
    public let did: String
    public let handle: String
    public let displayName: String
    public let avatarURL: URL?
    public let model: TimelineViewModel
    public let header: ProfileHeaderViewModel

    public init(
        did: String,
        handle: String,
        displayName: String,
        avatarURL: URL?,
        model: TimelineViewModel,
        header: ProfileHeaderViewModel
    ) {
        self.did = did
        self.handle = handle
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.model = model
        self.header = header
    }

    /// Sidebar title: the display name, falling back to the handle when blank.
    public var title: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "@\(handle)" : trimmed
    }
}
```

In `WorkspaceModel`, add the published store (it has no `didSet` — author tabs are not persisted):

```swift
    @Published public private(set) var authors: [AuthorTab] = []
```

Add the two injected closures as stored properties:

```swift
    private let makeAuthorModel: @MainActor (String) -> TimelineViewModel
    private let makeAuthorHeader: @MainActor (String, AuthorProfile?) -> ProfileHeaderViewModel
```

Extend the initializer signature and body (add the two parameters and assignments; keep everything else unchanged):

```swift
    public init(
        filterStore: SavedFilterStore,
        persistence: ConversationPersisting = EphemeralConversationStore(),
        makeThreadModel: @escaping @MainActor (String) -> ThreadViewModel,
        makeFilterModel: @escaping @MainActor (SavedFilter) -> TimelineViewModel,
        makeAuthorModel: @escaping @MainActor (String) -> TimelineViewModel,
        makeAuthorHeader: @escaping @MainActor (String, AuthorProfile?) -> ProfileHeaderViewModel
    ) {
        self.filterStore = filterStore
        self.persistence = persistence
        self.makeThreadModel = makeThreadModel
        self.makeFilterModel = makeFilterModel
        self.makeAuthorModel = makeAuthorModel
        self.makeAuthorHeader = makeAuthorHeader
        self.filters = filterStore.filters.map { FilterTab(filter: $0, makeModel: makeFilterModel) }
        restore()
    }
```

Add the author API in a new `// MARK: - Authors` section (after the conversations section):

```swift
    // MARK: - Authors

    /// Open `did` in a view-only author tab. If a tab for the same user already
    /// exists it is re-selected rather than duplicated. The tapped avatar's basics
    /// seed an instant header while the full profile loads.
    public func openAuthor(did: String, handle: String, displayName: String, avatarURL: URL?) {
        if let existing = authors.first(where: { $0.did == did }) {
            selection = .author(existing.id)
            return
        }
        let initial = AuthorProfile(
            did: did, handle: handle,
            displayName: displayName.isEmpty ? nil : displayName,
            avatarURL: avatarURL, bio: nil
        )
        let tab = AuthorTab(
            did: did, handle: handle, displayName: displayName, avatarURL: avatarURL,
            model: makeAuthorModel(did),
            header: makeAuthorHeader(did, initial)
        )
        authors.append(tab)
        selection = .author(tab.id)
    }

    /// Close an author tab. When the closed tab was selected, select the adjacent
    /// author if any, otherwise fall back to home.
    public func closeAuthor(_ id: UUID) {
        let wasSelected = selection == .author(id)
        let index = authors.firstIndex { $0.id == id }
        authors.first { $0.id == id }?.model.stopPolling()
        authors.removeAll { $0.id == id }

        guard wasSelected else { return }
        if let index, !authors.isEmpty {
            selection = .author(authors[min(index, authors.count - 1)].id)
        } else {
            selection = .home
        }
    }

    public func author(id: UUID) -> AuthorTab? {
        authors.first { $0.id == id }
    }
```

Extend `orderedTabs`:

```swift
    public var orderedTabs: [WorkspaceTab] {
        [.home, .notifications]
            + filters.map { .filter($0.id) }
            + conversations.map { .conversation($0.id) }
            + authors.map { .author($0.id) }
    }
```

- [ ] **Step 4: Run, see it pass.**

```bash
cd core && swift test --filter WorkspaceModelTests
```

Expected: `Executed N tests, with 0 failures` (all existing plus the two new ones).

- [ ] **Step 5: Add the close-fallback test.**

Append to `WorkspaceModelTests`:

```swift
    func testCloseAuthorSelectsAdjacentThenHome() async {
        let model = makeModel(persistence: FakePersistence())
        model.openAuthor(did: "did:plc:a", handle: "a", displayName: "A", avatarURL: nil)
        model.openAuthor(did: "did:plc:b", handle: "b", displayName: "B", avatarURL: nil)
        let bID = model.authors[1].id

        model.closeAuthor(bID)
        XCTAssertEqual(model.authors.map(\.did), ["did:plc:a"])
        XCTAssertEqual(model.selection, .author(model.authors[0].id))

        model.closeAuthor(model.authors[0].id)
        XCTAssertTrue(model.authors.isEmpty)
        XCTAssertEqual(model.selection, .home)
    }

    func testOrderedTabsAppendsAuthorsLast() async {
        let model = makeModel(persistence: FakePersistence())
        model.openConversation(post(id: "at://c"))
        model.openAuthor(did: "did:plc:a", handle: "a", displayName: "A", avatarURL: nil)

        XCTAssertEqual(model.orderedTabs.last, .author(model.authors[0].id))
    }
```

- [ ] **Step 6: Run, see it pass.**

```bash
cd core && swift test --filter WorkspaceModelTests
```

Expected: `Executed N tests, with 0 failures`.

- [ ] **Step 7: Run the full core suite to confirm nothing regressed.**

```bash
cd core && swift test
```

Expected: all tests pass (no failures).

- [ ] **Step 8: Commit.**

```bash
git ai-commit
```

Message: `Add author tab kind and openAuthor plumbing to WorkspaceModel`

---

## Task 4: `LiveAuthorFeedLoader`

**Files:**
- `apps/macos/Timeline/LiveAuthorFeedLoader.swift` (create)

This is app-target wiring (no SPM test target); verify by building the app. Run `xcodegen generate` first if the project is missing.

- [ ] **Step 1: Create the loader (mirrors `LiveTimelineLoader`).**

Create `apps/macos/Timeline/LiveAuthorFeedLoader.swift`:

```swift
import Foundation
import os
import BlueskyCore
import YoruMimizukuKit
import PlatformApple

/// Live `TimelineLoading` for one user's feed: wires the real `AuthorFeedService`
/// through a `LiveServiceContext`, fetches a page of `actor`'s posts (passing the
/// cursor for infinite scroll), persists any refreshed tokens, and maps the feed
/// into `PostDisplay` rows. `actor` is the user's DID.
struct LiveAuthorFeedLoader: TimelineLoading {
    let accountManager: AccountManager
    let config: OAuthClientConfig
    let actor: String

    init(accountManager: AccountManager, config: OAuthClientConfig = .yoruMimizuku, actor: String) {
        self.accountManager = accountManager
        self.config = config
        self.actor = actor
    }

    func loadPage(cursor: String?) async throws -> TimelinePage {
        let context = try LiveServiceContext(accountManager: accountManager, config: config)
        let service = AuthorFeedService(
            sender: context.sender, metadataResolver: context.metadataResolver,
            config: context.config, refreshGate: context.refreshGate
        )

        let result = try await service.getAuthorFeed(
            pds: context.account.pds,
            issuer: context.issuer,
            accessToken: context.account.accessToken,
            refreshToken: context.account.refreshToken,
            actor: actor,
            cursor: cursor,
            filter: "posts_and_author_threads"
        )

        try context.persist(result.refreshed)

        let posts = result.response.feed.map(PostDisplay.init)
        return TimelinePage(posts: posts, cursor: result.response.cursor)
    }
}
```

- [ ] **Step 2: Build the app to confirm it compiles.**

The new file is unused until Task 6 wires it, but it must compile. Add it to the project (XcodeGen picks up files under `apps/macos/` by glob; regenerate if needed) and build:

```bash
xcodegen generate
xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj CODE_SIGN_IDENTITY="-"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit.**

```bash
git ai-commit
```

Message: `Add LiveAuthorFeedLoader backing the author feed`

---

## Task 5: `LiveAuthorProfileLoader`

**Files:**
- `apps/macos/Timeline/LiveAuthorProfileLoader.swift` (create)

`ProfileService.getProfile` returns `ProfileViewBasic`, which has `did`, `handle`, `displayName?`, `avatar?` but **no `description`/bio field** (verified in `core/Sources/BlueskyCore/Models/Timeline.swift`). So `bio` maps to nil for now; the header still shows name/handle/avatar. (A follow-up could add a detailed profile model to populate bio.)

- [ ] **Step 1: Create the loader.**

Create `apps/macos/Timeline/LiveAuthorProfileLoader.swift`:

```swift
import Foundation
import BlueskyCore
import YoruMimizukuKit

/// Live `AuthorProfileLoading`: resolves a user's profile via the existing
/// `ProfileService` for the author tab header. Maps `ProfileViewBasic` into
/// `AuthorProfile`. The basic profile view carries no bio, so `bio` is nil for now;
/// the header renders display name, handle, and avatar regardless.
struct LiveAuthorProfileLoader: AuthorProfileLoading {
    let accountManager: AccountManager
    let config: OAuthClientConfig

    init(accountManager: AccountManager, config: OAuthClientConfig = .yoruMimizuku) {
        self.accountManager = accountManager
        self.config = config
    }

    func loadProfile(actor: String) async throws -> AuthorProfile {
        let context = try LiveServiceContext(accountManager: accountManager, config: config)
        let service = ProfileService(
            sender: context.sender, metadataResolver: context.metadataResolver,
            config: context.config, refreshGate: context.refreshGate
        )

        let result = try await service.getProfile(
            pds: context.account.pds,
            issuer: context.issuer,
            accessToken: context.account.accessToken,
            refreshToken: context.account.refreshToken,
            actor: actor
        )

        try context.persist(result.refreshed)

        let basic = result.response
        return AuthorProfile(
            did: basic.did,
            handle: basic.handle,
            displayName: basic.displayName,
            avatarURL: basic.avatar.flatMap(URL.init(string:)),
            bio: nil
        )
    }
}
```

- [ ] **Step 2: Build the app.**

```bash
xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj CODE_SIGN_IDENTITY="-"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit.**

```bash
git ai-commit
```

Message: `Add LiveAuthorProfileLoader mapping ProfileViewBasic to AuthorProfile`

---

## Task 6: Wire the author factories into `RootView`

**Files:**
- `apps/macos/Views/RootView.swift` (modify)

- [ ] **Step 1: Pass the two closures into `WorkspaceModel`.**

In `AuthenticatedRootView.init`, extend the `WorkspaceModel(...)` construction (the `makeThreadModel` / `makeFilterModel` site) by adding the two new closures:

```swift
        _workspace = StateObject(
            wrappedValue: WorkspaceModel(
                filterStore: filterStore,
                persistence: UserDefaultsConversationStore(key: "workspace.conversations.v1.\(did)"),
                makeThreadModel: { uri in
                    ThreadViewModel(
                        loader: LiveThreadLoader(accountManager: accountManager), uri: uri,
                        interactor: LivePostInteractor(accountManager: accountManager)
                    )
                },
                makeFilterModel: { filter in
                    TimelineViewModel(loader: LiveSearchLoader(accountManager: accountManager, subqueries: filter.subqueries))
                },
                makeAuthorModel: { authorDID in
                    TimelineViewModel(
                        loader: LiveAuthorFeedLoader(accountManager: accountManager, actor: authorDID),
                        interactor: LivePostInteractor(accountManager: accountManager)
                    )
                },
                makeAuthorHeader: { authorDID, initial in
                    ProfileHeaderViewModel(
                        loader: LiveAuthorProfileLoader(accountManager: accountManager),
                        actor: authorDID,
                        initial: initial
                    )
                }
            )
        )
```

- [ ] **Step 2: Build the app.**

```bash
xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj CODE_SIGN_IDENTITY="-"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit.**

```bash
git ai-commit
```

Message: `Wire author feed and profile factories into the workspace`

---

## Task 7: `AuthorView`

**Files:**
- `apps/macos/Views/AuthorView.swift` (create)

The view shows a profile header above a reused `FeedView`. Reusing `FeedView` brings the Phase B `f`/`o`/copy shortcuts and the avatar-tap affordance along automatically. `onOpenAuthor` is threaded through so tapping an avatar inside the author feed opens (or re-selects) that user.

- [ ] **Step 1: Create the view.**

Create `apps/macos/Views/AuthorView.swift`:

```swift
import SwiftUI
import YoruMimizukuKit

/// One author tab's content: a profile header (avatar / display name / @handle /
/// bio) above the user's posts. The feed reuses `FeedView`, so j/k focus, infinite
/// scroll, and the post action affordances come along unchanged. View-only: there
/// is no follow or edit control. The header loads on appear; the feed is polled by
/// the window only while this tab is active.
struct AuthorView: View {
    @ObservedObject var tab: AuthorTab
    @ObservedObject var header: ProfileHeaderViewModel
    @EnvironmentObject private var theme: ThemeStore

    let now: Date
    var onImageTap: ([URL], Int) -> Void
    var onOpenConversation: (PostDisplay) -> Void
    var onOpenAuthor: (PostDisplay) -> Void
    var onReply: (PostDisplay) -> Void = { _ in }
    var onQuote: (PostDisplay) -> Void = { _ in }

    init(
        tab: AuthorTab,
        now: Date,
        onImageTap: @escaping ([URL], Int) -> Void,
        onOpenConversation: @escaping (PostDisplay) -> Void,
        onOpenAuthor: @escaping (PostDisplay) -> Void,
        onReply: @escaping (PostDisplay) -> Void = { _ in },
        onQuote: @escaping (PostDisplay) -> Void = { _ in }
    ) {
        self.tab = tab
        self.header = tab.header
        self.now = now
        self.onImageTap = onImageTap
        self.onOpenConversation = onOpenConversation
        self.onOpenAuthor = onOpenAuthor
        self.onReply = onReply
        self.onQuote = onQuote
    }

    var body: some View {
        VStack(spacing: 0) {
            profileHeader
            FeedView(
                model: tab.model, title: nil, now: now,
                onImageTap: onImageTap,
                onOpenConversation: onOpenConversation,
                onOpenAuthor: onOpenAuthor,
                onReply: onReply,
                onQuote: onQuote
            )
        }
        .background(theme.canvas)
        .task { await header.load() }
    }

    private var profileHeader: some View {
        let profile = header.profile
        let name = profile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                RemoteImage(url: profile?.avatarURL ?? tab.avatarURL, maxPointSize: 56) { phase in
                    if case let .success(image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        theme.avatarPlaceholder
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(theme.hairline, lineWidth: 1))

                VStack(alignment: .leading, spacing: 2) {
                    Text((name?.isEmpty == false ? name! : "@\(tab.handle)"))
                        .font(.app(.title3, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                    Text("@\(profile?.handle ?? tab.handle)")
                        .font(.app(.callout))
                        .foregroundStyle(theme.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
            }
            if let bio = profile?.bio, !bio.isEmpty {
                Text(bio)
                    .font(.app(.callout))
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 36)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.divider).frame(height: 1)
        }
    }
}
```

Note: `FeedView`'s `onOpenAuthor` parameter is added in Task 10. Implement `AuthorView` now but expect the build to fail until Task 10 adds that parameter — OR reorder locally so Task 10's `FeedView` change lands first. To keep each task independently building, **do Task 10's `FeedView`/`PostRowView` change before building this task** (the build step below assumes Task 10's `FeedView.onOpenAuthor` exists). If you follow the listed order strictly, defer this task's build verification to after Task 10.

- [ ] **Step 2: Build the app (after Task 10's FeedView change is present).**

```bash
xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj CODE_SIGN_IDENTITY="-"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit.**

```bash
git ai-commit
```

Message: `Add AuthorView with profile header over a reused feed`

---

## Task 8: Sidebar "ユーザー" section

**Files:**
- `apps/macos/Views/SidebarView.swift` (modify)

Author rows carry no badge, mirroring the conversation section.

- [ ] **Step 1: Add the section after the conversations block.**

In `SidebarView.tabList`, after the `if !workspace.conversations.isEmpty { ... }` block (and still inside the `VStack`), add:

```swift
                if !workspace.authors.isEmpty {
                    sectionLabel("ユーザー")
                    ForEach(workspace.authors) { tab in
                        SidebarRow(
                            title: tab.title,
                            meta: "@\(tab.handle)",
                            isSelected: workspace.selection == .author(tab.id),
                            onClose: { workspace.closeAuthor(tab.id) }
                        ) { workspace.selection = .author(tab.id) }
                    }
                }
```

- [ ] **Step 2: Build the app.**

```bash
xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj CODE_SIGN_IDENTITY="-"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit.**

```bash
git ai-commit
```

Message: `Add a user section to the sidebar for author tabs`

---

## Task 9: `MainWindowView` detail case and active-only polling

**Files:**
- `apps/macos/Views/MainWindowView.swift` (modify)

Author tabs poll **only while active** — they are not started in the always-on `.task` block. `syncActiveTab()` starts polling + setActive on the selected author tab and stops polling + setActive(false) on the others.

- [ ] **Step 1: Add the `.author` detail case.**

In `MainWindowView.detail`, after the `.conversation` case, add:

```swift
        case let .author(id):
            if let tab = workspace.author(id: id) {
                AuthorView(
                    tab: tab,
                    now: now,
                    onImageTap: { urls, index in lightbox = ImageGallery(urls: urls, index: index) },
                    onOpenConversation: { workspace.openConversation($0) },
                    onOpenAuthor: { workspace.openAuthor(did: ATURI.repo($0.id) ?? "", handle: $0.authorHandle, displayName: $0.authorDisplayName, avatarURL: $0.avatarURL) },
                    onReply: { openReplyComposer($0, refreshing: tab.model) },
                    onQuote: { openQuoteComposer($0, refreshing: tab.model) }
                )
                .id(id)
            } else {
                Color.clear.background(theme.canvas)
            }
```

`ATURI` is in `BlueskyCore`; add `import BlueskyCore` to the top of `MainWindowView.swift` if it is not already imported.

- [ ] **Step 2: Extend `syncActiveTab()` for active-only author polling.**

Replace the body of `syncActiveTab()` with:

```swift
    private func syncActiveTab() {
        model.setActive(workspace.selection == .home)
        notifications.setActive(workspace.selection == .notifications)
        for tab in workspace.filters {
            tab.model.setActive(workspace.selection == .filter(tab.id))
        }
        for tab in workspace.authors {
            let isActive = workspace.selection == .author(tab.id)
            tab.model.setActive(isActive)
            if isActive {
                tab.model.startPolling(every: pollInterval)
            } else {
                tab.model.stopPolling()
            }
        }
    }
```

Do **not** add author polling to the always-on `.task` block; leave that block as-is. Because `syncActiveTab()` runs on `.task` and on every `selection` change, selecting an author tab starts its poll and deselecting it stops it.

- [ ] **Step 3: Build the app.**

```bash
xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj CODE_SIGN_IDENTITY="-"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit.**

```bash
git ai-commit
```

Message: `Render author tabs and poll them only while active`

---

## Task 10: Avatar-tap wiring from posts, notifications, and conversations

**Files:**
- `apps/macos/Views/PostRowView.swift` (modify)
- `apps/macos/Views/FeedView.swift` (modify)
- `apps/macos/Views/NotificationsView.swift` (modify)
- `apps/macos/Views/ConversationView.swift` (modify)
- `core/Sources/BlueskyCore/XRPC/ATURI.swift` (modify, only if Phase B absent)

This task adds the avatar tap to the three sources the spec names. `PostDisplay` has no DID field, so the author DID is derived from the post URI via `ATURI.repo(post.id)`.

- [ ] **Step 0 (only if Phase B is NOT merged): add `ATURI.repo` with a test.**

Confirm whether `ATURI.repo` exists:

```bash
grep -n "func repo" core/Sources/BlueskyCore/XRPC/ATURI.swift
```

If it prints nothing, add a failing test to `core/Tests/BlueskyCoreTests/ATURITests.swift` (create it if absent):

```swift
import XCTest
@testable import BlueskyCore

final class ATURITests: XCTestCase {
    func testRepoReturnsAuthority() {
        XCTAssertEqual(ATURI.repo("at://did:plc:alice/app.bsky.feed.post/aaa"), "did:plc:alice")
    }

    func testRepoReturnsNilForNonATURI() {
        XCTAssertNil(ATURI.repo("https://example.com"))
    }
}
```

Run it (`cd core && swift test --filter ATURITests`), see it fail, then add to `ATURI`:

```swift
    /// The authority (repo DID/handle) of an AT-URI, or nil when the string is not a
    /// `at://authority/collection/rkey` triple. Used to address the author of a post.
    public static func repo(_ uri: String) -> String? {
        guard uri.hasPrefix("at://") else { return nil }
        let parts = uri.dropFirst("at://".count).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[0].isEmpty else { return nil }
        return String(parts[0])
    }
```

Re-run (`cd core && swift test --filter ATURITests`), see it pass, and commit (`git ai-commit`, message `Add ATURI.repo for the author authority`). If `ATURI.repo` already exists from Phase B, skip this step entirely.

- [ ] **Step 1: Add `onAvatarTap` to `PostRowView`.**

In `PostRowView`, add the callback near the other closures (e.g. after `onQuote`):

```swift
    /// Called when the author avatar is tapped, so the host can open the author tab.
    var onAvatarTap: () -> Void = {}
```

Make the avatar tappable. Replace the `avatar` computed property with:

```swift
    private var avatar: some View {
        RemoteImage(url: post.avatarURL, maxPointSize: avatarSize) { phase in
            if case let .success(image) = phase {
                image.resizable().scaledToFill()
            } else {
                theme.avatarPlaceholder
            }
        }
        .frame(width: avatarSize, height: avatarSize)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(theme.hairline, lineWidth: 1))
        .contentShape(Circle())
        .onTapGesture { onAvatarTap() }
        .help("@\(post.authorHandle) のページを開く")
    }
```

- [ ] **Step 2: Thread `onOpenAuthor` through `FeedView`.**

In `FeedView`, add the closure after `onQuote`:

```swift
    /// Opens the author tab for a tapped avatar.
    var onOpenAuthor: (PostDisplay) -> Void = { _ in }
```

In `postList(_:)`, add `onAvatarTap` to each `PostRowView`:

```swift
                    onSelect: { focusedPostID = post.id },
                    onLike: { Task { await model.toggleLike(post) } },
                    onRepost: { Task { await model.toggleRepost(post) } },
                    onQuote: { onQuote(post) },
                    onAvatarTap: { onOpenAuthor(post) }
```

- [ ] **Step 3: Wire `onOpenAuthor` at the home and filter `FeedView` call sites in `MainWindowView`.**

In `MainWindowView.detail`, add `onOpenAuthor` to the `.home` and `.filter` `FeedView(...)` calls (the same closure used in the author case):

For `.home`:

```swift
            FeedView(
                model: model, title: nil, now: now,
                onImageTap: { urls, index in lightbox = ImageGallery(urls: urls, index: index) },
                onOpenConversation: { workspace.openConversation($0) },
                onCompose: { compose(refreshing: model) },
                onReply: { openReplyComposer($0, refreshing: model) },
                onQuote: { openQuoteComposer($0, refreshing: model) },
                onOpenAuthor: { workspace.openAuthor(did: ATURI.repo($0.id) ?? "", handle: $0.authorHandle, displayName: $0.authorDisplayName, avatarURL: $0.avatarURL) }
            )
```

For `.filter` (inside the `if let tab` branch):

```swift
                FeedView(
                    model: tab.model, title: tab.title, now: now,
                    onImageTap: { urls, index in lightbox = ImageGallery(urls: urls, index: index) },
                    onOpenConversation: { workspace.openConversation($0) },
                    onCompose: { compose(refreshing: tab.model) },
                    onReply: { openReplyComposer($0, refreshing: tab.model) },
                    onQuote: { openQuoteComposer($0, refreshing: tab.model) },
                    onOpenAuthor: { workspace.openAuthor(did: ATURI.repo($0.id) ?? "", handle: $0.authorHandle, displayName: $0.authorDisplayName, avatarURL: $0.avatarURL) }
                )
                .id("\(id)-\(tab.contentKey)")
```

The empty DID guard: `openAuthor` with an empty `did` would still open a tab; to avoid that, skip the call when the DID cannot be derived. Use a small helper on `MainWindowView` to centralize the three identical sites:

```swift
    /// Open the author tab for `post`, deriving the author DID from the post URI.
    /// No-op when the URI is not a well-formed AT-URI.
    private func openAuthor(for post: PostDisplay) {
        guard let did = ATURI.repo(post.id), !did.isEmpty else { return }
        workspace.openAuthor(did: did, handle: post.authorHandle, displayName: post.authorDisplayName, avatarURL: post.avatarURL)
    }
```

Then replace the three `onOpenAuthor:` closures (home, filter, author) with `onOpenAuthor: { openAuthor(for: $0) }`.

- [ ] **Step 4: Make notification actor avatars tappable.**

In `NotificationsView`, add an `onOpenAuthor` closure threaded from the view down to each avatar. First add a property to `NotificationsView`:

```swift
    var onOpenAuthor: (NotificationGroup.Actor) -> Void = { _ in }
```

Pass it to each row in `list(_:)`:

```swift
                NotificationRowView(item: item, now: now, onOpenAuthor: onOpenAuthor)
```

Add the property to `NotificationRowView`:

```swift
    var onOpenAuthor: (NotificationGroup.Actor) -> Void = { _ in }
```

Make `avatarCircle` tappable by passing the actor. Change the `avatarRow` and `actorList` call sites to pass the actor, and update `avatarCircle` to accept it:

In `avatarRow`:

```swift
            ForEach(Array(displayedActors.enumerated()), id: \.offset) { _, actor in
                avatarCircle(actor, size: 26)
            }
```

In `actorList`:

```swift
                    avatarCircle(actor, size: 24)
```

Replace `avatarCircle`:

```swift
    private func avatarCircle(_ actor: NotificationGroup.Actor, size: CGFloat) -> some View {
        RemoteImage(url: actor.avatarURL, maxPointSize: size) { phase in
            if case let .success(image) = phase {
                image.resizable().scaledToFill()
            } else {
                theme.avatarPlaceholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(theme.hairline, lineWidth: 1))
        .contentShape(Circle())
        .onTapGesture { onOpenAuthor(actor) }
        .help("@\(actor.handle) のページを開く")
    }
```

(The `subjectSnippet` thumbnail uses its own inline `RemoteImage`, not `avatarCircle`, so it is unaffected.)

Wire it at the `MainWindowView` `.notifications` case. `NotificationGroup.Actor` carries `displayName`, `handle`, `avatarURL` but **no DID**, so resolve by handle (`getAuthorFeed`/`getProfile` accept a handle as `actor`):

```swift
        case .notifications:
            NotificationsView(
                model: notifications, now: now,
                onOpenAuthor: { actor in
                    workspace.openAuthor(did: actor.handle, handle: actor.handle, displayName: actor.displayName, avatarURL: actor.avatarURL)
                }
            )
```

Note the dedupe key here is the handle rather than a DID. This is an accepted limitation of the notification model (no DID on the actor); opening the same user from a post (DID key) and from a notification (handle key) could create two tabs for the same user. Document this in the wiki as a known edge.

- [ ] **Step 5: Thread `onOpenAuthor` through `ConversationView`.**

In `ConversationView`, add:

```swift
    var onOpenAuthor: (PostDisplay) -> Void = { _ in }
```

Pass `onAvatarTap` to the two `PostRowView`s. In `parentBlock(_:)`:

```swift
            PostRowView(
                post: parent, density: displaySettings.density, now: now,
                showReplyMarker: false, interactiveActions: false,
                onAvatarTap: { onOpenAuthor(parent) }
            )
```

In `focusBlock(_:)`:

```swift
            PostRowView(
                post: focus, density: displaySettings.density, now: now,
                showReplyMarker: false, onImageTap: onImageTap,
                onLike: { Task { await model.toggleLike(focus) } },
                onRepost: { Task { await model.toggleRepost(focus) } },
                onAvatarTap: { onOpenAuthor(focus) }
            )
```

Wire it at the `MainWindowView` `.conversation` case:

```swift
                ConversationView(
                    model: tab.model,
                    now: now,
                    onImageTap: { urls, index in lightbox = ImageGallery(urls: urls, index: index) },
                    onOpenConversation: { workspace.openConversation($0) },
                    onOpenAuthor: { openAuthor(for: $0) }
                )
                .id(id)
```

- [ ] **Step 6: Build the app (this also unblocks Task 7's `AuthorView` build).**

```bash
xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj CODE_SIGN_IDENTITY="-"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Run the full core suite once more.**

```bash
cd core && swift test
```

Expected: all tests pass.

- [ ] **Step 8: Commit.**

```bash
git ai-commit
```

Message: `Open author tabs from post, notification, and conversation avatars`

---

## Done criteria

- [ ] Tapping an avatar in the home feed, a filter feed, a notification row, a conversation, or an author feed opens (or re-selects) that user's tab.
- [ ] The author tab shows a profile header (avatar / display name / @handle / bio when available) above the user's `getAuthorFeed` posts (`filter=posts_and_author_threads`).
- [ ] Re-tapping the same user (by DID) re-selects the existing tab instead of duplicating it.
- [ ] The author tab is view-only (no follow/edit), carries no sidebar badge, and is not persisted across launches.
- [ ] The author feed polls only while its tab is the active selection.
- [ ] `cd core && swift test` is green and the app builds with `xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj CODE_SIGN_IDENTITY="-"`.

## Notes / assumptions

- **Bio is nil for now.** `ProfileService` decodes `profileViewDetailed` into `ProfileViewBasic`, which models only `did`/`handle`/`displayName`/`avatar` — no `description`. So `AuthorProfile.bio` is nil until a detailed profile model is added; the header still renders name/handle/avatar. The header VM and view already accommodate a non-nil bio for that future work.
- **Notification actors have no DID.** `NotificationGroup.Actor` exposes only `displayName`/`handle`/`avatarURL`. Author tabs opened from notifications dedupe by handle (passed as both the `actor` query value and the dedupe key), whereas tabs opened from posts dedupe by DID. Opening the same user from both sources can briefly create two tabs; this is an accepted limitation given the model.
- **Phase B dependency.** This plan relies on `ATURI.repo(_:)` from Phase B to derive a post author's DID. Task 10 Step 0 adds it (with a test) if Phase B has not yet landed.
- **Task ordering caveat.** `AuthorView` (Task 7) references `FeedView.onOpenAuthor`, which Task 10 adds. Either land Task 10's `FeedView`/`PostRowView` change before building Task 7, or treat Tasks 7 and 10 as one build unit. All commits remain individually meaningful.
