---
title: Platform — iPadOS
type: platform
updated: 2026-07-10
sources:
  - docs/superpowers/specs/2026-06-08-yorumimizuku-ipados-design.md
  - docs/superpowers/specs/2026-06-24-yorumimizuku-ipados-parity-design.md
  - docs/superpowers/plans/2026-06-24-yorumimizuku-ipados-parity.md
  - docs/superpowers/specs/2026-07-02-post-interaction-affordances-design.md
  - docs/superpowers/plans/2026-07-02-post-interaction-affordances.md
  - docs/superpowers/plans/2026-07-10-yorumimizuku-ipados-parity-phase3.md
  - project.yml
  - apps/ipados/YoruMimizukuPadApp.swift
  - apps/ipados/Views/RootView.swift
  - apps/ipados/Views/PostRowView.swift
  - apps/ipados/Views/TimelineListView.swift
  - apps/ipados/Views/NotificationsListView.swift
  - apps/ipados/Views/VideoPosterView.swift
  - apps/ipados/Views/QuoteCardView.swift
  - apps/ipados/Views/ComposerView.swift
  - apps/ipados/Views/SettingsView.swift
  - apps/ipados/Views/FilterEditorView.swift
  - apps/ipados/Views/ToastView.swift
  - apps/ipados/Theme.swift
  - apps/ipados/Typography.swift
  - apps/ipados/DisplaySettings.swift
  - apps/ipados/NotificationSettings.swift
  - apps/ipados/Auth/ASWebAuthBrowserSession.swift
  - core/Sources/YoruMimizukuKit/PostDisplay.swift
  - core/Sources/YoruMimizukuKit/PostDisplay+Mapping.swift
  - core/Sources/YoruMimizukuKit/ToastCenter.swift
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

The shell uses `NavigationSplitView` with a touch-first sidebar. Home,
notifications, saved search tabs, author tabs, and conversation tabs are available.
Rows expose visible reply, repost, like, quote, copy-link, and open-in-browser
actions. Hardware-keyboard parity is also wired without visible toolbar clutter:
`j` / `k` move timeline focus, `f` likes the focused post, `o` opens it in the
browser, and `n` opens compose. Copying uses `UIPasteboard` and now raises a
transient "リンクをコピーしました" toast (`ToastCenter` + an iPad `ToastView`,
mirroring macOS); opening a permalink uses SwiftUI's `openURL`. Body links are
routed by the shell's `OpenURLAction`: hashtag links open saved-search tabs and
`@mention` links open the author's tab in-app (via `RichText.mentionDID` →
`WorkspaceModel.openAuthor`), matching macOS; every other link falls through to
the browser (`apps/ipados/Views/PostRowView.swift`, `apps/ipados/Views/RootView.swift`,
`apps/ipados/Views/TimelineListView.swift`, `apps/ipados/Views/ToastView.swift`,
`2026-07-10-yorumimizuku-ipados-parity-phase3.md`).

## Settings, filters, and notifications parity (Phase 3)

As of `2026-07-10-yorumimizuku-ipados-parity-phase3.md`, the iPad gained the
surfaces that were previously macOS-only:

- **Settings sheet.** A `gearshape` toolbar button opens `SettingsView`, an
  iPad-native `NavigationStack` + `Form` with four sections: 配色 (paste a
  randoma11y URL to recolor via the shared `ThemeStore`), 表示 (timeline
  `DisplayDensity`), フォント (UI font family via `UIFont.familyNames`, driven by an
  iPad `FontSettingsStore`), and 通知 (poll interval + unread-badge toggle via an
  iPad `NotificationSettingsStore` copied from macOS). Changing the font family
  re-ids the split view so every `.font(.app(...))` re-renders. There is **no
  update tab** — the iPad ships via TestFlight, not Sparkle
  (`apps/ipados/Views/SettingsView.swift`, `apps/ipados/DisplaySettings.swift`,
  `apps/ipados/NotificationSettings.swift`).
- **Structured filter editor.** Alongside the inline single-keyword quick-add, a
  `slider.horizontal.3` button opens `FilterEditorView` (multi-row typed terms —
  keyword / user / hashtag / mention — with an AND/OR combinator), and each filter
  row's context menu offers 編集 / 削除. It reuses the shared `SavedFilter` /
  `WorkspaceModel` filter APIs, so a blank name falls back to the generated
  `fallbackName` exactly as on macOS (`apps/ipados/Views/FilterEditorView.swift`).
- **Notification actor expansion.** Grouped like/repost rows with more than one
  actor show a chevron toggle that expands the collapsed avatar strip into a
  per-actor list (avatar + display name + `@handle`), mirroring macOS
  (`apps/ipados/Views/NotificationsListView.swift`).
- **Notification polling is now settings-driven.** The shell starts and restarts
  home / notifications / filter polling at the user's chosen interval and gates
  the sidebar badges on the "show unread badges" preference, replacing the
  previously hardcoded 30-second cadence.

## Timeline rendering parity

