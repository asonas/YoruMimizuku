---
title: Timeline Fetching and Streaming
type: behavior
updated: 2026-06-24
sources:
  - docs/superpowers/specs/2026-06-04-yorumimizuku-design.md
  - docs/superpowers/specs/2026-06-24-yorumimizuku-ipados-parity-design.md
  - docs/superpowers/plans/2026-06-24-yorumimizuku-ipados-parity.md
  - apps/ipados/Views/PostRowView.swift
  - apps/ipados/Views/TimelineListView.swift
  - apps/ipados/Views/LinkCardView.swift
  - apps/ipados/Views/QuoteCardView.swift
  - apps/ipados/Views/VideoPosterView.swift
  - core/Sources/YoruMimizukuKit/LinkPreviewLoader.swift
  - core/Sources/YoruMimizukuKit/FeedThreading.swift
  - apps/macos/Views/LinkCardView.swift
  - docs/superpowers/specs/2026-06-08-yorumimizuku-timeline-ux-enhancements-design.md
  - docs/superpowers/specs/2026-06-08-yorumimizuku-ipados-design.md
  - docs/superpowers/plans/2026-06-08-phase-b-like-permalink-browser.md
  - docs/superpowers/plans/2026-06-08-phase-d-conversation-child-tree.md
  - docs/superpowers/plans/2026-06-11-yorumimizuku-v1.0.0-roadmap.md
  - docs/superpowers/plans/2026-06-11-quote-and-video-embeds.md
  - core/Sources/YoruMimizukuKit/PostInteracting.swift
  - core/Sources/YoruMimizukuKit/TimelineViewModel.swift
  - core/Sources/YoruMimizukuKit/LoadFailure.swift
  - apps/macos/Views/PostRowView.swift
  - apps/macos/Views/FeedView.swift
  - core/Sources/BlueskyCore/Models/Timeline.swift
  - apps/macos/Views/QuoteCardView.swift
  - apps/macos/Views/VideoPosterView.swift
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
  - name: Delete own post
    macos: full
    windows: full
    ios: full
    android: planned
    note: "macOS, iPadOS, and Windows offer a 「削除」 action on the viewer's own rows (post AT-URI repo DID == account DID), confirm, then prune the row (Windows via yoru_post_delete; restores on failure). iPadOS uses a SwiftUI confirmationDialog ([[windows]], [[ipados]])."
  - name: Load error states (offline / 429 / 5xx) with retry
    macos: full
    windows: full
    ios: full
    android: planned
    note: "macOS, iPadOS, and Windows classify a failed first load into offline / rate-limited / server / unknown and show a titled message with a 「再試行」 button. Windows carries the shared LoadFailure on the bridge error envelope (kind/title/message) ([[windows]], [[ipados]])."
  - name: External link preview cards (OGP)
    macos: full
    windows: full
    ios: full
    android: planned
    note: "macOS, iPadOS, and Windows render app.bsky.embed.external cards and fall back to a client-side OGP fetch for bare links (Windows via the yoru_ogp_load bridge endpoint; iPadOS via the ported LinkCardView + LazyLinkCardView) ([[windows]], [[ipados]])."
  - name: Quote post (record embed) cards
    macos: full
    windows: full
    ios: full
    android: planned
    note: "macOS, iPadOS, and Windows render app.bsky.embed.record / recordWithMedia quotes as a bordered card (author, body, thumbnails / video poster) that opens the quoted post's conversation ([[windows]], [[ipados]])."
  - name: Video embed poster (no inline playback)
    macos: full
    windows: full
    ios: full
    android: planned
    note: "macOS, iPadOS, and Windows show the app.bsky.embed.video poster with a play badge and open the post in the browser on click; inline playback is post-1.0 everywhere ([[windows]], [[ipados]])."
  - name: Conversation child reply tree
    macos: full
    windows: full
    ios: full
    android: planned
    note: "macOS, iPadOS, and Windows render the descendant reply tree below the anchor; Windows builds it from the tested ThreadNode.childTree via the extended yoru_thread_load and indents each reply with a left connector, tappable to re-anchor ([[ipados]], [[windows]])."
  - name: Thread grouping in the feed (web-style)
    macos: full
    windows: full
    ios: full
    android: planned
    note: "macOS, iPadOS, and Windows regroup same-thread posts into one oldest-first block (all over the tested FeedThreading.arrange; Windows via the yoru_feed_arrange bridge wrapper) with a connector line under the avatar and the in-block reply marker/divider dropped ([[windows]], [[ipados]])."
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

## Deleting your own posts

A row whose author is the signed-in account carries a destructive **「削除」** action in its context menu. Ownership is decided by the host, not the row: `FeedView` compares the post URI's repo authority (`ATURI.repo(post.id)`) against the window's `currentDID` and only sets the row's `canDelete` flag for a match, so the action never appears on other people's posts (and is disabled entirely in previews where `currentDID` is nil). Choosing it raises a confirmation dialog (「この投稿を削除しますか？」); confirming calls the shared `TimelineViewModel.deletePost(_:)`, which **optimistically** removes the row from the loaded list, asks the injected `PostInteracting.deletePost(uri:)` to delete the record, and — if that throws — reinserts the post at its original index so a transient failure never silently drops a post the server still holds. The delete capability flows down the view hierarchy as `currentDID` (RootView → MainWindowView → FeedView / AuthorView). The pure prune/restore logic is unit-tested in `TimelineViewModelTests` (success, failure, and no-op when the post is absent). The delete capability is shared (`PostInteracting.deletePost`, `TimelineViewModel.deletePost`), but the delete UI exists only on macOS so far; [[ipados]] and [[windows]] do not wire it yet (`PostInteracting.swift`, `TimelineViewModel.swift`, `apps/macos/Views/PostRowView.swift`, `apps/macos/Views/FeedView.swift`).

