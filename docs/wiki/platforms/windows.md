---
title: Platform — Windows
type: platform
updated: 2026-11-21
sources:
  - docs/adr/0027-windows-csharp-core.md
  - docs/adr/0004-windows-multiplatform-structure.md
  - apps/windows/README.md
  - core/Package.swift
  - apps/windows/App/Services/RelativeTime.cs
  - apps/windows/App/ViewModels/ComposerViewModel.cs
  - apps/windows/App/Views/ComposerDialog.xaml
  - apps/windows/App/Views/ComposerDialog.xaml.cs
  - apps/windows/App/ViewModels/SavedFilterModel.cs
  - apps/windows/App/ViewModels/WorkspaceViewModel.cs
  - apps/windows/App/ViewModels/AuthorViewModel.cs
  - apps/windows/App/ViewModels/NotificationsViewModel.cs
  - apps/windows/App/Views/AuthorView.xaml.cs
  - apps/windows/App/Views/FilterEditorDialog.xaml.cs
  - apps/windows/App/Views/FeedView.xaml.cs
  - apps/windows/App/Services/ToastCenter.cs
  - apps/windows/App/Services/VideoAttachment.cs
  - apps/windows/Core/VideoUploadService.cs
  - apps/windows/Core/TimelineLayout.cs
  - apps/windows/App/Views/ConversationView.xaml.cs
  - apps/windows/App/MainWindow.xaml.cs
  - apps/windows/Core/DetailPaneModel.cs
  - docs/adr/0026-macos-three-pane.md
  - scripts/windows/build-app.ps1
  - scripts/windows/release.ps1
  - apps/windows/App/Services/ImageProcessing.cs
  - apps/windows/App/Services/NotificationAlerts.cs
  - apps/windows/App/Services/WindowPlacement.cs
  - apps/windows/App/Services/AppSettings.cs
  - apps/windows/Interop/CoreClients.cs
  - apps/windows/Core/Accounts/LegacySwiftAccountStore.cs
  - apps/windows/App/App.xaml.cs
  - apps/windows/App/Program.cs
  - scripts/windows/test.ps1
  - scripts/windows/ci.ps1
  - scripts/windows/installer.iss
  - README.md
---

# Platform — Windows

Status: **implemented and running**. A WinUI 3 (C#/.NET 10) app with its own C#
core under `apps/windows`; no Swift toolchain, bridge DLL or P/Invoke into a core
(`0027-windows-csharp-core.md`, `apps/windows/README.md`).

This page matters for cross-machine context: the Windows build runs on a
different machine / agent, so it reconstructs the same picture from this wiki.

The C# core replaced the earlier Swift core + C ABI bridge (`YoruMimizukuBridge`,
`PlatformWindows`) in Phases 0-6 of the handoff spec; those Swift targets are
deleted. Phase 7, bringing the 2026-11-20 macOS redesign to Windows, is next.

## Architecture

```
apps/windows
├── Core/ (+ Core.Tests/)        C# port of the BlueskyCore / YoruMimizukuKit logic
├── Interop/ (+ Interop.Tests/)  ICoreClient / IAccountClient over Core, DTOs, CoreException
└── App/                         WinUI views, view models, services
```

Each window holds an `IAccountClient` for its own account (DID), so its reads and
writes do not follow another window's account switch.

**Difference: one-time sign-in again.** The C# core stores accounts with DPAPI under
`%LOCALAPPDATA%\YoruMimizuku\accounts` and never reads the Swift core's old store;
the first launch after the switch deletes it and tells the user once to sign in
again ([[accounts]]). On an expired session Windows keeps the account and asks
the user to sign in to it again, as macOS does ([[oauth-flow]]).

## apps/windows (WinUI 3)

- The app reaches the core only through `ICoreClient` / `IAccountClient`.
- C# MVVM view models mirror `YoruMimizukuKit`: Timeline / Thread / Notifications /
  Login / Composer / Workspace / SavedFilter (+ `PostItem` with optimistic like/repost).
