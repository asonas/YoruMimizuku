---
type: log
---

# Wiki Log

Append-only operation log for wiki maintenance. New entries go at the **top**.
Each entry is a `## YYYY-MM-DD <op>` heading followed by a short bullet body
(`sources` / `updated` / `created` / `note` as appropriate).
Recent activity: `grep "^## " log.md | head -5`.

## 2026-06-08 ingest

- sources: [[2026-06-08-phase-c-author-tab]] (plan)
- created: [[author-tab]]
- updated: [[app-shell]]
- note: Ingested Phase C — the author (user) tab. Tapping a user's avatar in the home feed, a filter feed, a notification row, a conversation, or an author feed opens a view-only tab: a profile header (avatar / display name / @handle / bio-when-available) over that user's `app.bsky.feed.getAuthorFeed` posts (`filter=posts_and_author_threads`). New `WorkspaceTab.author(UUID)` backed by an ephemeral `AuthorTab` (reused `TimelineViewModel` via `LiveAuthorFeedLoader`/`AuthorFeedService`, plus `ProfileHeaderViewModel` via `LiveAuthorProfileLoader`/`ProfileService`). Deduped by DID, no unread badge, not persisted; polled only while the active selection. Documented two accepted limitations: bio is nil (ProfileViewBasic has no description), and notification-opened tabs dedupe by handle (no DID on `NotificationGroup.Actor`) while post-opened tabs dedupe by DID. Also noted `ATURI.repo(_:)` was added to derive the author DID from a post's AT-URI (Phase B was not merged). Cross-linked from [[app-shell]].

## 2026-06-08 ingest

- updated: [[macos]]
- note: Added a "Scroll performance" subsection to the timeline rendering page. Time Profiler of scrolling showed most main-thread time in framework layout / AttributeGraph (inherent to hosting SwiftUI rows in List), with `s_strFromUTF8WithSub` (ICU UTF-8) as the top self-weight leaf we own. Two fixes recorded: the body `AttributedString` is now precomputed once on `PostDisplay.bodyAttributedString` (links carry only `.link`; color via the view's `.tint`) instead of rebuilt per render, and the `now` refresh tick was coarsened 1s -> 15s.

## 2026-06-08 ingest

- updated: [[macos]]
- note: Documented the timeline rendering decision — the feed uses SwiftUI `List` rather than `ScrollView { LazyVStack }`. A blank gap appeared below rows because LazyVStack keeps a stale estimated slot height that normal body re-renders (the per-second `now` tick) never revisit; it only collapses on a forced re-layout (scroll / scene-phase change). The gap was independent of text length, width, AttributedString vs plain text, `.fixedSize`, and `.textSelection`. A plain VStack was rejected (~98% CPU, ~1 GB memory); `List` measures variable heights correctly and recycles rows. Recorded the neutralizing modifiers and the j/k scroll path. Implementation in `apps/macos/Views/FeedView.swift`.

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
