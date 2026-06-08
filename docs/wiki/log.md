---
type: log
---

# Wiki Log

Append-only operation log for wiki maintenance. New entries go at the **top**.
Each entry is a `## YYYY-MM-DD <op>` heading followed by a short bullet body
(`sources` / `updated` / `created` / `note` as appropriate).
Recent activity: `grep "^## " log.md | head -5`.

## 2026-06-08 ingest

- created: [[app-shell]], [[accounts]], [[architecture]], [[notifications]], [[glossary]]
- updated: [[overview]], [[timeline-streaming]], [[oauth-flow]], [[filters]], [[macos]], [[conventions]]
- note: Structural pass to fill wiki gaps. Added behavior pages for the app shell (window/tabs/sidebar/density — the cmux-sidebar content moved here out of timeline-streaming), multi-account persistence, and notifications; a `concept` page for the ports-and-adapters architecture (was only a paragraph in overview); and a `reference` glossary of AT Protocol/OAuth terms. Tightened citations: oauth-flow now cites the granular oauth/dpop/login plans, filters cites the filter-tabs/structured-filters plans, and macos cites the app-icon design+plan. Extended the wiki tool's `typeOrder`/`sourcedTypes` with `concept` and `reference` so the new page types order and validate correctly; updated conventions accordingly.

## 2026-06-08 format

- updated: [[conventions]]
- note: Reformatted log.md to the Obsidian wiki/log.md style — frontmatter, newest-first entries, and a `## YYYY-MM-DD <op>` heading with a bullet body instead of a single crammed heading line. Updated the conventions ingest step to match.

## 2026-06-07 ingest

- updated: [[windows]]
- note: Windows release ZIP layout now uses a top-level `YoruMimizuku.exe` launcher with the self-contained WinUI payload under `app/`, keeping dependency DLLs and satellite resource folders out of the extracted root.

## 2026-06-07 ingest

- updated: [[compose-post]], [[windows]]
- note: Reply composer wiring landed on macOS and Windows: timeline reply buttons now open the existing composer with `replyParentURI`, matching the compose-post page; reply facets continue through `PostService.createPost`.

## 2026-06-07 ingest

- updated: [[compose-post]], [[windows]]
- note: Quote posts — added a repost/quote MenuFlyout to the Windows feed (引用 opens ComposerDialog with the post's uri+cid and a preview), matching the macOS popover. compose-post updated (quote moved into scope, record/recordWithMedia embeds, repost-menu entry).

## 2026-06-07 ingest

- updated: [[windows]]
- note: Documented Windows distribution — `scripts/windows/release.ps1` builds a self-contained ZIP, signing is decoupled/optional (deferred), MSIX is the eventual installable form.

## 2026-06-06 ingest

- updated: [[windows]]
- note: Recorded the C ABI JSON date convention — the request decoder is `deferredToDate`, so C# must not send ISO8601 Date fields. This was the root cause of saved-filter searches returning nothing.

## 2026-06-06 ingest

- updated: [[oauth-flow]]
- note: Documented token-refresh coalescing (RefreshGate) and session-expiry re-login (SessionExpiry), after fixing the concurrent-refresh `invalid_grant` bug.

## 2026-06-06 tooling

- note: Fixed the wiki CLI to normalize CRLF so lint/index work on Windows checkouts.

## 2026-06-06 ingest

- updated: [[windows]], [[macos]]
- note: Windows follow-up — documented `build-app.ps1` / `make-appicon.ps1` and the `RelativeTime.cs` / `AppIcon.cs` services (RelativeTime mirrors the Swift formatter) on the windows page. macos.md notes swift-crypto + the SignpostTracing port are landed.

## 2026-06-06 ingest

- sources: apps/windows/README.md, core/Package.swift
- updated: [[windows]], [[overview]]
- note: Windows support shipped (PlatformWindows, YoruMimizukuBridge DLL, apps/windows WinUI 3). Updated the windows page from planned to implemented, refreshed the overview structure, and reconciled AGENTS.md.

## 2026-06-06 bootstrap

- created: [[overview]], [[oauth-flow]], [[timeline-streaming]], [[compose-post]], [[filters]], [[macos]], [[windows]], [[conventions]]
- note: Initial ingest of docs/superpowers/specs and plans into the LLM-wiki layer. Added the wiki tool, pre-commit hook, and shared Claude/Cursor commands.
