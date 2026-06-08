---
title: Timeline Fetching and Streaming
type: behavior
updated: 2026-06-06
sources:
  - docs/superpowers/specs/2026-06-04-yorumimizuku-design.md
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

The window, tabs, and the vertical-tab sidebar that host these sources are described in [[app-shell]].
