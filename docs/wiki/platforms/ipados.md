---
title: Platform — iPadOS
type: platform
updated: 2026-07-03
sources:
  - docs/superpowers/specs/2026-06-08-yorumimizuku-ipados-design.md
  - docs/superpowers/specs/2026-06-24-yorumimizuku-ipados-parity-design.md
  - docs/superpowers/plans/2026-06-24-yorumimizuku-ipados-parity.md
  - docs/superpowers/specs/2026-07-02-post-interaction-affordances-design.md
  - docs/superpowers/plans/2026-07-02-post-interaction-affordances.md
  - project.yml
  - apps/ipados/YoruMimizukuPadApp.swift
  - apps/ipados/Views/RootView.swift
  - apps/ipados/Views/PostRowView.swift
  - apps/ipados/Views/TimelineListView.swift
  - apps/ipados/Views/VideoPosterView.swift
  - apps/ipados/Views/QuoteCardView.swift
  - apps/ipados/Theme.swift
  - apps/ipados/Typography.swift
  - apps/ipados/Auth/ASWebAuthBrowserSession.swift
  - core/Sources/YoruMimizukuKit/PostDisplay.swift
  - core/Sources/YoruMimizukuKit/PostDisplay+Mapping.swift
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
browser, and `n` opens compose. Copying uses `UIPasteboard`, opening a permalink
uses SwiftUI's `openURL`, and hashtag links open saved-search tabs
(`apps/ipados/Views/PostRowView.swift`, `apps/ipados/Views/RootView.swift`,
`apps/ipados/Views/TimelineListView.swift`).

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
posts, and up to four image attachments through `PhotosPicker`; images are
compressed to JPEG on the app side before the shared `PostService` uploads them
(`apps/ipados/Views/ComposerView.swift`, `apps/ipados/Media/ImageEncoder.swift`).

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

The timeline rendering gap with macOS is closed (see the section above). The
remaining differences are settings surfaces and live updates, not row appearance.

- **No settings surface yet.** The shared `ThemeStore` and `DisplayDensity` are now
  wired into the iPad scene and applied to every row, so the look matches macOS at
  the default (comfortable density, default palette). But there is **no UI to switch
  them** on iPad: the display-density A/B toggle, the randoma11y theme picker, and
  the custom-font-family / size picker from the macOS settings screen are not yet
  replicated. The font-family picker in particular needs a `UIFont` family
  enumeration the iPad `Typography` does not yet expose
  (`2026-06-24-yorumimizuku-ipados-parity-design.md` §3). This is Phase 3 of the
  parity plan.
- **Jetstream live updates are not wired** on iPadOS. The shell starts 30-second
  polling for home and notifications; this matches the v1 decision (interval polling
  is the supported mode everywhere) rather than being an iPad-specific gap.
- **Saved search creation is a simple keyword search tab.** The full structured
  filter editor (multi-row terms, AND/OR) from macOS is not yet replicated.
- **No in-app notification settings** (poll interval / badge toggle) as macOS and
  Windows have. OS banners and app badge updates are also limited because iPadOS
  background polling is not a reliable notification strategy.
- **Notifications** show reason icons, relative timestamps, actor taps, and unread
  row tint, but still use a compact summary list rather than the macOS actor
  expansion UI.
- **Compose** is functional (`PhotosPicker`, JPEG re-encoding, alt text, replies,
  quotes) but does not yet mirror every macOS affordance such as file import or
  drag-and-drop attach.
- **The 2026-07-02 post-interaction affordances are macOS-only so far.** A
  timestamp tap that re-anchors the conversation view, the copy-link toast
  (`ToastCenter`), and in-app author-tab routing for body `@mention` taps
  (`RichText.mentionDID`) all landed on macOS only; iPadOS keeps its existing
  whole-row-tap-opens-thread behavior and its `openURL` handler still
  intercepts only hashtags, not mentions (`apps/ipados/Views/RootView.swift`).
  Bringing these to iPad — `ToastCenter` is already shared core — is a
  documented follow-up, not yet started
  (`2026-07-02-post-interaction-affordances.md`, "Follow-up" section; see also
  [[timeline-streaming]]).
