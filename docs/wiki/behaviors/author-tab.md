---
title: Author (User) Tab
type: behavior
updated: 2026-06-08
sources:
  - docs/superpowers/plans/2026-06-08-phase-c-author-tab.md
  - docs/superpowers/specs/2026-06-04-yorumimizuku-design.md
  - docs/superpowers/specs/2026-06-08-yorumimizuku-ipados-design.md
  - core/Sources/YoruMimizukuBridge/BridgeOperations.swift
  - apps/windows/App/ViewModels/AuthorViewModel.cs
  - apps/windows/App/ViewModels/WorkspaceViewModel.cs
  - apps/windows/App/Views/AuthorView.xaml.cs
  - apps/windows/App/Views/FeedView.xaml.cs
features:
  - name: Author (user) tab
    macos: full
    windows: full
    ios: full
    android: planned
---

# Author (User) Tab

The author tab is a view-only window onto a single user: a profile header above that user's posts. It is opened by tapping a user's avatar anywhere the avatar appears, and it reuses the existing feed machinery rather than introducing a new list view. It is one of the tab kinds hosted by the [[app-shell]], and the posts it shows come from the same rendering path as [[timeline-streaming]] (`2026-06-08-phase-c-author-tab.md`).

## Opening an author tab

Tapping an author's avatar in the home feed, a filter feed, a notification row, a conversation, or an author feed opens (or re-selects) that user's tab. The avatar is made tappable on `PostRowView` (threaded through `FeedView` as `onOpenAuthor`), on notification rows (`NotificationsView`), and on conversation rows (`ConversationView`); each calls back to `WorkspaceModel.openAuthor(...)` (`2026-06-08-phase-c-author-tab.md` Task 10).

Because `PostDisplay` carries no DID field, the author's DID is derived from the post's AT-URI via `ATURI.repo(_:)`, which returns the authority segment of `at://<authority>/<collection>/<rkey>`. This helper was added as part of this work. When the URI is not a well-formed AT-URI the open is a no-op, so a malformed post never opens an empty tab (`2026-06-08-phase-c-author-tab.md` Task 10 Step 3).

## What the tab shows

The tab is a profile header (avatar, display name, `@handle`, and bio when available) above the user's `app.bsky.feed.getAuthorFeed` posts, fetched with `filter=posts_and_author_threads`. The header captures the tapped avatar's basics so it renders instantly, then loads the full profile in the background; a failed profile load keeps the initial snapshot rather than surfacing an error, because the header is cosmetic. The feed reuses `FeedView`, so j/k focus, infinite scroll, and the post action affordances come along unchanged. The tab is strictly view-only — there is no follow or edit control (`2026-06-08-phase-c-author-tab.md` Tasks 1, 2, 7).

On [[windows]], `yoru_author_feed_load` exposes `AuthorFeedService.getAuthorFeed` over the C ABI and `yoru_profile_load` exposes `ProfileService.getProfile`. `AuthorViewModel` owns the profile snapshot plus a reused `TimelineViewModel` over `BridgeClient.AuthorFeedLoadAsync`, and `AuthorView` renders the profile header above a nested `FeedView`. Feed and conversation avatars derive the DID from the post AT-URI; notification actors still open by handle because the grouped notification actor DTO has no DID, matching the accepted limitation below (`core/Sources/YoruMimizukuBridge/BridgeOperations.swift`, `apps/windows/App/ViewModels/AuthorViewModel.cs`, `apps/windows/App/Views/AuthorView.xaml.cs`).

On [[ipados]], post rows use the same AT-URI DID derivation and call
`WorkspaceModel.openAuthor(...)`; the author tab renders a small SwiftUI profile
header above a reused `TimelineListView` (`apps/ipados/Views/PostRowView.swift`,
`apps/ipados/Views/RootView.swift`).

## Architecture and lifecycle

A new `WorkspaceTab.author(UUID)` kind is backed by an ephemeral `AuthorTab`, which owns a reused `TimelineViewModel` (fed by `LiveAuthorFeedLoader` over the new `AuthorFeedService`) plus a small `ProfileHeaderViewModel` (fed by `LiveAuthorProfileLoader` over the existing `ProfileService`). `AuthorFeedService` mirrors `TimelineService`'s auth handling exactly — the `use_dpop_nonce` retry lives in the sender, and a 401 that is not a nonce challenge refreshes the access token once and retries — decoding into the existing `TimelineResponse` (`2026-06-08-phase-c-author-tab.md` Tasks 2–5).

`WorkspaceModel` de-duplicates author tabs by DID: re-tapping the same user re-selects the existing tab instead of opening a second one. Author tabs carry no unread badge and are not persisted across launches. `MainWindowView` polls an author tab only while it is the active selection — author polling is deliberately left out of the always-on `.task` block and is started/stopped from `syncActiveTab()` on selection changes (`2026-06-08-phase-c-author-tab.md` Tasks 3, 9). The sidebar lists open author tabs under a "ユーザー" section with no badge, mirroring the conversation section (Task 8).

## Known limitations

Two limitations are accepted in this version:

- **Bio is nil for now.** `ProfileService` decodes into `ProfileViewBasic`, which models only `did` / `handle` / `displayName` / `avatar` and has no `description` field, so `AuthorProfile.bio` is always nil until a detailed profile model is added. The header still renders name, handle, and avatar, and both the header view model and view already accommodate a non-nil bio for that future work.
- **Notification actors have no DID.** `NotificationGroup.Actor` exposes only `displayName` / `handle` / `avatarURL`, so author tabs opened from a notification dedupe by **handle** (passed as both the `actor` query value and the dedupe key), whereas tabs opened from a post dedupe by **DID**. Opening the same user from both a post and a notification can briefly create two tabs for that user.
