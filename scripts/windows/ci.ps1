<#
.SYNOPSIS
    Windows CI entry point: build and test the Swift core, then build the WinUI app.

.DESCRIPTION
    Runs the same checks a Windows CI job should run:
      1. swift build / swift test (core package)
      2. stage the bridge DLL
      3. dotnet build (WinUI app)
    Intended to be invoked from any CI runner with the Swift toolchain, .NET 8
    SDK, and the WinUI/Windows App SDK workload installed.
#>

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

Write-Host "== Swift core: build + test =="
& (Join-Path $PSScriptRoot "test.ps1")
if ($LASTEXITCODE -ne 0) { throw "swift test failed" }

Write-Host "== Stage bridge DLL =="
& (Join-Path $PSScriptRoot "stage-bridge.ps1")
if ($LASTEXITCODE -ne 0) { throw "stage-bridge failed" }

Write-Host "== WinUI app: dotnet build =="
$solution = Join-Path $repoRoot "apps\windows\YoruMimizuku.Windows.sln"
dotnet build $solution -c Debug
if ($LASTEXITCODE -ne 0) { throw "dotnet build failed" }

Write-Host "CI checks passed."
