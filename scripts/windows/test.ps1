<#
.SYNOPSIS
    Run the Windows app's test suites (the C# core and the app's interop layer).

.DESCRIPTION
    Runs `dotnet test` for apps/windows/Core.Tests and apps/windows/Interop.Tests.
    Extra arguments are forwarded to both runs (e.g. --filter SomeTests).

.EXAMPLE
    scripts\windows\test.ps1
    scripts\windows\test.ps1 --filter FeedThreadingTests
#>

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$projects = @(
    "apps\windows\Core.Tests\YoruMimizuku.Core.Tests.csproj",
    "apps\windows\Interop.Tests\YoruMimizuku.App.Interop.Tests.csproj"
)

foreach ($project in $projects) {
    dotnet test (Join-Path $repoRoot $project) @args
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
