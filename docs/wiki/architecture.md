---
title: Architecture (Ports & Adapters)
type: concept
updated: 2026-06-08
sources:
  - docs/superpowers/specs/2026-06-04-yorumimizuku-design.md
  - docs/superpowers/plans/2026-06-04-yorumimizuku-core-foundation.md
---

# Architecture (Ports & Adapters)

The structural decision that makes YoruMimizuku cross-platform is a clean split between pure AT Protocol logic and OS-specific side effects. Every side effect crosses a protocol boundary (a "port"), and each platform supplies its own concrete adapter. This page is the backbone that the per-behavior and per-platform pages build on; the high-level map is in [[overview]].

## Two layers

- **`BlueskyCore`** (Swift Package, UI-independent): holds the AT Protocol logic purely, with no dependency on SwiftUI / AppKit / UIKit. It targets macOS / iOS and is designed so the same package can later reach Windows / Android (`2026-06-04-yorumimizuku-design.md` §4.1).
- **The app layer** (SwiftUI on macOS / WinUI 3 on Windows): a thin UI that sits on top of the core. The display models and view-model logic live one step in, in `YoruMimizukuKit`, so they stay unit-testable independent of the UI framework.

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

The ports are realized per platform: `PlatformApple` provides the Apple adapters (`#if os(macOS)`), and on Windows `PlatformWindows` provides DPAPI / `BCryptGenRandom` adapters, reached from a C# WinUI app through a C ABI bridge DLL. Those platform specifics are in [[macos]] and [[windows]]. Persistence avoids SwiftData precisely to keep this portability: settings are Codable files, secrets are in the Keychain (`2026-06-04-yorumimizuku-design.md` §10).
