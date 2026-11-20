# macOS Sidebar: Pinned Feeds and Lists

- Date: 2026-11-20
- Status: Implemented (PR 2 of the desktop UI update)
- Target: `apps/macos`, `BlueskyCore` (new query service and response models), `YoruMimizukuKit` (`SavedFeedsModel`, `WorkspaceTab.savedFeed`); `apps/ipados` and `apps/windows` unchanged
- Builds on: `2026-11-20-macos-three-pane-design.md`

## 1. Overview

The macOS sidebar lists the feeds and lists the account pinned in Bluesky, so a
custom feed (Discover, a topic feed) or a curated list reads like home: select it
and its timeline fills the middle column. Pins live in the account's preferences
on the server (`app.bsky.actor.getPreferences`, `savedFeedsPrefV2`), so they
match what other clients show and need no local storage.

## 2. Decisions

- Sidebar order: ホーム, 通知, フィード (pinned feeds), リスト (pinned lists),
  フィルター. A section with no pins is hidden. The following timeline is the
  home row, so a pinned `timeline` item is not listed twice.
- Read-only in this PR: subscribing, unpinning and reordering are not offered.
  Pins are read when the window opens and again whenever the app becomes
  active, so a change made on another device shows up. A reload replaces the
  pins; a feed unpinned elsewhere disappears, stops
  polling, and if it was selected the window falls back to home.
- Only the selected pinned feed polls, and pinned feeds carry no unread badge,
  so pinning many feeds does not multiply requests.
- The feed header has an ⓘ button whose popover shows the description, the
  creator's handle and the AT-URI, so the reader can tell where the posts come
  from.
- A deleted feed or a list the server no longer resolves (`getList` answers
  400) is skipped instead of failing the whole section. Any other failure keeps
  the pins already shown.
- Pinned feeds and lists appear grouped (feeds, then lists) in both the sidebar
  and the ⌘⇧J/K cycling order, even when the pins interleave them.

## 3. Endpoints

| Purpose | NSID |
|---|---|
| Pins | `app.bsky.actor.getPreferences` |
| Feed names, descriptions, creators | `app.bsky.feed.getFeedGenerators` (one request) |
| List names | `app.bsky.graph.getList` (one request per list, `limit=1`) |
| Feed timeline | `app.bsky.feed.getFeed` |
| List timeline | `app.bsky.feed.getListFeed` |

`XRPCQueryService` runs these with the same DPoP nonce retry and single token
refresh as the existing services, so each endpoint is a call site rather than a
new service type. `getFeed` and `getListFeed` answer in the `getTimeline` shape
and reuse `TimelineResponse` and `TimelineViewModel`.

## 4. Not in this PR

- Editing pins, and showing unpinned saved feeds.
- Unread badges for pinned feeds.
- iPadOS: `WorkspaceTab.savedFeed` exists in the shared model, but the iPad app
  never selects it.
