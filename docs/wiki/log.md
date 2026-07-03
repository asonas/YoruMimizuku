---
type: log
---

# Wiki Log

Append-only operation log for wiki maintenance. New entries go at the **top**.
Each entry is a `## YYYY-MM-DD <op>` heading followed by a short bullet body
(`sources` / `updated` / `created` / `note` as appropriate).
Recent activity: `grep "^## " log.md | head -5`.

## 2026-07-03 ingest

- sources: `docs/superpowers/specs/2026-07-03-design-catalog-design.md`, `docs/superpowers/plans/2026-07-03-design-catalog.md`
- created: [[design-system]]
- updated: [[overview]] (added link to [[design-system]]), `AGENTS.md` (Coding Conventions pointer)
- note: Ingested the design catalog work on `feature/design-catalog` (Tasks 1–10 complete). Documented the naming rule (component = view type name minus `View`; slots = existing computed-property names; spacing/radius = `DesignMetrics` identifiers) with a full reference table of all 8 `DesignMetrics` members and their values/call sites. Documented the DEBUG-only in-app gallery on both platforms (macOS: ヘルプ > デザインカタログ window; iPadOS: sidebar row → sheet, no theme menu) and its toolbar controls (density, theme [macOS only], width slider crossing the 680pt reflow boundary, caption toggle). Documented snapshot-test operations: `YoruMimizukuTests`/`YoruMimizukuPadTests`, the iPad Pro 13-inch (M5) / iOS 26.5 simulator pin, the `EnvironmentValues.catalogPreloadedImages` determinism mechanism, and the actual re-record procedure verified against the resolved `swift-snapshot-testing` source (`SNAPSHOT_TESTING_RECORD=all|missing` env var, since neither test file passes an explicit `record:` argument). Recorded two verified parity findings between the macOS and iPad `PostRowView` implementations as drift candidates, not yet fixed: (1) iPad's `actionBarSection` is missing the external `actionBarTopGap` (6pt) wrap that macOS applies around `actionBar`/`staticActionBar` — both platforms share an identical internal `.padding(.top, 3)` inside those views, so this is a missing 6pt wrap on iPad, not a 3-vs-6 value mismatch; (2) macOS's `staticActionBar` still uses raw literals (`HStack(spacing: 26)`, `.padding(.top, 3)`) while macOS's own `actionBar` and iPad's `staticActionBar` already use the `DesignMetrics` constants. This clears the 2026-07-03 design-catalog spec/plan pair from the lint "uncited source" warning. Regenerated index (no `features:` block on this page — it is a `concept` page, not a `behavior` page, so the support matrix is unaffected).

## 2026-07-03 fix

- sources: `apps/ipados/Views/PostRowView.swift` (commit cb5d8e1 "Play post videos inline on iPad instead of opening Bluesky"), `core/Sources/YoruMimizukuKit/PostDisplay.swift`, `core/Sources/YoruMimizukuKit/PostDisplay+Mapping.swift`
- updated: [[timeline-streaming]], [[ipados]]
- note: Fixed a documentation/reality mismatch: the wiki still said video "inline playback is post-1.0 everywhere", but iPadOS (commit cb5d8e1, 2026-06-25) now plays a top-level post's video inline via a full-screen AVKit player (`PostRowView.VideoPlayerScreen`) using the new `PostVideo.playlistURL` field, falling back to the browser only when the embed has no playlist. Renamed the [[timeline-streaming]] matrix row from "Video embed poster (no inline playback)" to "Video embed playback" and flipped iOS to `differs`; rewrote the video-poster prose and added an "Inline video playback" section plus a known-differences bullet to [[ipados]]. Also corrected a stale claim in the same paragraph ("Both renderings are macOS-only today") that predated the Windows/iPadOS quote-card and video-poster support already reflected elsewhere on the page — quote cards and video posters render on macOS, Windows, and iPadOS alike; only iPadOS plays inline. Noted that a quoted post's video (inside `QuoteCardView`) stays a non-interactive poster on every platform, since the quote card's own tap opens the quoted conversation instead. Regenerated support-matrix and index.

## 2026-07-03 ingest

