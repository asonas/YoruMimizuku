<#
.SYNOPSIS
    Build the WinUI app so you only have to launch the resulting exe.

.DESCRIPTION
    Stops any running instance (so the locked exe can be overwritten), builds the
    solution (Debug x64), and prints the path of the exe to launch.

.EXAMPLE
    scripts\windows\build-app.ps1
#>

$ErrorActionPreference = "Continue"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# 1. Stop a running instance so the exe is not locked.
taskkill /F /IM YoruMimizuku.App.exe 2>$null | Out-Null
Start-Sleep -Milliseconds 500

# 2. Build the WinUI solution.
$solution = Join-Path $repoRoot "apps\windows\YoruMimizuku.Windows.sln"
dotnet build $solution -c Debug
if ($LASTEXITCODE -ne 0) { throw "dotnet build failed (exit $LASTEXITCODE)" }

# 3. Report the exe to launch.
$exe = Join-Path $repoRoot "apps\windows\App\bin\x64\Debug\net10.0-windows10.0.19041.0\win-x64\YoruMimizuku.App.exe"
Write-Host ""
Write-Host "Build complete. Launch:" -ForegroundColor Green
Write-Host "  $exe"
