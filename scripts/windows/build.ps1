<#
.SYNOPSIS
    Build the Swift core package on Windows.

.DESCRIPTION
    Sets up the Swift/MSVC environment, then runs `swift build` inside the
    core package. Extra arguments are forwarded to `swift build`
    (e.g. -c release).

.EXAMPLE
    scripts\windows\build.ps1
    scripts\windows\build.ps1 -c release
#>

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot "Enter-SwiftEnv.ps1")

Push-Location (Join-Path $repoRoot "core")
try {
    swift build @args
} finally {
    Pop-Location
}
