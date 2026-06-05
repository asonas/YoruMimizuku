# Windows Multi-Platform Directory Structure

Status: Draft (architecture memo, not yet implemented)
Date: 2026-06-05
Decision owner: asonas

## Goal

Prepare the repository to grow a Windows client alongside the existing macOS
client, without compromising the macOS build. The chosen direction is a **native
Swift core shared across platforms, with a C#/WinUI 3 frontend on Windows** that
calls the Swift core through a C ABI boundary.

This memo records the analysis of the current structure, the technical
feasibility of running Swift on Windows, the bridging strategy between C# and
Swift, the target directory layout, and a non-destructive migration order. No
code has been changed yet.

## Current Structure Assessment

The existing module split (`BlueskyCore` for platform-independent logic,
`YoruMimizukuKit` for view models, `app/YoruMimizuku` for the macOS SwiftUI app)
already follows the right principle: OS touchpoints are abstracted behind
protocols (`SecureStorage`, `DPoPCryptoProvider`, `RandomBytesGenerator`,
`HTTPClient`). The foundation is sound. The problems are about *where the
concrete, Apple-only implementations live*, not about the abstractions.

### Problem 1: Apple-only concrete implementations live inside the cross-platform target

`BlueskyCore` is supposed to be platform-independent, but its `Platform/` folder
contains files that import Apple-only frameworks. Swift fails the **entire
target build** when any single file imports an unavailable module, so
`BlueskyCore` cannot compile on Windows as-is.

| File | Dependency | Status on Windows |
|---|---|---|
| `Platform/KeychainStorage.swift` | `import Security` | Unavailable |
| `Platform/RandomBytesGenerator.swift` | `import Security` (`SecRandomCopyBytes`) | Unavailable |
| `Platform/CryptoKitDPoPProvider.swift` | `import CryptoKit` | Unavailable (needs swift-crypto) |
| `Platform/URLSessionHTTPClient.swift`, `Platform/HTTP.swift` | `URLSession` | Needs `import FoundationNetworking` |

The protocols are already separated, but the concrete adapters sit in the same
target and the same `Platform/` folder as the abstractions. Ports (protocols)
and adapters (OS implementations) are not physically separated.

### Problem 2: The pure view-model layer leaks `os`

`YoruMimizukuKit/PerfSignpost.swift` and `YoruMimizukuKit/TimelineViewModel.swift`
import `os`. `os.signpost` / `Logger` are Apple-only, so this layer is not
actually pure. It should depend on a `Logger` protocol, with per-OS adapters
injected at the edge. (For contrast, `PaletteColor.swift` deliberately avoids
SwiftUI and is a good model to follow.)

### Problem 3: `app/` is macOS-only but generically named and singular

`app/YoruMimizuku` is entirely SwiftUI/AppKit and cannot be reused on Windows.
`project.yml` is macOS-specific. There is no home for a Windows app or for
Windows platform adapters.

## Technical Feasibility: Swift on Windows

Running the **non-UI core** on Windows is viable for production use, with these
caveats:

- **Officially supported.** Windows is a supported Swift platform; swift.org
  ships a Windows toolchain. `swift build` / `swiftc` work directly.
- **Foundation works but is split.** Windows uses swift-corelibs-foundation, and
  networking (`URLSession`, etc.) is in a separate `FoundationNetworking`
  module. A single `#if canImport(FoundationNetworking)` guard absorbs this. The
  existing `URLSessionHTTPClient.swift` needs only this change to run on Windows.