- sources: `docs/superpowers/specs/2026-07-02-post-interaction-affordances-design.md`, `docs/superpowers/plans/2026-07-02-post-interaction-affordances.md`
- updated: [[timeline-streaming]], [[ipados]]
- note: Ingested the 2026-07-02 post-interaction affordances (macOS-only, implementation complete). Timestamp tap opens/re-anchors the conversation view (`PostRowView.timestampView`, hover cursor + underline, wired through `FeedView`/`ConversationView`); a copy-link toast via the new shared `YoruMimizukuKit.ToastCenter` (monotonic-token auto-dismiss) + `ToastView`/`MainWindowView` bottom overlay, fired from `FeedView.copyPermalink`/`ConversationView.copyPermalink`; and in-app author-tab routing for body `@mention` taps via `RichText.mentionDID(from:)` checked in `MainWindowView.openURL` right after the hashtag branch. Added three new [[timeline-streaming]] matrix rows (macOS full; Windows none, not addressed; iOS/Android planned, iPad parity tracked as a dedicated follow-up plan per the spec's non-goals) and a new "Post-row interaction affordances" prose section. Added the same follow-up as a known-differences bullet on [[ipados]]. This clears the two lint "uncited source" warnings for the spec/plan pair. Regenerated support-matrix and index.

## 2026-06-24 ingest

- sources: `docs/superpowers/specs/2026-06-24-yorumimizuku-ipados-parity-design.md`, `docs/superpowers/plans/2026-06-24-yorumimizuku-ipados-parity.md`
- updated: [[ipados]], [[timeline-media-layout]], [[timeline-streaming]], [[sensitive-media]]
- note: Ingested the iPadOS timeline parity work on `feature/ipados-parity`. The iPad timeline now renders like macOS: the AppKit-free presentation foundation (ThemeStore, density store, RemoteImage/ImageDownsampler) was duplicated into `apps/ipados`, with a new UIFont-based `Typography`; the link/quote/video cards were ported; `PostRowView` was rewritten to match macOS (themed type/colors, density, 5:4 tall-image crop + 全体表示 hint, RemoteImage grid, video poster, OGP link card + lazy fallback, quote card, sensitive-media blur, reply marker, repost/quote popover, delete context menu, wide-column reflow); `TimelineListView` now does FeedThreading.arrange grouping with the connector line, themed canvas/divider, classified load-failure states, themed empty/loading states, delete confirmation, and scene-width reflow. Flipped the iOS status to `full` on [[timeline-media-layout]] (both rows), [[sensitive-media]], and [[timeline-streaming]] (delete own post, load error states, OGP cards, quote cards, video poster, thread grouping). Also fixed a latent build break: the iPad target did not compile because `TimelineListView` still treated `TimelineViewModel.state` `.failed` as a String. Remaining iPad gaps are settings surfaces only (density/theme/font pickers, structured filter editor, notification settings) — Phase 3, not yet done. Visual confirmation on device by the author is still pending.

## 2026-06-23 ingest

- sources: `docs/superpowers/specs/2026-06-23-timeline-image-reflow-design.md`, `docs/superpowers/plans/2026-06-23-timeline-image-reflow.md`
- created: [[timeline-media-layout]]
- updated: [[overview]] (added link to [[timeline-media-layout]])
- note: Ingested the timeline image reflow feature landed on `feature/timeline-image-reflow`. New `TimelineLayout` helper (platform-neutral, `YoruMimizukuKit`) supplies the 5:4 crop threshold, reflow threshold (680 pt), media rail width (300 pt), column gap (16 pt), and text column cap (620 pt). macOS `PostRowView` now crops tall single images to 5:4 with a top-anchor + `tallCropHint` fade overlay; wide feed columns (≥ 680 pt region width) reflow to body-left / media-right two-column layout measured once in `FeedView.onGeometryChange`. Quote cards stay in the left (text) column in both layouts. Windows and iOS are `none`/`planned` — the helper constants land in the shared core but the SwiftUI view changes are macOS-only.

## 2026-06-20 ingest

- sources: `apps/windows/App/**`, `core/Sources/YoruMimizukuBridge/{BridgeOperations,CABI}.swift`
- updated: [[windows]], [[timeline-streaming]], [[sensitive-media]], [[notifications]]
- note: Brought the Windows app to macOS 1.0.0-dev.8 feature parity. The bridge `PostDisplayDTO` now carries the quoted record, video poster, and `mediaWarning`; a new `yoru_post_delete` deletes own posts; and the error envelope carries the shared `LoadFailure` (kind/title/message). Windows feed rows now render quote cards, video posters (poster + browser open), and a tap-to-reveal sensitive-media curtain (an opaque cover, not a Gaussian blur — WinUI has no cheap subtree blur, so the matrix marks Windows `differs`). Added own-post delete (confirm + optimistic prune via `yoru_post_delete`), classified load-failure states with a 再試行 button, and a 通知 settings section (poll interval 15/30/60/300s + unread-badge toggle, applied live). Remaining macOS-implemented gaps: none in this scope. See `docs/HANDOFF-windows-parity.md` for the blur deviation and other deferrals.

## 2026-06-17 ingest

- sources: `core/Sources/BlueskyCore/Models/Timeline.swift`, `core/Sources/YoruMimizukuKit/{PostDisplay,PostDisplay+Mapping}.swift`, `apps/macos/Views/PostRowView.swift`, `docs/superpowers/specs/2026-06-04-yorumimizuku-design.md`, `docs/superpowers/plans/2026-06-11-yorumimizuku-v1.0.0-roadmap.md`
- created: [[sensitive-media]]
- updated: [[overview]] (linked the new page), `docs/superpowers/specs/2026-06-04-yorumimizuku-design.md` §14 (NSFW media blur minimal now in v1.0.0)
- note: Ingested the minimal NSFW/sensitive-media blur landed on `feature/nsfw-media-blur` (commit 5437d01). New `Label` decode on `PostView.labels`, `MediaWarning.from(labels:)` mapping (adult = porn/sexual/nudity, graphic = graphic-media/gore, honoring `neg`), and a tap-to-reveal blur curtain in the macOS `PostRowView`. New "Sensitive media blur (content labels)" matrix row: macOS full; Windows/iPadOS none (label decode shared in core, but only macOS gates the UI); Android planned. Per-user moderation preferences (getPreferences, subscribed labelers, per-label hide/warn/show, account-level labels) remain deferred. Regenerated support-matrix and index.

## 2026-06-15 ingest

- sources: `docs/superpowers/plans/2026-06-11-yorumimizuku-v1.0.0-roadmap.md`, `core/Sources/BlueskyCore/Account/AccountManager.swift`, `core/Sources/YoruMimizukuKit/{PostInteracting,TimelineViewModel,LoadFailure}.swift`, `apps/macos/{NotificationSettings.swift,Views/{SidebarView,FeedView,PostRowView,SettingsView,MainWindowView,RootView,NewPostCommand}.swift}`
- updated: [[timeline-streaming]], [[accounts]], [[notifications]], [[app-shell]]
- note: Ingested four v1.0.0 finishing features landed on `feature/v1.0.0-finishing` (commits ece0f37, de381ce, cf17589, 07d028d). B-3 delete-own-post: new "Delete own post" feature row (macOS full; iPadOS/Windows none — the PostInteracting.deletePost capability is shared but no delete UI is wired off macOS) + prose on the host-decided `canDelete` ownership, confirmation dialog, and the optimistic-with-restore `TimelineViewModel.deletePost` over `PostInteracting.deletePost`. B-5 error UX: new "Load error states (offline / 429 / 5xx) with retry" row (macOS full; iPadOS/Windows unknown, not yet audited) + prose on the tested `LoadFailure` classifier and `FeedView.failedState`'s 再試行 button; refresh/loadMore swallow failures; no separate 429 backoff (poll interval is the limiter). A-5 account selector: documented the macOS sidebar-footer account `Menu` and `AccountManager.summaries()` / `removeAndAdvance(did:)` in [[accounts]], and noted the switcher lives in the sidebar footer (not the design's top-right) in [[app-shell]]. B-4 notification settings: documented the 通知 settings tab (poll interval 15/30/60/300s, badge toggle) backed by `NotificationSettingsStore` and the ⌘, settings command in [[notifications]] and [[app-shell]]. Regenerated support-matrix and index.

