<#
.SYNOPSIS
    Produce a distributable Windows build (framework-dependent ZIP).

.DESCRIPTION
    Publishes the WinUI app framework-dependent for win-x64 -- the .NET 8 Desktop
    runtime and the Windows App SDK runtime are NOT bundled -- then lays out a
    small top-level YoruMimizuku.exe launcher plus an app/ payload directory
    (holding the app, the YoruMimizukuBridge DLL, and the Swift runtime) and zips
    it into build/. Dropping the two bundled runtimes keeps the ZIP near ~40 MB
    (versus ~90 MB self-contained), small enough to upload as a Tangled tag
    artifact (which is stored as an atproto blob, ~50 MB limit on a default PDS).

    The user installs the runtimes once. The app prompts and links to the download
    on first run if a runtime is missing: the .NET apphost shows a dialog for the
    .NET 8 Desktop Runtime, and the Windows App SDK bootstrapper prompts for the
    Windows App Runtime (enabled via WindowsAppSDKBootstrapAutoInitializeOptions_OnNoMatch_ShowUI
    in the csproj). The Edge WebView2 runtime (preinstalled on Windows 11 and most
    Windows 10) is still needed for OAuth sign-in.

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

.PARAMETER Installer
    Also build an Inno Setup installer EXE for WinSparkle / GitHub Releases.

.PARAMETER WinSparklePrivateKey
    Path to the WinSparkle EdDSA private key. When supplied with -Installer,
    release.ps1 signs the installer and writes appcast-windows*.xml under build/.

.PARAMETER Channel
    Appcast channel to write when -WinSparklePrivateKey is supplied.

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
    [string]$CertPassword = "",
    [switch]$Installer,
    [ValidateSet("stable", "development")]
    [string]$Channel = "stable",
    [string]$WinSparklePrivateKey = "",
    [string]$WinSparkleTool = "",
    [string]$GitHubRepo = "asonas/YoruMimizuku"
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

function Find-InnoSetup {
    $candidates = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }
    $cmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "ISCC.exe not found. Install Inno Setup 6 or add ISCC.exe to PATH."
}

function Find-WinSparkleTool {
    param([string]$Explicit)
    if ($Explicit) {
        if (Test-Path $Explicit) { return $Explicit }
        throw "winsparkle-tool not found at $Explicit"
    }
    $packages = Join-Path $env:USERPROFILE ".nuget\packages\winsparkle"
    if (Test-Path $packages) {
        $found = Get-ChildItem $packages -Recurse -Filter winsparkle-tool.exe -ErrorAction SilentlyContinue |
            Sort-Object FullName | Select-Object -ExpandProperty FullName
        if ($found.Count -gt 0) { return $found[-1] }
    }
    $cmd = Get-Command winsparkle-tool.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "winsparkle-tool.exe not found. Restore the WinSparkle NuGet package or pass -WinSparkleTool."
}

function Escape-Xml {
    param([string]$Value)
    return [System.Security.SecurityElement]::Escape($Value)
}