- **No CryptoKit; use swift-crypto.** [swift-crypto](https://github.com/apple/swift-crypto)
  provides an API-compatible `import Crypto` that works on Windows (and Apple).
  Changing `import CryptoKit` to `import Crypto` makes the DPoP provider a single
  shared implementation across both OSes (P-256 signing + SHA-256).
- **No Security.framework (Keychain).** This genuinely needs a Windows-specific
  adapter: Windows Credential Manager (`CredWrite`/`CredRead`) or DPAPI for
  `SecureStorage`, and `BCryptGenRandom` (or similar) for random bytes. Win32
  APIs are callable from Swift via `import WinSDK`.
- **Swift 6 strict concurrency is supported on Windows.** Existing
  `Sendable` / `MainActor` design carries over unchanged.

Conclusion: "Swift core on Windows, UI in C#/WinUI" is technically sound. The
remaining design question is the C# ↔ Swift bridge.

## C# ↔ Swift Bridging Strategy

There is no first-class way to call Swift from C# directly. The established
approach is: **expose the Swift core as a C ABI (cdecl) DLL, then call it from
C# via P/Invoke (`DllImport`).**

- A thin bridge target in the Swift core exposes C-compatible entry points using
  `@_cdecl("yoru_login_start")`-style functions, built into `YoruMimizuku.dll`
  with `-emit-library`.
- Return structs and collections (e.g. timeline arrays) are passed as UTF-8 JSON
  `char*` strings, paired with a `yoru_free` function for deallocation. This
  avoids ABI struct-layout mismatches. Async work is surfaced via a callback
  function pointer or a pollable handle exposed over the C ABI.
- On the C# side, a wrapper class holds the `[DllImport("YoruMimizuku.dll")]`
  declarations. The WinUI XAML / view models only ever see that wrapper.

Isolating the bridge into its own Swift target keeps `unsafe` pointer handling
and C-string lifetime management contained in one place.

## Target Directory Structure

Decision: **single SPM package** (Option A). The platform adapters are targets
under `core/Sources/`, not a separate `platform/` package. BlueskyCore purity is
enforced by the target dependency graph (the `BlueskyCore` target depends on
nothing platform-specific), and each adapter file is gated with `#if os(...)` so
the package builds on every OS. Splitting into a separate package is a cheap
future refactor if it ever becomes warranted (see Open Questions).

```
yorumimizuku/
├── core/                              # single SPM package
│   ├── Package.swift                  #   add swift-crypto dependency
│   └── Sources/
│       ├── BlueskyCore/               # PURE: Foundation only. logic / models / protocols
│       │   ├── OAuth/  XRPC/  Models/  Account/  DPoP/
│       │   └── Ports/                 #   protocols: SecureStorage, DPoPCryptoProvider,
│       │                              #     HTTPClient, RandomBytesGenerator, Logger
│       ├── YoruMimizukuKit/            # PURE view models. replace `os` with a Logger abstraction
│       ├── PlatformApple/             #   Keychain / os.signpost logger. files gated #if os(macOS)
│       ├── PlatformWindows/           #   Credential Manager (DPAPI) / BCryptGenRandom / logger.
│       │                              #     files gated #if os(Windows) (import WinSDK)
│       └── YoruMimizukuBridge/         # NEW: C ABI surface (@_cdecl). Windows DLL entry points.
│                                      #   The C# P/Invoke boundary. unsafe is confined here.
├── apps/
│   ├── macos/                         # move current app/YoruMimizuku here (SwiftUI + project.yml)
│   └── windows/                       # NEW: C#/.NET solution
│       ├── YoruMimizuku.Windows.sln
│       ├── App/                       #   WinUI 3 (XAML + C# view models)
│       └── Interop/                   #   DllImport wrappers (C# bindings for the Swift DLL)
├── docs/  design/                     # unchanged
```

Key relationships:

- **`YoruMimizukuBridge` (new)** is the core of this change. It collects `@_cdecl`
  functions and, on Windows, builds `YoruMimizuku.dll` via `-emit-library`. macOS
  does not use it (the macOS app imports `YoruMimizukuKit` directly) — an
  intentionally asymmetric setup. Keeping the bridge as its own target confines
  `unsafe` pointer work and C-string management to one layer.
- **`apps/windows/Interop/`** is the C# mirror image: it holds the
  `DllImport` declarations and the JSON ↔ C# model deserialization, nothing more.
  The WinUI XAML / view models only touch `Interop`.
- **crypto / HTTP need no OS split** (swift-crypto + the `FoundationNetworking`
  guard cover both). The only truly per-OS code is the Keychain-equivalent secure
  storage and the logger in `PlatformApple` / `PlatformWindows`.

## Migration Order (non-destructive, Tidy First)

To converge on this structure without breaking the macOS build, the order
matters. Each step is a structural-only change that keeps `cd core && swift test`
(currently `cd BlueskyCore && swift test`) green.

1. Abstract the `os` dependency behind a `Logger` protocol, purifying
   `YoruMimizukuKit`. Move the macOS implementation into `PlatformApple`.
2. Swap `CryptoKit` for `swift-crypto` (`import Crypto`) and add the
   `#if canImport(FoundationNetworking)` guard to the URLSession HTTP client.
   Update the test files that import CryptoKit directly
   (`CryptoKitDPoPProviderTests`, `DPoPProofIntegrationTests`) in the same step.
   The core is now theoretically *compilable* on Windows — note that this guard
   only fixes compilation, not runtime behavior (see Open Questions for the
   URLSession-on-Windows spike).
3. Move Apple concrete implementations (Keychain, etc.) out of `Platform/` into
   the `core/Sources/PlatformApple` target, and collect protocols into `Ports/`.
   The tests that
   exercise these concrete adapters (`CryptoKitDPoPProviderTests`,
   `URLSessionHTTPClientTests`, `RandomBytesGeneratorTests`) must move alongside
   them, or `BlueskyCoreTests` must gain a dependency on `PlatformApple`. This is
   a test-target reorganization, not just a source move — account for it so the
   "structural-only, stays green" property actually holds.
4. Confirm macOS behaves identically via the test suite (structural change only,
   behavior unchanged).
5. Add `YoruMimizukuBridge`, `core/Sources/PlatformWindows`, and `apps/windows` as
   new additions.

Each step is committable as a structural-only change, keeping the build green
throughout.

## Open Questions

- Exact async surface over the C ABI (callback function pointer vs. pollable
  handle) — to be decided when `YoruMimizukuBridge` is implemented.
- ~~Single SPM package vs. split packages.~~ **Decided: single package (Option
  A).** The platform adapters live as targets under `core/Sources/`, gated with
  `#if os(...)`. Rationale: BlueskyCore purity is already enforced by the target
  dependency graph, the `#if os(...)` gating is required either way, and one
  `swift test` / one manifest matches the TDD workflow. Splitting `platform/`
  into its own SPM package becomes worthwhile only if it grows large, needs
  independent versioning, or `BlueskyCore` is published standalone — a cheap
  structural refactor to do later. (Note: a separate `platform/` *directory*
  sibling to `core/` was rejected because SPM cannot declare a target whose
  sources live outside the package root, `../platform/...`.)
- URLSession on Windows: the `FoundationNetworking` guard only guarantees
  compilation. swift-corelibs-foundation's URLSession (incl. the async
  `data(for:)` API) has historically been less mature on Windows. Run a runtime
  connectivity spike before relying on `URLSessionHTTPClient` as the Windows HTTP
  stack; have a fallback (e.g. an `HTTPClient` adapter over WinHTTP/libcurl) in
  mind if it does not work end-to-end.
- Build/packaging pipeline for the Windows DLL + C# solution (out of scope for
  this memo).
