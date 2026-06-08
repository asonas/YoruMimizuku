# Phase B: f-like / permalink copy / o-browser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add keyboard-driven liking (`f`), a permalink copy icon, and browser-open (`o`) for the focused post, working in both the feed and the conversation view.

**Architecture:** A pure, unit-tested core builds the `https://bsky.app/profile/{handle-or-did}/post/{rkey}` permalink (`PostPermalink.url(for:)` in `YoruMimizukuKit`, backed by a new `ATURI.repo` DID extractor in `BlueskyCore`). The view layer wires three thin, untestable side effects directly in the macOS SwiftUI views: `model.toggleLike` for `f`, `NSPasteboard` for the copy icon, and `NSWorkspace.open` for `o`. Per the design these side effects are intentionally inline (no injected port) because only the permalink builder carries logic worth testing.

**Tech Stack:** Swift 6.0, SwiftUI, XCTest, AppKit (NSPasteboard/NSWorkspace)

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `core/Sources/BlueskyCore/XRPC/ATURI.swift` | Modify | Add `repo(_:)` returning the AT-URI authority (the DID). |
| `core/Tests/BlueskyCoreTests/ATURITests.swift` | Modify | Tests for `ATURI.repo`. |
| `core/Sources/YoruMimizukuKit/PostPermalink.swift` | Create | Pure `PostPermalink.url(for:)` permalink builder. |
| `core/Tests/YoruMimizukuKitTests/PostPermalinkTests.swift` | Create | Unit tests covering handle / DID / fallback / nil cases. |
| `apps/macos/Views/FeedView.swift` | Modify | `f` like + `o` browser shortcuts; `copyPermalink` NSPasteboard helper; wire `onCopyLink`. |
| `apps/macos/Views/PostRowView.swift` | Modify | Add copy-link icon button + `onCopyLink` closure to the interactive action bar. |
| `apps/macos/Views/ConversationView.swift` | Modify | Apply `f` / `o` / copy-link to the conversation's focused post. |

References: design spec `docs/superpowers/specs/2026-06-08-yorumimizuku-timeline-ux-enhancements-design.md` sections 5.3 (`f` でいいね) and 5.4 (permalink コピー + `o` でブラウザ).

---

## Task 1: `ATURI.repo()` DID extractor (BlueskyCore, TDD)

Extracts the authority segment (the DID) from an AT-URI, mirroring the existing `rkey` helper. This is the source of the DID used as the permalink fallback when a handle is unusable.

**Files:**
- Modify: `core/Sources/BlueskyCore/XRPC/ATURI.swift` (add a static method after `rkey`, lines ~8-13)
- Test: `core/Tests/BlueskyCoreTests/ATURITests.swift` (add tests after the existing ones, line ~16)

- [ ] **Step 1: Write a failing test for `ATURI.repo`.**

Add these two test methods to `core/Tests/BlueskyCoreTests/ATURITests.swift`, before the closing brace of `final class ATURITests`:

```swift
    func testRepoExtractsAuthority() {
        XCTAssertEqual(
            ATURI.repo("at://did:plc:me/app.bsky.feed.post/3kabc123"),
            "did:plc:me"
        )
    }

    func testRepoReturnsNilWhenMalformed() {
        XCTAssertNil(ATURI.repo("not-an-at-uri"))
        XCTAssertNil(ATURI.repo("at://did:plc:me/app.bsky.feed.post"))
        XCTAssertNil(ATURI.repo(""))
    }
```

- [ ] **Step 2: Run the test and confirm it fails to compile (red).**

```bash
cd core && swift test --filter ATURITests
```

Expected: a build error such as `type 'ATURI' has no member 'repo'`. This confirms the test exercises the missing API.

- [ ] **Step 3: Implement `ATURI.repo` (minimal green).**

In `core/Sources/BlueskyCore/XRPC/ATURI.swift`, add the method immediately after the closing brace of `rkey(_:)` (after line 13, inside the `enum`):

```swift
    /// The repository authority (first path segment, normally the author DID) of
    /// an AT-URI, or nil when the string is not a `at://authority/collection/rkey`
    /// triple. Used as the permalink profile segment when a handle is unusable.
    public static func repo(_ uri: String) -> String? {
        guard uri.hasPrefix("at://") else { return nil }
        let parts = uri.dropFirst("at://".count).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[0].isEmpty else { return nil }
        return String(parts[0])
    }
