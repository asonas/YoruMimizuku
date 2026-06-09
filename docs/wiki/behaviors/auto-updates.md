---
title: Auto Updates (Sparkle)
type: behavior
updated: 2026-06-09
sources:
  - docs/superpowers/specs/2026-06-08-yorumimizuku-sparkle-auto-update-design.md
  - docs/superpowers/plans/2026-06-09-yorumimizuku-sparkle-auto-update.md
  - https://sparkle-project.org/documentation/customization/
  - https://sparkle-project.github.io/documentation/gentle-reminders
features:
  - name: Sparkle auto-update checks and install
    macos: planned
    windows: none
    ios: none
    android: none
    note: "The approved Sparkle design is macOS-only; Windows/iPadOS/Android need separate updater mechanisms if they ever gain auto-update support ([[macos]], [[windows]], [[ipados]])."
---

# Auto Updates (Sparkle)

YoruMimizuku's planned macOS auto-update path uses Sparkle 2. Sparkle is
macOS/AppKit-specific, so the updater belongs in `apps/macos` and must not enter
`BlueskyCore`, `YoruMimizukuKit`, or the Windows/iPadOS front ends
(`2026-06-08-yorumimizuku-sparkle-auto-update-design.md` §Why this placement).

## User experience

The app should check for updates in the background but should not interrupt the
user with Sparkle's modal for scheduled checks. Instead, a small accent dot appears
on the settings gear when an update is available. The user opens the settings
sheet, switches to a new **アップデート** tab, and starts the normal Sparkle
download, signature verification, in-place replacement, and relaunch flow from
there (`2026-06-08-yorumimizuku-sparkle-auto-update-design.md` §Goal,
§Settings sheet & gear dot).

Manual installation remains the only install mode. `SUAutomaticallyUpdate` is not
enabled, so the app does not silently download or install updates. The settings
tab exposes "今すぐ確認" and a toggle for Sparkle's
`automaticallyChecksForUpdates` preference (`2026-06-08-yorumimizuku-sparkle-auto-update-design.md`
§Architecture, §Sparkle configuration).

## App-side architecture

The implementation plan centers on a macOS-only `UpdateController` that owns
`SPUStandardUpdaterController` and is injected into the SwiftUI environment from
`YoruMimizukuApp`. `UpdateController` publishes `updateAvailable`,
`canCheckForUpdates`, and `automaticallyChecksForUpdates`; the sidebar gear reads
`updateAvailable`, while the update settings tab drives manual checks and the
automatic-check toggle (`2026-06-08-yorumimizuku-sparkle-auto-update-design.md`
§Architecture, `2026-06-09-yorumimizuku-sparkle-auto-update.md` Task 3).

The Sparkle-free state machine and version formatting live in a separate
`UpdateBadgeState` value type so they can be unit-tested without loading Sparkle.
Sparkle delegate glue stays thin and remains in the macOS app layer
(`2026-06-08-yorumimizuku-sparkle-auto-update-design.md` §Testing strategy).

For gentle reminders, the standard user driver delegate declares support for
gentle scheduled update reminders and returns `false` from
`standardUserDriverShouldHandleShowingScheduledUpdate(_:andInImmediateFocus:)`
when the app wants to handle a scheduled update non-modally. Sparkle documents
that returning `false` makes the delegate responsible for showing the reminder,
which in this app means setting the gear dot until the user interacts with the
update session (Sparkle gentle reminders documentation).

## Release and appcast

The appcast is hosted on GitHub Pages from the `gh-pages` branch at
`https://asonas.github.io/YoruMimizuku/appcast.xml`. Each release tag uploads two
artifacts to GitHub Releases: a notarized/stapled `.app` ZIP for Sparkle and a
signed/notarized/stapled DMG for first-time manual downloads
(`2026-06-08-yorumimizuku-sparkle-auto-update-design.md` §Hosting & appcast).

The EdDSA public key is committed in the macOS app's generated Info.plist via
`SUPublicEDKey`; the private key stays in the macOS Keychain and is never
committed or logged. Forks must generate their own Sparkle key pair and replace
the public key, because they cannot sign updates with the upstream private key
(`2026-06-08-yorumimizuku-sparkle-auto-update-design.md` §Key management &
security).

The release task chain changes from DMG-only notarization to app-first
notarization: export a Developer ID `.app`, notarize and staple the `.app`, build
the DMG from that stapled app, create the Sparkle ZIP from that stapled app, sign
the ZIP with Sparkle's EdDSA key, then generate and publish `appcast.xml`
(`2026-06-08-yorumimizuku-sparkle-auto-update-design.md` §Release pipeline
changes).
