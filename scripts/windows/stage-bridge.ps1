<#
.SYNOPSIS
    Build YoruMimizukuBridge.dll and stage it (with the Swift runtime DLLs) into
    the WinUI app's native/ folder so the C# project can run against it.

.DESCRIPTION
    The WinUI app loads YoruMimizukuBridge.dll via P/Invoke. That DLL depends on
    the Swift runtime redistributable DLLs (swiftCore.dll, Foundation.dll, etc.),
    which must sit next to it. This script builds the bridge, then copies it plus
    the Swift runtime into apps/windows/App/native.

.EXAMPLE
    scripts\windows\stage-bridge.ps1
    scripts\windows\stage-bridge.ps1 -Configuration release
#>

param(
    [ValidateSet("debug", "release")]
    [string]$Configuration = "debug"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

. (Join-Path $PSScriptRoot "Enter-SwiftEnv.ps1")
$ErrorActionPreference = "Continue"

$corePath = Join-Path $repoRoot "core"
Push-Location $corePath
try {
    $buildArgs = @("build", "--product", "YoruMimizukuBridge")
    if ($Configuration -eq "release") { $buildArgs += @("-c", "release") }
    swift @buildArgs
    if ($LASTEXITCODE -ne 0) { throw "swift build failed (exit $LASTEXITCODE)" }
} finally {
    Pop-Location
}

$buildDir = Join-Path $corePath ".build\x86_64-unknown-windows-msvc\$Configuration"
$bridgeDll = Join-Path $buildDir "YoruMimizukuBridge.dll"
if (-not (Test-Path $bridgeDll)) { throw "bridge DLL not found at $bridgeDll" }

$nativeDir = Join-Path $repoRoot "apps\windows\App\native"
New-Item -ItemType Directory -Force -Path $nativeDir | Out-Null

Copy-Item $bridgeDll -Destination $nativeDir -Force
# Any sibling Swift DLLs the bridge links (BlueskyCore etc. are statically linked,
# but copy any produced *.dll just in case).
Get-ChildItem $buildDir -Filter *.dll | ForEach-Object { Copy-Item $_.FullName -Destination $nativeDir -Force }

# Swift runtime redistributable DLLs.
$swiftRoot = Join-Path $env:LOCALAPPDATA "Programs\Swift"
$runtime = Get-ChildItem (Join-Path $swiftRoot "Runtimes") -Directory |
    Sort-Object Name | Select-Object -Last 1
if ($runtime) {
    $runtimeBin = Join-Path $runtime.FullName "usr\bin"
    Get-ChildItem $runtimeBin -Filter *.dll | ForEach-Object {
        Copy-Item $_.FullName -Destination $nativeDir -Force
    }
}

Write-Host "Staged bridge + Swift runtime into $nativeDir"
