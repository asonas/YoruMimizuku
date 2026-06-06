<#
.SYNOPSIS
    Generate apps/windows/App/Assets/AppIcon.ico from the shared owl app icon.

.DESCRIPTION
    Wraps the 256x256 PNG (the macOS app icon raster) in a single-entry ICO that
    embeds the PNG directly (Vista+ PNG-in-ICO), so no image tooling is required.
#>

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$source = Join-Path $repoRoot "apps\macos\Assets.xcassets\AppIcon.appiconset\icon_256x256.png"
if (-not (Test-Path $source)) { throw "source PNG not found: $source" }

$assets = Join-Path $repoRoot "apps\windows\App\Assets"
New-Item -ItemType Directory -Force -Path $assets | Out-Null
$out = Join-Path $assets "AppIcon.ico"

$png = [System.IO.File]::ReadAllBytes($source)
$stream = New-Object System.IO.MemoryStream
$writer = New-Object System.IO.BinaryWriter($stream)
# ICONDIR
$writer.Write([uint16]0)            # reserved
$writer.Write([uint16]1)            # type = icon
$writer.Write([uint16]1)            # image count
# ICONDIRENTRY
$writer.Write([byte]0)              # width  (0 => 256)
$writer.Write([byte]0)              # height (0 => 256)
$writer.Write([byte]0)              # color count
$writer.Write([byte]0)              # reserved
$writer.Write([uint16]1)            # color planes
$writer.Write([uint16]32)           # bits per pixel
$writer.Write([uint32]$png.Length)  # size of image data
$writer.Write([uint32]22)           # offset of image data (6 + 16)
$writer.Write($png)
$writer.Flush()
[System.IO.File]::WriteAllBytes($out, $stream.ToArray())
$writer.Dispose()

Write-Host "Wrote $out ($($png.Length) byte PNG)"
