<#
.SYNOPSIS
    Prepare the current PowerShell session to build the Swift core on Windows.

.DESCRIPTION
    The Swift toolchain on Windows needs two things that are not configured by
    default:
      1. The MSVC developer environment (so `link.exe`, INCLUDE, LIB are set).
      2. SDKROOT pointing at the bundled Windows Swift SDK (so the standard
         library for x86_64-unknown-windows-msvc can be loaded).

    Dot-source this script to apply the environment to the current session:
        . scripts\windows\Enter-SwiftEnv.ps1

    It auto-detects the Visual Studio install (via vswhere) and the latest
    installed Swift toolchain under %LOCALAPPDATA%\Programs\Swift.
#>

$ErrorActionPreference = "Stop"

function Find-VisualStudio {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) {
        throw "vswhere.exe not found at $vswhere. Is Visual Studio (or Build Tools) installed?"
    }
    $path = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath
    if (-not $path) {
        throw "No Visual Studio instance with the MSVC C++ tools (VC.Tools.x86.x64) was found."
    }
    return $path.Trim()
}

function Find-SwiftRoot {
    $root = Join-Path $env:LOCALAPPDATA "Programs\Swift"
    if (-not (Test-Path $root)) {
        throw "Swift install not found at $root. Install with: winget install --id Swift.Toolchain"
    }
    return $root
}

function Get-LatestChild {
    param([string]$Path)
    Get-ChildItem $Path -Directory |
        Sort-Object { try { [version](($_.Name -split '\+')[0]) } catch { [version]"0.0.0" } } |
        Select-Object -Last 1
}

$vsPath = Find-VisualStudio
$devShell = Join-Path $vsPath "Common7\Tools\Launch-VsDevShell.ps1"
if (-not (Test-Path $devShell)) {
    throw "Launch-VsDevShell.ps1 not found at $devShell."
}
& $devShell -Arch amd64 -HostArch amd64 -SkipAutomaticLocation | Out-Null

$swiftRoot = Find-SwiftRoot
$toolchain = Get-LatestChild (Join-Path $swiftRoot "Toolchains")
$runtime   = Get-LatestChild (Join-Path $swiftRoot "Runtimes")
$platform  = Get-LatestChild (Join-Path $swiftRoot "Platforms")

$toolchainBin = Join-Path $toolchain.FullName "usr\bin"
$runtimeBin   = Join-Path $runtime.FullName "usr\bin"
$sdk          = Join-Path $platform.FullName "Windows.platform\Developer\SDKs\Windows.sdk"
if (-not (Test-Path $sdk)) {
    throw "Windows Swift SDK not found at $sdk."
}

$env:Path = "$toolchainBin;$runtimeBin;$env:Path"
$env:SDKROOT = $sdk

# Restore a non-fatal error preference so that swift writing progress/warnings to
# stderr does not abort the caller's pipeline (this script is meant to be
# dot-sourced before running `swift build` / `swift test`).
$ErrorActionPreference = "Continue"

Write-Host "Swift environment ready."
Write-Host "  Visual Studio : $vsPath"
Write-Host "  Toolchain     : $($toolchain.Name)"
Write-Host "  SDKROOT       : $env:SDKROOT"
