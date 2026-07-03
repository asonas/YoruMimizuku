# Feed Self-Thread-Only Grouping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the timeline feed from collapsing multi-author, branching reply trees into one flat chronological block by restricting `FeedThreading.arrange` grouping to same-author self-threads.

**Architecture:** The only production change is the `groupKey(for:)` climb condition inside `FeedThreading.arrange` (`YoruMimizukuKit`): it must climb `replyParent` links only while the parent's author matches the current post's author, so the group boundary falls where the author changes. Rows that split back out are rendered by the existing `FeedView` / `PostRowView` machinery — a non-grouped reply (`connectsToPrevious == false`) already shows its "@X への返信" context marker, so no view code changes. Windows and iPadOS share the same `FeedThreading.arrange`, so the fix propagates automatically.

**Tech Stack:** Swift 6.0, SwiftPM (`core/` package), XCTest. Build/test with `swift test` from `core/`.

## Global Constraints

- Swift 6.0 / strict concurrency; `FeedThreading` is a pure `enum` with a `static` function and stays `Sendable`-safe (no shared mutable state).
- Commit with the `/commit` skill (`git ai-commit`); never run `git commit` directly. Commit messages in English, capitalized first letter, not Conventional Commits.
- Work happens in the worktree `.worktrees/feature/feed-self-thread-only` (branch `feature/feed-self-thread-only`). Do not commit on `main`.
- Author identity for grouping is compared via `PostDisplay.authorHandle` (the only author identifier `PostDisplay` exposes). Do NOT introduce a `BlueskyCore` import or DID extraction — see spec §3.
- TDD: one test at a time, Red → Green → Refactor. Run the full `YoruMimizukuKitTests` suite each step to confirm no regression.
- Ground-truth spec: `docs/superpowers/specs/2026-07-03-feed-self-thread-grouping-design.md`.

---

### Task 1: Restrict feed grouping to same-author self-threads

**Files:**
- Modify: `core/Sources/YoruMimizukuKit/FeedThreading.swift` (the `groupKey(for:)` closure inside `arrange`, around lines 30–44)
- Test: `core/Tests/YoruMimizukuKitTests/FeedThreadingTests.swift`

**Interfaces:**
- Consumes: `FeedThreading.arrange(_ posts: [PostDisplay]) -> [ThreadedFeedItem]` (existing, unchanged signature); `PostDisplay.authorHandle: String`, `PostDisplay.replyParent: ReplyParent?`, `ThreadedFeedItem.connectsToPrevious/Next: Bool`.
- Produces: no signature change. Behavior change only: `arrange` groups a post with its parent **only when they share the same `authorHandle`**.

- [ ] **Step 1: Extend the test helper to take an author, then write the failing multi-author test**

In `FeedThreadingTests.swift`, replace the `post` helper so the author (handle) is configurable, defaulting to the existing `"a.example"` so all current tests keep compiling unchanged:

```swift
/// Build a post; `author` sets both display name and handle (defaults keep
/// existing single-author tests unchanged); `parent` links it as reply parent.
private func post(
    _ id: String,
    createdAt: TimeInterval,
    author: String = "a.example",
    parent: PostDisplay? = nil
) -> PostDisplay {
    PostDisplay(
        id: id,
        authorDisplayName: author,
        authorHandle: author,
        body: "body \(id)",
        createdAt: Date(timeIntervalSince1970: createdAt),
        replyParent: parent.map(ReplyParent.init)
    )
}
```

Then add this test (a reduced form of the reported DDJ-FLX4 thread: one root with two replies by different people):

```swift
func testMultiAuthorRepliesDoNotMergeIntoOneBlock() {
    // root by A; two replies to root by different authors B and C. The old
    // behavior merged all three into one chronological block; now each reply
    // is an independent row (parent author != reply author).
    let root = post("root", createdAt: 100, author: "a.example")
    let b = post("b", createdAt: 200, author: "b.example", parent: root)
    let c = post("c", createdAt: 300, author: "c.example", parent: root)

    // Realistic newest-first page order.
    let items = FeedThreading.arrange([c, b, root])

    XCTAssertEqual(items.map(\.post.id), ["c", "b", "root"])
    XCTAssertEqual(items.map(\.connectsToPrevious), [false, false, false])
    XCTAssertEqual(items.map(\.connectsToNext), [false, false, false])
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd core && swift test --filter FeedThreadingTests/testMultiAuthorRepliesDoNotMergeIntoOneBlock`
Expected: FAIL. With the current author-agnostic climb, all three merge under `root` and emit oldest-first as `["root", "b", "c"]` with `connectsToPrevious == [false, true, true]`, so both the id-order and the connector assertions fail.

