# Phase D: Conversation Child Reply Tree Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render the recursive child reply tree below the anchor post in the conversation view, with shallow indentation, a left connecting line, a depth cap (~3 levels), and a "さらに表示" re-anchor button for deeper subtrees.

**Architecture:** `app.bsky.feed.getPostThread` is asked for descendants (`depth>0`); `ThreadViewPost` gains a tolerant `replies` array that skips notFound/blocked nodes. A pure `ThreadNode` tree model and `childTree(of:maxDepth:)` builder map the anchor's descendants into depth-tagged display nodes. `ThreadViewModel` loads a `ConversationThread` (focus + child tree) and `ConversationView` renders the focus's ancestors+focus (unchanged) followed by the indented child tree.

**Tech Stack:** Swift 6.0, SwiftUI, XCTest, AT Protocol XRPC (app.bsky.feed.getPostThread)

---

## File Structure

| File | Created/Modified | Responsibility |
|---|---|---|
| `core/Sources/BlueskyCore/Models/Thread.swift` | Modify | Add tolerant `replies: [ThreadViewPost]` decoding + `ReplyNodeBox`; add `init(post:parent:replies:)` |
| `core/Tests/BlueskyCoreTests/ThreadResponseTests.swift` | Modify | New test: decode a `replies` array (nested + a skipped notFound child) |
| `core/Sources/BlueskyCore/XRPC/ThreadService.swift` | Modify | `threadURL` requests descendants (`depth=6`); update doc comment |
| `core/Tests/BlueskyCoreTests/ThreadServiceTests.swift` | Modify | Assert the request URL carries a positive `depth` |
| `core/Sources/YoruMimizukuKit/ThreadNode.swift` | Create | Pure `ThreadNode` tree model + `childTree(of:maxDepth:)` builder |
| `core/Tests/YoruMimizukuKitTests/ThreadNodeTests.swift` | Create | Order, nesting, depth assignment, maxDepth truncation |
| `core/Sources/YoruMimizukuKit/ThreadViewModel.swift` | Modify | Add `ConversationThread`; change `ThreadLoading` + `State.loaded` to it |
| `core/Tests/YoruMimizukuKitTests/ThreadViewModelTests.swift` | Modify | StubLoader returns `ConversationThread`; update assertions |
| `apps/macos/Timeline/LiveThreadLoader.swift` | Modify | Build `ConversationThread(focus:replies:)` from the thread response |
| `apps/macos/Views/ConversationView.swift` | Modify | Render the child tree (indent + connector + depth-cap + さらに表示 re-anchor) |

---

## Task 1: ThreadViewPost gains tolerant `replies` decoding

The lexicon's `threadViewPost.replies` is an array whose elements are `threadViewPost | notFoundPost | blockedPost`. A notFound/blocked element has no `post`, so decoding it as `ThreadViewPost` throws — we collapse those out, mirroring the `FacetFeatureBox` idiom in `Timeline.swift`. Server reply order is preserved.

