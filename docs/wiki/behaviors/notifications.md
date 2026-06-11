---
title: Notifications
type: behavior
updated: 2026-06-11
sources:
  - docs/superpowers/specs/2026-06-04-yorumimizuku-design.md
  - core/Sources/BlueskyCore/XRPC/NotificationsService.swift
  - docs/superpowers/specs/2026-06-08-yorumimizuku-ipados-design.md
  - docs/superpowers/plans/2026-06-08-phase-a-polling-and-badges.md
  - docs/superpowers/plans/2026-06-08-macos-compose-notification-followups.md
  - apps/windows/App/ViewModels/NotificationsViewModel.cs
  - apps/windows/App/MainWindow.xaml.cs
features:
  - name: In-app notifications tab
    macos: full
    windows: full
    ios: full
    android: planned
  - name: OS banner + unread badge
    macos: full
    windows: limited
    ios: limited
    android: planned
    note: "Windows and iPadOS keep in-app unread badges while active, but neither has a complete OS toast/banner + badge path yet ([[windows]], [[ipados]], [[macos]])."
---

# Notifications

Notifications reach the user through two channels: an in-app "Notifications" tab and OS-level surfacing (a banner plus a Dock badge). Both are fed by polling the same endpoints (`2026-06-04-yorumimizuku-design.md` §9).

## In-app tab

The Notifications tab fetches `listNotifications` and groups items by kind (like / repost / follow / reply / mention / quote). Read state is advanced with `updateSeen`. As a polled, server-computed source it shares the timeline machinery — interval polling + backoff + pull-to-refresh — described in [[timeline-streaming]] (§6.3), and it additionally calls `getUnreadCount` to drive the badge.

The `listNotifications` request always carries an explicit `priority=false`. When the parameter is omitted, the AppView falls back to the account-level "priority notifications" preference, which silently drops notifications (such as replies) from accounts the viewer does not follow. The app has no priority-only mode of its own, so it always requests the full stream (`NotificationsService.swift` `notificationsURL`).

## OS banner + Dock badge

A background polling actor periodically calls `getUnreadCount` / `listNotifications`, surfaces anything new since the last seen marker as an `UNUserNotificationCenter` banner, and sets the Dock badge to the unread count. Notification permission is requested on first use. The polling interval is configurable (default 30–60s) with backoff to avoid over-polling (`2026-06-04-yorumimizuku-design.md` §9). `UNUserNotificationCenter` is one of the six OS-touchpoint ports (see [[architecture]]); the Apple specifics are on the [[macos]] page.

## Sidebar / navigation unread badge

The app also has an in-app unread badge path. On Windows, `NotificationsViewModel` keeps a local `UnreadCount` using the same "items above the last seen top item" rule as `UnreadCounter`, and `MainWindow` refreshes notifications every 30 seconds while the shell is open. Selecting the Notifications tab calls `SetActive(true)` / `MarkSeen()` and clears the badge; leaving the tab lets the next poll accumulate a count on the NavigationView row. This is not an OS toast or taskbar badge, so the support matrix marks Windows limited until those OS surfaces exist (`apps/windows/App/ViewModels/NotificationsViewModel.cs`, `apps/windows/App/MainWindow.xaml.cs`).

On [[ipados]], `NotificationsViewModel` drives the in-app tab and sidebar badge
through foreground polling. The MVP intentionally does not promise background
polling-based banners; push notifications would need a separate design
(`2026-06-08-yorumimizuku-ipados-design.md` §9).

## Opening notification subjects

On macOS, a notification with a target post (`subjectURI`) opens that post in a
conversation tab when the target-post snippet is clicked. This covers likes and
reposts and any other subject-backed notification group. `WorkspaceModel` has a
URI-based `openConversation(anchorID:title:handle:subtitle:)` entry point for this
case because notification groups carry a subject URI and snippet, not a full
`PostDisplay`. Notifications without a `subjectURI`, such as follows, remain
non-opening (`2026-06-08-macos-compose-notification-followups.md`,
`WorkspaceModel.swift`, `apps/macos/Views/NotificationsView.swift`).
