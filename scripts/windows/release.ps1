<#
.SYNOPSIS
    Produce a distributable Windows build (self-contained ZIP).

.DESCRIPTION
    Publishes the WinUI app self-contained for win-x64 (bundling the .NET and
    Windows App SDK runtimes, the YoruMimizukuBridge DLL, and the Swift runtime),
    places that payload under app/, builds a small top-level launcher exe, and
    zips the layout into build/. The result is "download, extract, run" — no
    installer and no runtime prerequisites beyond the Edge WebView2 runtime
    (preinstalled on Windows 11 and most Windows 10).

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

function Enter-MSVC {
    if (Get-Command cl.exe -ErrorAction SilentlyContinue) { return }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) {
        throw "vswhere.exe not found at $vswhere. Install Visual Studio or Build Tools with the C++ workload."
    }
    $vsPath = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath
    if (-not $vsPath) {
        throw "No Visual Studio instance with the MSVC C++ tools was found."
    }
    $devShell = Join-Path $vsPath.Trim() "Common7\Tools\Launch-VsDevShell.ps1"
    if (-not (Test-Path $devShell)) {
        throw "Launch-VsDevShell.ps1 not found at $devShell."
    }
    & $devShell -Arch amd64 -HostArch amd64 -SkipAutomaticLocation | Out-Null
}

function Build-Launcher {
    param(
        [string]$SourcePath,
        [string]$OutputPath
    )
    Enter-MSVC
    $source = @'
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <stdio.h>
#include <wchar.h>

int APIENTRY wWinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPWSTR lpCmdLine, int nCmdShow) {
    (void)hInstance;
    (void)hPrevInstance;

    wchar_t launcherPath[MAX_PATH];
    if (GetModuleFileNameW(NULL, launcherPath, MAX_PATH) == 0) {
        MessageBoxW(NULL, L"Failed to locate the launcher.", L"YoruMimizuku", MB_OK | MB_ICONERROR);
        return 1;
    }

    wchar_t *lastSlash = wcsrchr(launcherPath, L'\\');
    if (lastSlash == NULL) {
        MessageBoxW(NULL, L"Failed to resolve the app directory.", L"YoruMimizuku", MB_OK | MB_ICONERROR);
        return 1;
    }
    *lastSlash = L'\0';

    wchar_t appDir[MAX_PATH];
    wchar_t appPath[MAX_PATH];
    if (swprintf_s(appDir, MAX_PATH, L"%s\\app", launcherPath) < 0 ||
        swprintf_s(appPath, MAX_PATH, L"%s\\YoruMimizuku.App.exe", appDir) < 0) {
        MessageBoxW(NULL, L"The app path is too long.", L"YoruMimizuku", MB_OK | MB_ICONERROR);
        return 1;
    }

    HINSTANCE result = ShellExecuteW(NULL, L"open", appPath, lpCmdLine, appDir, nCmdShow);
    if ((INT_PTR)result <= 32) {
        MessageBoxW(NULL, L"Failed to launch app\\YoruMimizuku.App.exe.", L"YoruMimizuku", MB_OK | MB_ICONERROR);
        return 1;
    }
    return 0;
}
'@
    Set-Content -Path $SourcePath -Value $source -Encoding UTF8
    cl.exe /nologo /O2 /W4 /DUNICODE /D_UNICODE /Fe:$OutputPath $SourcePath user32.lib shell32.lib
    if ($LASTEXITCODE -ne 0) { throw "launcher build failed (exit $LASTEXITCODE)" }
}

function Compress-Directory {
    param(
        [string]$SourcePath,
        [string]$DestinationPath
    )

    Add-Type -AssemblyName System.IO.Compression | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null

    $sourceRoot = (Resolve-Path $SourcePath).Path
    $zipMode = [System.IO.Compression.ZipArchiveMode]::Create
    $compression = [System.IO.Compression.CompressionLevel]::Optimal
    $fileMode = [System.IO.FileMode]::CreateNew
    $fileAccess = [System.IO.FileAccess]::ReadWrite
    $fileShare = [System.IO.FileShare]::None

    $zipStream = [System.IO.File]::Open($DestinationPath, $fileMode, $fileAccess, $fileShare)
    try {
        $archive = [System.IO.Compression.ZipArchive]::new($zipStream, $zipMode)
        try {
            Get-ChildItem -LiteralPath $sourceRoot -Recurse -File | ForEach-Object {
                $relativePath = $_.FullName.Substring($sourceRoot.Length + 1).Replace('\', '/')
                $entry = $archive.CreateEntry($relativePath, $compression)

                $readAttempts = 5
                for ($attempt = 1; $attempt -le $readAttempts; $attempt++) {
                    try {
                        $input = [System.IO.File]::Open(
                            $_.FullName,
                            [System.IO.FileMode]::Open,
                            [System.IO.FileAccess]::Read,
                            [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
                        )
                        try {
                            $output = $entry.Open()
                            try {
                                $input.CopyTo($output)
                            } finally {
                                $output.Dispose()
                            }
                        } finally {
                            $input.Dispose()
                        }
                        break
                    } catch {
                        if ($attempt -eq $readAttempts) {
                            throw "failed to zip $($_.FullName): $($_.Exception.Message)"
                        }
                        Start-Sleep -Milliseconds (200 * $attempt)
                    }
                }
            }
        } finally {
            $archive.Dispose()
        }
    } finally {
        $zipStream.Dispose()
    }
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

$buildDir = Join-Path $repoRoot "build"
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
$layoutDir = Join-Path $buildDir "YoruMimizuku-$rid-$Version"
$appDir = Join-Path $layoutDir "app"
if (Test-Path $layoutDir) { Remove-Item $layoutDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $appDir | Out-Null
Copy-Item -Path (Join-Path $publishDir "*") -Destination $appDir -Recurse -Force

$launcherSource = Join-Path $buildDir "YoruMimizukuLauncher.cpp"
$launcherExe = Join-Path $layoutDir "YoruMimizuku.exe"
Build-Launcher -SourcePath $launcherSource -OutputPath $launcherExe

# Optional Authenticode signing (no-op unless a cert is provided).
if ($Thumbprint -or $CertPath) {
    $signtool = Find-SignTool
    $targets = @($launcherExe, (Join-Path $appDir "YoruMimizuku.App.exe"), (Join-Path $appDir "YoruMimizukuBridge.dll")) |
        Where-Object { Test-Path $_ }
    $signArgs = @("sign", "/fd", "SHA256", "/tr", "http://timestamp.digicert.com", "/td", "SHA256")
    if ($Thumbprint) { $signArgs += @("/sha1", $Thumbprint) }
    else { $signArgs += @("/f", $CertPath); if ($CertPassword) { $signArgs += @("/p", $CertPassword) } }
    & $signtool @signArgs @targets
    if ($LASTEXITCODE -ne 0) { throw "signtool failed" }
    Write-Host "Signed: $($targets -join ', ')"
} else {
    Write-Host "No cert provided - producing an UNSIGNED build (SmartScreen will warn)."
}

# Zip the launcher layout into build/.
$zip = Join-Path $buildDir "YoruMimizuku-$rid-$Version.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Directory -SourcePath $layoutDir -DestinationPath $zip

Write-Host ""
Write-Host "Release ZIP: $zip" -ForegroundColor Green
