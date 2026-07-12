---
title: Architecture (Ports & Adapters)
type: concept
updated: 2026-07-12
sources:
  - docs/superpowers/specs/2026-06-04-yorumimizuku-design.md
  - docs/superpowers/specs/2026-06-08-yorumimizuku-ipados-design.md
  - docs/superpowers/plans/2026-06-04-yorumimizuku-core-foundation.md
  - core/Sources/YoruMimizukuKit/RichText.swift
  - core/Sources/YoruMimizukuKit/WebURL.swift
  - core/Sources/YoruMimizukuKit/LinkCard.swift
---

# Architecture (Ports & Adapters)

The structural decision that makes YoruMimizuku cross-platform is a clean split between pure AT Protocol logic and OS-specific side effects. Every side effect crosses a protocol boundary (a "port"), and each platform supplies its own concrete adapter. This page is the backbone that the per-behavior and per-platform pages build on; the high-level map is in [[overview]].

## Two layers

- **`BlueskyCore`** (Swift Package, UI-independent): holds the AT Protocol logic purely, with no dependency on SwiftUI / AppKit / UIKit. It targets macOS / iOS and is designed so the same package can later reach Windows / Android (`2026-06-04-yorumimizuku-design.md` §4.1).
- **The app layer** (SwiftUI on macOS / iPadOS, WinUI 3 on Windows): a thin UI that sits on top of the core. The display models and view-model logic live one step in, in `YoruMimizukuKit`, so they stay unit-testable independent of the UI framework.

## The six ports

Inside `BlueskyCore`, OS touchpoints are isolated behind six protocols, with Apple implementations in a separate file group. This makes swapping in Windows/Android implementations cheap (`2026-06-04-yorumimizuku-design.md` §4.2):

1. Secure storage (Apple: Keychain / Security) — see [[accounts]]
2. Crypto / P-256 signing (Apple: CryptoKit) — for DPoP, see [[oauth-flow]]
3. WebSocket (Apple: URLSessionWebSocketTask) — for Jetstream, see [[timeline-streaming]]
4. HTTP (Apple: URLSession)
5. Browser authorization session (Apple: ASWebAuthenticationSession) — see [[oauth-flow]]
6. OS notifications (Apple: UNUserNotificationCenter) — see [[notifications]]

The pure logic — the OAuth state machine, Jetstream framing/decoding, Codable models, facet parsing, and the stores — depends on none of these and stays OS-independent. Tests inject fakes for each port (e.g. `FakeHTTPClient`, an in-memory `SecureStorage`), so the suite runs without real network or Keychain access (`2026-06-04-yorumimizuku-core-foundation.md`).

## BlueskyCore modules

The core is organized into focused modules (`2026-06-04-yorumimizuku-design.md` §4.3): `ATProtoHTTP` (XRPC transport over `/xrpc/<nsid>`, `XRPCError`), `DPoP` (P-256 keys + proof JWTs + nonce retry), `OAuthClient` (identity resolution, discovery, PAR, PKCE, token exchange/refresh), `IdentityResolver` (handle↔DID, DID document → PDS), `AccountManager` / `SessionStore` (per-DID sessions, accounts index, refresh), `Models` (the Codable lexicon subset), `BlueskyAPI` (typed high-level calls), `RichText` (facet parsing on **UTF-8 byte offsets**), `Jetstream` (the WebSocket client + watchdog), and `Stores` (per-source timeline / cursor stores + cache).

## Concurrency model

Networking, streams, and stores are `actor`-based for thread safety. Each tab's data source is abstracted by the `TimelineSource` protocol (`loadLatest()` / `loadOlder(cursor:)`, optional `liveUpdates`), with concrete `HomeSource` / `FeedSource` / `ListSource` / `AuthorSource` / `SearchSource` / `NotificationSource` / `ThreadSource` implementations — detailed in [[timeline-streaming]] (`2026-06-04-yorumimizuku-design.md` §4.4).

## How the platforms attach

The ports are realized per platform: `PlatformApple` provides the Apple adapters used by macOS and iPadOS, and on Windows `PlatformWindows` provides DPAPI / `BCryptGenRandom` adapters, reached from a C# WinUI app through a C ABI bridge DLL. Those platform specifics are in [[macos]], [[ipados]], and [[windows]]. Persistence avoids SwiftData precisely to keep this portability: settings are Codable files, secrets are in secure storage (`2026-06-04-yorumimizuku-design.md` §10, `2026-06-08-yorumimizuku-ipados-design.md` §4).

## Image loading & caching (macOS app layer)

> Derived from code (`apps/macos/Media/RemoteImage.swift`, `apps/macos/Media/ImageDownsampler.swift`), not from a spec. This pipeline lives in the macOS app layer, not in the cross-platform core.

Avatars and post images do not use SwiftUI's `AsyncImage`, which keeps no decoded cache and decodes at full resolution. The app loads them through `RemoteImage`, an `AsyncImage`-shaped view backed by the `ImageDownsampler` actor. `RemoteImage` asks for a thumbnail sized to the view's longest edge in points times the display scale, so an image decodes no larger than it is shown and reloads only when its URL or the display scale changes.

`ImageDownsampler` serves each request through three layers. An in-memory `NSCache` of already-decoded bitmaps (cost-limited to roughly 64 MB, keyed by URL plus target pixel size) answers repeat requests immediately; concurrent requests for the same key are coalesced onto a single in-flight task; and the raw network bytes go through a `URLSession` whose `URLCache` persists to disk (16 MB in memory, 256 MB on disk) under the user's Caches directory. Decoding itself uses ImageIO's `CGImageSourceCreateThumbnailAtIndex` bounded by the target pixel size, so the full-resolution bitmap is never materialized.

## Untrusted server content

> Derived from code (`core/Sources/YoruMimizukuKit/RichText.swift`, `LinkCard.swift`, `WebURL.swift`), from a security review rather than a spec.

In atproto the PDS and every post are chosen or authored by other parties, so all server-derived content is treated as untrusted at the display boundary. Two measures matter most.

Facet ranges are UTF-8 **byte offsets** supplied by the server. `RichText.segments` bounds-checks every range (`byteStart >= 0`, `byteEnd <= bytes.count`, `byteStart < byteEnd`) and slices on the byte array with `String(decoding:as:)`, so a hostile or misaligned offset yields Unicode replacement characters rather than a crash. This is why the byte-offset detail called out in [[glossary]] is a trust boundary, not just a correctness note.

Server-supplied link URLs are restricted to web schemes. `URL.isWebLink` (`WebURL.swift`) accepts only `http` / `https`; a facet `.link` carrying any other scheme is dropped and rendered as plain, non-tappable text (`RichText`), and an external embed whose `uri` is non-web produces no link card (`LinkCard.init?`). A hostile post therefore cannot hand a `file://` or custom app-scheme URL to the system opener (`openURL` / `NSWorkspace.open`), which is only ever reached for `http(s)` links — the same guard the OGP fetcher already applied to preview fetches, now extended to the tap/open path. Hashtag and mention facets are routed to in-app tabs (see [[filters]], [[author-tab]]), not the system opener.

The on-disk cache must be created with `URLCache`'s `directory:` initializer: the legacy `diskPath:` form resolved its bare name against the filesystem root on modern macOS, failed to open, and silently fell back to memory-only caching while logging a stream of SQLite errors on every request.
