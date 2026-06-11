---
title: Auto Updates (Sparkle)
type: behavior
updated: 2026-06-11
sources:
  - docs/superpowers/specs/2026-06-08-yorumimizuku-sparkle-auto-update-design.md
  - docs/superpowers/plans/2026-06-09-yorumimizuku-sparkle-auto-update.md
  - apps/macos/AppDelegate.swift
  - https://sparkle-project.org/documentation/customization/
  - https://sparkle-project.github.io/documentation/gentle-reminders
features:
  - name: Sparkle auto-update checks and install
    macos: full
    windows: none
    ios: none
    android: none
    note: "Sparkle auto-update is macOS-only; Windows/iPadOS/Android need separate updater mechanisms if they ever gain auto-update support ([[macos]], [[windows]], [[ipados]])."
---

# Auto Updates (Sparkle)

YoruMimizuku's macOS auto-update path uses Sparkle 2. Sparkle is
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
tab exposes "今すぐ確認", a toggle for Sparkle's `automaticallyChecksForUpdates`
preference, and a channel picker for **リリース** versus **開発版**
(`2026-06-08-yorumimizuku-sparkle-auto-update-design.md` §Architecture,
§Sparkle configuration).

Status as of 2026-06-09: the app-side Sparkle wiring, settings UI, stable/dev
channel selection, EdDSA key setup, GitHub Pages appcasts, GitHub prerelease ZIP,
a development-channel update test (`v0.7.0-dev.1` → `v0.7.0-dev.2`), and the
stable production release flow (`v0.7.0` ZIP/DMG plus `appcast.xml`) have landed.

## App-side architecture

The implementation plan centers on a macOS-only `UpdateController` that owns
`SPUStandardUpdaterController` and is injected into the SwiftUI environment from
`YoruMimizukuApp`. `UpdateController` publishes `updateAvailable`,
`canCheckForUpdates`, `automaticallyChecksForUpdates`, and the selected
`UpdateChannel`; the sidebar gear reads `updateAvailable`, while the update
settings tab drives manual checks, the automatic-check toggle, and
stable/development channel selection (`2026-06-08-yorumimizuku-sparkle-auto-update-design.md`
§Architecture, `2026-06-09-yorumimizuku-sparkle-auto-update.md` Task 3).

The Sparkle-free state machine, version formatting, and channel persistence live
in small value/store types (`UpdateBadgeState`, `UpdateChannel`,
`UpdateChannelStore`) so they can be unit-tested without loading Sparkle. Sparkle
delegate glue stays thin and remains in the macOS app layer
(`2026-06-08-yorumimizuku-sparkle-auto-update-design.md` §Testing strategy).

Channel switching uses two appcast URLs rather than Sparkle's single-feed channel
tags. `SUFeedURL` remains the stable default, and `SPUUpdaterDelegate` supplies
the selected feed URL at runtime. The stable feed is
`https://asonas.github.io/YoruMimizuku/appcast.xml`; the development feed is
`https://asonas.github.io/YoruMimizuku/appcast-dev.xml`. Development releases use
tags like `v0.7.0-dev.1` and GitHub prereleases. Sparkle does not downgrade, so a
user who installs a development build and switches back to the stable channel
will not receive a stable update until the stable build number is greater than
the installed development build; immediate rollback is a manual reinstall.

For gentle reminders, the standard user driver delegate declares support for
gentle scheduled update reminders and returns `false` from
`standardUserDriverShouldHandleShowingScheduledUpdate(_:andInImmediateFocus:)`
when the app wants to handle a scheduled update non-modally. Sparkle documents
that returning `false` makes the delegate responsible for showing the reminder,
which in this app means setting the gear dot until the user interacts with the
update session (Sparkle gentle reminders documentation).

## Quit handling for "Install and Restart"

Sparkle terminates the app by sending a quit Apple event — never a force kill —
and waits for the process to exit before swapping the bundle and relaunching.
With the SwiftUI life cycle, AppKit cancels that event with `userCanceledErr`
whenever any window has a presented sheet, and the update UI lives inside the
settings sheet, so "Install and Restart" always arrived in exactly that state:
the app never quit, Sparkle silently waited, and the update only installed on
the next manual quit. The app therefore installs its own `kAEQuitApplication`
handler (`AppDelegate`, wired via `@NSApplicationDelegateAdaptor`): it ends every
attached sheet and re-enters `NSApp.terminate` on the next run-loop turn. The
behavior was verified with a minimal WindowGroup reproduction — the default
handler cancels while a sheet is up, `applicationShouldTerminate` is never
reached, and a synchronous terminate is still swallowed until the sheet has been
ended (`apps/macos/AppDelegate.swift`).

## Release and appcast

The appcasts are hosted on GitHub Pages from the `gh-pages` branch. Stable uses
`appcast.xml`; development uses `appcast-dev.xml`. Stable release tags
(`v0.6.0`, `v0.7.0`) upload a notarized/stapled `.app` ZIP for Sparkle and a
signed/notarized/stapled DMG for first-time manual downloads. Development tags
(`v0.7.0-dev.1`, `v0.7.0-dev.2`) upload the Sparkle ZIP to GitHub prereleases and
update `appcast-dev.xml` (`2026-06-08-yorumimizuku-sparkle-auto-update-design.md`
§Hosting & appcast).

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