**Files:**
- Modify: `core/Sources/BlueskyCore/Models/Thread.swift`
- Test: `core/Tests/BlueskyCoreTests/ThreadResponseTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `core/Tests/BlueskyCoreTests/ThreadResponseTests.swift`, inside the `final class ThreadResponseTests` body (before the closing brace):

```swift
    func testDecodesChildRepliesSkippingNotFoundAndBlocked() throws {
        let body = Data(##"""
        {
          "thread": {
            "$type": "app.bsky.feed.defs#threadViewPost",
            "post": {
              "uri": "at://did:plc:a/app.bsky.feed.post/anchor",
              "cid": "cida",
              "author": { "did": "did:plc:a", "handle": "alice.bsky.social" },
              "record": { "text": "起点", "createdAt": "2026-06-04T12:00:00.000Z" },
              "indexedAt": "2026-06-04T12:00:01.000Z"
            },
            "replies": [
              {
                "$type": "app.bsky.feed.defs#threadViewPost",
                "post": {
                  "uri": "at://did:plc:b/app.bsky.feed.post/b",
                  "cid": "cidb",
                  "author": { "did": "did:plc:b", "handle": "bob.bsky.social" },
                  "record": { "text": "返信B", "createdAt": "2026-06-04T12:05:00.000Z" },
                  "indexedAt": "2026-06-04T12:05:01.000Z"
                },
                "replies": [
                  {
                    "$type": "app.bsky.feed.defs#threadViewPost",
                    "post": {
                      "uri": "at://did:plc:c/app.bsky.feed.post/c",
                      "cid": "cidc",
                      "author": { "did": "did:plc:c", "handle": "carol.bsky.social" },
                      "record": { "text": "返信C", "createdAt": "2026-06-04T12:06:00.000Z" },
                      "indexedAt": "2026-06-04T12:06:01.000Z"
                    }
                  }
                ]
              },
              {
                "$type": "app.bsky.feed.defs#notFoundPost",
                "uri": "at://did:plc:ghost/app.bsky.feed.post/gone",
                "notFound": true
              },
              {
                "$type": "app.bsky.feed.defs#threadViewPost",
                "post": {
                  "uri": "at://did:plc:d/app.bsky.feed.post/d",
                  "cid": "cidd",
                  "author": { "did": "did:plc:d", "handle": "dave.bsky.social" },
                  "record": { "text": "返信D", "createdAt": "2026-06-04T12:07:00.000Z" },
                  "indexedAt": "2026-06-04T12:07:01.000Z"
                }
              }
            ]
          }
        }
        """##.utf8)

        let response = try JSONDecoder().decode(ThreadResponse.self, from: body)

        // notFound child dropped: B and D remain, in server order.
        XCTAssertEqual(response.thread.replies.count, 2)
        XCTAssertEqual(response.thread.replies[0].post.author.handle, "bob.bsky.social")
        XCTAssertEqual(response.thread.replies[1].post.author.handle, "dave.bsky.social")
        // Nested reply under B.
        XCTAssertEqual(response.thread.replies[0].replies.count, 1)
        XCTAssertEqual(response.thread.replies[0].replies[0].post.author.handle, "carol.bsky.social")
        // A leaf reply has no children.
        XCTAssertTrue(response.thread.replies[1].replies.isEmpty)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd core && swift test --filter ThreadResponseTests/testDecodesChildRepliesSkippingNotFoundAndBlocked`
Expected: FAIL — compile error `value of type 'ThreadViewPost' has no member 'replies'`.

- [ ] **Step 3: Add `replies` storage, decoding, and the `ReplyNodeBox` wrapper**

In `core/Sources/BlueskyCore/Models/Thread.swift`, edit the `ThreadViewPost` struct. First add the stored property right after `private let parentRef: ParentNodeRef?`:

```swift
    public let post: PostView
    private let parentRef: ParentNodeRef?

    /// The post's direct replies, in the order the server returned them. notFound /
    /// blocked children are dropped (they have no `post`), so this only carries
    /// viewable descendant nodes. Empty when the thread was fetched without
    /// descendants or the post has no viewable replies.
    public let replies: [ThreadViewPost]
```

Replace the two existing initializers and the `parentPost` accessor block so all three designated paths set `replies`:

```swift
    /// The next node up the reply tree, if any.
    public var parent: ThreadViewPost? { parentRef?.node }

    /// The hydrated immediate parent post, if any. Convenience over `parent.post`.
    public var parentPost: PostView? { parent?.post }

    public init(post: PostView, parent: ThreadViewPost? = nil, replies: [ThreadViewPost] = []) {
        self.post = post
        self.parentRef = parent.map(ParentNodeRef.init)
        self.replies = replies
    }

    /// Convenience initializer that wraps a bare parent post into a node. Kept so
    /// callers/tests can build a single-level thread without nesting by hand.
    public init(post: PostView, parentPost: PostView?) {
        self.init(post: post, parent: parentPost.map { ThreadViewPost(post: $0) })
    }
```

Add `replies` to `CodingKeys` and decode it tolerantly in `init(from:)`:

```swift
    enum CodingKeys: String, CodingKey { case post, parent, replies }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.post = try container.decode(PostView.self, forKey: .post)
        // A notFound/blocked parent has no `post`, so its decode throws and we
        // collapse it (and anything above it) to nil; a real parent recurses.
        let parent = (try? container.decodeIfPresent(ThreadViewPost.self, forKey: .parent)) ?? nil
        self.parentRef = parent.map(ParentNodeRef.init)
        // Replies are a union (threadViewPost | notFoundPost | blockedPost); the
        // non-viewable shapes have no `post` and decode to a nil box node, so we
        // drop them while preserving the server's ordering for the rest.
        let boxes = (try? container.decode([ReplyNodeBox].self, forKey: .replies)) ?? []
        self.replies = boxes.compactMap(\.node)
    }
```

Then add the `ReplyNodeBox` wrapper just below the `ParentNodeRef` class at the end of the file:

```swift
/// Wrapper that decodes one reply-list element tolerantly: a notFound / blocked
/// node has no `post`, so decoding it as `ThreadViewPost` throws and `node`
/// becomes nil rather than failing the whole reply list. Mirrors the
/// `FacetFeatureBox` idiom in `Timeline.swift`.
private struct ReplyNodeBox: Decodable {
    let node: ThreadViewPost?

    init(from decoder: Decoder) throws {
        self.node = try? ThreadViewPost(from: decoder)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd core && swift test --filter ThreadResponseTests`
Expected: PASS (all `ThreadResponseTests`, including the existing parent-chain tests).

- [ ] **Step 5: Commit**

```bash
git add core/Sources/BlueskyCore/Models/Thread.swift core/Tests/BlueskyCoreTests/ThreadResponseTests.swift
git ai-commit -m "Decode threadViewPost child replies, skipping notFound and blocked nodes"
```

---

## Task 2: Request descendants from getPostThread

`threadURL` currently sends `depth=0` (ancestors only). Phase D needs descendants, so raise `depth` to a positive value. Use `6` so a 3-level rendered tree always has room and the "さらに表示" affordance has real data below it.

**Files:**
- Modify: `core/Sources/BlueskyCore/XRPC/ThreadService.swift:74-81`
- Test: `core/Tests/BlueskyCoreTests/ThreadServiceTests.swift:57-58`

- [ ] **Step 1: Update the existing test to assert a positive depth**

In `core/Tests/BlueskyCoreTests/ThreadServiceTests.swift`, find this block (around line 57):

```swift
        XCTAssertTrue(sent.url.query?.contains("uri=") == true)
        XCTAssertTrue(sent.url.query?.contains("parentHeight=80") == true)
```

Replace it with:

```swift
        XCTAssertTrue(sent.url.query?.contains("uri=") == true)
        XCTAssertTrue(sent.url.query?.contains("parentHeight=80") == true)
        XCTAssertTrue(sent.url.query?.contains("depth=6") == true, "expected descendants requested: \(sent.url.query ?? "")")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd core && swift test --filter ThreadServiceTests`
Expected: FAIL — assertion `expected descendants requested` (current URL sends `depth=0`).

- [ ] **Step 3: Raise the requested depth**

In `core/Sources/BlueskyCore/XRPC/ThreadService.swift`, replace the doc comment and `queryItems` inside `threadURL`:

```swift
        // The conversation view climbs the full ancestor chain above the focused
        // post AND renders a few levels of descendants below it, so request both:
        // the lexicon's default ancestor height and a descendant depth deep enough
        // to feed the rendered child tree (3 levels) plus its "さらに表示" cue.
        components.queryItems = [
            URLQueryItem(name: "uri", value: uri),
            URLQueryItem(name: "depth", value: "6"),
            URLQueryItem(name: "parentHeight", value: "80")
        ]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd core && swift test --filter ThreadServiceTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add core/Sources/BlueskyCore/XRPC/ThreadService.swift core/Tests/BlueskyCoreTests/ThreadServiceTests.swift
git ai-commit -m "Request thread descendants so the conversation child tree has data"
```

---

## Task 3: ThreadNode model and childTree builder

A pure tree of display nodes for the anchor's descendants. Each node carries its `depth` (0 = a direct reply of the anchor). Recursion stops once `depth == maxDepth`: nodes at the cap keep `replies: []` so the view shows a "さらに表示" affordance instead of rendering deeper. Children map via `PostDisplay(postView:)` (no replyParent chain needed — the ancestor context is the anchor itself).

**Files:**
- Create: `core/Sources/YoruMimizukuKit/ThreadNode.swift`
- Test: `core/Tests/YoruMimizukuKitTests/ThreadNodeTests.swift`

- [ ] **Step 1: Write the failing test**

Create `core/Tests/YoruMimizukuKitTests/ThreadNodeTests.swift`:

```swift
import XCTest
@testable import YoruMimizukuKit
import BlueskyCore

final class ThreadNodeTests: XCTestCase {
    // Build a hydrated PostView with the given uri/handle and a child reply list.
    private func post(_ uri: String, handle: String) -> PostView {
        PostView(
            uri: uri, cid: "cid-\(uri)",
            author: Author(did: "did:\(handle)", handle: handle, displayName: nil, avatar: nil),
            record: PostRecord(text: "t-\(uri)", createdAt: "2026-06-04T12:00:00.000Z", facets: nil, reply: nil),
            embed: nil, replyCount: 0, repostCount: 0, likeCount: 0, indexedAt: "2026-06-04T12:00:01.000Z", viewer: nil
        )
    }

    private func node(_ uri: String, handle: String, replies: [ThreadViewPost] = []) -> ThreadViewPost {
        ThreadViewPost(post: post(uri, handle: handle), parent: nil, replies: replies)
    }

    func testMultipleChildrenPreserveServerOrder() {
        let anchor = node("anchor", handle: "a", replies: [
            node("b", handle: "b"),
            node("c", handle: "c")
        ])

        let tree = ThreadNode.childTree(of: anchor, maxDepth: 3)

        XCTAssertEqual(tree.map(\.id), ["b", "c"])
        XCTAssertEqual(tree.map(\.depth), [0, 0])
    }

    func testNestedChildrenIncrementDepth() {
        let anchor = node("anchor", handle: "a", replies: [
            node("b", handle: "b", replies: [
                node("c", handle: "c")
            ])
        ])

        let tree = ThreadNode.childTree(of: anchor, maxDepth: 3)

        XCTAssertEqual(tree.count, 1)
        XCTAssertEqual(tree[0].depth, 0)
        XCTAssertEqual(tree[0].replies.count, 1)
        XCTAssertEqual(tree[0].replies[0].id, "c")
        XCTAssertEqual(tree[0].replies[0].depth, 1)
    }

    func testMaxDepthTruncationLeavesRepliesEmpty() {
        // anchor -> b(0) -> c(1) -> d(2); with maxDepth 1, c is at the cap so its
        // own children (d) are not built.
        let anchor = node("anchor", handle: "a", replies: [
            node("b", handle: "b", replies: [
                node("c", handle: "c", replies: [
                    node("d", handle: "d")
                ])
            ])
        ])

        let tree = ThreadNode.childTree(of: anchor, maxDepth: 1)

        XCTAssertEqual(tree[0].id, "b")
        XCTAssertEqual(tree[0].replies[0].id, "c")
        XCTAssertEqual(tree[0].replies[0].depth, 1)
        XCTAssertTrue(tree[0].replies[0].replies.isEmpty, "node at the depth cap must not build deeper children")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd core && swift test --filter ThreadNodeTests`
Expected: FAIL — `cannot find 'ThreadNode' in scope`.

> Note: `PostView`, `Author`, `PostRecord` are existing `BlueskyCore` models. If their member-wise initializer parameter names differ from the test (e.g. `replyCount`/`viewer`), adjust the test's `post(_:handle:)` helper to match the real `PostView` initializer — read `core/Sources/BlueskyCore/Models/Timeline.swift` for the exact signature. Keep the assertions unchanged.

- [ ] **Step 3: Write the ThreadNode model and builder**

Create `core/Sources/YoruMimizukuKit/ThreadNode.swift`:

```swift
import Foundation
import BlueskyCore

/// A node in the conversation's child reply tree (below the anchor post). It is a
/// pure, value-typed display model: `post` is UI-ready, `replies` are the node's
/// own children (already capped by the builder), and `depth` is the render depth
/// where 0 is a direct reply of the anchor. Built by `childTree(of:maxDepth:)`.
public struct ThreadNode: Identifiable, Equatable, Sendable {
    public let post: PostDisplay
    public let replies: [ThreadNode]
    public let depth: Int

    public var id: String { post.id }

    public init(post: PostDisplay, replies: [ThreadNode], depth: Int) {
        self.post = post
        self.replies = replies
        self.depth = depth
    }

    /// Map the anchor's descendant `ThreadViewPost`s into a depth-tagged tree,
    /// preserving server order. Recursion stops once a node sits at `maxDepth`:
    /// such a node keeps `replies: []` so the view can show a "さらに表示" cue and
    /// re-anchor deeper. `maxDepth` is the deepest rendered depth (0-based), so
    /// `maxDepth: 3` renders depths 0, 1, 2, 3.
    public static func childTree(of node: ThreadViewPost, maxDepth: Int) -> [ThreadNode] {
        build(replies: node.replies, depth: 0, maxDepth: maxDepth)
    }

    private static func build(replies: [ThreadViewPost], depth: Int, maxDepth: Int) -> [ThreadNode] {
        replies.map { child in
            let deeper = depth < maxDepth
                ? build(replies: child.replies, depth: depth + 1, maxDepth: maxDepth)
                : []
            return ThreadNode(
                post: PostDisplay(postView: child.post),
                replies: deeper,
                depth: depth
            )
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd core && swift test --filter ThreadNodeTests`
Expected: PASS (all three cases).

- [ ] **Step 5: Commit**

```bash
git add core/Sources/YoruMimizukuKit/ThreadNode.swift core/Tests/YoruMimizukuKitTests/ThreadNodeTests.swift
git ai-commit -m "Add ThreadNode tree model and depth-capped childTree builder"
```

---

## Task 4: ConversationThread threads focus + child tree through the view model

`ThreadLoading` must now hand the view model both the focus (with its ancestor chain, unchanged) and the child tree. Introduce `ConversationThread` and switch `ThreadLoading.loadThread` and `State.loaded` to it. `toggleLike`/`toggleRepost` keep operating on the focus only — toggling a reply node in place is intentionally out of scope (tapping a reply re-anchors the tab, which reloads it as a focus). The focus accessors read `state`'s `focus`.

**Files:**
- Modify: `core/Sources/YoruMimizukuKit/ThreadViewModel.swift`
- Test: `core/Tests/YoruMimizukuKitTests/ThreadViewModelTests.swift`

- [ ] **Step 1: Update the tests to the new return type**

In `core/Tests/YoruMimizukuKitTests/ThreadViewModelTests.swift`, replace the `StubLoader` class and the two affected test bodies.

Replace the stub:

```swift
    private final class StubLoader: ThreadLoading, @unchecked Sendable {
        var result: Result<ConversationThread, Error>
        private(set) var requestedURIs: [String] = []
        init(result: Result<ConversationThread, Error>) { self.result = result }
        func loadThread(uri: String) async throws -> ConversationThread {
            requestedURIs.append(uri)
            return try result.get()
        }
    }
```

Replace `testToggleLikeUpdatesFocusedPost`:

```swift
    func testToggleLikeUpdatesFocusedPost() async {
        let focus = sample(id: "reply")
        let thread = ConversationThread(focus: focus, replies: [])
        let vm = ThreadViewModel(loader: StubLoader(result: .success(thread)), uri: "reply", interactor: FakeInteractor())
        await vm.load()

        await vm.toggleLike(focus)

        guard case let .loaded(updated) = vm.state else { return XCTFail("expected loaded") }
        XCTAssertTrue(updated.focus.isLiked)
        XCTAssertEqual(updated.focus.viewerLikeURI, "at://me/app.bsky.feed.like/new")
    }
```

Replace `testInitialStateIsIdle`:

```swift
    func testInitialStateIsIdle() {
        let thread = ConversationThread(focus: sample(id: "x"), replies: [])
        let vm = ThreadViewModel(loader: StubLoader(result: .success(thread)), uri: "x")
        XCTAssertEqual(vm.state, .idle)
    }
```

Replace `testSuccessfulLoadReachesLoadedAndRequestsURI`:

```swift
    func testSuccessfulLoadReachesLoadedAndRequestsURI() async {
        let parent = sample(id: "root")
        let focus = sample(id: "reply", parent: parent)
        let thread = ConversationThread(focus: focus, replies: [])
        let loader = StubLoader(result: .success(thread))
        let vm = ThreadViewModel(loader: loader, uri: "reply")

        await vm.load()

        XCTAssertEqual(vm.state, .loaded(thread))
        XCTAssertEqual(loader.requestedURIs, ["reply"])
    }
```

Replace `testFailedLoadReachesFailed` (the failure generic argument changes):

```swift
    func testFailedLoadReachesFailed() async {
        let vm = ThreadViewModel(loader: StubLoader(result: .failure(StubError())), uri: "x")
        await vm.load()
        guard case .failed = vm.state else {
            return XCTFail("expected failed state, got \(vm.state)")
        }
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd core && swift test --filter ThreadViewModelTests`
Expected: FAIL — `cannot find type 'ConversationThread' in scope` and `loadThread` signature mismatch.

- [ ] **Step 3: Add `ConversationThread` and rewire the view model**

In `core/Sources/YoruMimizukuKit/ThreadViewModel.swift`, replace the `ThreadLoading` protocol declaration and the top-of-file comment block down through it with:

```swift
import Foundation
import BlueskyCore

/// The data a conversation tab renders: the focused post (carrying its ancestor
/// chain via `replyParent`, unchanged from before) plus the child reply tree
/// below it. The app provides the live loader (authenticated XRPC + mapping);
/// tests inject a stub.
public struct ConversationThread: Equatable, Sendable {
    public let focus: PostDisplay
    public let replies: [ThreadNode]

    public init(focus: PostDisplay, replies: [ThreadNode]) {
        self.focus = focus
        self.replies = replies
    }
}

/// Loads a single post's thread as a `ConversationThread`: the focus's
/// `replyParent` is its immediate ancestor (recursively, when present), and
/// `replies` is the descendant tree below the focus.
public protocol ThreadLoading: Sendable {
    func loadThread(uri: String) async throws -> ConversationThread
}
```

Change the `State` enum's `loaded` case:

```swift
    public enum State: Equatable {
        case idle
        case loading
        case loaded(ConversationThread)
        case failed(String)

        public var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }
    }
```

Update the focus accessor and writer so they reach through `ConversationThread.focus`:

```swift
    /// Only the focused post is interactive in the conversation view; reply nodes
    /// are re-anchor targets, so a non-matching id resolves to nil.
    private func post(id: String) -> PostDisplay? {
        guard case let .loaded(thread) = state, thread.focus.id == id else { return nil }
        return thread.focus
    }

    private func write(_ post: PostDisplay) {
        guard case let .loaded(thread) = state, thread.focus.id == post.id else { return }
        state = .loaded(ConversationThread(focus: post, replies: thread.replies))
    }
```

Update `load()` to bind the new return type (variable rename for clarity):

```swift
    /// Load the thread for `uri`, moving through loading -> loaded/failed.
    public func load() async {
        state = .loading
        do {
            let thread = try await loader.loadThread(uri: uri)
            state = .loaded(thread)
        } catch {
            SessionExpiry.reportIfExpired(error)
            state = .failed(String(describing: error))
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd core && swift test --filter ThreadViewModelTests`
Expected: PASS.

- [ ] **Step 5: Run the whole core suite to confirm nothing else broke**

Run: `cd core && swift test`
Expected: PASS (BlueskyCoreTests + YoruMimizukuKitTests).

- [ ] **Step 6: Commit**

```bash
git add core/Sources/YoruMimizukuKit/ThreadViewModel.swift core/Tests/YoruMimizukuKitTests/ThreadViewModelTests.swift
git ai-commit -m "Thread focus and child reply tree through ConversationThread"
```

---

## Task 5: LiveThreadLoader builds a ConversationThread

The live loader currently returns a `PostDisplay`; update it to build the focus (ancestor chain) plus the child tree from the same response. Use `maxDepth: 3` to match the rendered cap. This is an app target, so verify by building (no unit test target wires the live loader).

**Files:**
- Modify: `apps/macos/Timeline/LiveThreadLoader.swift`

- [ ] **Step 1: Build the app to see the type mismatch**

If `YoruMimizuku.xcodeproj` is missing, run `xcodegen generate` first.

Run: `xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj CODE_SIGN_IDENTITY="-"`
Expected: FAIL — `LiveThreadLoader` no longer conforms to `ThreadLoading` (`loadThread` must return `ConversationThread`).

- [ ] **Step 2: Build the ConversationThread in the loader**

In `apps/macos/Timeline/LiveThreadLoader.swift`, change the return type and the final mapping. Replace the signature line:

```swift
    func loadThread(uri: String) async throws -> ConversationThread {
```

and replace the trailing `return PostDisplay(result.response.thread)` with:

```swift
        let thread = result.response.thread
        return ConversationThread(
            focus: PostDisplay(thread),
            replies: ThreadNode.childTree(of: thread, maxDepth: 3)
        )
```

Update the doc comment above the struct to mention the child tree:

```swift
/// Live `ThreadLoading`: wires the real `ThreadService` through a
/// `LiveServiceContext`, fetches a post's thread, persists any refreshed tokens,
/// and maps the focused post (with its ancestor chain) plus the descendant reply
/// tree into a `ConversationThread`.
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj CODE_SIGN_IDENTITY="-"`
Expected: FAIL — but now the only errors are in `ConversationView.swift` (it still switches on `case let .loaded(focus)` expecting a `PostDisplay`). The loader itself compiles. This is expected; Task 6 fixes the view.

- [ ] **Step 4: Commit**

```bash
git add apps/macos/Timeline/LiveThreadLoader.swift
git ai-commit -m "Build ConversationThread with focus and child tree in LiveThreadLoader"
```

---

## Task 6: ConversationView renders the child reply tree

Switch the view to a `ConversationThread`, keep the ancestors + focus rendering (now reading `thread.focus`), and add an indented recursive child tree below the focus. Each reply node is an interactive `PostRowView` inset by `depth * indentStep` with a left connector line. Nodes with non-empty `replies` recurse. A node truncated at the cap — a rendered leaf (`replies` empty) whose post still has `replyCount > 0` — shows a "さらに表示" button that re-anchors via `onOpenConversation(node.post)`. App target: verify by building.

**Files:**
- Modify: `apps/macos/Views/ConversationView.swift`

- [ ] **Step 1: Switch `loaded` to ConversationThread and render the child tree**

In `apps/macos/Views/ConversationView.swift`, replace the `case let .loaded(focus):` arm of the `content` switch:

```swift
        case let .loaded(thread):
            loaded(thread)
        }
```

Replace the `loaded(_ focus:)` function with one that takes the thread and appends the child tree after the focus:

```swift
    private func loaded(_ thread: ConversationThread) -> some View {
        let focus = thread.focus
        let ancestors = self.ancestors(of: focus)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if ancestors.isEmpty {
                    rootNotice
                }
                ForEach(ancestors) { ancestor in
                    parentBlock(ancestor)
                    Divider().overlay(theme.divider)
                    connector
                }
                focusBlock(focus)
                Divider().overlay(theme.divider)
                replyTree(thread.replies)
            }
        }
    }
```

Add the recursive child-tree views. Insert these methods right after `focusBlock(_:)` (before `connector`):

```swift
    /// Render the anchor's descendant reply nodes as a shallow indented tree. Each
    /// node is interactive (likes); deeper nodes recurse. A node whose subtree was
    /// truncated at the depth cap (a rendered leaf that still reports replies) gets
    /// a "さらに表示" button that re-anchors the tab on it.
    @ViewBuilder
    private func replyTree(_ nodes: [ThreadNode]) -> some View {
        ForEach(nodes) { node in
            replyRow(node)
            Divider().overlay(theme.divider)
            if node.replies.isEmpty {
                if node.post.replyCount > 0 {
                    showMoreButton(node.post)
                }
            } else {
                replyTree(node.replies)
            }
        }
    }

    /// One reply node: a left connector line + the post row, inset by its depth so
    /// the thread reads as a shallow outline without running off-screen.
    private func replyRow(_ node: ThreadNode) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(theme.divider)
                .frame(width: 2)
            PostRowView(
                post: node.post, density: displaySettings.density, now: now,
                showReplyMarker: false, onImageTap: onImageTap,
                onLike: { Task { await model.toggleLike(node.post) } },
                onRepost: { Task { await model.toggleRepost(node.post) } }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(node.depth + 1) * indentStep)
    }

    /// Re-anchor cue for a subtree that was cut at the depth cap. Tapping opens the
    /// node as a fresh conversation anchor (reusing the existing re-anchor path),
    /// which reloads it with its own descendants.
    private func showMoreButton(_ post: PostDisplay) -> some View {
        Button {
            onOpenConversation(post)
        } label: {
            Label("さらに表示", systemImage: "ellipsis.bubble")
                .font(.app(.caption))
                .foregroundStyle(theme.accent)
        }
        .buttonStyle(.plain)
        .padding(.leading, 16 + indentStep)
        .padding(.vertical, 8)
    }

    /// One indentation step for the reply tree. Modest so deep trees stay readable.
    private var indentStep: CGFloat { 18 }
```

- [ ] **Step 2: Update the header doc comment to mention the child tree**

Replace the file-top doc comment for `ConversationView`:

```swift
/// One conversation tab's content: the focused post (left-marked as "current")
/// preceded by its full ancestor chain (oldest first, each tappable to re-anchor)
/// and followed by its descendant reply tree. The ancestor chain comes from the
/// recursive `replyParent` links; the reply tree comes from `ConversationThread.replies`,
/// rendered with shallow indentation, a left connector line, a depth cap, and a
/// "さらに表示" re-anchor button for subtrees cut at the cap.
```

- [ ] **Step 3: Build to verify it compiles**

If `YoruMimizuku.xcodeproj` is missing, run `xcodegen generate` first.

Run: `xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj CODE_SIGN_IDENTITY="-"`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run the full core suite once more to confirm green end-to-end**

Run: `cd core && swift test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Views/ConversationView.swift
git ai-commit -m "Render the conversation child reply tree with indentation and re-anchor"
```

---

## Self-Review Notes

- **Spec coverage (5.6):** fetch children → Task 2 (`depth=6`); decode replies skipping notFound/blocked → Task 1 (`ReplyNodeBox`); recursive tree model + depth cap → Task 3 (`childTree(of:maxDepth:)`); VM/loader threading → Tasks 4–5 (`ConversationThread`); 1-step indentation + left connector + depth cap (~3 levels) + "show more"/re-anchor reusing `onOpenConversation` → Task 6.
- **Type consistency:** `ThreadNode`, `childTree(of:maxDepth:)`, `ConversationThread`, `ReplyNodeBox`, `replies` are used identically across all tasks. `ThreadLoading.loadThread` returns `ConversationThread` in the protocol (Task 4), the stub (Task 4), and the live loader (Task 5); `State.loaded(ConversationThread)` is consumed by the view (Task 6).
- **maxDepth:** the builder treats `maxDepth` as the deepest 0-based render depth, so `maxDepth: 3` renders depths 0–3 (four rows of replies). The live loader and the rendered cap both use `3`.
- **Toggle scope:** `toggleLike`/`toggleRepost` mutate the focus only; reply-node action callbacks are wired but their controller `post(id:)` returns nil for non-focus ids, so they are inert until the node is re-anchored. This is intentional for Phase D.