## Error states and retry

When a tab's *first* load fails, the feed shows a tailored error screen rather than a raw Swift error string. `TimelineViewModel`'s failed state carries a `LoadFailure` (`YoruMimizukuKit`), a small value built from any thrown `Error` that classifies it into one of four kinds — `offline` (URLSession connectivity codes such as `notConnectedToInternet` / `timedOut` / `dnsLookupFailed`), `rateLimited` (`XRPCError.requestFailed` with HTTP 429), `server` (HTTP 5xx), or `unknown` (decoding, other 4xx, anything else) — and exposes a Japanese `title` and `message` per kind plus a `detail` debug string. macOS `FeedView.failedState` renders a kind-specific SF Symbol, the title and message, and a **「再試行」** button that re-runs `model.load()`. The classification is unit-tested in `LoadFailureTests`. Only the initial load surfaces this screen: `refresh()` (periodic poll) and `loadMore()` (infinite scroll) swallow their failures so a blip never replaces already-loaded content with an error page — the next poll or scroll simply retries. There is no separate exponential backoff for 429; the poll interval (a notification setting, see [[notifications]]) is the effective rate limiter, and the user can retry on demand. `NotificationsViewModel` and `ThreadViewModel` reuse `LoadFailure` for its `message` text but keep a plain-string failed state without the icon/retry chrome. How [[ipados]] and [[windows]] surface these failures has not been audited against this classification (`LoadFailure.swift`, `TimelineViewModel.swift`, `apps/macos/Views/FeedView.swift`).

## External link preview cards

A post row can carry a link card styled after X's full large summary card: one bordered, rounded container stacking a wide 1.91:1 hero image, the page title in bold (2 lines), the description in grey (2 lines, comfortable density only), and a link-icon host line; links without a thumbnail render the same text section alone. The card sits between the body / image grid and the action bar; clicking it opens the URL in the default browser. Two sources feed the card. When the post's embed is `app.bsky.embed.external#view`, the card renders directly from the hydrated data the posting client captured (`PostEmbed.external` → `PostDisplay.linkCard`, `Timeline.swift`, `PostDisplay+Mapping.swift`). When a text-only post has no embed but its body contains a link facet, the first link's OGP metadata is fetched on demand and the same card is built client-side: `LinkPreviewLoader` (an actor) caches one result per URL — including misses — and deduplicates concurrent fetches, and the pure `OGP` parser extracts `og:title` / `og:description` / `og:image` with `<title>` / `meta description` fallbacks (`LinkPreviewLoader.swift`, `OGP.swift`, `apps/macos/Views/LinkCardView.swift`).

The fallback is intentionally skipped for posts that already attach images, keeping rows tight, and a page that yields no usable title renders nothing rather than an empty card. Note the privacy trade-off of the fallback path: resolving a bare link's preview fetches that page from the viewer's machine, so linked sites can observe the viewer's IP (the embed-provided path has no such fetch — its thumbnail comes from the Bluesky CDN). The card UI exists on [[macos]] only today; Windows and iPadOS rows render body text and images without link cards.

## Quote post cards and video posters

A post whose embed is `app.bsky.embed.record#view` (or `recordWithMedia#view`) renders the quoted post inside the row as a bordered, rounded card: a compact author line (small avatar, display name, handle, relative time), the quoted body capped at six lines, and the quoted post's own media — up to two small image thumbnails, or a video poster. Clicking the card opens the quoted post's conversation tab through the same URI-based `WorkspaceModel.openConversation(anchorID:)` entry point notifications use. Decoding is tolerant by shape, not `$type`: `PostEmbed` probes the `record` key both as the bare `viewRecord` (record#view) and as the one-level-deeper wrapper (recordWithMedia#view), and a `viewNotFound` / `viewBlocked` / `viewDetached` variant or a non-post record (a quoted list or feed generator) simply yields no card. A recordWithMedia post's `media` is decoded as a nested `PostEmbed` and merged, so its images / external / video render through the existing paths alongside the quote card (`Timeline.swift`, `PostDisplay+Mapping.swift`, `apps/macos/Views/QuoteCardView.swift`).

A post with `app.bsky.embed.video#view` renders the video's poster frame at its reported aspect ratio (16:9 when omitted) with a centered play badge. Playback is not inline in v1 — clicking the poster opens the post's public permalink in the default browser. The quote card reuses the same poster for a quoted post that carries video (`apps/macos/Views/VideoPosterView.swift`, `2026-06-11-quote-and-video-embeds.md`). The OGP fallback card for bare links is skipped for posts that already carry images, video, or a quote, keeping rows tight. Both renderings are macOS-only today; Windows and iPadOS rows still drop record and video embeds.

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
