---
title: Timeline Fetching and Streaming
type: behavior
updated: 2026-06-08
sources:
  - docs/superpowers/specs/2026-06-04-yorumimizuku-design.md
  - docs/superpowers/specs/2026-06-08-yorumimizuku-timeline-ux-enhancements-design.md
  - docs/superpowers/specs/2026-06-08-yorumimizuku-ipados-design.md
  - docs/superpowers/plans/2026-06-08-phase-b-like-permalink-browser.md
  - docs/superpowers/plans/2026-06-08-phase-d-conversation-child-tree.md
  - apps/windows/App/Views/FeedView.xaml
  - apps/windows/App/Views/FeedView.xaml.cs
  - apps/windows/App/Views/ConversationView.xaml
  - apps/windows/App/Views/ConversationView.xaml.cs
features:
  - name: Timeline load / refresh / infinite scroll
    macos: full
    windows: full
    ios: full
    android: planned
  - name: Jetstream live updates (home / list)
    macos: full
    windows: none
    ios: none
    android: planned
    note: "Windows and iPadOS feeds update by polling only today; neither front end wires Jetstream live top-merge yet ([[windows]], [[ipados]])."
  - name: Rich text + image grid / lightbox rendering
    macos: full
    windows: full
    ios: full
    android: planned
  - name: Keyboard navigation & post actions (j/k, n, f, o)
    macos: full
    windows: full
    ios: full
    android: planned
  - name: Copy post permalink
    macos: full
    windows: full
    ios: full
    android: planned
  - name: Conversation child reply tree
    macos: full
    windows: none
    ios: full
    android: planned
    note: "macOS and iPadOS render the descendant reply tree below the anchor; Windows shows the ancestor chain + re-anchor only ([[ipados]], [[windows]])."
---

# Timeline Fetching and Streaming

Each tab's data source is abstracted behind the `TimelineSource` protocol (`loadLatest()` / `loadOlder(cursor:)`, with an optional `liveUpdates`). Implementations are the Home / Feed / List / Author / Search / Notification / Thread sources. Networking, streams, and stores are kept thread-safe with an `actor`-based design (`2026-06-04-yorumimizuku-design.md` §4.4).

On the display side, the state machine (idle / loading / loaded / failed), polling, top-merge, and infinite scroll are centralized in `TimelineViewModel` (`YoruMimizukuKit`). Different sources are reused by swapping in a loader that satisfies the thin boundary `TimelineLoading.loadPage(cursor:) async throws -> TimelinePage`. Filter search rides on the same mechanism ([[filters]]).

## Home / List (Jetstream live)

The first page is fetched over XRPC (`getTimeline` / `getListFeed`). After that, Jetstream is subscribed with a filter on the target DIDs (home = follows, list = members) plus `app.bsky.feed.post`, and new items are merged at the top. Because Jetstream streams raw records only, new posts are batch-hydrated via `getPosts` (filling in author profiles and counts) before insertion. Counts lag slightly but that is acceptable (§6.1).

Knowledge carried over from tempest: cursor persistence, backfill on resume, suppression of like/repost replays from the cursor, and a **watchdog that detects a stall and forces reconnection** (the typical failure after macOS sleep/wake).

## Fallback (known limitation)

Jetstream's `wantedDids` filter has an upper bound. For users whose follow count exceeds it, subscribing to all DIDs + client-side filtering is too heavy, so **when the limit is exceeded, home falls back to short-interval polling** (a v1 compromise; the threshold is set at implementation time after confirming Jetstream's limit, §6.2). Jetstream live updates apply only to home / lists; filters and the rest poll.

## Other sources (polling)

Custom feed / search / author / notifications are server-computed or target non-follows, so they use interval polling + backoff + pull-to-refresh. Notifications additionally use `getUnreadCount` for the badge (§6.3); the in-app tab, OS banner, and Dock badge are described in [[notifications]].

## Keyboard actions and permalinks

The feed acts on the *focused* post — the row that `j` / `k` navigation currently sits on. Pressing **f** toggles the like on the focused post (through the same optimistic `TimelineViewModel.toggleLike` used by the action bar), and **o** opens it in the default browser; both are no-ops when no post is focused. The conversation view binds the same `f` / `o` shortcuts to its anchor (focused) post (`2026-06-08-yorumimizuku-timeline-ux-enhancements-design.md` §5.3).