- [ ] **Step 3: Add the same-author condition to `groupKey`**

In `core/Sources/YoruMimizukuKit/FeedThreading.swift`, update the comment and the `while` condition of the `groupKey(for:)` closure:

```swift
// Resolve each post to the topmost ancestor on this page that is still part
// of the same author's self-thread: climb replyParent links only while the
// parent shares the current post's author. The climb stops where the author
// changes, so multi-author / branching replies do not collapse into one
// chronological block. A visited set guards against (malformed) parent cycles.
func groupKey(for post: PostDisplay) -> String {
    var current = post
    var visited: Set<String> = [post.id]
    while let parentID = current.replyParent?.post.id,
          let parent = byID[parentID],
          !visited.contains(parentID),
          parent.authorHandle == current.authorHandle {
        visited.insert(parentID)
        current = parent
    }
    return current.id
}
```

- [ ] **Step 4: Run the new test and the full suite to verify green**

Run: `cd core && swift test --filter FeedThreadingTests`
Expected: PASS — the new test passes and all pre-existing `FeedThreadingTests` still pass (they all use the default single author `"a.example"`, so their grouping is unchanged).

- [ ] **Step 5: Commit**

Use the `/commit` skill (`git ai-commit`) in the worktree. Stage only:
- `core/Sources/YoruMimizukuKit/FeedThreading.swift`
- `core/Tests/YoruMimizukuKitTests/FeedThreadingTests.swift`

Suggested message: `Group feed replies only within a single author's self-thread`

---

### Task 2: Lock in the mixed self-thread + foreign-reply boundary

**Files:**
- Test: `core/Tests/YoruMimizukuKitTests/FeedThreadingTests.swift`

**Interfaces:**
- Consumes: `FeedThreading.arrange` (behavior from Task 1); `post` helper with the `author` parameter added in Task 1.
- Produces: no production change — a characterization test proving a same-author self-thread still groups while a foreign-author reply to it splits off.

- [ ] **Step 1: Write the mixed-boundary test**

Add to `FeedThreadingTests.swift`:

```swift
func testSelfThreadGroupsWhileForeignReplySplitsOff() {
    // A's self-thread root -> a2 (same author) stays one block; B's reply to
    // a2 (different author) splits into its own row.
    let root = post("root", createdAt: 100, author: "a.example")
    let a2 = post("a2", createdAt: 200, author: "a.example", parent: root)
    let b = post("b", createdAt: 300, author: "b.example", parent: a2)

    // Newest-first page order.
    let items = FeedThreading.arrange([b, a2, root])

    // b is emitted first (its group is encountered first in page order); the
    // {root, a2} self-thread block is emitted oldest-first at a2's position.
    XCTAssertEqual(items.map(\.post.id), ["b", "root", "a2"])
    XCTAssertEqual(items.map(\.connectsToPrevious), [false, false, true])
    XCTAssertEqual(items.map(\.connectsToNext), [false, true, false])
}
```

- [ ] **Step 2: Run the test to verify it passes**

