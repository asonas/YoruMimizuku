# Wiki Log

Append-only operation log. One line per operation: `## [YYYY-MM-DD] <op> | <summary>`.
Recent activity: `grep "^## \[" log.md | tail -5`.

## [2026-06-06] bootstrap | Initial ingest of docs/superpowers/specs and plans into the LLM-wiki layer (overview, behaviors: oauth-flow / timeline-streaming / compose-post / filters, platforms: macos / windows, conventions). Added the wiki tool, pre-commit hook, and shared Claude/Cursor commands.
## [2026-06-06] ingest | Windows support shipped (PlatformWindows, YoruMimizukuBridge DLL, apps/windows WinUI 3). Updated windows page from planned to implemented, refreshed overview structure, and reconciled AGENTS.md. Sources: apps/windows/README.md, core/Package.swift.
