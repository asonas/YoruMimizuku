---
title: Platform — Windows
type: platform
updated: 2026-06-06
sources:
  - docs/superpowers/specs/2026-06-05-windows-multiplatform-structure.md
  - apps/windows/README.md
  - core/Package.swift
---

# Platform — Windows

Status: **implemented (initial client landed)**. The repo now ships a Windows front end: a **native Swift core shared across platforms, with a C#/WinUI 3 (.NET 8) frontend that calls the Swift core through a C ABI DLL bridge** (`apps/windows/README.md`). This realizes the direction set in `2026-06-05-windows-multiplatform-structure.md`. The Swift core builds and tests on Windows; the macOS build is unaffected ([[macos]]).

This page matters for cross-machine context: the Windows build runs on a different machine / agent, so it reconstructs the same picture from this wiki and the repo.

## Swift core on Windows

The non-UI core runs on Windows:

- **Officially supported toolchain.** `swift build` / `swift test` work directly; Swift 6 strict concurrency carries over unchanged. Install with `winget install --id Swift.Toolchain` (`apps/windows/README.md`).
- **Foundation split absorbed.** Networking uses `FoundationNetworking`, gated by `#if canImport(FoundationNetworking)`.
- **swift-crypto for DPoP.** `Package.swift` depends on `swift-crypto` (`from: 3.0.0`); `import Crypto` is API-compatible with CryptoKit on Apple and works on Windows, so the DPoP provider (P-256 + SHA-256) is a single shared implementation in `BlueskyCore/Adapters` (`core/Package.swift`).
- **Windows secure storage.** `core/Sources/PlatformWindows` provides `DPAPISecureStorage` (DPAPI, the Keychain equivalent) and `BCryptRandomBytesGenerator` (`BCryptGenRandom`) via `import WinSDK`. Covered by a `PlatformWindowsTests` test target.

## C# ↔ Swift bridge (as built)

The Swift core is exposed as a C ABI DLL and called from C# via P/Invoke.

- `core/Sources/YoruMimizukuBridge` is a **dynamic library target** producing `YoruMimizukuBridge.dll`, with `@_cdecl("yoru_...")` entry points (`Bridge.swift`, `BridgeOperations.swift`, `CABI.swift`). It depends on `BlueskyCore`, `YoruMimizukuKit`, and `PlatformWindows`. `unsafe` pointer / C-string lifetime handling is confined here.
- Data crosses the boundary as **UTF-8 JSON `char*`** with a paired free function, avoiding ABI struct-layout mismatches.
- On the C# side, `apps/windows/App/Interop` holds the P/Invoke layer: `NativeMethods` (`DllImport`), `BridgeClient` (the JSON facade), and `Dtos`. The rest of the app only touches `Interop`. `App.xaml.cs` initializes the bridge (`yoru_init`) at launch.

## WinUI 3 app (apps/windows)

A WinUI 3 / C# / .NET 8 app (`apps/windows/YoruMimizuku.Windows.sln`):

```
apps/windows/App
├── Interop/         P/Invoke (NativeMethods), JSON facade (BridgeClient), DTOs
├── Mvvm/            ObservableObject + AsyncRelayCommand
├── ViewModels/      Login / Timeline / Thread / Notifications / Composer / Workspace / SavedFilter
├── Views/           XAML: Login (WebView2 OAuth), Feed, Notifications, Conversation, Composer, Settings
├── Services/        AppSettings, ThemeService (randoma11y)
└── MainWindow       NavigationView shell, tab cycling (Ctrl+Shift+J/K), login gate
```

- **OAuth** runs in a WebView2 control (the Windows counterpart to macOS's `ASWebAuthenticationSession`; [[oauth-flow]]).
- The view-model surface mirrors macOS (timeline / thread / notifications / composer / saved filters), driven through the bridge rather than `YoruMimizukuKit` directly.

## Build & packaging

```powershell
scripts\windows\stage-bridge.ps1        # build the bridge DLL + stage it (with the Swift runtime) into App/native
dotnet build apps\windows\YoruMimizuku.Windows.sln -c Debug
```

`scripts/windows/ci.ps1` runs the Windows CI path. Prerequisites: Swift Windows toolchain, .NET 8 SDK, Visual Studio 2022 (C++ workload + Windows App SDK / WinUI 3), and the Edge WebView2 runtime (`apps/windows/README.md`).

## Notes / remaining work

- The single-SPM-package decision held: platform adapters are targets under `core/Sources/`, gated `#if os(...)`, and BlueskyCore purity is enforced by the target dependency graph.
- The earlier "URLSession on Windows maturity" open question is settled enough that the core builds and tests on Windows; watch for runtime networking edge cases and keep a WinHTTP / libcurl `HTTPClient` adapter in mind as a fallback if they surface.
- Signing / installer packaging for distribution is not covered here.
