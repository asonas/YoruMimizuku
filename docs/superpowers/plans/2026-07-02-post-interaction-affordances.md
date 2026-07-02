# Post Interaction Affordances Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three macOS timeline affordances — timestamp click opens the conversation view, a copy-link toast, and in-app routing for body `@mention` taps.

**Architecture:** Logic lives in the shared `YoruMimizukuKit` core (a pure URL parser and an observable `ToastCenter`), tested with XCTest. The macOS SwiftUI views (`PostRowView`, `MainWindowView`, `FeedView`, `ConversationView`) are thin wiring on top: a tappable timestamp, a bottom overlay for the toast, and a new branch in the window's `openURL` action.

**Tech Stack:** Swift 6.0 (strict concurrency), SwiftUI, XCTest, SPM (`core/`), XcodeGen for the app project.

## Global Constraints

- Swift 6.0 / strict concurrency: mind `MainActor` isolation and `Sendable`. `ToastCenter` is `@MainActor`.
- Keep `BlueskyCore`/`YoruMimizukuKit` core logic free of Apple-framework dependencies. `ToastCenter` and `RichText.mentionDID` use only Foundation.
- Commits: use the `/commit` skill (runs `git ai-commit`). Never run `git commit` directly. Messages in English, capitalized first letter, not Conventional Commits.
- Core tests run with `cd core && swift test`. Test targets: `BlueskyCoreTests`, `YoruMimizukuKitTests` (under `core/Tests/`).
- New files under `apps/macos/` are picked up by XcodeGen source globs: run `xcodegen generate` before building the app after adding a file.
- Toast copy text is exactly `リンクをコピーしました`. No emoji.
- **Scope: macOS only.** iPadOS has a divergent structure (`TimelineListView`/`onOpenThread`, optional closures, whole-row tap already opens the thread). iPad parity for these three affordances is a documented follow-up plan, not part of this one.

---

### Task 1: `RichText.mentionDID(from:)` — parse the mention identifier out of a profile URL

**Files:**
- Modify: `core/Sources/YoruMimizukuKit/RichText.swift` (add a static method next to `hashtag(from:)`, ~line 80)
- Test: `core/Tests/YoruMimizukuKitTests/RichTextSegmentTests.swift` (append tests)

**Interfaces:**
- Consumes: nothing.
- Produces: `public static func mentionDID(from url: URL) -> String?` on `enum RichText`. Returns the identifier for `https://bsky.app/profile/<id>` (a bare profile URL, exactly 2 path components `profile`/`<id>`), `nil` for post permalinks (`/profile/<id>/post/<rkey>`), hashtag URLs, non-`bsky.app` hosts, and empty identifiers.

- [ ] **Step 1: Write the failing tests**

Append to `core/Tests/YoruMimizukuKitTests/RichTextSegmentTests.swift` (inside the existing `final class RichTextSegmentTests: XCTestCase`):

```swift
func testMentionDIDExtractsDIDFromProfileURL() {
    let url = URL(string: "https://bsky.app/profile/did:plc:abc123")!
    XCTAssertEqual(RichText.mentionDID(from: url), "did:plc:abc123")
}

func testMentionDIDExtractsHandleFromProfileURL() {
    let url = URL(string: "https://bsky.app/profile/alice.bsky.social")!
    XCTAssertEqual(RichText.mentionDID(from: url), "alice.bsky.social")
}

func testMentionDIDIsNilForPostPermalink() {
    let url = URL(string: "https://bsky.app/profile/did:plc:abc123/post/3kabc")!
    XCTAssertNil(RichText.mentionDID(from: url))
}

func testMentionDIDIsNilForHashtagURL() {
    let url = URL(string: "https://bsky.app/hashtag/swift")!
    XCTAssertNil(RichText.mentionDID(from: url))
}

func testMentionDIDIsNilForForeignHost() {
    let url = URL(string: "https://example.com/profile/did:plc:abc123")!
    XCTAssertNil(RichText.mentionDID(from: url))
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd core && swift test --filter RichTextSegmentTests`
Expected: FAIL — compile error, `mentionDID` is not a member of `RichText`.

- [ ] **Step 3: Implement `mentionDID(from:)`**

In `core/Sources/YoruMimizukuKit/RichText.swift`, add directly below the `hashtag(from:)` method (after its closing brace, before `private static func feature`):

