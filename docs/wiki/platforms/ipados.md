---
title: Platform — iPadOS
type: platform
updated: 2026-06-08
sources:
  - docs/superpowers/specs/2026-06-08-yorumimizuku-ipados-design.md
  - project.yml
  - apps/ipados/YoruMimizukuPadApp.swift
  - apps/ipados/Views/RootView.swift
  - apps/ipados/Auth/ASWebAuthBrowserSession.swift
---

# Platform — iPadOS

Status: **implemented as a dedicated iPadOS target**. The app is not Mac Catalyst
and does not share the AppKit-bound macOS view files directly. It reuses
`BlueskyCore`, `YoruMimizukuKit`, and `PlatformApple`, with iPad-specific SwiftUI
and UIKit edges under `apps/ipados` (`2026-06-08-yorumimizuku-ipados-design.md`).

## Build

`project.yml` defines a separate `YoruMimizukuPad` application target with iOS
17.0 deployment, bundle id `as.ason.YoruMimizukuPad`, and the same OAuth callback
scheme (`as.ason`) as the macOS app. Regenerate the project before building:

```bash
xcodegen generate
xcodebuild build -scheme YoruMimizukuPad -project YoruMimizuku.xcodeproj -destination 'generic/platform=iOS Simulator'
```

## Architecture

The iPadOS app attaches directly to the Swift packages, matching the macOS shape
rather than the Windows C ABI bridge. `RootView` builds the shared `AccountManager`
over `KeychainStorage`, wires `LoginViewModel` to an iPadOS
`ASWebAuthenticationSession`, and creates scene-local `TimelineViewModel`,
`NotificationsViewModel`, and `WorkspaceModel` instances. Each iPad scene owns its
active account and tab set, while secure account data and the shared
`RefreshGate` remain in the core account layer (`apps/ipados/Views/RootView.swift`,
`2026-06-08-yorumimizuku-ipados-design.md` §5).

## UI and features

The shell uses `NavigationSplitView` with a touch-first sidebar. Home,
notifications, saved search tabs, author tabs, and conversation tabs are available.
Rows expose visible reply, repost, like, quote, copy-link, and open-in-browser
actions; hardware keyboard shortcuts are also available for `j` / `k` / `n` /
`f` / `o` where they make sense. Copying uses `UIPasteboard`, and opening a
permalink uses SwiftUI's `openURL` (`apps/ipados/Views/PostRowView.swift`,
`apps/ipados/Views/RootView.swift`).

Compose is presented as a sheet. It supports top-level posts, replies, quote
posts, and up to four image attachments through `PhotosPicker`; images are
compressed to JPEG on the app side before the shared `PostService` uploads them
(`apps/ipados/Views/ComposerView.swift`, `apps/ipados/Media/ImageEncoder.swift`).

## Known differences

- Jetstream live updates are not wired on iPadOS yet. The shell starts 30-second
  polling for home and notifications; foreground live sockets and background
  backfill are future work.
- OS banners and app badge updates are limited. The in-app notifications tab and
  sidebar badges work while the app is active, but background polling is not a
  reliable iPadOS notification strategy.
- Saved search creation is present as a simple keyword search tab. The full
  structured filter editor from macOS is not yet replicated in the iPad UI.
- The image grid renders inline thumbnails, but there is no dedicated lightbox
  yet.
