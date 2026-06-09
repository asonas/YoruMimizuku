---
type: log
---

# Wiki Log

Append-only operation log for wiki maintenance. New entries go at the **top**.
Each entry is a `## YYYY-MM-DD <op>` heading followed by a short bullet body
(`sources` / `updated` / `created` / `note` as appropriate).
Recent activity: `grep "^## " log.md | head -5`.

## 2026-06-08 ingest

- sources: `2026-06-08-yorumimizuku-sparkle-auto-update-design.md`, `2026-06-09-yorumimizuku-sparkle-auto-update.md`
- created: [[auto-updates]]
- updated: [[overview]], [[macos]]
- note: Ingested the approved Sparkle auto-update design and added an implementation plan. The wiki now records the macOS-only Sparkle 2 scope, gentle settings-gear reminder, update settings tab, GitHub Pages appcast, GitHub Release ZIP/DMG split, app-first notarization, EdDSA key handling, and release task changes. The support matrix marks Sparkle auto-update as planned for macOS and unsupported on Windows/iPadOS/Android.

## 2026-06-08 ingest

- updated: [[ipados]], [[timeline-streaming]]
- note: iPadOS closed several macOS parity gaps. Timeline rows now show relative timestamps, support hidden j/k/f/o keyboard actions, open a full-screen image lightbox, and intercept hashtag links into saved-search tabs. Conversation tabs now include ancestors and a 「さらに表示」 re-anchor cue for capped reply branches. Notifications gained reason icons, relative timestamps, actor taps, and unread tint. Remaining iPadOS gaps are settings/theme/font/density UI, Jetstream live updates, OS-level notifications, full structured-filter editing, and some composer affordances.

## 2026-06-08 ingest

- updated: [[ipados]], [[app-shell]], [[timeline-streaming]]
- note: Corrected the iPadOS/macOS parity story after comparing the current SwiftUI implementations. The iPad app is functional but thinner than macOS: no settings/theme/font/density UI, no j/k focused-row navigation or f/o focused-post shortcuts, no timeline lightbox/relative-time/focus layer, simplified notifications, and a simpler conversation view without ancestors/connectors/show-more re-anchor. The support matrix now marks iOS display density as none, keyboard/post shortcuts as limited, and conversation child tree as limited.

## 2026-06-08 ingest

- sources: `2026-06-08-macos-compose-notification-followups.md`
- updated: [[compose-post]], [[notifications]]
- note: Added planned macOS follow-ups requested from the product backlog: reply composers should preview the replied-to post (avatar, user name, body start), submit loading should replace the Post button instead of resizing the sheet, `Command-Return` / `Control-Return` should submit, and target-post snippets in notifications (notably likes) should open the post's conversation tab.

## 2026-06-08 ingest

- sources: `2026-06-08-yorumimizuku-ipados-design.md`
- created: [[ipados]]
- updated: [[overview]], [[architecture]], [[macos]], [[accounts]], [[app-shell]], [[author-tab]], [[compose-post]], [[filters]], [[notifications]], [[oauth-flow]], [[timeline-streaming]]
- note: Added the dedicated iPadOS target to the wiki. iPadOS imports `BlueskyCore` / `YoruMimizukuKit` / `PlatformApple` directly (no bridge), with touch-first SwiftUI views under `apps/ipados`. Marked iOS support full for OAuth, accounts, core timeline loading, compose, author tabs, copy permalink, keyboard/post actions, and conversation reply trees; limited/differs for shell mechanics, structured filters, notifications, and rich image rendering; none for Jetstream live updates until the iPad app wires foreground live streams.

## 2026-06-08 ingest

- updated: [[architecture]]
- note: Documented the macOS image loading & caching pipeline (code-derived, no spec) — `RemoteImage` over the `ImageDownsampler` actor: thumbnail downsample sized to the view, in-memory decoded `NSCache`, request coalescing, and an on-disk `URLCache`. Prompted by a scroll-performance pass that fixed the disk cache (the legacy `URLCache(diskPath:)` resolved to the filesystem root, failed to open, and disabled disk caching while spamming SQLite errors); now created with the `directory:` initializer. The other changes in that pass (cached ISO8601 formatters, lazy font-family enumeration, hover-highlight extracted into an isolated layer so scrolling skips row re-typeset, `PostRowView: Equatable`) are internal performance work with no user-facing behavior change and are not separately ingested.

## 2026-06-08 ingest

- updated: [[filters]], [[windows]]
- note: Windows structured filters reached parity with macOS for OR pagination. `yoru_search_load` now decodes/returns `CompositeCursor` for multi-subquery OR filters, skips exhausted subqueries on follow-up pages, merges each page newest-first, and preserves infinite scroll. The support matrix now marks Windows saved-search filters full.

## 2026-06-08 ingest

