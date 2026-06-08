---
title: Platform — macOS
type: platform
updated: 2026-06-08
sources:
  - docs/superpowers/specs/2026-06-04-yorumimizuku-design.md
  - docs/superpowers/specs/2026-06-05-windows-multiplatform-structure.md
  - docs/superpowers/specs/2026-06-08-yorumimizuku-ipados-design.md
  - docs/superpowers/specs/2026-06-04-yorumimizuku-app-icon-design.md
  - docs/superpowers/plans/2026-06-04-yorumimizuku-app-icon.md
---

# Platform — macOS

macOS is the first target (SwiftUI / Swift 6). Windows is implemented as a C#/WinUI 3 app over a C ABI bridge ([[windows]]), and iPadOS is implemented as a separate SwiftUI target over the same Swift core ([[ipados]]). The macOS app depends on `YoruMimizukuKit` directly and does not use the bridge (an intentionally asymmetric setup).

## Build

The project uses **XcodeGen**; `YoruMimizuku.xcodeproj` and `apps/macos/Info.plist` are generated artifacts and are gitignored, so generate them first.

```bash
brew install xcodegen          # once
xcodegen generate              # regenerate after editing project.yml
cd core && swift test          # fast core tests — run most of the time
xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj
```

The package lives at `core/` (an earlier note about an `BlueskyCore/` path in AGENTS.md is obsolete; AGENTS.md now uses `core/`) ([[overview]]).

## Apple-only implementations

OS touchpoints from the core's ports are implemented in `core/Sources/PlatformApple`, with files gated by `#if os(macOS)`:

- **Secure storage**: Keychain via `import Security`. Holds OAuth access/refresh tokens and the DPoP P-256 private key, per-DID ([[oauth-flow]]).
- **Random bytes**: `SecRandomCopyBytes` (`import Security`).
- **Crypto (DPoP)**: now `swift-crypto` (`import Crypto`), a single shared implementation across macOS and Windows (`2026-06-05-windows-multiplatform-structure.md`). The concrete `CryptoKitDPoPProvider` lives in `BlueskyCore/Adapters`, not in `PlatformApple`.
- **HTTP**: `URLSession` with a `#if canImport(FoundationNetworking)` guard, shared with Windows (`URLSessionHTTPClient` in `BlueskyCore/Adapters`).
- **Browser authorization**: `ASWebAuthenticationSession` (wired in `apps/macos/Auth`), opening the OAuth authorize endpoint and catching the `as.ason:/callback` redirect.
- **OS notifications**: `UNUserNotificationCenter` for banners; the Dock badge shows the unread count. A background polling actor periodically calls `getUnreadCount` / `listNotifications`; permission is requested on first use. The cross-platform behavior is in [[notifications]].

## Persistence

Secrets go to the Keychain; settings/state are Codable files under Application Support (account index, window/tab layout, display settings, Jetstream cursor, optional timeline snapshots). SwiftData is not used, to keep persistence reusable across all Swift platforms (`2026-06-04-yorumimizuku-design.md` §10).

## Timeline rendering: `List`, not `LazyVStack`

The feed (`apps/macos/Views/FeedView.swift`) renders its rows with a SwiftUI `List` (`.listStyle(.plain)`), not the more obvious `ScrollView { LazyVStack }`. This is deliberate, and the reasoning matters because the obvious choice has a real bug.

`LazyVStack` lays rows out from an *estimated* height before each row is actually measured. On the first layout pass a row can be assigned a slot taller than its content, and a normal body re-render — including the per-second relative-time (`now`) tick that the window already drives ([[app-shell]]) — does **not** revisit that estimate. The result is a blank gap below the row that only collapses when a full re-layout is forced (scrolling the row off and back, or a scene-phase change such as backgrounding the app). The gap was reproducible at launch, independent of the row's text length, width, `AttributedString` rich-text vs plain text, `.fixedSize`, and `.textSelection` — i.e. it is a `LazyVStack` slot-estimation artifact, not a content-measurement one.

A plain `VStack` measures every row eagerly and sidesteps the estimation, but realizing the whole feed at once is not viable (~98% CPU and ~1 GB memory on a long timeline). `List` is the middle ground: it measures variable row heights correctly (no phantom gap) and recycles rows (bounded memory). The cost is that `List` brings its own chrome, which is neutralized per-row with `.listRowInsets(EdgeInsets())`, `.listRowSeparator(.hidden)` (each row draws its own `Divider` so the separator color follows the theme), `.listRowBackground(Color.clear)`, plus `.scrollContentBackground(.hidden)` and `.environment(\.defaultMinListRowHeight, 0)` on the list. j/k focus still scrolls via `ScrollViewReader.scrollTo`, and the loading / failed / empty states render outside the `List` in a plain `ScrollView`. The same row view ([[timeline-streaming]]) is reused unchanged.