Run: `cd core && swift test --filter FeedThreadingTests/testSelfThreadGroupsWhileForeignReplySplitsOff`
Expected: PASS (Task 1's implementation already produces this; this test documents the boundary and guards against regressions).

- [ ] **Step 3: Run the full suite**

Run: `cd core && swift test --filter FeedThreadingTests`
Expected: PASS — all `FeedThreadingTests` green.

- [ ] **Step 4: Commit**

Use the `/commit` skill. Stage only `core/Tests/YoruMimizukuKitTests/FeedThreadingTests.swift`.
Suggested message: `Add test for self-thread grouping with a foreign-author reply boundary`

---

### Task 3: Update the wiki to describe self-thread-only grouping

**Files:**
- Modify: `docs/wiki/behaviors/timeline-streaming.md` (the "## Thread grouping in the feed" paragraph and the `Thread grouping in the feed (web-style)` matrix-row `note:`)
- Modify: `docs/wiki/support-matrix.md` (the `**Thread grouping in the feed (web-style)**` bullet)
- Regenerate: `docs/wiki/index.md` (via tooling — never hand-edit)

**Interfaces:**
- Consumes: nothing at runtime; documentation only.
- Produces: wiki text consistent with the new behavior; `mise run wiki:lint` passes and `docs/wiki/index.md` is regenerated.

- [ ] **Step 1: Rewrite the behavior paragraph in `timeline-streaming.md`**

Replace the paragraph under `## Thread grouping in the feed` (currently starting "A feed page that contains several posts of the same reply chain …") with:

```markdown
A feed page that contains several posts of the same author's self-thread ("1/3 … 3/3") no longer lists them as independent newest-first rows. The pure `FeedThreading.arrange` (`YoruMimizukuKit`, unit-tested) climbs each post's `replyParent` links **only while the parent shares the post's author**, resolving it to the topmost same-author ancestor present on the page and emitting that self-thread as one block, oldest first, at the feed position of the block's newest member. The climb stops where the author changes, so a multi-author, branching conversation is **not** collapsed into one flat chronological block: each reply to (or from) another account stays an independent row and keeps its "@x への返信" context marker. Posts whose parents are not on the page stay where they were, and duplicate post IDs are emitted once. The macOS `FeedView` renders a grouped self-thread block with a thread connector line between the grouped rows' avatars, hides the now-redundant reply marker inside a block, and drops the divider between grouped rows; j/k focus movement and the infinite-scroll trigger follow the displayed order (`FeedThreading.swift`, `apps/macos/Views/FeedView.swift`, `apps/macos/Views/PostRowView.swift`).
```

- [ ] **Step 2: Update the matrix-row note in `timeline-streaming.md`**

Replace the `note:` line of the `Thread grouping in the feed (web-style)` matrix entry (around line 113) with:

```yaml
    note: "macOS, iPadOS, and Windows group only a single author's self-thread into one oldest-first block (all over the tested FeedThreading.arrange; Windows via the yoru_feed_arrange bridge wrapper) with a connector line under the avatar and the in-block reply marker/divider dropped; multi-author/branching replies stay independent rows with their reply-context marker ([[windows]], [[ipados]])."
```

- [ ] **Step 3: Update the matrix bullet in `support-matrix.md`**

Replace the `**Thread grouping in the feed (web-style)**` bullet with:

```markdown
- **Thread grouping in the feed (web-style)** ([[timeline-streaming]]): macOS, iPadOS, and Windows group only a single author's self-thread into one oldest-first block (all over the tested FeedThreading.arrange; Windows via the yoru_feed_arrange bridge wrapper) with a connector line under the avatar and the in-block reply marker/divider dropped; multi-author/branching replies stay independent rows with their reply-context marker ([[windows]], [[ipados]]).
```

- [ ] **Step 4: Lint and regenerate the index**

Run: `mise run wiki:lint && mise run wiki:index`
Expected: lint passes (warnings about uncited specs/plans are non-fatal); `docs/wiki/index.md` is regenerated to cite the new spec/plan if applicable.

- [ ] **Step 5: Commit**

Use the `/commit` skill. Stage the modified wiki files and the regenerated `docs/wiki/index.md`.
Suggested message: `Document self-thread-only feed grouping in the wiki`

---

## Self-Review

**1. Spec coverage:**
- Spec §3 (climb only while author matches, via `authorHandle`, no `BlueskyCore` import) → Task 1 Step 3. ✓
- Spec §4 display consequence (foreign replies become independent rows with the existing "@X への返信" marker; no `FeedView`/`PostRowView` change) → covered by Task 1 (behavior) and stated in Architecture; no view task needed because the marker path already exists (`showReplyMarker && !connectsToPrevious && replyParent != nil`). ✓
- Spec §6 tests: multi-author-does-not-merge (Task 1), self-thread-preserved (existing `testSelfThreadIsGroupedOldestFirst`, kept green), mixed boundary (Task 2), regression of cycle/duplicate/absent-parent (existing tests, kept green). ✓
- Spec §7 (wiki + support-matrix update; iPadOS/Windows auto-propagate) → Task 3. ✓

**2. Placeholder scan:** No TBD/TODO; every code and doc step shows exact content. ✓

**3. Type consistency:** `authorHandle`, `replyParent?.post.id`, `connectsToPrevious/Next`, and `FeedThreading.arrange` match the current source (verified against `FeedThreading.swift` lines 27–44 and `FeedThreadingTests.swift`). The `post` helper's added `author` parameter is introduced in Task 1 Step 1 before its first use in Task 1's new test and reused in Task 2. ✓
