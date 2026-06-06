---
title: Platform — Windows
type: platform
updated: 2026-06-06
sources:
  - docs/superpowers/specs/2026-06-05-windows-multiplatform-structure.md
---

# Platform — Windows

Status: **draft / architecture memo, not yet implemented**. No Windows code exists in the repo yet. The chosen direction is a **native Swift core shared across platforms, with a C#/WinUI 3 frontend that calls the Swift core through a C ABI boundary** (`2026-06-05-windows-multiplatform-structure.md`).

This page matters for cross-machine context: the Windows build runs on a different machine / agent, so it must reconstruct the same plan from this wiki and the source memo. The core direction is settled; the open items below are what an implementer must still decide.

## Feasibility of Swift on Windows

Running the non-UI core on Windows is viable:

- **Officially supported.** swift.org ships a Windows toolchain; `swift build` / `swiftc` work directly. Swift 6 strict concurrency (`Sendable` / `MainActor`) carries over unchanged.
- **Foundation is split.** Networking (`URLSession`) lives in a separate `FoundationNetworking` module; a single `#if canImport(FoundationNetworking)` guard absorbs this for compilation.
- **No CryptoKit → use swift-crypto.** `import Crypto` is API-compatible and works on both Windows and Apple, making the DPoP provider (P-256 signing + SHA-256) a single shared implementation.
- **No Security.framework (Keychain).** This genuinely needs a Windows-specific adapter: Windows Credential Manager (`CredWrite` / `CredRead`) or DPAPI for `SecureStorage`, and `BCryptGenRandom` for random bytes. Win32 APIs are reachable via `import WinSDK`.

## C# ↔ Swift bridge

There is no first-class way to call Swift from C#. The approach is to **expose the Swift core as a C ABI (cdecl) DLL and call it from C# via P/Invoke (`DllImport`)**.

- A thin bridge target (`YoruMimizukuBridge`) exposes `@_cdecl("yoru_...")` functions, built into `YoruMimizuku.dll` with `-emit-library`.
- Return structs / collections (e.g. timeline arrays) are passed as UTF-8 JSON `char*` strings, paired with a `yoru_free` for deallocation, avoiding ABI struct-layout mismatches. Async work is surfaced via a callback function pointer or a pollable handle.
- On the C# side, a wrapper class holds the `[DllImport]` declarations; the WinUI XAML / view models only see that wrapper. Isolating the bridge confines all `unsafe` pointer and C-string lifetime handling to one layer.

## Target structure (additions)

These targets/dirs do not exist yet; they are the planned additions on top of the current layout ([[overview]]):

```
core/Sources/
├── PlatformWindows/      # Credential Manager (DPAPI) / BCryptGenRandom / logger, #if os(Windows), import WinSDK
└── YoruMimizukuBridge/    # C ABI surface (@_cdecl). Windows DLL entry points. unsafe confined here.
apps/windows/
├── YoruMimizuku.Windows.sln
├── App/                  # WinUI 3 (XAML + C# view models)
└── Interop/              # DllImport wrappers (C# bindings for the Swift DLL)
```

Decision: a **single SPM package** (Option A). Platform adapters are targets under `core/Sources/`, gated by `#if os(...)`; BlueskyCore purity is enforced by the target dependency graph. crypto / HTTP need no OS split (swift-crypto + the `FoundationNetworking` guard cover both). The only truly per-OS code is the Keychain-equivalent secure storage and the logger.

## Migration order (non-destructive, Tidy First)

Each step is a structural-only change keeping `cd core && swift test` green:

1. Abstract `os` behind a `Logger` protocol, purifying `YoruMimizukuKit`; move the macOS impl to `PlatformApple`.
2. Swap `CryptoKit` for `swift-crypto` and add the `#if canImport(FoundationNetworking)` guard to the URLSession HTTP client (update the CryptoKit-importing tests in the same step). The core is now *compilable* on Windows — compilation only, not runtime.
3. Move Apple concrete impls out of `Platform/` into `PlatformApple`, collect protocols into `Ports/`. Move the adapter tests alongside (a test-target reorg, not just a source move).
4. Confirm macOS behaves identically via the test suite.
5. Add `YoruMimizukuBridge`, `PlatformWindows`, and `apps/windows`.

## Open questions

- Exact async surface over the C ABI (callback pointer vs. pollable handle).
- **URLSession on Windows**: the `FoundationNetworking` guard only guarantees compilation. swift-corelibs-foundation's URLSession has historically been less mature on Windows; run a runtime connectivity spike before relying on it, with a fallback (an `HTTPClient` adapter over WinHTTP / libcurl) in mind.
- Build/packaging pipeline for the Windows DLL + C# solution (out of scope for the memo).
