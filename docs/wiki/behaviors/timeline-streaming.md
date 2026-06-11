---
title: Timeline Fetching and Streaming
type: behavior
updated: 2026-06-11
sources:
  - docs/superpowers/specs/2026-06-04-yorumimizuku-design.md
  - core/Sources/YoruMimizukuKit/LinkPreviewLoader.swift
  - core/Sources/YoruMimizukuKit/FeedThreading.swift
  - apps/macos/Views/LinkCardView.swift
  - docs/superpowers/specs/2026-06-08-yorumimizuku-timeline-ux-enhancements-design.md
  - docs/superpowers/specs/2026-06-08-yorumimizuku-ipados-design.md
  - docs/superpowers/plans/2026-06-08-phase-b-like-permalink-browser.md
  - docs/superpowers/plans/2026-06-08-phase-d-conversation-child-tree.md
  - docs/superpowers/plans/2026-06-11-yorumimizuku-v1.0.0-roadmap.md
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
    macos: none
    windows: none
    ios: none
    android: planned
    note: "Designed in the v1 spec but deferred by decision on 2026-06-11: interval polling is the permanent supported mode for v1.0.0 on macOS and Windows alike (the Windows 30s `RefreshAsync` top-merges like `TimelineViewModel.startPolling`). No WebSocket port, Jetstream decoder, or watchdog exists in core ([[macos]], [[windows]], [[ipados]])."
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
  - name: External link preview cards (OGP)
    macos: full
    windows: full
    ios: none
    android: planned
    note: "macOS and Windows render app.bsky.embed.external cards and fall back to a client-side OGP fetch for bare links (Windows via the yoru_ogp_load bridge endpoint); iPadOS rows do not render link cards yet ([[windows]], [[ipados]])."
  - name: Conversation child reply tree
    macos: full
    windows: full
    ios: full
    android: planned
    note: "macOS, iPadOS, and Windows render the descendant reply tree below the anchor; Windows builds it from the tested ThreadNode.childTree via the extended yoru_thread_load and indents each reply with a left connector, tappable to re-anchor ([[ipados]], [[windows]])."
  - name: Thread grouping in the feed (web-style)
    macos: full
    windows: full
    ios: none
    android: planned
    note: "macOS and Windows regroup same-thread posts into one oldest-first block (Windows via the yoru_feed_arrange bridge wrapper over the tested FeedThreading.arrange) with a connector line under the avatar and the in-block reply marker/divider dropped; iPadOS still lists reply-chain posts as independent newest-first rows ([[windows]], [[ipados]])."
---

# Timeline Fetching and Streaming

Each tab's data source is abstracted behind the `TimelineSource` protocol (`loadLatest()` / `loadOlder(cursor:)`, with an optional `liveUpdates`). Implementations are the Home / Feed / List / Author / Search / Notification / Thread sources. Networking, streams, and stores are kept thread-safe with an `actor`-based design (`2026-06-04-yorumimizuku-design.md` §4.4).

On the display side, the state machine (idle / loading / loaded / failed), polling, top-merge, and infinite scroll are centralized in `TimelineViewModel` (`YoruMimizukuKit`). Different sources are reused by swapping in a loader that satisfies the thin boundary `TimelineLoading.loadPage(cursor:) async throws -> TimelinePage`. Filter search rides on the same mechanism ([[filters]]).

## Thread grouping in the feed

A feed page that contains several posts of the same reply chain — typically an author's self-thread ("1/3 … 3/3") — no longer lists them as independent newest-first rows. Mirroring Bluesky's web client, the pure `FeedThreading.arrange` (`YoruMimizukuKit`, unit-tested) resolves each post to its topmost ancestor present on the page and emits the whole chain as one block, oldest first, at the feed position of the block's newest member; posts whose parents are not on the page stay where they were, and duplicate post IDs are emitted once. The macOS `FeedView` renders the block with a thread connector line between the grouped rows' avatars, hides the now-redundant "@x への返信" marker inside a block, and drops the divider between grouped rows; j/k focus movement and the infinite-scroll trigger follow the displayed order (`FeedThreading.swift`, `apps/macos/Views/FeedView.swift`, `apps/macos/Views/PostRowView.swift`).

## Home / List (Jetstream live) — designed, deferred

The original v1 design (§6.1) called for Jetstream live updates on home and list tabs: after the first XRPC page, subscribe Jetstream filtered on the target DIDs (home = follows, list = members) plus `app.bsky.feed.post`, batch-hydrate new posts via `getPosts`, and merge them at the top — with cursor persistence, backfill on resume, and a **watchdog that detects a stall and forces reconnection** (the typical failure after macOS sleep/wake), all carried over from tempest.

**On 2026-06-11 Jetstream was deferred out of the v1.0.0 scope entirely** (design spec §14 addendum, `docs/superpowers/plans/2026-06-11-yorumimizuku-v1.0.0-roadmap.md`): nothing of it exists in the codebase — no WebSocket port, no Jetstream decoder, no watchdog in `BlueskyCore` — and interval polling, originally specified as the fallback for users whose follow count exceeds Jetstream's `wantedDids` limit (§6.2), is now the permanent supported mode for every source including home. Revisiting Jetstream would start from a new dedicated design spec; it is not scheduled.

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

## External link preview cards

A post row can carry a link card styled after X's full large summary card: one bordered, rounded container stacking a wide 1.91:1 hero image, the page title in bold (2 lines), the description in grey (2 lines, comfortable density only), and a link-icon host line; links without a thumbnail render the same text section alone. The card sits between the body / image grid and the action bar; clicking it opens the URL in the default browser. Two sources feed the card. When the post's embed is `app.bsky.embed.external#view`, the card renders directly from the hydrated data the posting client captured (`PostEmbed.external` → `PostDisplay.linkCard`, `Timeline.swift`, `PostDisplay+Mapping.swift`). When a text-only post has no embed but its body contains a link facet, the first link's OGP metadata is fetched on demand and the same card is built client-side: `LinkPreviewLoader` (an actor) caches one result per URL — including misses — and deduplicates concurrent fetches, and the pure `OGP` parser extracts `og:title` / `og:description` / `og:image` with `<title>` / `meta description` fallbacks (`LinkPreviewLoader.swift`, `OGP.swift`, `apps/macos/Views/LinkCardView.swift`).

The fallback is intentionally skipped for posts that already attach images, keeping rows tight, and a page that yields no usable title renders nothing rather than an empty card. Note the privacy trade-off of the fallback path: resolving a bare link's preview fetches that page from the viewer's machine, so linked sites can observe the viewer's IP (the embed-provided path has no such fetch — its thumbnail comes from the Bluesky CDN). The card UI exists on [[macos]] only today; Windows and iPadOS rows render body text and images without link cards.

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
