# YoruMimizuku for Windows (WinUI 3)

A WinUI 3 (C#/.NET 8) front end for YoruMimizuku that reuses the shared Swift
core (`BlueskyCore` + `YoruMimizukuKit`) through a C ABI DLL bridge
(`YoruMimizukuBridge.dll`), called via P/Invoke with UTF-8 JSON.

## Architecture

```
apps/windows/App
├── Interop/         P/Invoke (NativeMethods), JSON facade (BridgeClient), DTOs
├── Mvvm/            ObservableObject + AsyncRelayCommand
├── ViewModels/      Login / Timeline / Thread / Notifications / Composer / Workspace / SavedFilter
├── Views/           XAML: Login (WebView2 OAuth), Feed, Notifications, Conversation, Composer, Settings
├── Services/        AppSettings, ThemeService (randoma11y)
├── App.xaml(.cs)    Initializes the bridge (yoru_init) at launch
└── MainWindow       NavigationView shell, tab cycling (Ctrl+Shift+J/K), login gate
```

The Swift core is platform-independent and already builds and tests on Windows.
Windows OS touchpoints live in `core/Sources/PlatformWindows` (DPAPI secure
storage, `BCryptGenRandom`). The bridge entry points are in
`core/Sources/YoruMimizukuBridge`.

## Prerequisites

- Swift toolchain for Windows: `winget install --id Swift.Toolchain`
- .NET 10 SDK: `winget install --id Microsoft.DotNet.SDK.10`
- Visual Studio 2022 (or Build Tools) with the C++ workload and the
  Windows App SDK / WinUI 3 component (`dotnet workload install` is handled by VS).
- Microsoft Edge WebView2 Runtime (preinstalled on current Windows 11).

## Build & run

```powershell
# 1. Build the Swift core bridge DLL and stage it (+ Swift runtime) into App/native
scripts\windows\stage-bridge.ps1

# 2. Build and run the WinUI app
dotnet build apps\windows\YoruMimizuku.Windows.sln -c Debug
# Framework-dependent output lands under a win-x64 subfolder:
.\App\bin\x64\Debug\net10.0-windows10.0.19041.0\win-x64\YoruMimizuku.App.exe
```

`scripts\windows\ci.ps1` runs the full chain (core build/test + stage + dotnet build).

The project targets **.NET 10** + **Windows App SDK 2.1.3** and is configured
**framework-dependent** (`SelfContained=false` + `WindowsAppSDKSelfContained=false`):
the .NET 10 Desktop runtime and the Windows App SDK runtime are **not** bundled,
so both must be installed on the machine.
On a developer machine they already are. If a runtime is missing at launch the
app prompts: the .NET apphost shows a download dialog, and the Windows App SDK
bootstrapper prompts for the Windows App Runtime
(`WindowsAppSDKBootstrapAutoInitializeOptions_OnNoMatch_ShowUI`).
Startup/runtime errors are written to `%LOCALAPPDATA%\YoruMimizuku\app.log`.

## Distribution

`scripts\windows\release.ps1` produces a distributable **ZIP** under `build/`.
It publishes the app framework-dependent (neither the .NET nor the Windows App
SDK runtime is bundled), lays out a small top-level `YoruMimizuku.exe` launcher
plus an `app/` payload directory (the app, the bridge DLL, the Swift runtime,
and the remaining dependency DLLs), and zips it:

```powershell
scripts\windows\release.ps1 -Version 0.5.0
# add -StageBridge to rebuild the Swift bridge (release) first, after core/ changes
# -> build\YoruMimizuku-win-x64-0.5.0.zip   (~40 MB)
```

For WinSparkle auto-updates, build an installer EXE in addition to the ZIP:

```powershell
scripts\windows\release.ps1 -Version 0.7.1 -Installer
# -> build\YoruMimizuku-win-x64-0.7.1-Setup.exe

# When the Windows WinSparkle EdDSA private key is available, also generate the
# GitHub Pages appcast for the installer enclosure.
scripts\windows\release.ps1 -Version 0.7.1 -Installer `
  -WinSparklePrivateKey C:\path\to\winsparkle-private.key `
  -Channel stable
# -> build\appcast-windows.xml
```

The app contains WinSparkle wiring and an Update section in Settings. It remains
disabled until the Windows EdDSA public key placeholder in `UpdateService` is
replaced and a signed installer appcast is published.

Dropping the two bundled runtimes shrinks the ZIP from ~90 MB (self-contained) to
**~40 MB** — small enough to upload as a Tangled tag artifact, which is stored as
an atproto blob (~50 MB limit on a default PDS). The release script also strips the
Windows ML / AI stack that Windows App SDK 2.x bundles by default (`onnxruntime.dll`,
`DirectML.dll`, the `AI.MachineLearning` projection — ~16 MB zipped) since this app
uses no ML APIs and there is no supported project-level opt-out
([microsoft/WindowsAppSDK#5969](https://github.com/microsoft/WindowsAppSDK/issues/5969)).

Runtime prerequisites the user installs once (the app prompts and links to the
download on first run if missing):

- **.NET 10 Desktop Runtime** (x64)
- **Windows App Runtime 2.1** (the channel the app is built against)
- **Edge WebView2 runtime** (preinstalled on Windows 11 and most Windows 10), for OAuth sign-in

Code signing is **optional and decoupled** so it can be added later without
changing anything else: pass `-Thumbprint <sha1>` (a cert in the store) or
`-CertPath <pfx> -CertPassword <pw>` and the launcher + app binaries are
Authenticode-signed before zipping. With no cert the ZIP is unsigned and Windows
shows a one-time SmartScreen "more info -> run". (Windows has no free notarization
equivalent to macOS; a publicly trusted signature needs a paid/again-free-for-OSS
cert.)

## OAuth

Login uses the spec's WebView2 flow: `yoru_login_begin` returns the authorization
URL, the app loads it in an embedded `WebView2`, intercepts the redirect to the
`as.ason:` callback scheme, and calls `yoru_login_complete` to finish the token
exchange. No custom protocol registration is required.

## Status / remaining work

Implemented and verified (Swift side): the C ABI bridge, `PlatformWindows`
adapters (unit-tested), and the core build/test on Windows.

The WinUI front end is wired end-to-end (bridge -> view models -> XAML) for the
core surfaces: login, home timeline (infinite scroll, 30s refresh, j/k, like /
repost, n-to-compose), conversation (ancestor + re-anchor), notifications,
composer (text + images + reply/quote), saved-filter tabs, and settings
(density / randoma11y theme / font size).

Refinements still open (parity polish): rich-text segment rendering (links /
hashtags / mentions as tappable runs incl. hashtag-to-filter), inline image
grid + lightbox with arrow-key navigation, drag-and-drop image attach, WIC
image downsampling and upload re-encode, account switcher UI, font-family
enumeration, and MSIX packaging. These are scoped in `plan.md` / the spec.
