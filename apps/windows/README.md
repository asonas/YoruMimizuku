# YoruMimizuku for Windows (WinUI 3)

A WinUI 3 (C#/.NET 10) app for YoruMimizuku with its own C# core: a port of the
Swift `BlueskyCore` and `YoruMimizukuKit` logic the macOS app uses
(`docs/superpowers/specs/2026-11-21-windows-csharp-core-handoff.md`). Everything
is managed code; no Swift toolchain or native bridge DLL is involved.

## Architecture

```
apps/windows
├── Core/            YoruMimizuku.Core: XRPC client and models, OAuth (PKCE + PAR + DPoP),
│                    accounts (DPAPI storage, token refresh), feed / notification / search /
│                    post / profile services, display mapping, FeedThreading, OGP
├── Core.Tests/      xUnit tests for Core, translated from the Swift core's tests
├── Interop/         YoruMimizuku.App.Interop: CoreClient (ICoreClient) and
│                    CoreAccountClient (IAccountClient), mapping Core's models to the DTOs
│                    the view models consume; CoreException for failures
├── Interop.Tests/   xUnit tests for the client layer and the DTO mapping
└── App/             The WinUI app
    ├── Interop/         WinSparkle P/Invoke (WinSparkleNative)
    ├── Mvvm/            ObservableObject + AsyncRelayCommand
    ├── ViewModels/      Login / Timeline / Thread / Notifications / Composer / Workspace / SavedFilter
    ├── Views/           XAML: Login (WebView2 OAuth), Feed, Notifications, Conversation, Composer, Settings
    ├── Services/        AppSettings, ThemeService (randoma11y), UpdateService, ...
    ├── App.xaml(.cs)    Creates the CoreClient every window shares
    └── MainWindow       NavigationView shell, tab cycling (Ctrl+Shift+J/K), login gate
```

Each window holds an `IAccountClient` for its own account, so its reads and writes
never follow another window's account switch.

Accounts are stored with DPAPI in `%LOCALAPPDATA%\YoruMimizuku\accounts`. Builds
before the C# core kept accounts in `%LOCALAPPDATA%\as.ason.YoruMimizuku\secure`,
which this app never reads: at launch it deletes that store if one is there, and
when an account was signed in to it, tells the user once to sign in again.

## Prerequisites

- .NET 10 SDK: `winget install --id Microsoft.DotNet.SDK.10`
- Visual Studio 2022 (or Build Tools) with the Windows App SDK / WinUI 3 component,
  plus the C++ workload for `release.ps1`, which compiles the launcher with `cl.exe`.
- Microsoft Edge WebView2 Runtime (preinstalled on current Windows 11).
- For `release.ps1 -Installer` only: Inno Setup 6.

## Build & run

```powershell
dotnet build apps\windows\YoruMimizuku.Windows.sln -c Debug -p:Platform=x64
# Framework-dependent output lands under a win-x64 subfolder:
.\apps\windows\App\bin\x64\Debug\net10.0-windows10.0.19041.0\win-x64\YoruMimizuku.App.exe
```

`scripts\windows\build-app.ps1` stops a running instance, builds, and prints the
exe path.

## Test

```powershell
dotnet test apps\windows\Core.Tests\YoruMimizuku.Core.Tests.csproj
dotnet test apps\windows\Interop.Tests\YoruMimizuku.App.Interop.Tests.csproj
```

`scripts\windows\test.ps1` runs both (extra arguments such as `--filter` go to
each run), and `scripts\windows\ci.ps1` runs the tests and then the Debug build.

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
plus an `app/` payload directory (`YoruMimizuku.App.exe`, `YoruMimizuku.Core.dll`,
`YoruMimizuku.App.Interop.dll` and the remaining dependency DLLs), and zips it:

```powershell
scripts\windows\release.ps1 -Version 0.5.0
# -> build\YoruMimizuku-win-x64-0.5.0.zip   (~12 MB)
```

It deletes `App\bin\x64\Release` before publishing, because `dotnet publish` keeps
files from an earlier publish (for example the Swift DLLs of builds before the C#
core).

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

Not bundling the two runtimes keeps the ZIP near **12 MB** — small enough to upload
as a Tangled tag artifact, which is stored as an atproto blob (~50 MB limit on a
default PDS). The release script also strips the
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

Login uses the spec's WebView2 flow: `ICoreClient.LoginBeginAsync` returns the
authorization URL, the app loads it in an embedded `WebView2`, intercepts the
redirect to the `as.ason:` callback scheme, and calls `LoginCompleteAsync` to
finish the token exchange. No custom protocol registration is required.

## Status / remaining work

The WinUI front end is wired end-to-end (C# core -> view models -> XAML) for the
core surfaces: login, home timeline (infinite scroll, 30s refresh, j/k, like /
repost, n-to-compose), conversation (ancestor + re-anchor), notifications,
composer (text + images + reply/quote), saved-filter tabs, and settings
(density / randoma11y theme / font size).

Refinements still open (parity polish): rich-text segment rendering (links /
hashtags / mentions as tappable runs incl. hashtag-to-filter), inline image
grid + lightbox with arrow-key navigation, drag-and-drop image attach, WIC
image downsampling and upload re-encode, account switcher UI, font-family
enumeration, and MSIX packaging. These are scoped in `plan.md` / the spec.
