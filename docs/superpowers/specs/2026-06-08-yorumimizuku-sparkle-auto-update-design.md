# YoruMimizuku Sparkle Auto-Update Design

**Date:** 2026-06-08
**Status:** Approved (design); pending implementation plan
**Scope:** macOS app only (`apps/macos`). Windows is explicitly out of scope.

## Goal

Let the macOS app discover, present, and install new releases of itself using
[Sparkle 2](https://sparkle-project.org). A background check finds new versions;
instead of interrupting the user with a modal, the app marks the gear (settings)
icon with a small dot. The user installs from a new "アップデート" tab in the
existing settings sheet, which runs Sparkle's standard download → verify → in-place
replace → relaunch flow.

## Resolved decisions

These were settled during brainstorming and are fixed for this design:

1. **Framework:** Sparkle 2.x, added via SwiftPM to the `apps/macos` target.
2. **Automation level:** automatic background *check*, manual *install* (no silent
   install, no automatic download).
3. **Notification UX:** Sparkle "gentle reminder" — suppress the automatic modal for
   background-found updates; instead show a dot on the gear icon and let the user
   open the update from the settings sheet.
4. **Feed (appcast.xml) URL:** GitHub Pages, served from a dedicated `gh-pages`
   branch of the `YoruMimizuku` repo, at the permanent URL
   `https://asonas.github.io/YoruMimizuku/appcast.xml`.
5. **Binaries:** GitHub Releases attached to each `vX.Y.Z` tag. Two artifacts per
   release: a `.app` ZIP for Sparkle updates and a DMG for first-time manual
   download.
6. **Notarization target:** the `.app` (stapled), not the DMG, so the ZIP Sparkle
   ships contains an already-notarized, already-stapled app. The DMG is still built,
   signed, notarized, and stapled for the website/Releases download path.
7. **Signing key:** Sparkle EdDSA (ed25519). Public key in `Info.plist`; private key
   in the macOS Keychain, never committed.

## Why this placement

Sparkle depends on AppKit and is macOS-specific, so it must not enter `BlueskyCore`
(the platform-independent core) — the same boundary the image pipeline respects. All
update code lives in the `apps/macos` app layer. We deliberately do **not** introduce
a cross-platform "updater port" now (YAGNI); Windows would later use a different
mechanism (e.g. WinSparkle) behind its own surface. This is recorded in the wiki.

## Architecture

```
YoruMimizukuApp
  └─ creates UpdateController (ObservableObject), injects via .environmentObject
       ├─ wraps SPUStandardUpdaterController (Sparkle)
       ├─ conforms to SPUUpdaterDelegate + SPUStandardUserDriverDelegate
       └─ publishes: updateAvailable, canCheckForUpdates, automaticallyChecksForUpdates

SidebarView (gear button, line ~172)
  └─ overlays a small accent dot when updateController.updateAvailable

SettingsView
  └─ new SettingsTab .update → UpdateSettingsView
       ├─ current version (CFBundleShortVersionString + build)
       ├─ "今すぐ確認" → updateController.checkForUpdates()
       └─ "起動時に自動で確認" toggle ↔ automaticallyChecksForUpdates
```

### New / modified files

- **Create `apps/macos/Update/UpdateController.swift`** — the SwiftUI-facing wrapper
  around Sparkle. Owns `SPUStandardUpdaterController`. Conforms to `SPUUpdaterDelegate`
  and `SPUStandardUserDriverDelegate`. Marked `@MainActor`, an `ObservableObject`.
- **Create `apps/macos/Update/UpdateBadgeState.swift`** — a tiny, Sparkle-free value
  type holding the badge state machine and the version-string formatter, so the logic
  is unit-testable without Sparkle. `UpdateController` delegates to it.
- **Create `apps/macos/Views/UpdateSettingsView.swift`** — the settings tab body.
- **Modify `apps/macos/YoruMimizukuApp.swift`** — instantiate `UpdateController` and
  inject it as an environment object.
- **Modify `apps/macos/Views/SettingsView.swift`** — add `.update` to `SettingsTab`
  (title "アップデート", icon `arrow.down.circle`) and route it to `UpdateSettingsView`.
- **Modify `apps/macos/Views/SidebarView.swift`** — overlay the dot on the gear button
  when an update is available.
- **Modify `project.yml`** — add the Sparkle SPM package + dependency and the Sparkle
  `Info.plist` keys.

### UpdateController behavior

- Constructs `SPUStandardUpdaterController(startingUpdater: true, updaterDelegate:
  self, userDriverDelegate: self)`.
- `@Published var updateAvailable: Bool` — drives the gear dot.
- `@Published var canCheckForUpdates: Bool` — mirrors `updater.canCheckForUpdates`
  (observed) so the "今すぐ確認" button can disable while a check is in flight.
- `var automaticallyChecksForUpdates: Bool` — get/set forwarding to
  `updater.automaticallyChecksForUpdates`, used by the toggle.
- `func checkForUpdates()` — calls the standard controller, presenting Sparkle's
  normal UI. Used by the manual button and to surface a previously-found update.
- **Gentle-reminder hooks:**
  - `standardUserDriverShouldHandleShowingScheduledUpdate(_:andInImmediateFocus:)`
    returns `false` so a background-found update does not pop a modal.
  - On a background update being found, set `updateAvailable = true`.
  - When the update session finishes/dismisses or an install begins, set
    `updateAvailable = false`.

### Settings sheet & gear dot

The settings sheet already renders a left sidebar of `SettingsTab`s and a detail pane
(`SettingsView.swift`). We add one tab. The gear that opens the sheet lives in
`SidebarView` (`ChromeIconButton(systemImage: "gearshape", ...)`, line ~172); we wrap
it so an `overlay(alignment: .topTrailing)` draws a ~6pt `theme.accent` circle when
`updateController.updateAvailable` is true. Opening the settings sheet does **not**
itself clear the dot; the dot clears when the update is installed or the user dismisses
the Sparkle update session.

## Sparkle configuration

### SwiftPM

Add to `project.yml`:

- `packages.Sparkle`: `url: https://github.com/sparkle-project/Sparkle`, pinned to a
  `from: 2.x.y` version (exact version chosen in the plan).
- `targets.YoruMimizuku.dependencies`: `package: Sparkle, product: Sparkle`.

Sparkle embeds an `Autoupdate` helper and an XPC-free updater for non-sandboxed apps.
This app is **not** sandboxed (no `.entitlements`, Hardened Runtime on), so the simple
non-sandboxed setup applies. When Xcode re-signs the app it must also sign the embedded
`Sparkle.framework` (and its `XPCServices`, `Updater.app`, `Autoupdate`) with the same
Developer ID, Hardened Runtime, and a secure timestamp — Xcode does this automatically
for SPM-embedded frameworks; the plan verifies it post-archive.

### Info.plist keys (via `project.yml` `info.properties`)

| Key | Value |
|---|---|
| `SUFeedURL` | `https://asonas.github.io/YoruMimizuku/appcast.xml` |
| `SUPublicEDKey` | the ed25519 public key string from `generate_keys` |
| `SUEnableAutomaticChecks` | `true` |
| `SUScheduledCheckInterval` | `86400` (daily; explicit so the cadence is documented) |

`SUAutomaticallyUpdate` is left at its default (`false`) so installs stay manual.

## Hosting & appcast

- **Feed:** `appcast.xml` lives at the root of a dedicated `gh-pages` branch and is
  served at `https://asonas.github.io/YoruMimizuku/appcast.xml`. Keeping it on a
  separate branch isolates the feed from `docs/` and from app source. (One-time:
  enable GitHub Pages for the repo with source = `gh-pages` branch, root.)
- **Binaries:** each release tag `vX.Y.Z` gets a GitHub Release with:
  - `YoruMimizuku-X.Y.Z.zip` — the notarized/stapled `.app`, zipped (Sparkle enclosure).
  - `YoruMimizuku-X.Y.Z.dmg` — the notarized/stapled DMG (manual first download).
- The appcast `enclosure url` points at the stable GitHub Releases download URL of the
  ZIP (`https://github.com/asonas/YoruMimizuku/releases/download/vX.Y.Z/...zip`),
  produced with `generate_appcast --download-url-prefix`.

## Release pipeline changes (mise)

The current chain is `generate → archive → export → dmg(notarize DMG) → release`.
Notarization moves to the `.app`, and two new artifacts + the appcast are produced.
New env: a `SPARKLE_BIN` pointing at the directory holding Sparkle's CLI tools
(`generate_keys`, `sign_update`, `generate_appcast`), obtained via
`brew install --cask sparkle` or the Sparkle release archive (documented in README).

Reworked tasks (exact scripts in the implementation plan):

1. `generate` → `archive` → `export` — unchanged; yields a Developer ID-signed `.app`.
2. **`notarize-app`** (depends `export`) — zip the `.app`, `notarytool submit --wait`,
   then `stapler staple` the **`.app`** itself.
3. **`dmg`** (depends `notarize-app`) — build the DMG from the stapled `.app`, then
   `codesign` + `notarytool submit` + `stapler staple` the DMG (download path stays
   fully notarized).
4. **`sparkle-zip`** (depends `notarize-app`) — `ditto -c -k --keepParent` the stapled
   `.app` into `YoruMimizuku-<version>.zip`.
5. **`appcast`** (depends `sparkle-zip`) — `sign_update` the ZIP (Keychain key), then
   `generate_appcast` over the local archives dir with `--download-url-prefix` set to
   the GitHub Releases download base, producing `appcast.xml`.
6. **`publish`** (manual, depends nothing automatically) — `gh release create vX.Y.Z`
   (or `upload`) attaching the ZIP and DMG, then commit/push the regenerated
   `appcast.xml` to the `gh-pages` branch. Kept separate from the build chain because
   it performs outward-facing pushes.

The existing `bump` task is unchanged; release notes for each version are embedded by
`generate_appcast` from a per-version notes file (mechanism finalized in the plan).

## Key management & security (public repo)

- Generate the EdDSA key pair once with Sparkle's `generate_keys`. The **public** key
  goes into `Info.plist` (`SUPublicEDKey`) and is safe to publish. The **private** key
  is stored by Sparkle in the macOS Keychain and is **never** committed to git or
  written to logs — same rule as DPoP keys and OAuth tokens.
- `sign_update` reads the private key from the Keychain at release time.
- README/wiki gains a short "forking" note: a fork must run `generate_keys` to create
  its own pair and replace `SUPublicEDKey`, since it cannot sign updates with the
  upstream private key.

## Testing strategy

- **Unit tests (`UpdateBadgeState`):** the badge state machine — no update → found →
  cleared on install/dismiss — and the version-string formatter
  (`CFBundleShortVersionString` + build → display string). These are Sparkle-free and
  run under `xcodebuild test` for the app target (or pure logic moved where the test
  target can reach it).
- **Not unit-tested:** `SPUStandardUpdaterController` wiring, notarization, real
  download/replace — these are external dependencies. `UpdateController` keeps its
  Sparkle glue thin and pushes testable logic into `UpdateBadgeState`.
- **Manual acceptance:** publish a higher version to a *staging* appcast, run an older
  build, confirm: background check sets the gear dot (no modal) → open settings →
  アップデートタブ → "今すぐ確認"/install → app downloads, verifies signature, replaces
  itself, relaunches at the new version. Verify Gatekeeper accepts the replaced app
  offline (stapled).

## Out of scope / future

- Windows auto-update (would use WinSparkle or equivalent; separate spec).
- Release channels / beta feed (single stable channel for now).
- Delta updates (can be enabled later via `generate_appcast`; not required initially).
- Automatic (silent) install — intentionally excluded.
