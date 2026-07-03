---
title: YoruMimizuku Overview
type: overview
updated: 2026-06-08
sources:
  - docs/superpowers/specs/2026-06-04-yorumimizuku-design.md
  - docs/superpowers/specs/2026-06-05-windows-multiplatform-structure.md
  - docs/superpowers/specs/2026-06-08-yorumimizuku-ipados-design.md
  - docs/superpowers/specs/2026-06-08-yorumimizuku-sparkle-auto-update-design.md
  - AGENTS.md
---

# YoruMimizuku Overview

This page is the entry point so that any agent reading this repository (Claude / Cursor on macOS, a build agent on Windows) forms the same picture of the app. Details live in the per-behavior and per-platform pages. The ground truth is `docs/superpowers/specs/` and `plans/`; this wiki is a derived layer that integrates them (see [[conventions]]).

## What the app is

YoruMimizuku (夜ミミズク / 星月夜) is a native client for Bluesky (the AT Protocol). It avoids Electron and aims for a memory-efficient native implementation. The UI follows Yorufukurou: a single column switched between multiple timelines via top tabs / a sidebar. Authentication uses Bluesky OAuth (PKCE + DPoP); app passwords are not used. It targets macOS first (SwiftUI / Swift 6), now also Windows (a C#/WinUI 3 app over a shared Swift core), and has a dedicated iPadOS SwiftUI target that reuses the same core/kit layers (`docs/superpowers/specs/2026-06-04-yorumimizuku-design.md`, [[windows]], [[ipados]]).

The reference implementation is the same author's Ruby terminal client `tempest` (`/Users/asonas/ghq/github.com/asonas/tempest`). Its proven logic for XRPC, token refresh, multi-account, Jetstream, and facet detection serves as the blueprint, but this is a high-quality Swift reimplementation, not a port.

## Architectural backbone

OS-dependent side effects (Keychain, crypto, WebSocket, HTTP, browser authorization, OS notifications) are all isolated behind protocols (ports), keeping the pure logic (OAuth state machine, Jetstream decoding, Codable models, facet parsing, stores) OS-independent. This is the foundation for cross-platform reach; the full ports-and-adapters breakdown is in [[architecture]] (`2026-06-04-yorumimizuku-design.md` §4, [[macos]] / [[windows]]).

## Actual directory layout

The repository migrated to a Windows-ready structure (`2026-06-05-windows-multiplatform-structure.md`); AGENTS.md was reconciled to match it on 2026-06-06. The layout is:

```
yorumimizuku/
├── core/                         # single SPM package
│   └── Sources/
│       ├── BlueskyCore/          # pure logic: OAuth / DPoP / XRPC / Models / Account / RichText
│       │   └── Ports/            #   protocols for side effects (SecureStorage, HTTPClient, ...)
│       ├── YoruMimizukuKit/       # display logic & view models (depends on BlueskyCore)
│       ├── PlatformApple/        # Apple-only impls (Keychain / os logger, #if os(macOS))
│       ├── PlatformWindows/      # Windows-only impls (DPAPI / BCryptGenRandom, #if canImport(WinSDK))
│       └── YoruMimizukuBridge/   # C ABI (@_cdecl) DLL surface for the WinUI app
├── apps/
│   ├── macos/                    # SwiftUI app (Auth / Workspace / Compose / Views / Timeline ...)
│   ├── ipados/                   # SwiftUI iPadOS app (dedicated touch-first UI over the shared core)
│   └── windows/                  # WinUI 3 (C#/.NET 8) app: Interop (P/Invoke) + MVVM + XAML
├── docs/
│   ├── superpowers/{specs,plans} # ground-truth sources (this wiki's citations)
│   └── wiki/                     # this derived documentation layer
└── design/app-icon/
```

macOS, iPadOS, and Windows are implemented. macOS and iPadOS import the Swift
packages directly through Apple adapters; Windows reaches the same core through
`YoruMimizukuBridge` (C ABI DLL) and `apps/windows` (C#/WinUI 3). See [[macos]],
[[ipados]], and [[windows]].

## v1 scope

OAuth auth, multi-account, automatic token refresh; a single column with tabs for 7 sources (home / notifications / custom feed / list / author / search / thread); Jetstream live updates for home and lists; full write path (post / reply / like / repost / image attach); notifications (in-app tab + OS banner + Dock badge); multiple windows; and display density A/B (`2026-06-04-yorumimizuku-design.md` §2).

## Architecture & reference

- [[architecture]] — the ports-and-adapters backbone (two layers, six OS ports, core modules, concurrency)
- [[design-system]] — the component/spacing naming vocabulary (`DesignMetrics`), the DEBUG-only in-app design catalog, and snapshot-test operations
- [[glossary]] — AT Protocol / OAuth terms used across the wiki

## Behaviors

- [[app-shell]] — window, top tabs, vertical sidebar, multi-window, display density A/B
- [[oauth-flow]] — OAuth (PKCE + DPoP) login flow and token management
- [[accounts]] — multi-account persistence and per-window account switching
- [[timeline-streaming]] — timeline fetching, Jetstream live updates, and fallback
- [[compose-post]] — posting (facet detection, images, replies)
- [[filters]] — saved-search filters (structured terms and AND/OR)
- [[notifications]] — in-app tab, OS banner, and Dock badge
- [[sensitive-media]] — blurring adult / graphic media behind a tap-to-reveal curtain from content labels
- [[timeline-media-layout]] — tall-image 5:4 crop with "全体表示" hint, and wide-column body-left / media-right reflow
- [[auto-updates]] — planned macOS Sparkle update checks, settings-tab install flow, and release appcast

## Platforms

- [[macos]] — current state of the macOS build and Apple-only implementations
- [[ipados]] — dedicated iPadOS target and touch-first SwiftUI app
- [[windows]] — Windows support plan (Swift core + C#/WinUI bridge)
- [[support-matrix]] — at-a-glance star chart of which feature works on which platform (○ / △ / × / − / ?), generated from each behavior page's `features:` block
