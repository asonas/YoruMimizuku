---
title: Notifications
type: behavior
updated: 2026-06-08
sources:
  - docs/superpowers/specs/2026-06-04-yorumimizuku-design.md
---

# Notifications

Notifications reach the user through two channels: an in-app "Notifications" tab and OS-level surfacing (a banner plus a Dock badge). Both are fed by polling the same endpoints (`2026-06-04-yorumimizuku-design.md` §9).

## In-app tab

The Notifications tab fetches `listNotifications` and groups items by kind (like / repost / follow / reply / mention / quote). Read state is advanced with `updateSeen`. As a polled, server-computed source it shares the timeline machinery — interval polling + backoff + pull-to-refresh — described in [[timeline-streaming]] (§6.3), and it additionally calls `getUnreadCount` to drive the badge.

## OS banner + Dock badge

A background polling actor periodically calls `getUnreadCount` / `listNotifications`, surfaces anything new since the last seen marker as an `UNUserNotificationCenter` banner, and sets the Dock badge to the unread count. Notification permission is requested on first use. The polling interval is configurable (default 30–60s) with backoff to avoid over-polling (`2026-06-04-yorumimizuku-design.md` §9). `UNUserNotificationCenter` is one of the six OS-touchpoint ports (see [[architecture]]); the Apple specifics are on the [[macos]] page.

## Sidebar unread badge (open question)

Whether the sidebar's navigation rows (home / notifications) show a numeric unread badge — as the reference app cmux does — is an open question carried in [[app-shell]], to be settled alongside this notification work.