```

- [ ] **Step 4: Run the test and confirm it passes (green).**

```bash
cd core && swift test --filter ATURITests
```

Expected: `Executed 4 tests, with 0 failures` (the two new tests plus the two pre-existing `rkey` tests).

- [ ] **Step 5: Run the full BlueskyCore suite to confirm nothing regressed.**

```bash
cd core && swift test
```

Expected: all tests pass, `0 failures`.

- [ ] **Step 6: Commit.**

```bash
git ai-commit
```

Suggested message: `Add ATURI.repo to extract the AT-URI authority DID`

---

## Task 2: `PostPermalink.url(for:)` pure builder (YoruMimizukuKit, TDD)

The testable core of Phase B. Builds the bsky.app permalink from a `PostDisplay`, preferring the handle and falling back to the DID extracted from the post's AT-URI `id`.

**Files:**
- Create: `core/Sources/YoruMimizukuKit/PostPermalink.swift`
- Test: `core/Tests/YoruMimizukuKitTests/PostPermalinkTests.swift`

Note: `YoruMimizukuKit` depends on `BlueskyCore`, so the builder does `import BlueskyCore` to call `ATURI`. `PostDisplay`'s `id` is the AT-URI (e.g. `at://did:plc:xxx/app.bsky.feed.post/3k...`); there is no `authorDID` property, so the DID must come from `ATURI.repo(post.id)`. A minimal test post uses the convenience init `PostDisplay(id:authorDisplayName:authorHandle:body:createdAt:)`.

- [ ] **Step 1: Write a failing test with the valid-handle case.**

Create `core/Tests/YoruMimizukuKitTests/PostPermalinkTests.swift`:

```swift
import XCTest
@testable import YoruMimizukuKit

final class PostPermalinkTests: XCTestCase {
    private func post(id: String, handle: String) -> PostDisplay {
        PostDisplay(
            id: id,
            authorDisplayName: "Test",
            authorHandle: handle,
            body: "hello",
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    func testValidHandleBuildsHandleURL() {
        let p = post(id: "at://did:plc:me/app.bsky.feed.post/3kabc123", handle: "alice.bsky.social")
        XCTAssertEqual(
            PostPermalink.url(for: p),
            URL(string: "https://bsky.app/profile/alice.bsky.social/post/3kabc123")
        )
    }
}
```

- [ ] **Step 2: Run the test and confirm it fails to compile (red).**

```bash
cd core && swift test --filter PostPermalinkTests
```

Expected: a build error such as `cannot find 'PostPermalink' in scope`. This confirms the builder does not exist yet.

- [ ] **Step 3: Implement `PostPermalink.url(for:)` (minimal green).**

Create `core/Sources/YoruMimizukuKit/PostPermalink.swift`:

```swift
import Foundation
import BlueskyCore

/// Builds the public bsky.app permalink for a post:
/// `https://bsky.app/profile/{handle-or-did}/post/{rkey}`.
///
/// The profile segment prefers the author handle, but falls back to the author
/// DID (extracted from the post's AT-URI `id`) when the handle is empty or the
/// sentinel `"handle.invalid"`. Returns nil when no rkey can be parsed or when
/// neither a usable handle nor a DID is available.
public enum PostPermalink {
    public static func url(for post: PostDisplay) -> URL? {
        guard let rkey = ATURI.rkey(post.id) else { return nil }
        let handle = post.authorHandle
        let usableHandle = (!handle.isEmpty && handle != "handle.invalid") ? handle : nil
        guard let profile = usableHandle ?? ATURI.repo(post.id) else { return nil }
        return URL(string: "https://bsky.app/profile/\(profile)/post/\(rkey)")
    }
}
```

- [ ] **Step 4: Run the test and confirm it passes (green).**

```bash
cd core && swift test --filter PostPermalinkTests
```

Expected: `Executed 1 test, with 0 failures`.

- [ ] **Step 5: Add the remaining failing cases (red).**

Add these four methods to `PostPermalinkTests`, before the closing brace:

```swift
    func testInvalidHandleFallsBackToDID() {
        let p = post(id: "at://did:plc:me/app.bsky.feed.post/3kabc123", handle: "handle.invalid")
        XCTAssertEqual(
            PostPermalink.url(for: p),
            URL(string: "https://bsky.app/profile/did:plc:me/post/3kabc123")
        )
    }

    func testEmptyHandleFallsBackToDID() {
        let p = post(id: "at://did:plc:me/app.bsky.feed.post/3kabc123", handle: "")
        XCTAssertEqual(
            PostPermalink.url(for: p),
            URL(string: "https://bsky.app/profile/did:plc:me/post/3kabc123")
        )
    }

    func testNonATURIIDReturnsNil() {
        let p = post(id: "https://example.com/not-at-uri", handle: "alice.bsky.social")
        XCTAssertNil(PostPermalink.url(for: p))
    }

    func testMissingRkeyReturnsNil() {
        let p = post(id: "at://did:plc:me/app.bsky.feed.post", handle: "alice.bsky.social")
        XCTAssertNil(PostPermalink.url(for: p))
    }
