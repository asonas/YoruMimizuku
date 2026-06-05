# Windows Build Notes

Spec: `docs/superpowers/specs/2026-06-05-windows-multiplatform-structure.md`

The multi-platform migration of the Swift core (compile on Windows, swift-crypto
for DPoP, `PlatformApple` target for Apple-only adapters, a `SignpostTracing`
port for `os` signposts) has landed on `main`. The Swift core under `core/`
builds and tests on Windows.

## Building / testing the core on Windows

The Swift toolchain on Windows needs the MSVC developer environment and an
`SDKROOT` pointing at the bundled Windows SDK. The helper scripts configure both:

- `scripts/windows/Enter-SwiftEnv.ps1` - dot-source to set up the environment.
- `scripts/windows/build.ps1` - build the `core/` package (`swift build`).
- `scripts/windows/test.ps1` - run the `core/` test suite (`swift test`).

```powershell
# one-off build / test
scripts\windows\build.ps1
scripts\windows\test.ps1
```

Prerequisites (install once):

- `winget install --id Swift.Toolchain`
- `winget install --id Microsoft.DotNet.SDK.8` (for the future WinUI front end)
- Visual Studio (or Build Tools) with the MSVC C++ workload.

## Remaining Windows work (per the spec)

- `HoshidukiyoBridge` C ABI target (`@_cdecl`, `-emit-library`).
- `PlatformWindows` adapters (Credential Manager / `BCryptGenRandom` / logger).
- `apps/windows` C#/WinUI 3 solution with the P/Invoke interop layer.
