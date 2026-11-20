# Windows: Replace the Swift Core with C# (Handoff)

- Date: 2026-11-21
- Status: Proposed. The approach in §3 is the recommendation; the user confirms it (and the open decisions in §7) before Phase 2 starts.
- Audience: the agent developing YoruMimizuku on the Windows machine.
- Target: `apps/windows` (WinUI 3 / C#), `scripts/windows`, and the Windows-only targets in `core/Package.swift` (`PlatformWindows`, `YoruMimizukuBridge`)
- Builds on: `2026-06-05-windows-multiplatform-structure.md`

## 1. Where things stand

Windows users have a working client: OAuth sign-in in WebView2, home timeline, author pages, threads, notifications with toasts, saved filters, composing with images, multi-window, and WinSparkle updates (`docs/wiki/platforms/windows.md` describes all of it as built).

It runs on the Swift core. `BlueskyCore` (about 4,300 lines) and `YoruMimizukuKit` (about 4,400) are compiled for Windows. `YoruMimizukuBridge` (about 1,100 lines, 26 `@_cdecl` functions) exposes them to C# as UTF-8 JSON in, JSON out. `PlatformWindows` supplies DPAPI storage and `BCryptGenRandom`. The WinUI app (about 5,000 lines of C# and XAML) talks only to `apps/windows/App/Interop/BridgeClient.cs`.

Nothing under `apps/windows` or the bridge has changed since 2026-06-23 (`Bump app version to 1.0.0-dev.12`). Since then macOS was redesigned (the 2026-11-20 specs listed in §5, Phase 5), so Windows now trails macOS in features and looks.

## 2. Why reconsider the Swift core

The bridge made sense when the goal was to write the protocol logic once. In practice every feature crosses three layers: Swift logic in the core, a bridge endpoint with hand-written DTOs, and a C# DTO plus view model. The costs that showed up:

- Each new macOS feature that lives in `YoruMimizukuKit` (saved feeds, list membership, the detail pane) needs a new bridge endpoint before Windows can use it.
- The JSON boundary has its own bugs. Request dates must not be ISO8601 strings because the bridge decodes them with `deferredToDate`; this once made saved-filter searches return nothing silently.
- Async Swift is turned synchronous with a semaphore per call, and C# wraps each call in `Task.Run`.
- Building needs the Swift toolchain for Windows alongside .NET (`scripts/windows/Enter-SwiftEnv.ps1`, `stage-bridge.ps1`), and a failure can sit in either runtime.

Coding agents now port well-specified logic between languages quickly, and the Swift core comes with about 90 test files that state its behavior. Writing the core twice is cheaper than it was, while the bridge's cost stays.

## 3. Approaches

| | Approach | For | Against |
|---|---|---|---|
| A | Keep the Swift core and the bridge | Logic is written once; already works | Every feature crosses three layers; two toolchains; the JSON boundary bugs; Windows keeps trailing |
| **B** | **Port the core to C# by hand, keep the WinUI app** (recommended) | One language and toolchain on Windows; idiomatic `async`; one debugger; the Swift tests become the port's spec | Two implementations of the core to keep in step; OAuth/DPoP must be re-done correctly |
| C | C# core on a third-party .NET AT Protocol library | Less code to write | Maturity unverified. Of the libraries found (ATProtoNet, idunno.AtProto, FishyFlip), ATProtoNet's NuGet page claims OAuth with DPoP, PAR and PKCE; the others' DPoP support could not be confirmed by search. The app's mapping logic (display models, grouping, filters) still has to be ported. |
| D | A cross-platform UI (Avalonia, Uno, Flutter, Tauri) | Possibly one UI for more platforms | Rewrites the working WinUI UI; Tauri and Flutter work against the project's memory-efficient native goal; macOS stays SwiftUI anyway |
| E | Move the shared core to another language (Rust, Kotlin Multiplatform) | Still one core | Forces a macOS rewrite for a Windows problem |

**Recommendation: B.** Keep the WinUI app, view models and XAML as they are, put an interface where `BridgeClient` is, and implement it in a C# class library ported from the Swift core. Use C as a fallback only if a library is found, on the Windows machine, to pass the OAuth tests in Phase 3 unchanged; owning the OAuth code keeps it testable against the Swift tests. A and the remaining options are not recommended.

## 4. What stays shared when code is not

With two cores, consistency comes from shared specifications and data instead of shared code:

- **Behavior:** the wiki (`docs/wiki/behaviors/`) and the specs under `docs/superpowers/specs/` describe what each feature does. Port from these and from the Swift tests, and update the wiki when Windows behavior changes, as AGENTS.md requires.
- **Visual design:** the desktop prototype (Lenses) is the visual source of truth for both platforms. It is in Figma file `LzPa70A5H3MKkdPrsAnjKu`; its HTML is not in this repository. The macOS app (`apps/macos`) implements it and is the next best reference. The color tokens are in `core/Sources/YoruMimizukuKit/DesignTokens.swift`, the spacing in `DesignMetrics.swift`, and the icons in `design/icons` (SVG, with Lucide's license in `LICENSE-lucide.txt`, which must ship with the Windows app too).
- **OAuth client:** the same public client metadata (`docs/client-metadata.json`, `client_id` `https://ason.as/yorumimizuku/client-metadata.json`, redirect `as.ason:/callback`).
- **Settings keys:** `AppSettings` already uses the macOS keys; keep them.

## 5. Plan

Each phase ends in a check on Windows before the next starts.

**Phase 0. Baseline.** Build and run the current app with the existing scripts (`apps/windows/README.md`). Sign in, load the timeline, open a thread. Note anything already broken, so it is not blamed on the port later.

**Phase 1. Seam.** Extract an interface from `BridgeClient` with the same methods and DTOs (account, login begin/complete, timeline, author feed, thread, notifications, search, post create/delete, like/repost, permalink, avatar, profile, OGP, feed arrange). Make `BridgeClient` implement it and have the app depend on the interface. No behavior change. Check: the app runs as in Phase 0.

**Phase 2. C# core library.** A new class library (for example `apps/windows/Core`) with an xUnit test project. Port in this order, each with its Swift tests translated alongside (test names in `core/Tests/BlueskyCoreTests` and `core/Tests/YoruMimizukuKitTests` map one to one):

1. XRPC models and decoding (`*ResponseTests`), `ATURI`, `PostText`, `RichText` segments and facet detection.
2. Display mapping: `PostDisplay`, notification grouping, `ThreadNode` child tree, `FeedThreading.arrange`, `LoadFailure` classification, relative time.
3. Filters: `SavedFilter`, the search merge and the per-subquery composite cursor.
4. Services over an `HttpClient`: timeline, author feed, thread, notifications, search, posts (create, delete, like, repost, image upload), profile, OGP.

Check: the ported tests pass with `dotnet test`.

**Phase 3. OAuth and accounts.** Identity resolution (handle to DID to PDS), server metadata discovery, PKCE, PAR, DPoP proofs with ECDSA P-256 (`System.Security.Cryptography`), the DPoP nonce retry, token refresh guarded so concurrent requests refresh once (`RefreshGateTests`, `SessionRefresherTests`), and account storage with DPAPI (`ProtectedData`). This is the security-sensitive part. Port `OAuthClientTests`, `DPoP*Tests`, `PKCETests`, `AccountManagerTests` and `PersistedAccountTests` first and make them pass before wiring the UI. Tokens and the DPoP private key never go to logs or the repository (AGENTS.md, Publishing Policy). Check: sign in, relaunch and stay signed in, switch accounts, sign out.

**Phase 4. Switch and remove the bridge.** Implement the Phase 1 interface with the C# core and switch the app to it in one step. Once every screen from Phase 0 works, delete `BridgeClient`'s native path (`Interop/NativeMethods`), the bridge staging and Swift environment scripts, the Swift parts of `scripts/windows/*.ps1` and `release.ps1`, and the `PlatformWindows` and `YoruMimizukuBridge` targets from `core/Package.swift` with their tests. Confirm the macOS build and `swift test` in `core` still pass after the target removal (ask the user to run them on the Mac if needed). Update the wiki (`docs/wiki/platforms/windows.md`, `architecture.md`, `overview.md`). Check: a release build from `release.ps1` installs and runs on a clean user account.

**Phase 5. Catch up with macOS.** Bring the 2026-11-20 redesign to Windows natively, using these specs and the prototype (§4):

- `2026-11-20-macos-three-pane-design.md` (sidebar, timeline, detail pane)
- `2026-11-20-macos-saved-feeds-sidebar-design.md` (pinned feeds and lists)
- `2026-11-20-macos-commands-and-lists-design.md` (search, shortcuts, list membership, drag to add)
- `2026-11-20-macos-prototype-colors-design.md` (light and dark tokens)
- `2026-11-20-macos-prototype-chrome-design.md`, `-rows-design.md`, `-detail-pane-design.md`
- `2026-11-20-macos-svg-icons-design.md` (the shared icon set)

The macOS specs name platform conventions (menu bar, ⌘ shortcuts); map them to Windows conventions (Ctrl, the window's command bar) rather than copying them.

## 6. Things to know

- **Fixes already made in Swift.** The Swift core and view models carry fixes for races found in review: stale responses overwriting newer loads, list membership writes racing reads, the new-arrivals count, notification refresh ordering, muting during an in-flight fetch, and requests using the window's account rather than the active one. The corresponding Swift tests (`TimelineViewModelTests`, `ListMembershipModelTests`, `NotificationsViewModelTests`, `NotificationPipelineRegressionTests`) are the spec; port them, not just the happy paths.
- **Known gaps in the Swift core, not to copy.** An old 401 response can roll back a refresh token, and the timeline cursor is not escaped for `+`. Fix them in the C# port and tell the user, so macOS gets the same fix.
- **Existing Windows sign-ins.** Accounts are stored by the Swift `AccountManager` as JSON encrypted with DPAPI under Application Support (`core/Sources/PlatformWindows/DPAPISecureStorage.swift`). Reading that blob in C# keeps users signed in across the switch; otherwise they sign in once more (§7).
- **Workflow.** Follow AGENTS.md: a worktree per piece of work, TDD one step at a time, English commit messages, the wiki updated with `wiki-update`. YoruMimizuku has no pull requests; after the user confirms, fast-forward `main` and push.

## 7. Decisions for the user

1. Adopt approach B (port the core to C#), or stay with A.
2. If a third-party .NET AT Protocol library turns out to pass the OAuth tests, may it replace the hand port (approach C)?
3. On the switch, may existing Windows users be asked to sign in again, or must their stored accounts carry over?
4. May Phase 4 remove `PlatformWindows` and `YoruMimizukuBridge` from `core/Package.swift`, leaving the Swift core Apple-only?
5. How does the Windows agent see the prototype: Figma access on that machine, or the Lenses HTML committed to the repository?
