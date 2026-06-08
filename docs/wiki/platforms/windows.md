---
title: Platform — Windows
type: platform
updated: 2026-06-08
sources:
  - docs/superpowers/specs/2026-06-05-windows-multiplatform-structure.md
  - apps/windows/README.md
  - core/Package.swift
  - apps/windows/App/Services/RelativeTime.cs
  - apps/windows/App/ViewModels/ComposerViewModel.cs
  - apps/windows/App/Views/ComposerDialog.xaml
  - apps/windows/App/Views/ComposerDialog.xaml.cs
  - apps/windows/App/ViewModels/SavedFilterModel.cs
  - apps/windows/App/ViewModels/WorkspaceViewModel.cs
  - apps/windows/App/ViewModels/AuthorViewModel.cs
  - apps/windows/App/ViewModels/NotificationsViewModel.cs
  - apps/windows/App/Views/AuthorView.xaml.cs
  - apps/windows/App/Views/FilterEditorDialog.xaml.cs
  - apps/windows/App/Views/FeedView.xaml.cs
  - apps/windows/App/Views/ConversationView.xaml.cs
  - apps/windows/App/MainWindow.xaml.cs
  - scripts/windows/build-app.ps1
  - scripts/windows/release.ps1
  - README.md
---

# Platform — Windows

