---
title: Sensitive Media Blur
type: behavior
updated: 2026-06-17
sources:
  - docs/superpowers/specs/2026-06-04-yorumimizuku-design.md
  - docs/superpowers/plans/2026-06-11-yorumimizuku-v1.0.0-roadmap.md
  - core/Sources/BlueskyCore/Models/Timeline.swift
  - core/Sources/YoruMimizukuKit/PostDisplay.swift
  - core/Sources/YoruMimizukuKit/PostDisplay+Mapping.swift
  - apps/macos/Views/PostRowView.swift
features:
  - name: Sensitive media blur (content labels)
    macos: full
    windows: none
    ios: none
    android: planned
    note: "macOS blurs media on posts carrying an adult (porn/sexual/nudity) or graphic (graphic-media/gore) label behind a tap-to-reveal curtain. Label decode and the MediaWarning mapping live in shared core, but only the macOS row gates the UI; Windows and iPadOS render media unblurred ([[windows]], [[ipados]])."
---

# Sensitive Media Blur

A post can carry content labels that mark its media as adult or graphic. macOS honors these by blurring the post's images and video poster behind a "閲覧注意" curtain until the viewer taps to reveal it. This is the minimal moderation behavior shipped for v1.0.0; the spec's fuller moderation work (per-user label preferences, account-level labels, hiding whole posts) stays deferred (`2026-06-04-yorumimizuku-design.md` §13, §14; `2026-06-11-yorumimizuku-v1.0.0-roadmap.md` §D).

## Where labels come from

The AppView surfaces two kinds of label on a post view's `labels` array (`com.atproto.label.defs#label`): the author's **self-labels** (declared on the `app.bsky.feed.post` record, re-emitted with the author DID as `src`) and **labeler labels** applied by moderation services. Both arrive on `PostView.labels` without the client subscribing to anything, so the default Bluesky moderation labeler and any self-declared adult flag are both visible. Each label carries a `val`, an optional `src`, and an optional `neg` that retracts a previously applied value (`Timeline.swift`, `Label`).

## How the warning is derived

`MediaWarning.from(labels:)` maps the labels to a display-layer warning (`PostDisplay.swift`). A value still in force (one whose `neg` is not true) is matched against two fixed sets:

- **adult** — `porn`, `sexual`, `nudity`
- **graphic** — `graphic-media`, and the legacy `gore`

If any adult value is in force the post is `.adult`; otherwise any graphic value makes it `.graphic`; otherwise the warning is nil. Adult takes precedence when both apply. The result is stored on `PostDisplay.mediaWarning` during feed/thread mapping (`PostDisplay+Mapping.swift`), so every surface that renders a `PostDisplay` (timeline, author tab, conversation) carries the same warning.

## The blur curtain (macOS)

When `mediaWarning` is non-nil and the viewer has not revealed the post, `PostRowView` blurs the combined image grid and video poster, clips it to a rounded rectangle, and overlays an `eye.slash` curtain labelled 閲覧注意 (センシティブ for `.adult`, 過激なメディア for `.graphic`) with a "タップで表示" hint. While blurred the media's own gestures (lightbox, open-video) are disabled so the first tap only reveals; after revealing, taps behave normally. The reveal is per-row local state, so a row that scrolls out of the recycled `List` and back re-blurs by default (`PostRowView.swift`).

## Deferred

The minimal version always blurs the known adult/graphic labels. It does not read the viewer's moderation preferences (`app.bsky.actor.getPreferences`), resolve subscribed labelers, honor a per-label hide/warn/show choice or the global adult-content toggle, hide whole posts, or blur account-level labels (e.g. a labelled avatar). Those belong to the fuller moderation feature deferred past v1.0.0.
