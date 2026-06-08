# YoruMimizuku (夜ミミズク)

A native desktop client for [Bluesky](https://bsky.app) / the [AT Protocol](https://atproto.com).

YoruMimizuku is a single-column client in the spirit of Yorufukurou: one column with
top tabs for switching between timelines. It is written in Swift with SwiftUI and
deliberately avoids Electron, aiming for a small, memory-efficient native footprint.

## Why this exists

This is a personal, experimental project with two motivations behind it.

- **Experimenting with atproto OAuth.** The main reason it was built. Bluesky's OAuth is
  unusual: there is no client registration step and no client secret. The `client_id` is
  itself the HTTPS URL of a public *client metadata document*
  (`docs/client-metadata.json`, published at `https://ason.as/yorumimizuku/client-metadata.json`),
  and the app authenticates as a public client using PKCE + DPoP. Implementing that flow
  end to end was the thing I wanted to try.
- **Wanting to use Swift on Windows.** I wanted an excuse to try Swift outside of Apple's
  platforms. That goal shaped the architecture: all the protocol logic lives in a
  platform-independent core (`BlueskyCore`) with no direct Apple-framework dependencies, so
  it can eventually be shared with other platforms.

## Status

- **Bluesky (AT Protocol) is supported today.** Login (OAuth), timelines, posting,
  notifications, conversations, and image attachments work.
- **macOS and Windows are both supported.** macOS is a SwiftUI app; Windows is a
  WinUI 3 (C#/.NET 8) app that reuses the same Swift core through a C ABI DLL bridge
  (see `apps/windows`). The Windows app builds, runs self-contained, and signs in via
  OAuth end to end. iOS and Android are in view but not yet built.

This is early, evolving software. Expect rough edges.

## Architecture

The code is split into three layers so the core stays portable:

- **`BlueskyCore`** — platform-independent core: networking, OAuth (PKCE + DPoP), XRPC, and
  token management. No direct Apple-framework dependencies, so it can be reused on other
  platforms.
- **`YoruMimizukuKit`** — view models and display logic, depending on `BlueskyCore`.
- **`PlatformApple` / `PlatformWindows`** — the OS-specific adapters (secure storage,
  random bytes, logging) behind the core's port protocols: Keychain / `SecRandom` /
  `os.signpost` on Apple, DPAPI / `BCryptGenRandom` on Windows.
- **`apps/macos`** — the macOS app: SwiftUI views and the Apple-specific wiring (Keychain,
  `ASWebAuthenticationSession`, and so on).
- **`apps/windows`** — the Windows app: a WinUI 3 (C#/.NET 8) front end that calls the Swift
  core through the `YoruMimizukuBridge` C ABI DLL via P/Invoke. OAuth uses an embedded
  WebView2.

The same author's Ruby terminal client [tempest](https://github.com/asonas/tempest) served
as the reference implementation; this is a fresh Swift implementation rather than a port.

## Building

The project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) and
[mise](https://mise.jdx.dev/). `YoruMimizuku.xcodeproj` and `apps/macos/Info.plist` are
generated artifacts and are gitignored, so generate them first.

```bash
# Install tools and generate the Xcode project from project.yml
mise install
mise run generate

# Open in Xcode
open YoruMimizuku.xcodeproj
```

Re-run `mise run generate` (or `xcodegen generate`) after editing `project.yml`.

### Windows

The Windows app is built with the Swift toolchain for Windows plus the .NET 8 SDK and a
Visual Studio C++ workload. Helper scripts live in `scripts/windows`:

```powershell
# Build the Swift core bridge DLL and stage it (+ Swift runtime) into the app
scripts\windows\stage-bridge.ps1

# Build the WinUI app (framework-dependent: needs the .NET 10 + Windows App SDK runtimes installed)
dotnet build apps\windows\YoruMimizuku.Windows.sln -c Debug
# -> App\bin\x64\Debug\net10.0-windows10.0.19041.0\win-x64\YoruMimizuku.App.exe
```

See [`apps/windows/README.md`](apps/windows/README.md) for details. `scripts\windows\ci.ps1`
runs the full chain (core `swift build`/`swift test`, stage, then `dotnet build`).

### Tests

```bash
# Test the platform-independent core (fast)
cd core && swift test

# Build / test including the macOS app
xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj
xcodebuild test  -scheme YoruMimizuku -project YoruMimizuku.xcodeproj -destination 'platform=macOS'
```

### Release

The release tasks build, sign, notarize, and package a distributable DMG.

```bash
mise run setup-notary   # one-time: store notarytool credentials in the keychain
mise run bump 0.2.0     # set MARKETING_VERSION and bump the build number
mise run release        # -> build/YoruMimizuku.dmg (signed + notarized)
```

Distribution requires an Apple Developer ID; forks must set their own `DEVELOPMENT_TEAM` in
`project.yml`.

## License

YoruMimizuku is released under the [MIT License](LICENSE).

It depends on [swift-crypto](https://github.com/apple/swift-crypto) and
[swift-asn1](https://github.com/apple/swift-asn1), both licensed under Apache License 2.0,
which is compatible with MIT. When redistributing a built binary, retain their license and
NOTICE files as Apache 2.0 requires.