## 2026-06-11 ingest

- sources: `apps/windows/App/**`, `core/Sources/YoruMimizukuBridge/**`, `core/Sources/YoruMimizukuKit/PostText.swift` (Windows 0.8.0 parity; no new spec)
- updated: [[windows]], [[timeline-streaming]], [[compose-post]], [[notifications]], [[app-shell]]
- note: Brought the Windows app to macOS 0.8.0 parity (bumped to 0.8.0). New: external link preview cards (embed card + lazy OGP via `yoru_ogp_load`), web-style feed thread grouping (`yoru_feed_arrange` over the tested `FeedThreading`), the conversation descendant reply tree (`yoru_thread_load` now returns a `ConversationThread` from `ThreadNode.childTree`), a composer alt-text editor + WIC downsampling, OS toast + taskbar flash for new notifications, and multiple windows (`Ctrl+Shift+N`). Post submission now trims trailing blank lines via the shared `PostText`. Rebased onto the v1.0.0-roadmap merge, which independently reached the same Jetstream finding and deferred it past v1.0.0; this branch keeps that framing (Jetstream row stays none everywhere) and notes Windows interval polling is at parity. Windows is now the one platform with OS-level notification surfacing (toast + taskbar flash), ahead of the roadmap's deferred macOS OS-banner path; the numeric taskbar badge still awaits MSIX.

## 2026-06-11 ingest

- sources: `apps/macos/Views/LinkCardView.swift` (link card restyle; no new spec)
- updated: [[timeline-streaming]]
- note: The link card moved from the title-chip-overlay style to X's full large card: hero image, bold title, grey description, and a link-icon host line stacked in one bordered container; thumbnail-less links render the text section alone.