Every interactive post row also carries a copy-link action: a `link` icon in the action bar copies the post's public permalink to the clipboard. The permalink is `https://bsky.app/profile/{handle-or-did}/post/{rkey}`, assembled by the pure, unit-tested `PostPermalink.url(for:)` helper in `YoruMimizukuKit` (backed by `ATURI.repo` / `ATURI.rkey` in `BlueskyCore`); it prefers the author handle and falls back to the author DID when the handle is empty or the sentinel `handle.invalid`. The icon appears only on interactive rows, so the non-interactive ancestor rows in the conversation view do not show it (`2026-06-08-yorumimizuku-timeline-ux-enhancements-design.md` §5.4).

On [[windows]], `FeedView` now binds `j` / `k` / `n` / `f` / `o`: `f` toggles the selected row's like through the existing optimistic `PostItem.ToggleLikeAsync`, and `o` opens the shared bridge-built permalink in the default browser. Feed rows and the conversation focus row both show the copy-link action; it calls `yoru_post_permalink`, which wraps the shared `PostPermalink.url(id:authorHandle:)`, then writes the URL to the WinUI clipboard (`apps/windows/App/Views/FeedView.xaml.cs`, `apps/windows/App/Views/ConversationView.xaml.cs`).

On [[ipados]], rows expose visible touch actions for reply, repost, like, quote,
copy permalink, and open permalink. The hardware-keyboard path is wired without
toolbar-only controls: `j` / `k` move focus, `f` likes the focused post, `o` opens
its permalink, and `n` opens compose. Copy uses `UIPasteboard`, browser opening
uses SwiftUI `openURL`, and hashtag links are intercepted into saved-search tabs
(`apps/ipados/Views/PostRowView.swift`, `apps/ipados/Views/TimelineListView.swift`,
`apps/ipados/Views/RootView.swift`).

## Conversation view (ancestors + reply tree)

A conversation tab loads one post's thread through `app.bsky.feed.getPostThread` and renders three bands top-to-bottom: the focused post's **ancestor chain** (oldest first, each tappable to re-anchor the tab on it), the **focused anchor** itself (left-marked as current, fully interactive), and the focused post's **descendant reply tree**. The ancestor chain follows the recursive `replyParent` links the fetch hydrates; the reply tree comes from the post's descendants in the same response (`2026-06-08-yorumimizuku-timeline-ux-enhancements-design.md` §5.6).

To populate the tree, `getPostThread` is asked for descendants (`depth=6`, deeper than the rendered cap so there is headroom for future depth and for the re-anchor cue). `ThreadViewPost` decodes its `replies` array tolerantly: a `notFoundPost` / `blockedPost` element has no `post`, so it is dropped (via the `ReplyNodeBox` wrapper, mirroring the `FacetFeatureBox` idiom) while the server's order is preserved. A pure, unit-tested `ThreadNode.childTree(of:maxDepth:)` in `YoruMimizukuKit` maps those descendants into a depth-tagged tree capped at `maxDepth: 3`; the loader hands the view both the focus and the tree as a single `ConversationThread` value. `ConversationView` renders each reply node as an indented `PostRowView` (inset by depth, with a left connector line); a node whose subtree was cut at the cap but still reports replies shows a **「さらに表示」** button that re-anchors the tab on it (reusing the same re-anchor path as an ancestor tap).

Only the anchor post is mutable: `ThreadViewModel.toggleLike` / `toggleRepost` act on the focus alone, so the action bar on a reply node is intentionally inert until that reply is re-anchored as a new focus (a deliberate Phase D scope choice). Re-anchoring by tapping an arbitrary reply row is not wired yet — re-anchoring is available on ancestors and on the 「さらに表示」 cue (`2026-06-08-phase-d-conversation-child-tree.md`).

The iPadOS conversation view reuses the shared `ThreadViewModel` and
`ConversationThread` shape, rendering the focus post and descendant reply tree in
a `List` under `apps/ipados/Views/ConversationView.swift`. It now includes the
focused post's ancestor chain and a 「さらに表示」 re-anchor cue for reply nodes whose
subtree was capped, matching the macOS conversation-navigation behavior.

The window, tabs, and the vertical-tab sidebar that host these sources are described in [[app-shell]].
