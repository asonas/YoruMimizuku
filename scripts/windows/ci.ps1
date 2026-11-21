<#
.SYNOPSIS
    Windows CI entry point: test the C# core, then build the WinUI app.

.DESCRIPTION
    Runs the same checks a Windows CI job should run:
      1. dotnet test (Core.Tests, Interop.Tests)
      2. dotnet build (WinUI app, Debug x64)
    Intended to be invoked from any CI runner with the .NET 10 SDK and the
    WinUI/Windows App SDK workload installed.
#>

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

Write-Host "== C# core: dotnet test =="
& (Join-Path $PSScriptRoot "test.ps1")
if ($LASTEXITCODE -ne 0) { throw "dotnet test failed" }

Write-Host "== WinUI app: dotnet build =="
$solution = Join-Path $repoRoot "apps\windows\YoruMimizuku.Windows.sln"
dotnet build $solution -c Debug -p:Platform=x64
if ($LASTEXITCODE -ne 0) { throw "dotnet build failed" }

Write-Host "CI checks passed."
