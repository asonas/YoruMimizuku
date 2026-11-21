---
status: accepted
---

# macOS Icons as Lucide SVGs

- Date: 2026-11-20
- Status: Implemented (PR 8 of the desktop UI update)
- Target: `design/icons` (SVG + JSON + Lucide's license), `tools/icons/lint.py`, `apps/macos` (`AppIcon`, every former SF Symbol), `apps/macosTests` (icons, snapshots); core, `apps/ipados` and `apps/windows` unchanged
- Builds on: `0022-macos-prototype-detail-pane.md`

## 1. Overview

The macOS app stops using SF Symbols. Its 53 icons are SVGs in `design/icons`,
so the Windows app can use the same shapes. The user asked for SVG for that
reason, drawn to Lucide's conventions (<https://lucide.dev/contribute/icons/>).

## 2. Decisions

- **Origin.** The first drawings turned out to repeat Lucide's coordinates for
  about 20 icons (a Codex review found `at-sign` and `rss` identical; a
  numeric comparison of all 53 found the rest). The user chose to use Lucide's
  originals for every icon Lucide has: 51 SVGs and their metadata are copied
  unchanged from Lucide revision `d79f705`, three of them under Lucide's names
  (`triangle-exclamation-point`, `cloud-exclamation-point`, `panel-left`).
  Lucide's ISC license, with the Feather MIT notice, is kept as
  `design/icons/LICENSE-lucide.txt`. `video-plus` is Lucide's `video` with a
  plus added (a second Codex review found its body copied from `video`, so it
  is recorded as a modified Lucide icon), and `message-quote`, a round bubble
  Lucide lacks, is drawn here.
- **Set.** The icons cover every symbol the app used, including those of the
  Lenses prototype (branch `design-prototype-icons`, which is absorbed here and
  not merged on its own). Filled symbols map to the outline icon; liked and
  reposted are shown by color. The Windows window controls are left for the
  Windows work.
- **Checking.** `mise run icons:lint` (`tools/icons/lint.py`) checks the root
  attributes and their order, the allowed elements and attributes (plus `ry`
  on `rect` and `fill="currentColor"`, which Lucide's own `image` and `palette`
  use), the safe zone for simple shapes, kebab-case names, and the metadata
  keys, categories and pinned `$schema`. `AppIconTests` checks that every
  `AppIcon` case loads from the bundle and every bundled SVG has a case.
- **Loading.** The app and its test bundle copy `design/icons` as an `icons`
  folder; `AppIconImages` loads each SVG once as a template `NSImage`. `Icon(.x,
  size:)` draws an icon at a given size (1.25× the former SF Symbol point size,
  since the drawing fills 20 of the 24 units) and `Image.icon(.x)` gives a 16pt
  image for menu items and labels. The plan had the icons in the core package's
  Apple target; they live in the app instead because SPM would process the
  resources on the Windows build too, which cannot be checked here.
- **Accessibility.** SF Symbols carried a spoken name and the SVGs do not, so
  `Icon` is hidden from VoiceOver unless given a `label` (the verified badge),
  and every button whose label is only an icon names itself.
- **Snapshots.** The catalog snapshots are re-recorded in light and dark
  (`-dark` suffix) with the appearance pinned and the window background drawn,
  ending the failures that had been carried since the window rebuild.

## 3. Not in this PR

- The catalog still shows `PostRowView` and friends; the timeline's
  `TimelineRowView` and the rebuilt detail pane have no catalog variants yet,
  since `CatalogVariant` is shared with iPadOS.
- Windows window-control icons.
