---
title: Timeline Media Layout (Tall-Image Crop and Wide-Column Reflow)
type: behavior
updated: 2026-06-24
sources:
  - docs/superpowers/specs/2026-06-23-timeline-image-reflow-design.md
  - docs/superpowers/plans/2026-06-23-timeline-image-reflow.md
  - docs/superpowers/specs/2026-06-24-yorumimizuku-ipados-parity-design.md
  - docs/superpowers/plans/2026-06-24-yorumimizuku-ipados-parity.md
  - core/Sources/YoruMimizukuKit/TimelineLayout.swift
  - apps/macos/Views/PostRowView.swift
  - apps/macos/Views/FeedView.swift
  - apps/ipados/Views/PostRowView.swift
  - apps/ipados/Views/TimelineListView.swift
features:
  - name: Tall-image crop (5:4 cap with top-anchor and "全体表示" hint)
    macos: full
    windows: none
    ios: full
    android: planned
    note: "The 5:4 crop and TimelineLayout helpers live in YoruMimizukuKit (platform-neutral); the SwiftUI view (PostRowView singleImage, tallCropHint overlay) is now implemented on both macOS and iPadOS. Windows renders images via the bridge DTO unchanged ([[windows]], [[ipados]])."
  - name: Wide-column reflow (body left / media right at ≥ 680 pt)
    macos: full
    windows: none
    ios: full
    android: planned
    note: "Reflow is driven by the feed column width injected into PostRowView — on macOS via FeedView and on iPadOS via TimelineListView (scene-width onGeometryChange). Windows uses a fixed-width XAML column that does not yet adapt to window width ([[windows]], [[ipados]])."
---

# Timeline Media Layout (Tall-Image Crop and Wide-Column Reflow)

This page documents two related layout improvements to the timeline post row landed in the `feature/timeline-image-reflow` branch: a height cap for tall single images, and a two-column reflow that activates when the feed column is wide enough. Both are described in `2026-06-23-timeline-image-reflow-design.md`.

## Problem

Before this feature, a single attached image was rendered at its natural aspect ratio, clamped only to the range [0.7, 5.0] (width / height). A portrait image (ratio below 0.7) could therefore produce a display height of up to `width / 0.7 ≈ 1.43 × width`, reaching ~628 pt on the comfortable-density column. Posts with tall images occupied disproportionate vertical space and made the timeline feel stretched (`2026-06-23-timeline-image-reflow-design.md` §背景と問題).

Separately, the feed column lacked a maximum width. Widening the window caused body text to reflow edge-to-edge while images remained left-aligned at their fixed width — the extra horizontal space was wasted.

## Tall-Image Crop (All Column Widths)

Single images are now capped at a **5:4 aspect ratio** (height ≤ 1.25 × width), which corresponds to a minimum `ratio` of `0.8` (width/height). Images wider than 5:4 display at their natural ratio, unchanged. The panorama upper cap of `5.0` is also unchanged.

When the natural ratio is below `0.8`, the image is clipped to the 5:4 box using a top-anchored `scaledToFill` layout (`.overlay(alignment: .top)` on a `Color.clear` aspect-ratio frame, then `.clipped()`). A bottom gradient overlay — a `LinearGradient` from `.clear` to `.black.opacity(0.5)` — combined with an `arrow.up.left.and.arrow.down.right` icon and "全体表示" label (`tallCropHint`) signals that the image continues below. The hint is shown **only when a crop actually occurred** (`TimelineLayout.isTallCropped`), so images that fit within 5:4 show no overlay (`2026-06-23-timeline-image-reflow-design.md` §A). Tapping the image opens the lightbox (`openLightbox(at:)`), which always shows the full uncropped image.

Multi-image grids (two-column, each tile at 140 pt, `cover` crop) are not affected by this change — they already cropped at a fixed height.

## Layout Dimensions and Helper (`TimelineLayout`)

All layout constants and pure computations live in `TimelineLayout` (`core/Sources/YoruMimizukuKit/TimelineLayout.swift`), a platform-neutral `enum` that uses `Double` (not `CGFloat`) so it is shared across macOS and Windows. The macOS `PostRowView` converts to `CGFloat` at each call site.

| Constant | Value | Purpose |
|---|---|---|
| `reflowThreshold` | 680 pt | Region width at which the row switches to two columns |
| `mediaRailWidth` | 300 pt | Fixed width of the right media rail in reflow mode |
| `columnGap` | 16 pt | Spacing between text column and media rail |
| `minSingleImageRatio` | 0.8 | Lower bound on the single-image aspect ratio (5:4) |
| `maxSingleImageRatio` | 5.0 | Upper bound (panorama clamp, unchanged) |

The key functions are: `placement(regionWidth:)` → `.vertical` or `.reflow`; `clampedSingleImageRatio(_:)` → clamped ratio; `isTallCropped(_:)` → whether the crop hint should show. All are covered by `TimelineLayoutTests` in `YoruMimizukuKitTests`. (There is no text-column-width helper: in reflow the body fills the remaining width, so no width math is needed beyond the placement decision.)

## Wide-Column Reflow (≥ 680 pt Region Width)

When the feed column is wide enough, the post row's content region reflows from a single vertical stack to two adjacent columns (`2026-06-23-timeline-image-reflow-design.md` §B):

- **Left column (text):** author line, body text, quote card, action bar. Fills the remaining width (no cap).
- **Right column (media rail):** single image / image grid, video poster, and link card. Fixed 300 pt, **pinned to the row's right edge**.
- **Gap:** fixed 16 pt between the two columns (`HStack` spacing).

Quote cards stay in the left (text) column in both layouts. The body column grows to fill the region while the media rail stays pinned to the right edge, so no trailing whitespace builds up on the right and the media never strands mid-row. The body's line length therefore grows with the window — accepted deliberately to avoid a right-hand gap (this supersedes the original design, which capped the text column at 620 pt, left-aligned the row, and left blank space on the right; the gap was disliked in a wide window, `2026-06-23-timeline-image-reflow-design.md` §決定事項).

The width that drives this decision is measured **once per feed layout pass** in `FeedView`, not in each row. `FeedView` stores `@State private var contentWidth: CGFloat = 0` and updates it via `.onGeometryChange(for: CGFloat.self)` on the `List` (available on macOS 15+, the app's deployment target). The measured width is passed as `PostRowView.contentWidth` to every row. `PostRowView.regionWidth(forContentWidth:)` subtracts the row's horizontal padding, avatar column width, and column spacing to get the region width that `TimelineLayout.placement` consumes (`2026-06-23-timeline-image-reflow-design.md` §幅の測定方針).

## Edge Cases

- **No `aspectRatio` on an image:** treated as 4:3 (existing fallback), which is wider than 5:4, so no crop is applied and no hint is shown.
- **Sensitive-media blur:** the `mediaSection` component wraps both images and video as before; the blur curtain (see [[sensitive-media]]) applies to the whole `mediaSection` regardless of whether it is in the vertical stack or the right rail.
- **Image grid in the 300 pt rail:** each tile in the two-column grid is approximately (300 − 5) / 2 ≈ 147 pt wide; the 140 pt fixed height is preserved.
- **Posts with no media:** the reflow branch is never taken if `mediaColumn` has nothing to render — the `vertical` path is a plain `VStack` and quote-only or text-only posts are unaffected.