```

- [ ] **Step 6: Run the tests and confirm all five pass (green).**

```bash
cd core && swift test --filter PostPermalinkTests
```

Expected: `Executed 5 tests, with 0 failures`. The implementation from Step 3 already covers these cases — no production change is needed. If any test fails, re-read the fallback logic before changing code.

- [ ] **Step 7: Run the full suite to confirm no regression.**

```bash
cd core && swift test
```

Expected: all tests pass, `0 failures`.

- [ ] **Step 8: Commit.**

```bash
git ai-commit
```

Suggested message: `Add PostPermalink builder for bsky.app post URLs`

---

## Task 3: `f` key likes the focused post in FeedView (build-verified)

Wires an `f` keyboard shortcut into FeedView's hidden `postNavShortcuts` so the currently focused post is liked via the existing `model.toggleLike`. Keyboard side effects are not unit-testable, so this task is verified by a clean app build plus a manual-check note.

**Files:**
- Modify: `apps/macos/Views/FeedView.swift` (`postNavShortcuts`, lines ~175-189)

- [ ] **Step 1: Add a focused-post helper and the `f` shortcut.**

In `apps/macos/Views/FeedView.swift`, replace the entire `postNavShortcuts` computed property (lines 175-189) with the version below. It adds a `focusedPost` helper and an `f` button that likes it; the button is a no-op when there is no focused post.

```swift
    /// The post j/k focus currently sits on, if any.
    private var focusedPost: PostDisplay? {
        model.posts.first { $0.id == focusedPostID }
    }

    private var postNavShortcuts: some View {
        ZStack {
            Button("") { focusAdjacentPost(1) }
                .keyboardShortcut("j", modifiers: [])
            Button("") { focusAdjacentPost(-1) }
                .keyboardShortcut("k", modifiers: [])
            Button("") {
                if let post = focusedPost { Task { await model.toggleLike(post) } }
            }
            .keyboardShortcut("f", modifiers: [])
            if let onCompose {
                Button("") { onCompose() }
                    .keyboardShortcut("n", modifiers: [])
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
```

- [ ] **Step 2: Generate the Xcode project (if not already generated) and build the app.**

```bash
xcodegen generate
xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj CODE_SIGN_IDENTITY="-"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual verification (record in the PR / commit).**

Manual-check item (cannot be unit-tested): launch the app, move j/k focus to a post, press `f`, and confirm the heart toggles (filled/unfilled) and the like count changes. Press `f` again to confirm the un-like. With no post focused, `f` does nothing and does not crash.

- [ ] **Step 4: Commit.**

```bash
git ai-commit
```

Suggested message: `Like the focused post with the f key in the feed`

---

## Task 4: Copy-link icon in PostRowView + NSPasteboard wiring in FeedView (build-verified)

Adds a copy-link icon to the interactive action bar and wires it in FeedView to copy the permalink via `NSPasteboard`. The icon renders only when `interactiveActions` is on (matching how the other action buttons are gated — see `content`, lines 120-126, which shows `actionBar` only when `interactiveActions`, else `staticActionBar`). So the copy icon belongs inside `actionBar`, which is already the interactive-only path.

**Files:**
- Modify: `apps/macos/Views/PostRowView.swift` (add `onCopyLink` closure near lines ~29-34; add copy button to `actionBar`, lines ~206-246)
- Modify: `apps/macos/Views/FeedView.swift` (add `copyPermalink` helper; wire `onCopyLink` in `postList`, lines ~64-84; add `import AppKit`)

- [ ] **Step 1: Add the `onCopyLink` closure to PostRowView.**

In `apps/macos/Views/PostRowView.swift`, add the closure declaration immediately after `onQuote` (after line 34):

```swift
    /// Called when the copy-link icon is tapped (copies the post permalink).
    var onCopyLink: () -> Void = {}
```

- [ ] **Step 2: Add the copy-link icon button to the interactive action bar.**

In `apps/macos/Views/PostRowView.swift`, in `actionBar` (lines 206-246), add the copy button after the like `Button { … }.help(…)` block and before the closing `}` of the `HStack` (i.e. immediately after line 239, the like button's `.help`):

```swift

            Button {
                onSelect()
                onCopyLink()
            } label: {
                Image(systemName: "link")
                    .foregroundStyle(theme.tertiaryText)
            }
            .help("リンクをコピー")
```

The button has no count label, so it uses a plain `Image(systemName:)` styled with `theme.tertiaryText` like an inactive action label. It inherits the `actionBar`'s `.font(.app(.caption))` and `.buttonStyle(.plain)` modifiers (lines 241-244). It is added only to `actionBar` (the interactive path), not to `staticActionBar`, matching the existing gating.

- [ ] **Step 3: Add `import AppKit` and the `copyPermalink` helper to FeedView.**

In `apps/macos/Views/FeedView.swift`, change the imports at the top (lines 1-2) to add AppKit:

```swift
import SwiftUI
import AppKit
import YoruMimizukuKit
```

Then add the `copyPermalink` method to `FeedView`, immediately after the `focusAdjacentPost(_:)` method (after line 173):

```swift
    private func copyPermalink(_ post: PostDisplay) {
        guard let url = PostPermalink.url(for: post) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.absoluteString, forType: .string)
    }
```

- [ ] **Step 4: Wire `onCopyLink` into the post row in `postList`.**

In `apps/macos/Views/FeedView.swift`, in `postList`, add the `onCopyLink` argument to the `PostRowView(...)` initializer. Change the `onQuote` line (line 83) so the call ends with both arguments:

```swift
                    onQuote: { onQuote(post) },
                    onCopyLink: { copyPermalink(post) }
```

- [ ] **Step 5: Build the app.**

```bash
xcodegen generate
xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj CODE_SIGN_IDENTITY="-"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Manual verification (record in the PR / commit).**

Manual-check item: in comfortable density, confirm a `link` icon appears in the action bar next to like. Click it, then paste into a text field and confirm the clipboard holds `https://bsky.app/profile/.../post/...`. Hover shows the tooltip `リンクをコピー`. In conversation ancestor rows (non-interactive), the icon does not appear.

- [ ] **Step 7: Commit.**

```bash
git ai-commit
```

Suggested message: `Add a copy-permalink icon to the post action row`

---

## Task 5: `o` key opens the focused post in the browser in FeedView (build-verified)

Adds an `o` shortcut that opens the focused post's permalink in the default browser via `NSWorkspace`. Reuses the `focusedPost` helper added in Task 3.

**Files:**
- Modify: `apps/macos/Views/FeedView.swift` (`postNavShortcuts`, the property edited in Task 3)

- [ ] **Step 1: Add the `o` shortcut to `postNavShortcuts`.**

In `apps/macos/Views/FeedView.swift`, in `postNavShortcuts`, add the `o` button immediately after the `f` button block (after its `.keyboardShortcut("f", modifiers: [])` line):

```swift
            Button("") {
                if let post = focusedPost, let url = PostPermalink.url(for: post) {
                    NSWorkspace.shared.open(url)
                }
            }
            .keyboardShortcut("o", modifiers: [])
```

`NSWorkspace` comes from `AppKit`, which is already imported in Task 4. If Task 5 is implemented before Task 4 for any reason, ensure `import AppKit` is present at the top of the file.

- [ ] **Step 2: Build the app.**

```bash
xcodegen generate
xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj CODE_SIGN_IDENTITY="-"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual verification (record in the PR / commit).**

Manual-check item: move j/k focus to a post, press `o`, and confirm the default browser opens the post's bsky.app permalink. With no post focused, `o` does nothing and does not crash.

- [ ] **Step 4: Commit.**

```bash
git ai-commit
```

Suggested message: `Open the focused post in the browser with the o key`

---

## Task 6: Apply `f` / `o` / copy-link to ConversationView's focused post (build-verified)

Brings the same three affordances to the conversation view's anchor (focused) post. ConversationView exposes the focus only inside `.loaded(focus)` state (lines 44-46, 49), and the model is a `ThreadViewModel` that has `toggleLike`. We add a hidden shortcut layer that reads the focus from `model.state`, and wire `onCopyLink` into the focus block's `PostRowView`.

**Files:**
- Modify: `apps/macos/Views/ConversationView.swift` (add `import AppKit`; add a `focusedPost` helper + `conversationShortcuts`; attach via `.background`; add `copyPermalink`; wire `onCopyLink` in `focusBlock`, lines ~96-107)

- [ ] **Step 1: Add `import AppKit` to ConversationView.**

In `apps/macos/Views/ConversationView.swift`, change the imports (lines 1-2) to:

```swift
import SwiftUI
import AppKit
import YoruMimizukuKit
```

- [ ] **Step 2: Add a `focusedPost` helper, `copyPermalink`, and `conversationShortcuts`.**

In `apps/macos/Views/ConversationView.swift`, add these members to the `ConversationView` struct. Place them immediately before the `stateMessage` helper (before line 127):

```swift
    /// The conversation's anchor (focused) post, available only once loaded.
    private var focusedPost: PostDisplay? {
        if case let .loaded(focus) = model.state { return focus }
        return nil
    }

    private func copyPermalink(_ post: PostDisplay) {
        guard let url = PostPermalink.url(for: post) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.absoluteString, forType: .string)
    }

    /// Hidden f/o shortcuts that act on the anchor post, mirroring FeedView.
    private var conversationShortcuts: some View {
        ZStack {
            Button("") {
                if let post = focusedPost { Task { await model.toggleLike(post) } }
            }
            .keyboardShortcut("f", modifiers: [])
            Button("") {
                if let post = focusedPost, let url = PostPermalink.url(for: post) {
                    NSWorkspace.shared.open(url)
                }
            }
            .keyboardShortcut("o", modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
```

- [ ] **Step 3: Attach the shortcut layer to the view body.**

In `apps/macos/Views/ConversationView.swift`, in `body` (lines 17-21), add the shortcut layer as a background. Replace the `body` with:

```swift
    var body: some View {
        content
            .background(theme.canvas)
            .background { conversationShortcuts }
            .task { if case .idle = model.state { await model.load() } }
    }
```

- [ ] **Step 4: Wire `onCopyLink` into the focus block.**

In `apps/macos/Views/ConversationView.swift`, in `focusBlock(_:)` (lines 96-107), add `onCopyLink` to the focus `PostRowView`. Change the `onRepost` line (line 103) so the initializer ends with both closures:

```swift
                onRepost: { Task { await model.toggleRepost(focus) } },
                onCopyLink: { copyPermalink(focus) }
```

- [ ] **Step 5: Build the app.**

```bash
xcodegen generate
xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj CODE_SIGN_IDENTITY="-"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Manual verification (record in the PR / commit).**

Manual-check item: open a conversation tab. Press `f` and confirm the anchor post's like toggles. Press `o` and confirm the browser opens its permalink. Confirm the focus block's action bar shows the `link` copy icon and copies the permalink. Confirm ancestor rows (non-interactive) still show no copy icon.

- [ ] **Step 7: Run the full core suite once more (sanity) and commit.**

```bash
cd core && swift test
```

Expected: all tests pass, `0 failures`.

```bash
git ai-commit
```

Suggested message: `Apply f-like, o-browser, and copy-link to the conversation anchor post`

---

## Requirement-to-task map (self-review)

| Spec requirement (5.3 / 5.4) | Task(s) |
|------------------------------|---------|
| `f` likes the focused post in the feed | Task 3 |
| `f` likes the focused post in the conversation view | Task 6 |
| Build the permalink (pure, testable) | Task 1 (DID extractor), Task 2 (builder) |
| Copy icon copies the permalink to the clipboard | Task 4 (PostRowView icon + FeedView NSPasteboard), Task 6 (conversation) |
| `o` opens the focused post's permalink in the browser | Task 5 (feed), Task 6 (conversation) |

Names are consistent across tasks: `ATURI.repo`, `PostPermalink.url(for:)`, `onCopyLink`, `copyPermalink`, `focusedPost`. The copy icon is gated to the interactive `actionBar` only, matching existing button behavior.
