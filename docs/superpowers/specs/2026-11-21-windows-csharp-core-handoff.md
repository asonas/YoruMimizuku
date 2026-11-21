# Windows: Replace the Swift Core with C# (Handoff)

- Date: 2026-11-21
- Status: Approved 2026-11-21 (approach B, OAuth ported by hand).
- Audience: the agent developing YoruMimizuku on the Windows machine.
- Target: `apps/windows` (WinUI 3 / C#), `scripts/windows`, and the Windows-only targets in `core/Package.swift` (`PlatformWindows`, `YoruMimizukuBridge`)
- Builds on: `2026-06-05-windows-multiplatform-structure.md`

## 1. Where things stand

Windows users have a working client: OAuth sign-in in WebView2, home timeline, author pages, threads, notifications with toasts, saved filters, composing with images, and multi-window. `docs/wiki/platforms/windows.md` describes it as built.

It runs on the Swift core. `BlueskyCore` (4,256 lines) and `YoruMimizukuKit` (4,435) are compiled for Windows; `YoruMimizukuBridge` (1,132 lines, 26 `@_cdecl` functions) exposes them to C# as UTF-8 JSON in, JSON out; `PlatformWindows` supplies DPAPI storage and `BCryptGenRandom`. The WinUI app (5,048 lines of C# and XAML) reaches the core only through `apps/windows/App/Interop/BridgeClient.cs`. Some logic is already C#: relative time (`Services/RelativeTime.cs`) and the view models' state handling.

Nothing under `apps/windows` or the bridge has changed since 2026-06-23 (`ac3ade5`), while the shared core and macOS kept changing (the 2026-11-20 redesign, §6 Phase 7). The last shipped Windows build and a build of today's `main` may therefore behave differently.

## 2. Why reconsider the Swift core

Every feature crosses three layers: Swift logic, a bridge endpoint with hand-written DTOs, and a C# DTO plus view model. The costs that showed up:

- Each macOS feature in `YoruMimizukuKit` (saved feeds, list membership, the detail pane) needs a bridge endpoint before Windows can use it.
- The JSON boundary has its own bugs: request dates must not be ISO8601 strings because the bridge decodes them with `deferredToDate`, which once made saved-filter searches return nothing silently.
- Async Swift is made synchronous with a semaphore per call, and C# wraps each call in `Task.Run`.
- Building needs the Swift toolchain for Windows alongside .NET (`Enter-SwiftEnv.ps1`, `stage-bridge.ps1`), and a failure can sit in either runtime.

Coding agents now port well-specified logic quickly, and the Swift core has 96 test files that state its behavior, so writing the core twice costs less than it did, while the bridge's cost stays.

## 3. Approaches

| | Approach | For | Against |
|---|---|---|---|
| A | Keep the Swift core and the bridge | Logic written once; already works | Every feature crosses three layers; two toolchains; the JSON boundary bugs; Windows keeps trailing |
| **B** | **A C# core behind the existing `BridgeClient` surface, keeping the WinUI app** (recommended) | One language and toolchain on Windows; idiomatic `async`; one debugger | Two cores to keep in step; OAuth and DPoP must be right again |
| C | B, with OAuth/DPoP from a .NET AT Protocol library | Less security code to own | Unproven for this app (below) |
| D | A cross-platform UI (Avalonia, Uno, Flutter, Tauri) | Possibly one UI for more platforms | Rewrites the working WinUI UI; Tauri and Flutter work against the memory-efficient native goal; macOS stays SwiftUI |
| E | Move the shared core to another language (Rust, Kotlin Multiplatform) | Still one core | Forces a macOS rewrite for a Windows problem |

**Chosen: B, with OAuth ported by hand (not C).** Display mapping, grouping and filters are this app's own logic and are ported to C#. For OAuth, the candidates are ATProtoNet (its package page claims DPoP, PAR and PKCE), FishyFlip (`OAuth2SessionManager` has DPoP settings) and idunno (its DPoP documentation targets ASP.NET). None has been checked against this app's needs: the native redirect `as.ason:/callback`, the two-step login through WebView2, a DPoP key restored from DPAPI, and refresh after a relaunch. D and E were not chosen.

## 4. What stays shared when code is not

- **Behavior:** the wiki (`docs/wiki/behaviors/`, and the platform differences in `docs/wiki/support-matrix.md`) and the specs in `docs/superpowers/specs/`. Update the wiki when Windows behavior changes, as AGENTS.md requires.
- **Visual design:** the desktop prototype (Lenses) is the visual source of truth for both platforms. Read it from Figma file `LzPa70A5H3MKkdPrsAnjKu` (its HTML is not in this repository); the macOS app implements it. Color tokens: `core/Sources/YoruMimizukuKit/DesignTokens.swift`; spacing: `DesignMetrics.swift`; icons: `design/icons` (SVG; ship `LICENSE-lucide.txt` with the app).
- **OAuth client:** the public client metadata in `docs/client-metadata.json` (`client_id` `https://ason.as/yorumimizuku/client-metadata.json`, redirect `as.ason:/callback`).
- **Settings keys:** `AppSettings` uses the macOS keys; keep them.

## 5. Acceptance lists

**Parity cases.** Record each on the last shipped Windows build and on a build of current `main` in Phase 0; the C# core must match (or a deliberate difference is noted):

- Home timeline first page and the next page; author page; a thread with ancestors and a reply-to-a-reply.
- Like and repost notifications show the subject post's text and thumbnail (the core deduplicates subject URIs and batches `getPosts` after grouping).
- Posting: a reply (the conversation root comes from the parent record), a quote, images with alt text, a mention (resolved to a DID) and Japanese text with links (facet byte offsets).
- A labelled sensitive image starts covered.
- An OR filter loads its next page (one cursor per subquery).
- With two windows on two accounts, switching accounts in one window, a post or like from the other window still goes to that window's account.

**OAuth and accounts** (for the hand port and for any library alike):

- The callback's `state` and `iss` match the request and the issuer; the token response's `sub` equals the DID resolved at login start; a token without the `atproto` scope is rejected. The Swift core does not check `iss`, `sub` or the scope today: add these to the C# port and report them to the user so macOS gets the same fix.
- DPoP proofs with nonce retry; refresh happens once per account even when, say, the home timeline and notifications get 401 at the same time across services; the rotated token is saved before the retried request (as `XRPCQueryService` does), and a late, older response never overwrites it.
- Sign in, relaunch and stay signed in, switch accounts, sign out.

## 6. Plan

Each phase ends in a check on Windows before the next starts.

**Phase 0. Baseline.** Build the current app (`apps/windows/README.md`), run it, and record the parity cases on the last shipped build and on `main`. Note what is already broken, so it is not blamed on the port.

**Phase 1. Seam.** Put an interface where `BridgeClient` is, keeping its DTOs, but scope it to an account: a window gets a client for its own DID, or each operation takes the DID. Today `ComposerViewModel` calls `BridgeClient.Shared.PostCreateAsync` and the bridge uses whichever account is current, which breaks the two-window parity case. `BridgeClient` implements the interface, the app depends on it, and a setting available only in Debug builds chooses the implementation until Phase 5. Check: the parity cases as in Phase 0, plus the two-window case fixed.

**Phase 2. C# core library.** A class library (for example `apps/windows/Core`) with an xUnit project. Port in this order, translating the Swift tests that cover each part (same names under `core/Tests/BlueskyCoreTests` and `YoruMimizukuKitTests`):

1. XRPC models and decoding (`*ResponseTests`), `ATURI`, `PostText`, rich text segments and facet detection.
2. Display mapping: `PostDisplay`, notification grouping and subject hydration, the `ThreadNode` child tree, `FeedThreading.arrange`, `LoadFailure`.
3. Filters: `SavedFilter`, the search merge and the composite cursor.
4. Services over one `HttpClient` per account: timeline, author feed, thread, notifications, search, posts (create with reply root and mention resolution, delete, like, repost, image upload), profile, OGP.

Do not port what C# already does (relative time) or what the view models already own; apply the Swift regression cases (`TimelineViewModelTests`, `NotificationsViewModelTests`, `NotificationPipelineRegressionTests`) to the existing C# view models instead. `FeedThreading.arrange` groups a self-thread only when parent and child share an author, but the bridge sends no authors, so Windows groups other people's replies too; pass the author in the port and record the change. Check: `dotnet test`.

**Phase 3. OAuth and accounts.** Port `BlueskyCore`'s OAuth (identity resolution, metadata discovery, PKCE, PAR, DPoP with ECDSA P-256 from `System.Security.Cryptography`, refresh) and its tests. Store accounts with DPAPI (`ProtectedData`). Tokens and the DPoP private key never go to logs or the repository (AGENTS.md, Publishing Policy). Check: the OAuth list, with the Debug setting pointing sign-in and account operations at the C# core.

**Phase 4. Existing accounts.** Existing users sign in again after the switch; the Swift store (`accounts.index` and `account.<did>` as DPAPI `.bin` files under Application Support `as.ason.YoruMimizuku/secure`) is not read. Use a different storage location so the old files are never misread, delete them on first launch, and tell the user once why they are signed out. Check on one Windows user: install the last shipped build, sign in, install the new build over it, see the message, sign in again, and confirm each account's saved filters come back (they are keyed by DID, so they should).

**Phase 5. Switch.** Point the app at the C# core, feature group by feature group, each checked against its parity cases. When all pass, remove the Debug setting, the native path (`Interop/NativeMethods.cs`), the Swift scripts (`Enter-SwiftEnv.ps1`, `stage-bridge.ps1` and the Swift steps in the other `scripts/windows/*.ps1`), and the `native\**\*.dll` content item in `YoruMimizuku.App.csproj`. Check: the ZIP from `release.ps1` and the `-Installer` EXE both run for a clean Windows user, the installer updates an existing installation, and neither contains a Swift DLL.

**Phase 6. Remove the Windows targets from the Swift core:** delete `PlatformWindows`, `YoruMimizukuBridge` and their tests from `core/Package.swift`, and ask the user to run `swift test` in `core` and the macOS build on the Mac. Update the wiki (`docs/wiki/platforms/windows.md`, `architecture.md`, `overview.md`).

**Phase 7. Catch up with macOS.** Bring the 2026-11-20 redesign to Windows with these specs and the prototype, one spec at a time; each is done when its behavior page in the wiki holds on Windows and the screen matches the prototype:

- `2026-11-20-macos-three-pane-design.md` (sidebar, timeline, detail pane)
- `2026-11-20-macos-saved-feeds-sidebar-design.md` (pinned feeds and lists)
- `2026-11-20-macos-commands-and-lists-design.md` (search, shortcuts, list membership, drag to add)
- `2026-11-20-macos-prototype-colors-design.md` (light and dark tokens)
- `2026-11-20-macos-prototype-chrome-design.md`, `-rows-design.md`, `-detail-pane-design.md`
- `2026-11-20-macos-svg-icons-design.md` (the shared icons)

Map macOS conventions (menu bar, ⌘ shortcuts) to Windows ones (Ctrl, the window's command bar) rather than copying them.

## 7. Things to know

- **Updates.** WinSparkle is wired but off: `UpdateService` returns early while its public key is a placeholder. Turning it on (a key pair and a Windows appcast) is a separate decision, not part of this work.
- **Known Swift core gaps, not to copy.** An old 401 response can roll back a refresh token, and the timeline cursor is not escaped for `+`. Fix them in C# and tell the user.
- **Workflow.** Follow AGENTS.md: a worktree per piece of work, TDD one step at a time, English commit messages, the wiki updated with `wiki-update`. YoruMimizuku has no pull requests: when a phase's work is done, report it and fast-forward `main` and push only after the user approves that merge.

## 8. Decisions

Made by the user on 2026-11-21:

- Approach B: a C# core behind the `BridgeClient` surface; the WinUI app stays.
- Existing Windows users may be asked to sign in again (Phase 4).
- The Swift core becomes Apple-only (Phase 6).
- The prototype is read from Figma.
- OAuth and accounts are ported by hand from `BlueskyCore` (Phase 3), not taken from a .NET AT Protocol library.