function Write-WinSparkleAppcast {
    param(
        [string]$InstallerPath,
        [string]$Version,
        [string]$Channel,
        [string]$PrivateKey,
        [string]$ToolPath,
        [string]$Repo,
        [string]$OutputPath
    )
    $tool = Find-WinSparkleTool $ToolPath
    if (-not (Test-Path $PrivateKey)) { throw "WinSparkle private key not found at $PrivateKey" }
    $signatureOutput = & $tool sign --verbose --private-key-file $PrivateKey $InstallerPath
    if ($LASTEXITCODE -ne 0) { throw "winsparkle-tool sign failed" }
    $signatureAttrs = ($signatureOutput | Where-Object { $_ -match 'sparkle:edSignature=' } | Select-Object -Last 1)
    if (-not $signatureAttrs) { throw "winsparkle-tool did not print sparkle:edSignature" }
    $fileName = Split-Path -Leaf $InstallerPath
    $url = "https://github.com/$Repo/releases/download/v$Version/$fileName"
    $title = if ($Channel -eq "development") { "YoruMimizuku $Version (development)" } else { "YoruMimizuku $Version" }
    $pubDate = [DateTimeOffset]::UtcNow.ToString("R", [Globalization.CultureInfo]::InvariantCulture)
    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>YoruMimizuku Windows Updates</title>
    <item>
      <title>$(Escape-Xml $title)</title>
      <pubDate>$pubDate</pubDate>
      <sparkle:version>$(Escape-Xml $Version)</sparkle:version>
      <sparkle:shortVersionString>$(Escape-Xml $Version)</sparkle:shortVersionString>
      <enclosure url="$(Escape-Xml $url)" type="application/octet-stream" $signatureAttrs />
    </item>
  </channel>
</rss>
"@
    Set-Content -Path $OutputPath -Value $xml -Encoding UTF8
    Write-Host "Windows appcast ready: $OutputPath"
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
        [string]$OutputPath,
        [string]$IconPath = ""
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

    # Embed the app icon as a Win32 resource so Explorer shows the logo on the
    # top-level launcher exe (the C launcher has no icon otherwise). Resource id 1:
    # the shell uses the lowest-id icon group as a file's display icon. Falls back
    # to an icon-less build if the .ico or rc.exe is unavailable.
    $resArg = @()
    if ($IconPath -and (Test-Path $IconPath)) {
        $rcPath = [System.IO.Path]::ChangeExtension($SourcePath, ".rc")
        $resPath = [System.IO.Path]::ChangeExtension($SourcePath, ".res")
        Set-Content -Path $rcPath -Value ("1 ICON `"" + $IconPath.Replace('\', '\\') + "`"") -Encoding ascii
        $rc = Get-Command rc.exe -ErrorAction SilentlyContinue
        if ($rc) {
            & $rc.Source /nologo /fo $resPath $rcPath
            if ($LASTEXITCODE -ne 0) { throw "rc.exe failed (exit $LASTEXITCODE)" }
            $resArg = @($resPath)
        } else {
            Write-Host "rc.exe not found - building launcher without an icon."
        }
    }

    cl.exe /nologo /O2 /W4 /DUNICODE /D_UNICODE /Fe:$OutputPath $SourcePath @resArg user32.lib shell32.lib
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

Write-Host "Publishing framework-dependent $rid (Release)..."
# -p:Platform=x64 is required: invoking the project directly otherwise defaults to
# AnyCPU, which the Windows App SDK build rejects. --self-contained false makes the
# .NET runtime framework-dependent; WindowsAppSDKSelfContained=false (in the csproj)
# does the same for the Windows App SDK runtime, so neither runtime is bundled.
dotnet publish $proj -c Release -r $rid -p:Platform=x64 -p:Version=$Version -p:InformationalVersion=$Version --self-contained false
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed (exit $LASTEXITCODE)" }

# Resolve the publish dir without hardcoding the target framework (so a TFM bump
# like net8.0 -> net10.0 doesn't silently zip a stale build): pick the most
# recently written bin\x64\Release\net*-windows*\<rid>\publish that has the exe.
$releaseRoot = Join-Path $repoRoot "apps\windows\App\bin\x64\Release"
$publishDir = Get-ChildItem $releaseRoot -Directory -Filter "net*-windows*" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    ForEach-Object { Join-Path $_.FullName "$rid\publish" } |
    Where-Object { Test-Path (Join-Path $_ "YoruMimizuku.App.exe") } |
    Select-Object -First 1
if (-not $publishDir) { throw "no publish output found under $releaseRoot\net*-windows*\$rid\publish" }
$exe = Join-Path $publishDir "YoruMimizuku.App.exe"

$buildDir = Join-Path $repoRoot "build"
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
$layoutDir = Join-Path $buildDir "YoruMimizuku-$rid-$Version"
$appDir = Join-Path $layoutDir "app"
if (Test-Path $layoutDir) { Remove-Item $layoutDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $appDir | Out-Null
Copy-Item -Path (Join-Path $publishDir "*") -Destination $appDir -Recurse -Force

# Windows App SDK 2.x bundles the Windows ML / AI stack (onnxruntime.dll ~21 MB,
# DirectML.dll ~18 MB, the AI.MachineLearning projection) by default, and there is
# no supported project-level opt-out (microsoft/WindowsAppSDK#5969). This app uses
# no ML APIs, so those binaries are dead weight (~16 MB zipped) and would push the
# ZIP over the Tangled artifact limit. Drop them; they are only loaded on demand
# when Windows ML APIs are called, which never happens here.
$mlDrop = @("onnxruntime*.dll", "Microsoft.ML.OnnxRuntime*.dll", "DirectML.dll", "Microsoft.Windows.AI.MachineLearning*.dll", "Microsoft.WindowsAppSDK.ML*.dll")
Get-ChildItem -LiteralPath $appDir -File |
    Where-Object { $name = $_.Name; $mlDrop | Where-Object { $name -like $_ } } |
    ForEach-Object { Remove-Item $_.FullName -Force }

$launcherSource = Join-Path $buildDir "YoruMimizukuLauncher.cpp"
$launcherExe = Join-Path $layoutDir "YoruMimizuku.exe"
$launcherIcon = Join-Path $repoRoot "apps\windows\App\Assets\AppIcon.ico"
Build-Launcher -SourcePath $launcherSource -OutputPath $launcherExe -IconPath $launcherIcon

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

$sizeMB = [math]::Round((Get-Item $zip).Length / 1MB, 1)
Write-Host ""
Write-Host "Release ZIP: $zip ($sizeMB MB)" -ForegroundColor Green

if ($Installer) {
    $iscc = Find-InnoSetup
    $iss = Join-Path $PSScriptRoot "installer.iss"
    & $iscc "/DAppVersion=$Version" "/DSourceDir=$layoutDir" "/DOutputDir=$buildDir" $iss
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed" }
    $installerExe = Join-Path $buildDir "YoruMimizuku-win-x64-$Version-Setup.exe"
    if (-not (Test-Path $installerExe)) { throw "installer not found at $installerExe" }
    if ($Thumbprint -or $CertPath) {
        $signtool = Find-SignTool
        & $signtool @signArgs $installerExe
        if ($LASTEXITCODE -ne 0) { throw "signtool failed for installer" }
    }
    Write-Host "Installer EXE: $installerExe" -ForegroundColor Green

    if ($WinSparklePrivateKey) {
        $appcastName = if ($Channel -eq "development") { "appcast-windows-dev.xml" } else { "appcast-windows.xml" }
        $appcastPath = Join-Path $buildDir $appcastName
        Write-WinSparkleAppcast `
            -InstallerPath $installerExe `
            -Version $Version `
            -Channel $Channel `
            -PrivateKey $WinSparklePrivateKey `
            -ToolPath $WinSparkleTool `
            -Repo $GitHubRepo `
            -OutputPath $appcastPath
    }
}