### Scroll performance

Because `List` hosts each row in an `NSHostingView` and re-lays it out on scroll, per-row body work shows up directly as scroll cost. A Time Profiler capture of vigorous scrolling put most main-thread time in the framework layout / AttributeGraph machinery (inherent to hosting SwiftUI rows in `List`), but the top *self-weight* leaf we own was `s_strFromUTF8WithSub` (ICU UTF-8 conversion) followed by `NSAttributedString` metrics — both from building the body text. Two changes target that:

- **Precompute the body `AttributedString`.** `PostRowView` used to rebuild `Text`'s `AttributedString` from the post's rich-text segments on every render. The expensive part — the character build (`s_strFromUTF8WithSub`) — is now done once in `PostDisplay.bodyAttributedString` (at mapping time, theme-independent: link spans carry only the `.link` attribute). The row's `bodyAttributed` then re-applies the accent color to link runs per render, which only mutates run attributes (no re-conversion), so the hot leaf stays eliminated while link color stays theme-derived (`PostDisplay.swift`, `apps/macos/Views/PostRowView.swift`).
- **Coarsen the `now` tick.** The window refreshes `now` to advance relative timestamps; the timer was 1s but the displayed string is minutes/hours for all but the newest posts, so it re-rendered every visible row ~15x more often than needed. It is now 15s; only sub-minute ages ("30s") update in coarser steps (`apps/macos/Views/MainWindowView.swift`, see also [[app-shell]]).

The remaining cost (NSTableView row layout, `AG::Graph` updates) is structural to `List` + SwiftUI hosting and is not separately optimized.

### Body links are not selectable text

The post body `Text` does **not** use `.textSelection(.enabled)`. On macOS, a selectable `Text` and tappable `.link` runs are mutually incompatible: with both, the link spans render blank the moment the row re-lays-out (e.g. when j/k focus toggles the row background), so URLs vanish on focus and become unclickable. Tappable links win over body selection — sharing a post is covered by the copy-link action ([[timeline-streaming]]) (`apps/macos/Views/PostRowView.swift`).

### Inline images respect their aspect ratio

A lone attached image is laid out at its true aspect ratio rather than a fixed-height center crop, so a wide image shows in full (no left/right crop and no horizontal overflow) and a tall image fills the column width with only a slight crop. The source ratio comes from the embed's `aspectRatio` (`app.bsky.embed.images#view`), which the core now decodes onto `EmbedImage` and carries to the view as `PostImage.aspectRatio` (width / height; nil when the embed omits it). The view clamps that ratio to `[0.7, 5.0]` so an extreme panorama or portrait can't make the row absurdly short or tall — within the clamp the image fills its box exactly (cover equals contain, so a crop only ever touches the clamped extreme), and the decode size follows the box's longer edge to stay sharp. Two or more images keep the fixed-height cover-cropped grid, where uniform tiles read better than mismatched proportions (`apps/macos/Views/PostRowView.swift`, `PostDisplay.swift`, `Timeline.swift`).

## App icon

The macOS AppIcon depicts a horned owl (ミミズク), after the app name 星月夜 (a starlit, moonlit night). The artwork starts from a CC0 owl SVG and is recolored to the app's dark-ground / blue-accent palette, then exported as the full AppIcon set (16–1024px, including @2x) (`2026-06-04-yorumimizuku-app-icon-design.md`, `2026-06-04-yorumimizuku-app-icon.md`). Sources live in `design/app-icon/`. The Windows taskbar icon is generated from this same owl artwork ([[windows]]).

## Windows / iPadOS / Android

- The macOS target deliberately bypasses `YoruMimizukuBridge`.
- The iPadOS target also bypasses `YoruMimizukuBridge`; it has its own touch-first
  SwiftUI views under `apps/ipados` while sharing `BlueskyCore`,
  `YoruMimizukuKit`, and `PlatformApple` ([[ipados]]).
- The earlier purity leak (`YoruMimizukuKit` importing `os`) is resolved: the
  signpost dependency is abstracted behind a `SignpostTracing` port, with the
  `os.signpost` implementation in `PlatformApple` and a no-op elsewhere, so the
  view-model layer is platform-pure ([[windows]]).
