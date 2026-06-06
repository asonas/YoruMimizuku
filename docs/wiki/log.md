# Wiki Log

Append-only operation log. One line per operation: `## [YYYY-MM-DD] <op> | <summary>`.
Recent activity: `grep "^## \[" log.md | tail -5`.

## [2026-06-06] bootstrap | Initial ingest of docs/superpowers/specs and plans into the LLM-wiki layer (overview, behaviors: oauth-flow / timeline-streaming / compose-post / filters, platforms: macos / windows, conventions). Added the wiki tool, pre-commit hook, and shared Claude/Cursor commands.
## [2026-06-06] ingest | Windows support shipped (PlatformWindows, YoruMimizukuBridge DLL, apps/windows WinUI 3). Updated windows page from planned to implemented, refreshed overview structure, and reconciled AGENTS.md. Sources: apps/windows/README.md, core/Package.swift.
## [2026-06-06] ingest | Windows follow-up: documented build-app.ps1 / make-appicon.ps1 and the RelativeTime.cs / AppIcon.cs services (RelativeTime mirrors the Swift formatter) on the windows page. macos.md notes swift-crypto + the SignpostTracing port are landed.
## [2026-06-06] tooling | Fixed the wiki CLI to normalize CRLF so lint/index work on Windows checkouts.
## [2026-06-06] ingest | Documented token-refresh coalescing (RefreshGate) and session-expiry re-login (SessionExpiry) on the oauth-flow page, after fixing the concurrent-refresh invalid_grant bug.
## [2026-06-06] ingest | Recorded the C ABI JSON date convention on the windows page (request decoder is deferredToDate, so C# must not send ISO8601 Date fields) — the root cause of saved-filter searches returning nothing.
