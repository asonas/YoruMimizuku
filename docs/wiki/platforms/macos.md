---
title: Platform — macOS
type: platform
updated: 2026-06-06
sources:
  - docs/superpowers/specs/2026-06-04-yorumimizuku-design.md
  - docs/superpowers/specs/2026-06-05-windows-multiplatform-structure.md
---

# Platform — macOS

macOS is the first target (SwiftUI / Swift 6). Windows is now implemented too, as a C#/WinUI 3 app over a C ABI bridge ([[windows]]); the macOS app instead depends on `YoruMimizukuKit` directly and does not use the bridge (an intentionally asymmetric setup).

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
- **Crypto (DPoP)**: now `swift-crypto` (`import Crypto`), a single shared implementation across macOS and Windows (`2026-06-05-windows-multiplatform-structure.md`). The concrete `CryptoKitDPoPProvider` lives in `BlueskyCore/Adapters`, not in `PlatformApple`.
- **HTTP**: `URLSession` with a `#if canImport(FoundationNetworking)` guard, shared with Windows (`URLSessionHTTPClient` in `BlueskyCore/Adapters`).
- **Browser authorization**: `ASWebAuthenticationSession` (wired in `apps/macos/Auth`), opening the OAuth authorize endpoint and catching the `as.ason:/callback` redirect.
- **OS notifications**: `UNUserNotificationCenter` for banners; the Dock badge shows the unread count. A background polling actor periodically calls `getUnreadCount` / `listNotifications`; permission is requested on first use.

## Persistence

Secrets go to the Keychain; settings/state are Codable files under Application Support (account index, window/tab layout, display settings, Jetstream cursor, optional timeline snapshots). SwiftData is not used, to keep persistence reusable across all Swift platforms (`2026-06-04-yorumimizuku-design.md` §10).

## Windows / iOS / Android

- The macOS target deliberately bypasses `YoruMimizukuBridge`.
- The earlier purity leak (`YoruMimizukuKit` importing `os`) is resolved: the
  signpost dependency is abstracted behind a `SignpostTracing` port, with the
  `os.signpost` implementation in `PlatformApple` and a no-op elsewhere, so the
  view-model layer is platform-pure ([[windows]]).