As of `2026-06-24-yorumimizuku-ipados-parity-design.md`, the iPad timeline renders
the same way macOS does. The presentation foundation was duplicated into
`apps/ipados` (decision §5 in that spec — duplicate now, extract a shared module
later): the framework-agnostic `ThemeStore` (`apps/ipados/Theme.swift`), the density
store, the downsampling `RemoteImage` / `ImageDownsampler` (`apps/ipados/Media/`),
and a `UIFont`-based `Typography` (`apps/ipados/Typography.swift`) that mirrors the
macOS `Font.app(...)` helpers. The link, quote, and video cards were ported verbatim
at the time (they depend only on `ThemeStore`, `RemoteImage`, and `.app(...)`). The
video poster has since diverged from that verbatim port: see "Inline video
playback" below.

`apps/ipados/Views/PostRowView.swift` is now a structural copy of the macOS row:
themed typography and colors, the shared `DisplayDensity`, the single-image 5:4
top-anchored crop with the 「全体表示」 hint (via `TimelineLayout`), the `RemoteImage`
image grid, the video poster, the external-link (OGP) card with a lazy fallback, the
quote-post card, the sensitive-media blur curtain, the reply marker, a repost/quote
popover, and a copy-link / delete context menu. `TimelineListView` applies
`FeedThreading.arrange` thread grouping with the avatar connector line, a themed
canvas and divider, classified load-failure states (offline / 429 / 5xx) with retry,
themed empty and loading states, a delete confirmation dialog, and a scene-width
measurement that drives the wide-column reflow (body-left / media-right). The macOS
hover-performance layer (`.equatable()` rows, hover highlight) is intentionally
absent — iPad has no pointer hover and uses tap-to-focus.

Compose is presented as a sheet. It supports top-level posts, replies, quote
posts, up to four image attachments through `PhotosPicker`, and a single video
attachment (mutually exclusive with images). Images are compressed to JPEG on the
app side before the shared `PostService` uploads them; a picked video is loaded
through `VideoAttachment` with an upload/processing status line, matching macOS
(`apps/ipados/Views/ComposerView.swift`, `apps/ipados/Media/ImageEncoder.swift`,
`apps/ipados/Media/VideoAttachment.swift`). Video upload landed on iPad and macOS
together (`Add video upload to composer`); the remaining compose gap is macOS-only
file import / drag-and-drop attach.

## Inline video playback (iPad-only, ahead of macOS/Windows)

Tapping a top-level post's video poster on iPadOS plays it inline instead of
leaving the app: a full-screen `AVKit` `VideoPlayer` (`VideoPlayerScreen` in
`apps/ipados/Views/PostRowView.swift`) loads the embed's HLS playlist, autoplays
on appear, routes audio through the `.playback` `AVAudioSession` category so
it is heard even with the hardware mute switch on, and pauses when dismissed
via a close button in the top-leading corner. The tap falls back to opening
the post's public permalink only when the video embed carries no usable
`playlist` URL. The playlist itself is core data, not iPad-specific: it flows
from `EmbedVideo.playlist` through the new `PostVideo.playlistURL` field added
in `core/Sources/YoruMimizukuKit/PostDisplay.swift` /
`PostDisplay+Mapping.swift`, so [[macos]] and [[windows]] already have the URL
available whenever they add their own inline player — they still only show the
poster and open the browser today. This applies to a post's own video only: a
**quoted** post's video (rendered inside `QuoteCardView`) stays a
non-interactive poster on every platform, since the quote card's own tap opens
the quoted post's conversation instead of forwarding to video playback.

## Known differences

Timeline rendering, the settings surface, the structured filter editor, the
mention-tap / copy-link-toast affordances, notification actor expansion, and video
upload have all reached parity (see the sections above). The remaining differences
are narrow:

- **Font settings are family-only.** The iPad font tab picks a UI font family but
  has no body-size stepper: the iPad `AppTypography` deliberately pins its size
  ratio to 1, and reviving the `baseSize` machinery macOS drives is out of scope
  for now (user decision, `2026-07-10-yorumimizuku-ipados-parity-phase3.md`). This
  is the one settings control macOS has that the iPad does not.
- **Jetstream live updates are not wired** on iPadOS. The shell polls (now at the
  user-chosen interval, default 30s) for home, notifications, and filters. This
  matches the v1 decision (interval polling is the supported mode everywhere)
  rather than being an iPad-specific gap (see [[timeline-streaming]]).
- **Timestamp-tap re-anchor is not narrowed on iPad — by design.** macOS narrows
  the conversation re-anchor gesture to the timestamp because a pointer UI keeps
  the row otherwise inert; the iPad already re-anchors on the **whole row tap**
  (`apps/ipados/Views/PostRowView.swift`), which is equal-or-broader on touch, so
  no timestamp-only tap was added (`2026-07-10-yorumimizuku-ipados-parity-phase3.md`).
- **OS notification banners and the app badge** are still limited on iPadOS,
  because background polling is not a reliable OS-notification strategy. Only the
  in-app poll interval and sidebar unread badges are configurable.
- **Compose** does not yet mirror macOS file import / drag-and-drop attach (image
  and video attach via `PhotosPicker` is at parity).
