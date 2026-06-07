<#
.SYNOPSIS
    Produce a distributable Windows build (self-contained ZIP).

.DESCRIPTION
    Publishes the WinUI app self-contained for win-x64 (bundling the .NET and
    Windows App SDK runtimes, the YoruMimizukuBridge DLL, and the Swift runtime)
    and zips it into build/. The result is "download, extract, run" — no installer
    and no runtime prerequisites beyond the Edge WebView2 runtime (preinstalled on
    Windows 11 and most Windows 10).

    Code signing is OPTIONAL and can be added later without changing the pipeline:
    pass -Thumbprint (a cert already in the cert store) or -CertPath/-CertPassword
    (a PFX) and the app binaries are Authenticode-signed before zipping. With no
    cert the ZIP is unsigned (users get a one-time SmartScreen "more info -> run").

.PARAMETER Version
    Version string used in the zip name. Defaults to today's date (yyyyMMdd).

.PARAMETER StageBridge
    Rebuild + stage the Swift bridge DLL (release) first. Use after changing core/.

.PARAMETER Thumbprint
    SHA1 thumbprint of an Authenticode cert in the current user's store to sign with.

.PARAMETER CertPath
    Path to a PFX to sign with (alternative to -Thumbprint).

.PARAMETER CertPassword
    Password for the PFX given by -CertPath.

.EXAMPLE
    scripts\windows\release.ps1
    scripts\windows\release.ps1 -StageBridge -Version 0.4.0
    scripts\windows\release.ps1 -Thumbprint ABCD... -Version 0.4.0
#>

param(
    [string]$Version = (Get-Date -Format "yyyyMMdd"),
    [switch]$StageBridge,
    [string]$Thumbprint = "",
    [string]$CertPath = "",
    [string]$CertPassword = ""
)

$ErrorActionPreference = "Stop"

function Find-SignTool {
    $kitsBin = "C:\Program Files (x86)\Windows Kits\10\bin"
    if (Test-Path $kitsBin) {
        $found = Get-ChildItem $kitsBin -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match "\\x64\\" } |
            Sort-Object FullName | Select-Object -ExpandProperty FullName
        if ($found.Count -gt 0) { return $found[-1] }
    }
    throw "signtool.exe not found (install the Windows SDK)."
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$rid = "win-x64"
$proj = Join-Path $repoRoot "apps\windows\App\YoruMimizuku.App.csproj"

# Stop any running instance so files are not locked (always succeeds).
cmd /c "taskkill /F /IM YoruMimizuku.App.exe >nul 2>&1 & exit 0" | Out-Null
Start-Sleep -Milliseconds 500

if ($StageBridge) {
    & (Join-Path $PSScriptRoot "stage-bridge.ps1") -Configuration release
    if ($LASTEXITCODE -ne 0) { throw "stage-bridge failed" }
}

Write-Host "Publishing self-contained $rid (Release)..."
# -p:Platform=x64 is required: invoking the project directly otherwise defaults to
# AnyCPU, which the Windows App SDK self-contained build rejects.
dotnet publish $proj -c Release -r $rid -p:Platform=x64
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed (exit $LASTEXITCODE)" }

$publishDir = Join-Path $repoRoot "apps\windows\App\bin\x64\Release\net8.0-windows10.0.19041.0\$rid\publish"
$exe = Join-Path $publishDir "YoruMimizuku.App.exe"
if (-not (Test-Path $exe)) { throw "published exe not found at $exe" }

# Optional Authenticode signing (no-op unless a cert is provided).
if ($Thumbprint -or $CertPath) {
    $signtool = Find-SignTool
    $targets = @($exe, (Join-Path $publishDir "YoruMimizukuBridge.dll")) | Where-Object { Test-Path $_ }
    $signArgs = @("sign", "/fd", "SHA256", "/tr", "http://timestamp.digicert.com", "/td", "SHA256")
    if ($Thumbprint) { $signArgs += @("/sha1", $Thumbprint) }
    else { $signArgs += @("/f", $CertPath); if ($CertPassword) { $signArgs += @("/p", $CertPassword) } }
    & $signtool @signArgs @targets
    if ($LASTEXITCODE -ne 0) { throw "signtool failed" }
    Write-Host "Signed: $($targets -join ', ')"
} else {
    Write-Host "No cert provided - producing an UNSIGNED build (SmartScreen will warn)."
}

# Zip the publish output into build/.
$buildDir = Join-Path $repoRoot "build"
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
$zip = Join-Path $buildDir "YoruMimizuku-$rid-$Version.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $publishDir "*") -DestinationPath $zip -Force

Write-Host ""
Write-Host "Release ZIP: $zip" -ForegroundColor Green