- updated: [[timeline-streaming]]
- sources: `2026-06-08-yorumimizuku-timeline-ux-enhancements-design.md` §5.6, `2026-06-08-phase-d-conversation-child-tree.md`
- note: Phase D landed — the macOS conversation view now renders the descendant reply tree below the anchor. Added a "Conversation view (ancestors + reply tree)" section (tolerant `replies` decode skipping notFound/blocked, `depth=6` fetch, `ThreadNode.childTree(maxDepth:3)`, `ConversationThread`, indented render + 「さらに表示」 re-anchor) and a "Conversation child reply tree" feature row (macos full / windows none — Windows shows ancestors + re-anchor only). Documented that reply-node like/repost stay inert until re-anchored.

## 2026-06-08 ingest

- updated: [[macos]]
- note: Inline images now respect their aspect ratio. A single attached image was center-cropped to a fixed height (`scaledToFill` at 240pt), so wide images overflowed/protruded to the left and tall images were heavily clipped. The core now decodes the embed's `aspectRatio` (`app.bsky.embed.images#view`) onto `EmbedImage`/`ImageAspectRatio` and carries it to the view as `PostImage.aspectRatio` (width/height; nil when absent). `PostRowView` lays a lone image out at that ratio, clamped to `[0.7, 5.0]`, so wide images show in full and tall ones fill width with only a slight crop; multi-image posts keep the fixed-height grid. Added an "Inline images respect their aspect ratio" subsection.

## 2026-06-08 ingest

- updated: [[author-tab]], [[filters]], [[timeline-streaming]], [[notifications]], [[windows]]
- note: Documented Windows parity work for the support matrix gaps. Windows now has author tabs via `yoru_author_feed_load` / `yoru_profile_load`, feed/conversation f/o shortcuts, copy-permalink through shared `PostPermalink`, a multi-row AND/OR filter editor with per-account JSON persistence, and a local Notifications navigation unread badge. Remaining Windows limitations: OR filter pagination still lacks CompositeCursor parity, and notification OS toast/taskbar badge surfacing is not implemented yet.

## 2026-06-08 ingest

- updated: [[compose-post]], [[filters]], [[windows]]
- note: Resolved the remaining Windows `?` cells in [[support-matrix]]. The WinUI composer does send up to 4 PNG/JPEG image attachments through `yoru_post_create`, but image posting is marked limited because the dialog has no alt-text editor, drag/drop attach, WIC downsampling, or upload re-encode yet. Structured filters are also marked limited: `SavedFilterModel` serializes `terms` + `combinator` to `yoru_search_load`, while the current visible entry point creates single hashtag filter tabs from tapped tags rather than a full multi-row AND/OR editor.

## 2026-06-08 ingest

- updated: [[macos]]
- note: Fixed post-body links vanishing on focus. Root cause: `.textSelection(.enabled)` and tappable `.link` runs are mutually incompatible on macOS SwiftUI — the link spans render blank when the row re-lays-out (focus toggling its background), so URLs disappeared and could not be clicked. Removed `.textSelection(.enabled)` from the body `Text` (links win; copy-link covers sharing). Also corrected the precompute note: link color is re-applied per render on the row's `bodyAttributed` (run-attribute mutation only, no UTF-8 re-conversion), not left to `.tint`. Added a "Body links are not selectable text" subsection.

## 2026-06-08 feature

- created: [[support-matrix]] (generated)
- updated: [[conventions]], [[overview]], [[accounts]], [[app-shell]], [[author-tab]], [[compose-post]], [[filters]], [[notifications]], [[oauth-flow]], [[timeline-streaming]]
- note: Added a generated platform support matrix (star chart). Each behavior page now carries a `features:` frontmatter block (per-feature, four platforms macos/windows/ios/android, status full/differs/limited/none/planned/unknown → ○/△/×/−/?), and `support-matrix.md` (type `matrix`) is generated from those blocks by the wiki tool (`wiki matrix`), grouped per source page with a closing Notes section. The wiki CLI gained `matrix` / `matrix --check`; lint now requires every behavior page to declare complete feature statuses and a `note` for any differs/limited/none/unknown cell, so adding or changing a behavior forces a matrix update. Wired `wiki:matrix` into mise, `wiki check`, and the pre-commit hook. Recorded the known Windows gaps from the current wiki: Jetstream live, multiple windows, OS notification banner/badge, copy-permalink, and the author tab are macOS-only (×); browser authorization differs (WebView2 vs ASWebAuthenticationSession, △); f/o keyboard shortcuts are macOS-only (△); image attachment and structured-filter parity on Windows are unverified (?).

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
- note: Windows distribution switched to a framework-dependent ZIP (~40 MB) to fit the Tangled tag-artifact size limit (~50 MB atproto blob; a 60 MB self-contained build was rejected). Bumped to .NET 10 + Windows App SDK 2.1.3 and set `SelfContained=false` + `WindowsAppSDKSelfContained=false`; the user installs the .NET 10 Desktop and Windows App 2.1 runtimes once, and the app prompts on first run if missing (.NET apphost dialog + `WindowsAppSDKBootstrapAutoInitializeOptions_OnNoMatch_ShowUI`). `release.ps1` strips the WASDK 2.x Windows ML stack (`onnxruntime`/`DirectML`/`AI.MachineLearning`, ~16 MB zipped; no opt-out per WindowsAppSDK#5969) and resolves the publish dir TFM-agnostically. The launcher + `app/` ZIP layout is retained.

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