```swift
    /// Reverse of the mention URL built in `feature(_:)`: pulls the actor
    /// identifier back out of a bare `https://bsky.app/profile/<id>` URL, or nil
    /// for anything else (post permalinks, hashtags, foreign hosts). Lets the UI
    /// route mention taps to an in-app author tab instead of the browser.
    public static func mentionDID(from url: URL) -> String? {
        guard url.host == "bsky.app" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, parts[0] == "profile", !parts[1].isEmpty else { return nil }
        return parts[1]
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd core && swift test --filter RichTextSegmentTests`
Expected: PASS (all new tests plus the existing ones).

- [ ] **Step 5: Commit**

Use the `/commit` skill on this worktree. Message:
`Add RichText.mentionDID to parse profile URLs`

---

### Task 2: Route body `@mention` taps to the in-app author tab (macOS)

**Files:**
- Modify: `apps/macos/Views/MainWindowView.swift:134-140` (the `openURL` `OpenURLAction`)

**Interfaces:**
- Consumes: `RichText.mentionDID(from:)` (Task 1); `workspace.openAuthor(did:handle:displayName:avatarURL:)` (existing on `WorkspaceModel`).
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Add the mention branch**

Replace the existing `openURL` action (currently lines 134-140):

```swift
        .environment(\.openURL, OpenURLAction { url in
            if let tag = RichText.hashtag(from: url) {
                workspace.openHashtagFilter(tag: tag)
                return .handled
            }
            return .systemAction
        })
```

with:

```swift
        // Tapping a hashtag opens a filter tab; tapping a mention opens the
        // author's tab in-app; every other link falls through to the browser.
        .environment(\.openURL, OpenURLAction { url in
            if let tag = RichText.hashtag(from: url) {
                workspace.openHashtagFilter(tag: tag)
                return .handled
            }
            if let did = RichText.mentionDID(from: url) {
                // Only the identifier is available at tap time (the openURL action
                // sees a URL, not the "@handle" span text), so open by DID and let
                // the author model resolve handle / display name / avatar.
                workspace.openAuthor(did: did, handle: "", displayName: "", avatarURL: nil)
                return .handled
            }
            return .systemAction
        })
```

- [ ] **Step 2: Regenerate and build**

Run: `xcodegen generate && xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj`
Expected: BUILD SUCCEEDED. (No source files added, so `xcodegen generate` is a no-op safeguard.)

- [ ] **Step 3: Manual smoke check**

Launch the app, open a post whose body contains an `@mention`, click the mention. Expected: an author tab opens in-app (header fills in after the profile loads) and the browser does not launch. Clicking a plain external link still opens the browser.

- [ ] **Step 4: Commit**

Use the `/commit` skill. Message:
`Open body mention taps in an in-app author tab`

---

### Task 3: `ToastCenter` + `ToastMessage` — transient message store (core)

**Files:**
- Create: `core/Sources/YoruMimizukuKit/ToastCenter.swift`
- Test: `core/Tests/YoruMimizukuKitTests/ToastCenterTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `public struct ToastMessage: Identifiable, Equatable, Sendable { public let id: Int; public let text: String }`
  - `@MainActor public final class ToastCenter: ObservableObject` with:
    - `@Published public private(set) var current: ToastMessage?`
    - `public init(autoDismiss: Duration = .milliseconds(1800))`
    - `public func show(_ text: String)` — replaces `current` with a new message (monotonic `id`) and schedules an auto-dismiss.
    - `public func dismiss()` — clears `current` immediately.
    - `func expire(token: Int)` — internal; clears `current` only if its `id` still equals `token` (used by the scheduled task and by tests, avoiding real-time waits).

- [ ] **Step 1: Write the failing tests**

Create `core/Tests/YoruMimizukuKitTests/ToastCenterTests.swift`:

```swift
import XCTest
@testable import YoruMimizukuKit

@MainActor
final class ToastCenterTests: XCTestCase {
    func testShowSetsCurrentMessage() {
        let center = ToastCenter(autoDismiss: .seconds(60))
        center.show("リンクをコピーしました")
        XCTAssertEqual(center.current?.text, "リンクをコピーしました")
    }

    func testSecondShowReplacesTheFirst() {
        let center = ToastCenter(autoDismiss: .seconds(60))
        center.show("first")
        let firstID = center.current?.id
        center.show("second")
        XCTAssertEqual(center.current?.text, "second")
        XCTAssertNotEqual(center.current?.id, firstID)
    }

    func testDismissClearsCurrent() {
        let center = ToastCenter(autoDismiss: .seconds(60))
        center.show("hi")
        center.dismiss()
        XCTAssertNil(center.current)
    }

    func testExpireOnlyClearsWhenTokenMatchesCurrent() {
        let center = ToastCenter(autoDismiss: .seconds(60))
        center.show("first")
        let firstID = center.current!.id
        center.show("second")
        // A stale expiry from the first toast must not clear the second.
        center.expire(token: firstID)
        XCTAssertEqual(center.current?.text, "second")
        // The matching expiry clears it.
        center.expire(token: center.current!.id)
        XCTAssertNil(center.current)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd core && swift test --filter ToastCenterTests`
Expected: FAIL — compile error, `ToastCenter` / `ToastMessage` not found.

- [ ] **Step 3: Implement `ToastCenter`**

Create `core/Sources/YoruMimizukuKit/ToastCenter.swift`:

```swift
import Foundation

/// One transient message shown to the user (e.g. "リンクをコピーしました"). The
/// `id` is a monotonic token so SwiftUI transitions treat each toast as distinct
/// and the auto-dismiss task can tell whether it still owns the current message.
public struct ToastMessage: Identifiable, Equatable, Sendable {
    public let id: Int
    public let text: String

    public init(id: Int, text: String) {
        self.id = id
        self.text = text
    }
}

/// Holds the single transient toast the window overlays. `show` replaces any
/// visible toast and schedules its removal after `autoDismiss`; a newer `show`
/// supersedes the previous one so rapid copies just swap the text.
@MainActor
public final class ToastCenter: ObservableObject {
    @Published public private(set) var current: ToastMessage?

    private var lastToken = 0
    private let autoDismiss: Duration

    public init(autoDismiss: Duration = .milliseconds(1800)) {
        self.autoDismiss = autoDismiss
    }

    public func show(_ text: String) {
        lastToken += 1
        let token = lastToken
        current = ToastMessage(id: token, text: text)
        Task { [weak self, autoDismiss] in
            try? await Task.sleep(for: autoDismiss)
            self?.expire(token: token)
        }
    }

    public func dismiss() {
        current = nil
    }

    /// Clear the toast only if `token` still identifies the visible message; a
    /// stale token (a newer `show` already replaced it) is ignored.
    func expire(token: Int) {
        guard current?.id == token else { return }
        current = nil
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd core && swift test --filter ToastCenterTests`
Expected: PASS.

- [ ] **Step 5: Commit**

Use the `/commit` skill. Message:
`Add ToastCenter for transient window messages`

---

### Task 4: Toast UI — `ToastView`, window overlay, and copy-link wiring (macOS)

**Files:**
- Create: `apps/macos/Views/ToastView.swift`
- Modify: `apps/macos/Views/MainWindowView.swift` (add `@StateObject` toast center, overlay on the body `ZStack`, inject into `splitView`)
- Modify: `apps/macos/Views/FeedView.swift:283-288` (`copyPermalink`) and add an `@EnvironmentObject`
- Modify: `apps/macos/Views/ConversationView.swift:218-223` (`copyPermalink`) and add an `@EnvironmentObject`

**Interfaces:**
- Consumes: `ToastCenter`, `ToastMessage` (Task 3).
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Create `ToastView`**

Create `apps/macos/Views/ToastView.swift`:

```swift
import SwiftUI
import YoruMimizukuKit

/// A small pill shown at the bottom of the window for a transient confirmation
/// such as "リンクをコピーしました". Tapping it dismisses immediately; otherwise
/// `ToastCenter` clears it after a short delay.
struct ToastView: View {
    let message: ToastMessage

    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        Text(message.text)
            .font(.app(.caption))
            .foregroundStyle(theme.primaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().stroke(theme.divider, lineWidth: 1))
            .shadow(radius: 6, y: 2)
    }
}
```

- [ ] **Step 2: Add the toast center and overlay to `MainWindowView`**

In `apps/macos/Views/MainWindowView.swift`, add the state object next to the other `@State` declarations (after `@State private var now = Date()`, ~line 44):

```swift
    /// The window's transient toast (e.g. copy-link confirmation), injected into
    /// the feed / conversation views and rendered as a bottom overlay.
    @StateObject private var toastCenter = ToastCenter()
```

Then, in `body`, attach the overlay and animation to the `ZStack` (the block at lines 59-62). Change:

```swift
        ZStack {
            splitView
                .id("\(fontSettings.family)|\(fontSettings.baseSize)")
        }
```

to:

```swift
        ZStack {
            splitView
                .id("\(fontSettings.family)|\(fontSettings.baseSize)")
                .environmentObject(toastCenter)
        }
        .overlay(alignment: .bottom) {
            if let toast = toastCenter.current {
                ToastView(message: toast)
                    .padding(.bottom, 24)
                    .onTapGesture { toastCenter.dismiss() }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toastCenter.current)
```

- [ ] **Step 3: Fire the toast from `FeedView.copyPermalink`**

In `apps/macos/Views/FeedView.swift`, add the environment object near the other `@EnvironmentObject` declarations (search for `@EnvironmentObject` at the top of the struct):

```swift
    @EnvironmentObject private var toastCenter: ToastCenter
```

Then change `copyPermalink` (lines 283-288) from:

```swift
    private func copyPermalink(_ post: PostDisplay) {
        guard let url = PostPermalink.url(for: post) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.absoluteString, forType: .string)
    }
```

to:

```swift
    private func copyPermalink(_ post: PostDisplay) {
        guard let url = PostPermalink.url(for: post) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.absoluteString, forType: .string)
        toastCenter.show("リンクをコピーしました")
    }
```

- [ ] **Step 4: Fire the toast from `ConversationView.copyPermalink`**

In `apps/macos/Views/ConversationView.swift`, add the same environment object near the other `@EnvironmentObject` declarations:

```swift
    @EnvironmentObject private var toastCenter: ToastCenter
```

Then change `copyPermalink` (lines 218-223) to append the same line after `pb.setString(...)`:

```swift
        toastCenter.show("リンクをコピーしました")
```

- [ ] **Step 5: Regenerate, build, and run core tests**

Run: `cd core && swift test`
Expected: PASS.
Run: `xcodegen generate && xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj`
Expected: BUILD SUCCEEDED (this adds `ToastView.swift` to the project).

If any SwiftUI preview in `FeedView.swift` / `ConversationView.swift` fails to compile after adding the `@EnvironmentObject`, give that preview a `ToastCenter()` via `.environmentObject(ToastCenter())` — the same way it already supplies `ThemeStore`.

- [ ] **Step 6: Manual smoke check**

Launch the app. In the timeline, right-click a post → "リンクをコピー", and also click the link icon in the action bar. Expected: a "リンクをコピーしました" pill fades in at the bottom and disappears after ~1.8s; tapping it dismisses it instantly. Do the same inside a conversation tab. Verify the clipboard actually holds the permalink.

- [ ] **Step 7: Commit**

Use the `/commit` skill. Message:
`Show a toast when a post link is copied`

---

### Task 5: Timestamp click opens the conversation (macOS)

**Files:**
- Modify: `apps/macos/Views/PostRowView.swift` (add `import AppKit` guard, an `onOpenConversation` closure, hover state, and a tappable timestamp in `authorLine`)
- Modify: `apps/macos/Views/FeedView.swift:122-147` (pass `onOpenConversation`)
- Modify: `apps/macos/Views/ConversationView.swift` (`focusBlock` ~line 110 and `replyRow` ~line 160 pass `onOpenConversation`)

**Interfaces:**
- Consumes: `WorkspaceModel.openConversation(_:)` via the hosts' existing `onOpenConversation: (PostDisplay) -> Void` closures.
- Produces: `PostRowView.onOpenConversation: () -> Void` (default `{}`). Active only when `interactiveActions == true`, so the wrapping button in `ConversationView.parentBlock` (which uses `interactiveActions: false`) keeps handling its own taps.

- [ ] **Step 1: Add the AppKit import guard**

At the top of `apps/macos/Views/PostRowView.swift`, below the existing imports (lines 1-2), add:

```swift
#if canImport(AppKit)
import AppKit
#endif
```

- [ ] **Step 2: Add the closure and hover state**

In `PostRowView`, add the closure property after `onCopyLink` (line 38):

```swift
    /// Called when the timestamp is tapped, so the host can open this post's
    /// conversation. Only wired where the row is interactive.
    var onOpenConversation: () -> Void = {}
```

And add the hover state next to the other `@State` (after `revealMedia`, ~line 64):

```swift
    /// Whether the pointer is over the timestamp, so it underlines to signal it
    /// is clickable (macOS only; the resting timestamp stays unstyled).
    @State private var isTimestampHovered = false
```

- [ ] **Step 3: Make the timestamp tappable in `authorLine`**

In `authorLine` (lines 525-542), replace the trailing timestamp `Text`:

```swift
            Text(relativeTime)
                .font(.app(density == .compact ? .caption2 : .caption))
                .foregroundStyle(theme.tertiaryText)
                .monospacedDigit()
```

with a call to a new `timestampView`:

```swift
            timestampView
```

Then add `timestampView` as a computed property just above `authorLine`:

```swift
    @ViewBuilder
    private var timestampView: some View {
        // Keep the base a `Text` so `.underline(_:)` (a Text method) applies before
        // `.foregroundStyle` turns it into an opaque View.
        let base = Text(relativeTime)
            .font(.app(density == .compact ? .caption2 : .caption))
            .monospacedDigit()
            .underline(interactiveActions && isTimestampHovered)
        if interactiveActions {
            base
                .foregroundStyle(theme.tertiaryText)
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelect()
                    onOpenConversation()
                }
                .onHover { hovering in
                    isTimestampHovered = hovering
                    #if canImport(AppKit)
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    #endif
                }
        } else {
            base.foregroundStyle(theme.tertiaryText)
        }
    }
```

- [ ] **Step 4: Wire the host in `FeedView`**

In `apps/macos/Views/FeedView.swift`, in the `PostRowView(...)` call (lines 122-147), add after `onCopyLink: { copyPermalink(post) },`:

```swift
                        onOpenConversation: { onOpenConversation(post) },
```

- [ ] **Step 5: Wire the hosts in `ConversationView`**

In `apps/macos/Views/ConversationView.swift`, in `focusBlock`'s `PostRowView(...)` (lines 110-118), add after `onCopyLink: { copyPermalink(focus) },`:

```swift
                onOpenConversation: { onOpenConversation(focus) },
```

In `replyRow`'s `PostRowView(...)` (lines 160-168), add after `onCopyLink: { copyPermalink(node.post) },`:

```swift
                onOpenConversation: { onOpenConversation(node.post) },
```

Leave `parentBlock` (line 94) unchanged: it uses `interactiveActions: false`, so the timestamp stays non-tappable and its wrapping button keeps re-anchoring.

- [ ] **Step 6: Build and run core tests**

Run: `cd core && swift test`
Expected: PASS (no core changes, sanity check).
Run: `xcodegen generate && xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj`
Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Manual smoke check**

Launch the app. In the timeline, hover the timestamp: the pointer becomes a hand and the time underlines. Click it: the conversation view opens anchored on that post. Inside a conversation, clicking the focus row's or a reply row's timestamp re-anchors to that post. Clicking an ancestor row (or its timestamp) still re-anchors via the row button as before. The reply-count button and "@X への返信" marker still open the conversation as before.

- [ ] **Step 8: Commit**

Use the `/commit` skill. Message:
`Open the conversation when a post timestamp is clicked`

---

## Follow-up (out of scope, separate plan)

- **iPadOS parity.** The iPad app (`apps/ipados`) has a different shape: `TimelineListView` instead of `FeedView`, `onOpenThread`/`onCopyPermalink` optional closures, `UIPasteboard`, and a whole-row tap that already opens the thread (`PostRowView.swift:105`). Bring the toast (`ToastCenter` is already shared) and the mention-routing branch (`RootView.swift:338`) to iPad, and decide whether a timestamp tap adds value given the existing row-tap-opens-thread behavior. Track as a dedicated iPad parity plan.
- **Wiki.** After these land, update `docs/wiki/` (behaviors for timeline interactions) via the `wiki-update` skill, then `mise run wiki:lint` and `mise run wiki:index`.