## 2026-06-11 ingest

- sources: `FeedThreading.swift`, `apps/macos/Views/FeedView.swift`, `apps/macos/Views/PostRowView.swift` (feed thread grouping; no new spec)
- updated: [[timeline-streaming]]
- note: The macOS feed now groups same-thread posts the way Bluesky web does: `FeedThreading.arrange` resolves each post to its topmost on-page ancestor and emits the chain oldest-first at the newest member's position, with a connector line between avatars, the in-block reply marker hidden, and the in-block divider dropped. New "Thread grouping in the feed (web-style)" matrix row (macOS full, Windows/iPadOS none).

## 2026-06-11 ingest

- sources: `NewPostCommand.swift`, `AppDelegate.swift`, `LinkCardView.swift` (macOS UX fixes; no new spec)
- updated: [[app-shell]], [[auto-updates]], [[timeline-streaming]]
- note: Three macOS changes. (1) ⌘N now opens the new-post composer instead of the WindowGroup default New Window, via a FocusedValues-published action. (2) Sparkle "Install and Restart" works again: a custom quit-Apple-event handler ends presented sheets and re-enters terminate, because AppKit cancels the quit event with userCanceledErr while any sheet is up (the update UI lives in the settings sheet). (3) The external link card is restyled after X's large summary card: 1.91:1 hero image, title chip overlay, "hostから" line; thumbnail-less links use a bordered text card.

## 2026-06-11 ingest

- sources: `ComposerViewModel.swift`, `NotificationsService.swift`, `LinkPreviewLoader.swift`, `LinkCardView.swift` (v0.8.0-dev.2 behavior changes; no new spec)
- updated: [[compose-post]], [[notifications]], [[timeline-streaming]]
- note: Three shipped changes. (1) Submission now trims trailing whitespace/blank lines from the post body, preserving interior line breaks. (2) `listNotifications` always sends `priority=false` so an account-level priority setting can no longer silently drop reply notifications from non-followed accounts. (3) macOS post rows render external link preview cards: directly from `app.bsky.embed.external#view`, or via a cached client-side OGP fetch for a bare link facet in text-only posts; the card sits between body/images and the action bar. New "External link preview cards (OGP)" matrix row (macOS full, Windows/iPadOS none).

## 2026-06-09 ingest

- updated: [[auto-updates]], [[windows]]
- note: Added the Windows auto-update path. The WinUI app now has WinSparkle wiring and an Update settings section, guarded behind a placeholder Windows EdDSA public key. `release.ps1 -Installer` can build an Inno Setup installer EXE while preserving the ZIP artifact, and `-WinSparklePrivateKey` can sign that installer and generate `appcast-windows.xml` / `appcast-windows-dev.xml` for GitHub Pages and GitHub Releases hosting. The support matrix marks Windows updates limited until a real key and appcast are published.

## 2026-06-08 ingest

- sources: `2026-06-08-macos-compose-notification-followups.md`
- updated: [[compose-post]], [[notifications]]
- note: Implemented the macOS compose/notification follow-ups. Reply composers now carry the parent `PostDisplay` for a compact reply preview while still submitting only the parent URI; the Post button shows its own progress indicator; `Command-Return` / `Control-Return` submit drafts; notification subject snippets with `subjectURI` open or re-select a conversation tab through a URI-based `WorkspaceModel.openConversation(...)` path.

## 2026-06-08 ingest

- updated: [[auto-updates]], [[macos]]
- note: Marked macOS Sparkle auto-update as fully shipped after publishing the stable `v0.7.0` GitHub Release with DMG/ZIP artifacts and updating `appcast.xml` on `gh-pages`. The support matrix now marks Sparkle auto-update full on macOS; other platforms remain unsupported because they need separate updater mechanisms.

## 2026-06-08 ingest

- updated: [[auto-updates]], [[macos]]
- note: Reconciled Sparkle auto-update docs and plans with implementation status. The Sparkle app wiring, update settings tab, stable/development channel picker, EdDSA public key, GitHub Pages appcasts, development prerelease ZIP, and development-channel update test are complete. The support matrix now marks macOS auto-update as limited rather than planned because the stable production release path remains to be exercised.

## 2026-06-08 ingest

- sources: `2026-06-09-yorumimizuku-sparkle-auto-update.md`
- updated: [[auto-updates]]
- note: Added the GitHub-backed stable/development channel design to Sparkle auto-updates. The macOS updater now treats `appcast.xml` as the stable feed and `appcast-dev.xml` as the development feed, selected from the update settings tab and persisted in UserDefaults. Development builds use prerelease tags such as `v0.7.0-dev.1`; Sparkle does not downgrade when switching back to stable, so a later stable build must have a greater build number or the user reinstalls manually.

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
