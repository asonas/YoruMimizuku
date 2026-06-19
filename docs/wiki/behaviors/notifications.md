---
title: Notifications
type: behavior
updated: 2026-06-15
sources:
  - docs/superpowers/specs/2026-06-04-yorumimizuku-design.md
  - core/Sources/BlueskyCore/XRPC/NotificationsService.swift
  - docs/superpowers/specs/2026-06-08-yorumimizuku-ipados-design.md
  - docs/superpowers/plans/2026-06-08-phase-a-polling-and-badges.md
  - docs/superpowers/plans/2026-06-08-macos-compose-notification-followups.md
  - docs/superpowers/plans/2026-06-11-yorumimizuku-v1.0.0-roadmap.md
  - apps/macos/NotificationSettings.swift
  - apps/macos/Views/SettingsView.swift
  - apps/macos/Views/MainWindowView.swift
  - apps/windows/App/ViewModels/NotificationsViewModel.cs
  - apps/windows/App/MainWindow.xaml.cs
features:
  - name: In-app notifications tab
    macos: full
    windows: full
    ios: full
    android: planned
  - name: OS banner + unread badge
    macos: limited
    windows: differs
    ios: limited
    android: planned
    note: "macOS and iPadOS have in-app unread badges only — the designed UNUserNotificationCenter banner + Dock badge is not implemented on macOS and is deferred past v1.0.0. Windows is the exception: it now shows an OS toast (AppNotificationManager) plus a taskbar attention flash (FlashWindowEx) for new activity, though a persistent numeric taskbar badge still needs packaged (MSIX) identity ([[macos]], [[windows]], [[ipados]])."
  - name: In-app notification settings (interval / badges)
    macos: full
    windows: full
    ios: none
    android: planned
    note: "macOS and Windows expose a 通知 settings section to choose the poll interval (15/30/60/300s) and toggle the unread badge, persisted under the same keys (Windows in AppSettings, applied live to the notifications timer and tab badge); iPadOS has no such settings UI yet ([[windows]], [[ipados]])."
---

# Notifications

Notifications reach the user through two channels: an in-app "Notifications" tab and OS-level surfacing (a banner plus a Dock badge). Both are fed by polling the same endpoints (`2026-06-04-yorumimizuku-design.md` §9).

## In-app tab

The Notifications tab fetches `listNotifications` and groups items by kind (like / repost / follow / reply / mention / quote). Read state is advanced with `updateSeen`. As a polled, server-computed source it shares the timeline machinery — interval polling + backoff + pull-to-refresh — described in [[timeline-streaming]] (§6.3), and it additionally calls `getUnreadCount` to drive the badge.

The `listNotifications` request always carries an explicit `priority=false`. When the parameter is omitted, the AppView falls back to the account-level "priority notifications" preference, which silently drops notifications (such as replies) from accounts the viewer does not follow. The app has no priority-only mode of its own, so it always requests the full stream (`NotificationsService.swift` `notificationsURL`).

## OS banner + Dock badge — designed, not yet implemented

The v1 design (§9.2) calls for a background polling actor that periodically calls `getUnreadCount` / `listNotifications`, surfaces anything new since the last seen marker as an `UNUserNotificationCenter` banner, and sets the Dock badge to the unread count, with first-use permission request and a configurable interval (default 30–60s) with backoff. `UNUserNotificationCenter` is one of the six OS-touchpoint ports (see [[architecture]]).

**None of this exists on macOS yet**: the app contains no `UNUserNotificationCenter` or Dock-badge code, and the OS-notification port itself is undefined in core. Today the only unread surfacing on every platform is the in-app sidebar badge described below. By the 2026-06-11 scope decision the OS path is deferred past v1.0.0 into a 1.x release; v1.0.0 ships in-app notification settings (polling interval, badges) only (design spec §14 addendum, `docs/superpowers/plans/2026-06-11-yorumimizuku-v1.0.0-roadmap.md`).

## Notification settings (macOS)

macOS exposes the in-app notification behavior in a **「通知」** tab in Settings (the fifth tab alongside appearance / font / display / updates), reachable with ⌘, (see [[app-shell]]). It governs two things, persisted in `NotificationSettingsStore` (`@MainActor ObservableObject`, backed by `UserDefaults`):

- **Polling interval** — `pollIntervalSeconds`, chosen from a fixed set (`15 / 30 / 60 / 300`, default 30; a stored value off the set is snapped to the nearest choice on load). Exposed as a `Duration` (`pollInterval`). `MainWindowView` starts every poller — the home timeline, the notifications source, and each filter tab — at this interval, and re-applies it the moment it changes by restarting all pollers, so a setting change takes effect without a relaunch (key `notifications.pollIntervalSeconds`).
- **Badge visibility** — `showsUnreadBadges` (default on). When off, the sidebar suppresses every unread/new badge while polling continues unchanged, so counts are still tracked but never shown (key `notifications.showsUnreadBadges`).

OS notification banners and the Dock badge are deliberately out of this store's scope; they belong to the deferred OS path above (`NotificationSettings.swift`, `apps/macos/Views/SettingsView.swift`, `apps/macos/Views/MainWindowView.swift`, `2026-06-11-yorumimizuku-v1.0.0-roadmap.md` B-4).

## Sidebar / navigation unread badge

The app also has an in-app unread badge path. On Windows, `NotificationsViewModel` keeps a local `UnreadCount` using the same "items above the last seen top item" rule as `UnreadCounter`, and `MainWindow` refreshes notifications every 30 seconds while the shell is open. Selecting the Notifications tab calls `SetActive(true)` / `MarkSeen()` and clears the badge; leaving the tab lets the next poll accumulate a count on the NavigationView row. When that poll raises the unread count, `MainWindow` also fires an OS toast through the Windows App SDK `AppNotificationManager` and flashes the taskbar with `FlashWindowEx` (`Services/NotificationAlerts.cs`), so Windows — unlike macOS — does surface notifications at the OS level; only a persistent numeric taskbar badge is still missing, pending packaged (MSIX) identity (`apps/windows/App/ViewModels/NotificationsViewModel.cs`, `apps/windows/App/MainWindow.xaml.cs`).

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