- Views: WebView2 OAuth login, a feed (facet-aware rich text, image grid + lightbox,
  external link preview cards, web-style thread grouping, relative timestamps,
  like/repost/reply icons, infinite scroll, 30s refresh, j/k, n-to-compose,
  per-post separators), conversation (ancestor + descendant reply tree),
  notifications, composer, settings; a three-pane shell (ADR 0026): the
  `NavigationView` sidebar of timelines with `Ctrl+Shift+J/K` cycling, closable
  filter tabs and an account footer, the selected timeline, and a detail pane that
  shows one conversation or author page at a time, as on macOS (the tested
  `Core/DetailPaneModel.cs`); `Ctrl+Shift+N` opens a new window ([[app-shell]]).
- The composer can post text, replies, quotes, and up to 4 PNG/JPEG image
  attachments through `PostCreateAsync`. Each attachment now shows a thumbnail
  with a per-image alt-text editor and a remove button, and oversized images are
  scaled to a 2000px longest edge and re-encoded as JPEG via WIC before upload
  (`Services/ImageProcessing.cs`). The core also trims trailing blank
  lines via its `PostText` helper, matching the macOS submission boundary
  ([[compose-post]]).
- Saved-filter tabs call `SearchLoadAsync` with the structured
  `terms` + `combinator` JSON shape used by the Swift core. The WinUI shell has
  a multi-row AND/OR editor, edit/remove affordances, hashtag-link creation, and
  per-account JSON persistence. OR filters page with the same `CompositeCursor`
  shape as macOS: the core carries one cursor per subquery, skips exhausted
  subqueries, and merges each page newest-first ([[filters]]).
- Author pages open in the detail pane: avatar taps in feeds and conversations
  derive the actor DID from the post AT-URI, notification actors open by handle,
  and `AuthorView` renders a profile header over a reused feed loaded through
  `AuthorFeedLoadAsync` / `ProfileAsync` ([[author-tab]]).
- Timeline rows support the Windows parity shortcuts: j/k focus, n compose,
  f toggles like, o opens the focused post's bsky.app permalink, and the link
  action copies that permalink to the clipboard. Conversation focus rows support
  f/o/copy too ([[timeline-streaming]]).
