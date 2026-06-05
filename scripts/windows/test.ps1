<#
.SYNOPSIS
    Run the Swift core test suite on Windows.

.DESCRIPTION
    Sets up the Swift/MSVC environment, then runs `swift test` inside the
    core package. Extra arguments are forwarded to `swift test`
    (e.g. --filter SomeTests).

.EXAMPLE
    scripts\windows\test.ps1
    scripts\windows\test.ps1 --filter LoginViewModelTests
#>

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot "Enter-SwiftEnv.ps1")

Push-Location (Join-Path $repoRoot "core")
try {
    swift test @args
} finally {
    Pop-Location
}
