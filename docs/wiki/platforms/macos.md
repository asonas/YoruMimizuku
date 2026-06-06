---
title: Platform — macOS
type: platform
updated: 2026-06-06
sources:
  - docs/superpowers/specs/2026-06-04-yorumimizuku-design.md
  - docs/superpowers/specs/2026-06-05-windows-multiplatform-structure.md
---

# Platform — macOS

macOS is the first and currently the only working target (SwiftUI / Swift 6). The app lives in `apps/macos` and depends on `YoruMimizukuKit` directly; it does not use the C ABI bridge that Windows will need (an intentionally asymmetric setup, see [[windows]]).

## Build

The project uses **XcodeGen**; `YoruMimizuku.xcodeproj` and `apps/macos/Info.plist` are generated artifacts and are gitignored, so generate them first.

```bash
brew install xcodegen          # once
xcodegen generate              # regenerate after editing project.yml
cd core && swift test          # fast core tests — run most of the time
xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj
```

> Note: AGENTS.md still shows the old `cd BlueskyCore && swift test` path. The package now lives at `core/`, so use `cd core && swift test` ([[overview]]).

## Apple-only implementations

OS touchpoints from the core's ports are implemented in `core/Sources/PlatformApple`, with files gated by `#if os(macOS)`:

- **Secure storage**: Keychain via `import Security`. Holds OAuth access/refresh tokens and the DPoP P-256 private key, per-DID ([[oauth-flow]]).
- **Random bytes**: `SecRandomCopyBytes` (`import Security`).
- **Crypto (DPoP)**: currently `CryptoKit`. The Windows plan migrates this to `swift-crypto` (`import Crypto`) so a single shared implementation covers both OSes (`2026-06-05-windows-multiplatform-structure.md`).
- **HTTP**: `URLSession` (the cross-platform plan adds a `#if canImport(FoundationNetworking)` guard).
- **Browser authorization**: `ASWebAuthenticationSession` (wired in `apps/macos/Auth`), opening the OAuth authorize endpoint and catching the `as.ason:/callback` redirect.
- **OS notifications**: `UNUserNotificationCenter` for banners; the Dock badge shows the unread count. A background polling actor periodically calls `getUnreadCount` / `listNotifications`; permission is requested on first use.

## Persistence

Secrets go to the Keychain; settings/state are Codable files under Application Support (account index, window/tab layout, display settings, Jetstream cursor, optional timeline snapshots). SwiftData is not used, to keep persistence reusable across all Swift platforms (`2026-06-04-yorumimizuku-design.md` §10).

## Windows / iOS / Android

- The macOS target deliberately bypasses `YoruMimizukuBridge`.
- One purity caveat called out by the Windows memo: `YoruMimizukuKit` currently imports `os` (`PerfSignpost.swift`, `TimelineViewModel.swift`). That leaks an Apple-only dependency; the plan abstracts it behind a `Logger` protocol with per-OS adapters, moving the macOS implementation into `PlatformApple`. Until then the "pure" layer is not strictly pure on non-Apple platforms ([[windows]]).