- Feed rows render external link preview cards in the X-style large layout (hero
  image, bold title, grey description, host line). A post's own
  `app.bsky.embed.external` card comes through `PostDisplayDTO.linkCard`; a bare
  link in a text-only post resolves its OGP preview lazily via `OgpLoadAsync`
  (the core's `LinkPreviewLoader` / `Ogp`), cached per URL ([[timeline-streaming]]).
- The feed groups same-thread posts web-style: after each load the timeline sends
  every post's id / author DID / createdAt / reply-parent id to `FeedArrangeAsync`
  (the core's `FeedThreading.Arrange`) and reorders the rows in place
  with `Move`, drawing a connector under the avatar, hiding the in-block reply
  marker, and dropping the in-block divider ([[timeline-streaming]]).
- The conversation view renders the focused post's descendant reply tree:
  `ThreadLoadAsync` returns the focus + tree from the core's
  `ThreadNode.ChildTree(maxDepth: 3)`, and each reply is indented by depth
  with a left connector; the parent and each reply re-anchor the detail pane on
  that post, as on macOS. The focused post has a reply button, since the feed's
  reply count opens the conversation ([[timeline-streaming]], [[app-shell]]).
- The shell is multi-window: `Ctrl+Shift+N` opens another independent workspace
  window, the analogue of a macOS `WindowGroup` window. Only the primary window
  owns the updater, notification polling and OS toasts; every window keeps its
  own tabs, detail pane and account client ([[app-shell]]).
- The app runs as a single process (issue #20). Every process shares the DPAPI
  account store, but refresh coalescing and compare-and-save hold only inside one
  process (`Core/Accounts/AccountState.cs`), so a second process could write back a
  used refresh token and the next refresh would fail with `invalid_grant`.
  `App/Program.cs` replaces the XAML-generated `Main` (`DISABLE_XAML_GENERATED_MAIN`)
  and registers the Windows App SDK `AppInstance` key `main`. A second launch,
  direct or through the `YoruMimizuku.exe` launcher, redirects its activation to the
  running instance and exits before it touches the store; the running instance
  brings its last active window to the front, restoring it if minimized
  (`MainWindow.BringToFront`). `Ctrl+Shift+N` windows stay in the one process. The
  Windows App SDK scopes the key to the exe's path in the user's session, so a copy
  at another path (a second unzipped build, or a Debug build beside the installed
  app) still starts its own process and can race on the store.
- v1 embed parity in feed rows (the core's `PostDisplay` maps these into
  `PostDisplayDTO`): a **quote card** for
  `app.bsky.embed.record` / `recordWithMedia` (author line, body, thumbnails /
  video poster) that opens the quoted conversation; a **video poster** with a
  play badge that opens the post in the browser; and a **sensitive-media curtain**
  that covers (not blurs — no cheap WinUI subtree blur) labelled adult/graphic
  media until tapped ([[timeline-streaming]], [[sensitive-media]]).
- **Delete own post**: rows whose post AT-URI repo DID equals the account DID show
  a 削除 action that confirms, optimistically prunes, and calls `DeletePostAsync`
  (restoring on failure) ([[timeline-streaming]]).
- **Classified load failures**: `CoreException` carries the core's
  `LoadFailure` kind + friendly title/message, so a failed first load shows a
  titled offline / rate-limited / server / unknown message with a 再試行 button
  ([[timeline-streaming]]).
- **Notification settings**: a 通知 settings section picks the poll interval
  (15/30/60/300s) and toggles the unread badge, persisted in `AppSettings` under
  the same keys as the macOS store and applied live to the timer and tab badge
  ([[notifications]]).
- The notifications navigation row has a local unread badge driven by 30-second
  polling and cleared when the tab becomes active. When that poll raises the
  unread count, the app now also shows an OS toast via the Windows App SDK
  `AppNotificationManager` and flashes the taskbar with `FlashWindowEx`
  (`Services/NotificationAlerts.cs`). A persistent numeric taskbar badge still
  needs packaged (MSIX) identity, so the in-app tab badge carries the count
  meanwhile ([[notifications]]).
- Windows update checks use WinSparkle in the WinUI app layer, not the macOS
  Sparkle framework. The settings view exposes version/channel/automatic-check
  controls and a manual check button; the service stays disabled while the
  Windows EdDSA public key placeholder is present. `release.ps1 -Installer` can
  build an Inno Setup installer EXE and, when given the WinSparkle private key,
  generate `appcast-windows*.xml` for GitHub Pages / GitHub Releases hosting
  ([[auto-updates]]).
- **Timeline media layout**: a single image is capped at 5:4 with a top-anchored
  crop and a 全体表示 badge, and a row 680 wide or more moves its images, video
  and link card into a 300-wide rail on the right, using the C# port of
  `TimelineLayout` ([[timeline-media-layout]]).
- **Copy-link toast and mention links**: copying a permalink shows a
  「リンクをコピーしました」 pill in that window only (`Services/ToastCenter.cs`
  tags each message with its `XamlRoot`, since the shell is multi-window), and a
  feed body's `@mention` opens the account in the detail pane; the conversation view
  still renders bodies as plain text ([[timeline-streaming]]).
- **Video posts and draft protection**: the composer attaches one video
  (`.mp4` / `.m4v` / `.mov`, exclusive with images, with alt text), which the C#
  `PostService` uploads through the Bluesky video service with a PDS service-auth
  token; closing a draft with unsaved text or media asks first, and the dialog
  cannot close while a post is submitting ([[compose-post]]).
- The feed's repost button opens a `MenuFlyout` with **リポスト** (toggle) and
  **引用** (quote): choosing 引用 opens `ComposerDialog` with the post's
  `(uri, cid)` as the quote target plus a read-only preview, matching the macOS
  repost/quote popover ([[compose-post]]).
- **OAuth via WebView2** (the Windows counterpart to macOS's
  `ASWebAuthenticationSession`, [[oauth-flow]]): `LoginBeginAsync` returns the
  authorize URL, the app loads it in an embedded `WebView2`, intercepts the
  `as.ason:` redirect, and calls `LoginCompleteAsync` to finish the token
  exchange — no custom URI-scheme registration needed.
- **Relative timestamps** are formatted by `Services/RelativeTime.cs`, deliberately
  mirroring the Swift `RelativeTimeFormatter` ("now" / "30s" / "2m" / "3h" / "2d")
  so the Windows timeline reads like the macOS one ([[timeline-streaming]]). The
  window / taskbar icon is set by `Services/AppIcon.cs` from a bundled `.ico`
  generated off the shared macOS owl icon.
- Theme (randoma11y / monochrome), display density, and font size persist to a JSON
  file (not `ApplicationData.Current`, which is unavailable to an unpackaged app).
- **Window size/placement persistence**: macOS restores the window frame for free via
  SwiftUI `WindowGroup` scene restoration; WinUI 3 has no equivalent. `Services/WindowPlacement.cs`
  P/Invokes Win32 `GetWindowPlacement` / `SetWindowPlacement` to capture the normal
  position, size, and maximized state on window close (stored in `AppSettings` under
  `windowPlacement` as `"showCmd,left,top,right,bottom"`) and reapply it on the next
  launch. The earlier width-only `AppWindow.Resize` never stuck because the first
  `Activate` applies WinUI's default size and overwrites a pre-Activate resize (and it
  mixed DPI units — `AppWindow.Size` is physical px, `WindowSizeChanged` is DIPs), so
  the placement is reapplied **after** `Activate`; capture and restore share the
  `WINDOWPLACEMENT` coordinate space, making the round-trip DPI-consistent ([[app-shell]]).
- Targets **.NET 10** + **Windows App SDK 2.1.3**, framework-dependent
  (`SelfContained=false` + `WindowsAppSDKSelfContained=false`): the .NET 10 Desktop
  and Windows App SDK runtimes are kept out of the build (the user installs both
  once). On a missing runtime the app prompts on first run — the .NET apphost shows
  a download dialog, and `WindowsAppSDKBootstrapAutoInitializeOptions_OnNoMatch_ShowUI`
  makes the Windows App SDK bootstrapper prompt for the Windows App Runtime. This
  was chosen over self-contained to fit the distribution under the Tangled artifact
  size limit (see Distribution).

## Build (Windows)

.NET 10 SDK + Visual Studio with the Windows App SDK / WinUI 3 component (the C++
workload only for `release.ps1`'s launcher). Helpers under `scripts/windows/`
(`apps/windows/README.md`):

```powershell
scripts\windows\build-app.ps1        # stop running instance, build framework-dependent x64, print the exe
scripts\windows\test.ps1             # dotnet test Core.Tests and Interop.Tests
scripts\windows\make-appicon.ps1     # regenerate App/Assets/AppIcon.ico from the shared macOS owl PNG
scripts\windows\ci.ps1               # test.ps1, then dotnet build
```

## Distribution

`scripts\windows\release.ps1` publishes the app (**.NET 10** + **Windows App SDK
2.1.3**) **framework-dependent** for `win-x64` (neither the .NET 10 Desktop runtime
nor the Windows App SDK runtime is bundled), lays out a small top-level
`YoruMimizuku.exe` launcher plus an `app/` payload directory (the app, `YoruMimizuku.Core.dll`,
`YoruMimizuku.App.Interop.dll`, and the remaining dependency DLLs), and zips it into
`build/`. It also strips the Windows ML / AI stack that Windows App SDK 2.x bundles
by default (`onnxruntime.dll`, `DirectML.dll`, the `AI.MachineLearning` projection —
~16 MB zipped) since the app uses no ML APIs and there is no supported opt-out
(microsoft/WindowsAppSDK#5969). Dropping the two bundled runtimes, the ML stack and the
former Swift runtime brings the ZIP to **~12 MB** (`release.ps1`), so it fits as a
Tangled tag artifact, which is stored as an atproto blob (default PDS
blob limit ~50 MB; a 60 MB self-contained build was rejected). The trade-off is that
the user installs the **.NET 10 Desktop Runtime** and the **Windows App Runtime 2.1**
once (plus the Edge WebView2 runtime for OAuth); the app prompts and links to the
downloads on first run if any is missing. The macOS side ships a
signed + notarized DMG; the Windows analogue is this ZIP today, with MSIX as the
eventual installable form. Code signing is decoupled (optional `-Thumbprint` /
`-CertPath` on `release.ps1`): the launcher + app binaries are signed before
zipping; unsigned builds get a one-time SmartScreen prompt, and Windows has no
free notarization equivalent to macOS — a trusted signature needs a paid (or
free-for-OSS) Authenticode cert, deferred for now. For auto-updates, the same
script can additionally build and sign an installer EXE (`-Installer`) and emit a
WinSparkle appcast (`-WinSparklePrivateKey`, `-Channel stable|development`) whose
enclosure URL targets GitHub Releases. The installer removes the Swift DLLs that
builds up to 0.8.x installed (`scripts/windows/installer.iss`).

## Resolved / open questions

- **MSIX packaging** for distribution remains future work; development runs unpackaged.
