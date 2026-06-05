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
- .NET 8 SDK: `winget install --id Microsoft.DotNet.SDK.8`
- Visual Studio 2022 (or Build Tools) with the C++ workload and the
  Windows App SDK / WinUI 3 component (`dotnet workload install` is handled by VS).
- Microsoft Edge WebView2 Runtime (preinstalled on current Windows 11).

## Build & run

```powershell
# 1. Build the Swift core bridge DLL and stage it (+ Swift runtime) into App/native
scripts\windows\stage-bridge.ps1

# 2. Build and run the WinUI app
dotnet build apps\windows\YoruMimizuku.Windows.sln -c Debug
# Self-contained output lands under a win-x64 subfolder:
.\App\bin\x64\Debug\net8.0-windows10.0.19041.0\win-x64\YoruMimizuku.App.exe
```

`scripts\windows\ci.ps1` runs the full chain (core build/test + stage + dotnet build).

The project is configured **self-contained** (`SelfContained` +
`WindowsAppSDKSelfContained`): the .NET runtime and the Windows App SDK 1.5
runtime are bundled in the output, so the app runs without separately installing
the Windows App Runtime. Startup/runtime errors are written to
`%LOCALAPPDATA%\YoruMimizuku\app.log`.

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