Status: **implemented and running**. The Swift core builds and tests on Windows,
a C ABI bridge (`YoruMimizukuBridge.dll`) exposes it, and a WinUI 3 (C#/.NET 8)
app drives the UI. The app runs self-contained and signs in via OAuth end to end
(`2026-06-05-windows-multiplatform-structure.md`, `apps/windows/README.md`).

This page matters for cross-machine context: the Windows build runs on a
different machine / agent, so it reconstructs the same picture from this wiki.

## Architecture (as built)

Swift core shared across platforms, with a **C#/WinUI 3 frontend calling the Swift
core through a C ABI (cdecl) DLL** via P/Invoke. The pure logic and all mapping
(`PostDisplay`, `NotificationGroup`, `RichText`, filter subqueries) stay in
`BlueskyCore` / `YoruMimizukuKit`; C# is a thin MVVM + XAML layer ([[overview]]).

```
core/Sources/
├── PlatformWindows/       # DPAPI SecureStorage + BCryptGenRandom, #if canImport(WinSDK)
└── YoruMimizukuBridge/    # C ABI (@_cdecl) surface, built as a dynamic library (DLL)
apps/windows/App
├── Interop/         P/Invoke (NativeMethods), JSON facade (BridgeClient), DTOs
├── Mvvm/            ObservableObject + AsyncRelayCommand
├── ViewModels/      Login / Timeline / Thread / Notifications / Composer / Workspace / SavedFilter
├── Views/           XAML: Login (WebView2 OAuth), Feed, Notifications, Conversation, Composer, Settings
├── Services/        AppSettings, ThemeService (randoma11y), RelativeTime, AppIcon
└── MainWindow       NavigationView shell, tab cycling (Ctrl+Shift+J/K), login gate
```

## PlatformWindows (OS adapters)

The Apple-only ports get Windows equivalents under `core/Sources/PlatformWindows`
(gated `#if canImport(WinSDK)`), covered by a `PlatformWindowsTests` target:

- **Secure storage**: `DPAPISecureStorage` — `CryptProtectData` / `CryptUnprotectData`
  (per-user) persisting each value as an encrypted file under Application Support.
  DPAPI rather than Credential Manager because the account blob (OAuth tokens + the
  DPoP key) exceeds the Credential Manager per-item size limit. This is what makes
  login survive a relaunch ([[oauth-flow]]).
- **Random bytes**: `BCryptRandomBytesGenerator` — `BCryptGenRandom`.
- Linked Win32 libs: `bcrypt`, `crypt32` (see `core/Package.swift`).

Crypto and HTTP need no OS split: `CryptoKitDPoPProvider` uses `import Crypto`
(swift-crypto, `from: 3.0.0` in `core/Package.swift`, with an `@unchecked Sendable`
wrapper since swift-crypto's P256 key is not `Sendable` off Apple), and
`URLSessionHTTPClient` carries the `#if canImport(FoundationNetworking)` guard.
Both concretes live in `BlueskyCore/Adapters`.

## YoruMimizukuBridge (C ABI)

A dynamic-library target (`Bridge.swift`, `BridgeOperations.swift`, `CABI.swift`)
whose `@_cdecl("yoru_…")` functions are the P/Invoke boundary, all guarded
`#if canImport(WinSDK)` (macOS bypasses the bridge). `unsafe` pointer / C-string
lifetime handling is confined here.

- Every entry point takes one UTF-8 JSON request string and returns a newly
  allocated UTF-8 JSON response (`{ "ok": true, "data": … }` or
  `{ "ok": false, "error": … }`) the caller frees with `yoru_free`.
- Async work is bridged to a synchronous return with a semaphore; the C# side
  calls each function on a background thread (`Task.Run`), so the UI never blocks.
- **Date convention (gotcha):** request JSON is decoded with the default
  `JSONDecoder` (`deferredToDate`), while response DTOs serialize dates as ISO8601
  strings by hand. So the C# side must **not** send ISO8601 `Date` fields in a
  request — they fail to decode and error the whole call. (This was the cause of
  saved-filter searches silently returning nothing: C# was sending `createdAt`;
  it now omits it.)
- `yoru_init` builds the session (PlatformWindows adapters + `URLSessionHTTPClient`
  + swift-crypto DPoP + `AccountManager`). Endpoints mirror the macOS `Live*`
  layer: `yoru_login_begin` / `yoru_login_complete` (split for WebView2),
  `yoru_account_current/list/switch/remove`, `yoru_timeline_load`,
  `yoru_author_feed_load`, `yoru_thread_load`, `yoru_notifications_load`,
  `yoru_search_load`, `yoru_post_create`, `yoru_post_like/unlike/repost/unrepost`,
  `yoru_post_permalink`, `yoru_profile_avatar`, `yoru_profile_load`.

## apps/windows (WinUI 3)

- `Interop/`: `NativeMethods` (`DllImport`), `BridgeClient` (JSON facade + Task
  wrappers), and DTOs mirroring the bridge payloads. The rest of the app only
  touches `Interop`.
- C# MVVM view models mirror `YoruMimizukuKit`: Timeline / Thread / Notifications /
  Login / Composer / Workspace / SavedFilter (+ `PostItem` with optimistic like/repost).
- Views: WebView2 OAuth login, a feed (facet-aware rich text, image grid + lightbox,
  relative timestamps, like/repost/reply icons, infinite scroll, 30s refresh, j/k,
  n-to-compose, per-post separators), conversation (ancestor + re-anchor),
  notifications, composer, settings; a cmux-style `NavigationView` vertical-tab
  shell with `Ctrl+Shift+J/K` cycling, closable tabs, and an account footer.
- The composer can post text, replies, quotes, and up to 4 PNG/JPEG image
  attachments through `yoru_post_create`. It serializes `dataBase64`, `mimeType`,
  and `alt`, but the visible dialog currently exposes only file picking and
  thumbnails; no alt-text editor, drag/drop attach, WIC downsampling, or upload
  re-encode UI is present yet ([[compose-post]]).
- Saved-filter tabs call `yoru_search_load` with the structured
  `terms` + `combinator` JSON shape used by the Swift core. The WinUI shell has
  a multi-row AND/OR editor, edit/remove affordances, hashtag-link creation, and
  per-account JSON persistence. OR filters are still limited because the bridge
  merges only the first page of each OR subquery and does not yet return a
  `CompositeCursor` for infinite scroll parity ([[filters]]).
- Author tabs are implemented: avatar taps in feeds and conversations derive the
  actor DID from the post AT-URI, notification actors open by handle, and
  `AuthorView` renders a profile header over a reused feed loaded through
  `yoru_author_feed_load` / `yoru_profile_load` ([[author-tab]]).
- Timeline rows support the Windows parity shortcuts: j/k focus, n compose,
  f toggles like, o opens the focused post's bsky.app permalink, and the link
  action copies that permalink to the clipboard. Conversation focus rows support
  f/o/copy too ([[timeline-streaming]]).
- The notifications navigation row has a local unread badge driven by 30-second
  polling and cleared when the tab becomes active. OS toast notifications and a
  taskbar badge are still not implemented ([[notifications]]).
- The feed's repost button opens a `MenuFlyout` with **リポスト** (toggle) and
  **引用** (quote): choosing 引用 opens `ComposerDialog` with the post's
  `(uri, cid)` as the quote target plus a read-only preview, matching the macOS
  repost/quote popover ([[compose-post]]).
- **OAuth via WebView2** (the Windows counterpart to macOS's
  `ASWebAuthenticationSession`, [[oauth-flow]]): `yoru_login_begin` returns the
  authorize URL, the app loads it in an embedded `WebView2`, intercepts the
  `as.ason:` redirect, and calls `yoru_login_complete` to finish the token
  exchange — no custom URI-scheme registration needed.
- **Relative timestamps** are formatted by `Services/RelativeTime.cs`, deliberately
  mirroring the Swift `RelativeTimeFormatter` ("now" / "30s" / "2m" / "3h" / "2d")
  so the Windows timeline reads like the macOS one ([[timeline-streaming]]). The
  window / taskbar icon is set by `Services/AppIcon.cs` from a bundled `.ico`
  generated off the shared macOS owl icon.
- Theme (randoma11y / monochrome), display density, and font size persist to a JSON
  file (not `ApplicationData.Current`, which is unavailable to an unpackaged app).
- Targets **.NET 10** + **Windows App SDK 2.1.3**, framework-dependent
  (`SelfContained=false` + `WindowsAppSDKSelfContained=false`): the .NET 10 Desktop
  and Windows App SDK runtimes are kept out of the build (the user installs both
  once). On a missing runtime the app prompts on first run — the .NET apphost shows
  a download dialog, and `WindowsAppSDKBootstrapAutoInitializeOptions_OnNoMatch_ShowUI`
  makes the Windows App SDK bootstrapper prompt for the Windows App Runtime. This
  was chosen over self-contained to fit the distribution under the Tangled artifact
  size limit (see Distribution).

## Build (Windows)

Swift toolchain for Windows (`winget install --id Swift.Toolchain`) + .NET 10 SDK +
a Visual Studio C++ workload. Helpers under `scripts/windows/` (`apps/windows/README.md`):

```powershell
scripts\windows\build.ps1            # swift build (core)
scripts\windows\test.ps1             # swift test  (core)
scripts\windows\stage-bridge.ps1     # build the bridge DLL + stage it (+ Swift runtime)
scripts\windows\build-app.ps1        # stop running instance, build framework-dependent x64, print the exe
                                     #   add -StageBridge to rebuild the Swift bridge first (after core/ changes)
scripts\windows\make-appicon.ps1     # regenerate App/Assets/AppIcon.ico from the shared macOS owl PNG
scripts\windows\ci.ps1               # full chain: core build/test -> stage -> dotnet build
```

A `@MainActor` XCTest caveat: swift-corelibs-xctest on Windows cannot invoke a
synchronous `@MainActor` test method, so such tests are marked `async`.

## Distribution

`scripts\windows\release.ps1` publishes the app (**.NET 10** + **Windows App SDK
2.1.3**) **framework-dependent** for `win-x64` (neither the .NET 10 Desktop runtime
nor the Windows App SDK runtime is bundled), lays out a small top-level
`YoruMimizuku.exe` launcher plus an `app/` payload directory (the app, the bridge
DLL, the Swift runtime, and the remaining dependency DLLs), and zips it into
`build/`. It also strips the Windows ML / AI stack that Windows App SDK 2.x bundles
by default (`onnxruntime.dll`, `DirectML.dll`, the `AI.MachineLearning` projection —
~16 MB zipped) since the app uses no ML APIs and there is no supported opt-out
(microsoft/WindowsAppSDK#5969). Dropping the two bundled runtimes plus the ML stack
shrinks the ZIP from ~90 MB (self-contained) to **~40 MB** — chosen specifically so
it fits as a Tangled tag artifact, which is stored as an atproto blob (default PDS
blob limit ~50 MB; a 60 MB self-contained build was rejected). The trade-off is that
the user installs the **.NET 10 Desktop Runtime** and the **Windows App Runtime 2.1**
once (plus the Edge WebView2 runtime for OAuth); the app prompts and links to the
downloads on first run if any is missing. The macOS side ships a
signed + notarized DMG; the Windows analogue is this ZIP today, with MSIX as the
eventual installable form. Code signing is decoupled (optional `-Thumbprint` /
`-CertPath` on `release.ps1`): the launcher + app binaries are signed before
zipping; unsigned builds get a one-time SmartScreen prompt, and Windows has no
free notarization equivalent to macOS — a trusted signature needs a paid (or
free-for-OSS) Authenticode cert, deferred for now.

## Resolved / open questions

- **URLSession on Windows**: resolved — the app makes real HTTPS calls to bsky.social
  at runtime (login + timeline work), so the WinHTTP/libcurl fallback is not needed.
- **Async surface over the C ABI**: settled on synchronous-blocking entry points
  invoked on a C# background thread (callback pointers were the alternative).
- The single-SPM-package decision held: platform adapters are targets under
  `core/Sources/`, gated `#if os(...)` / `#if canImport(WinSDK)`, and BlueskyCore
  purity is enforced by the target dependency graph.
- **MSIX packaging** for distribution remains future work; development runs unpackaged.
