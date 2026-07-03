---
title: Design System (Vocabulary, Catalog, Snapshots)
type: concept
updated: 2026-07-03
sources:
  - docs/superpowers/specs/2026-07-03-design-catalog-design.md
  - docs/superpowers/plans/2026-07-03-design-catalog.md
---

# Design System (Vocabulary, Catalog, Snapshots)

This page documents the shared vocabulary for discussing layout ("PostRow の `actionBarTopGap`"), the DEBUG-only in-app design catalog used to eyeball components, and the snapshot-test setup that catches unintended visual regressions. It exists because spacing used to be scattered magic numbers with no common name, and there was no way to render a component in isolation outside the live timeline (`2026-07-03-design-catalog-design.md` §背景と問題). See [[architecture]] for the surrounding module layout.

## Naming rule

- **Component name** = the Swift view type name with the trailing `View` dropped (`PostRowView` → "PostRow"). This is the only naming layer for components; no separate design-system vocabulary is invented.
- **Slots** (parts of a component) = the view's existing `private var`/computed-property names, used as-is: `authorLine`, `bodyText`, `mediaSection`, `actionBar`, `staticActionBar`, `quoteSection`, `linkCardSection`, `verticalMedia`, `mediaColumn`.
- **Variant IDs** in the catalog are `"<ComponentName>/<variant-name>"` (e.g. `PostRow/two-images`), defined once as `CatalogVariant` (`core/Sources/YoruMimizukuKit/Catalog/CatalogVariant.swift`) and shared by both platforms' galleries and snapshot tests.
- **Spacing/radius values** are named constants in `DesignMetrics` (`core/Sources/YoruMimizukuKit/DesignMetrics.swift`). The identifier in conversation is the identifier in code — "bump `actionBarTopGap` from 6 to 8" changes one line and both platforms. Naming pattern is `<location><role>`. Only values that are discussed or reused are named; one-off decorative padding is left as a literal (`2026-07-03-design-catalog-design.md` §命名規約).

### DesignMetrics reference

All members of `DesignMetrics`, their values, and where each applies:

| Identifier | Value | Applies to |
|---|---|---|
| `actionBarTopGap` | 6 | Gap above `actionBar`/`staticActionBar` inside `actionBarSection` (PostRow, comfortable density only) |
| `actionBarItemSpacing` | 26 | Horizontal spacing between reply / repost / like / link actions inside `actionBar` and `staticActionBar` |
| `mediaTopGap` | 3 | Gap above inline media (`verticalMedia`), link cards (`linkCardSection`), and quote cards (`quoteSection`) |
| `gridGutter` | 5 | Gutter between tiles in the 2+ image grid (PostRow `imageGrid`) |
| `gridTileHeight` | 140 | Fixed tile height in the 2+ image grid |
| `thumbnailCornerRadius` | 10 | Corner radius of thumbnails, video posters, and media curtains |
| `bodyStackSpacing(_:)` | 2 (`.compact`) / 4 (`.comfortable`) | Vertical spacing of the author/body/media/actions stack, by `DisplayDensity` |
| `mediaMaxWidth(_:)` | 320 (`.compact`) / 440 (`.comfortable`) | Maximum media width in the vertical (non-reflow) layout, by `DisplayDensity` |

`DesignMetrics` lives in `YoruMimizukuKit` (platform-neutral) and is consumed by both `apps/macos/Views/PostRowView.swift` and `apps/ipados/Views/PostRowView.swift`, wrapped in `CGFloat(...)` at each SwiftUI call site since the constants are `Double`. Introducing the enum was a pure rename — it did not change any rendered value (`2026-07-03-design-catalog-design.md` §命名規約).

## Known parity findings

Adopting `DesignMetrics` on both platforms surfaced two drift points between the macOS and iPad `PostRowView` implementations. Both are documented here as findings, not yet fixed — matching the plan's constraint that constant extraction stay a value-preserving refactor (`2026-07-03-design-catalog.md` Task 2/3).

1. **iPad is missing the external `actionBarTopGap` wrap.** On macOS, `actionBarSection` wraps `actionBar`/`staticActionBar` in `.padding(.top, CGFloat(DesignMetrics.actionBarTopGap))` (6pt) before returning it (`apps/macos/Views/PostRowView.swift:347,349`). On iPad, `actionBarSection` returns `actionBar`/`staticActionBar` directly with no such wrap (`apps/ipados/Views/PostRowView.swift:309,311`). Both platforms' `actionBar`/`staticActionBar` share an *internal* `.padding(.top, 3)` (a raw literal, not a `DesignMetrics` constant) inside the HStack itself. The gap between platforms is the **missing 6pt external wrap on iPad**, not a "3 vs 6" value mismatch — the internal 3pt padding is identical on both platforms.
2. **macOS `staticActionBar` still uses raw literals.** macOS's `staticActionBar` uses `HStack(spacing: 26)` and `.padding(.top, 3)` as literals (`apps/macos/Views/PostRowView.swift:665,673`), while macOS's `actionBar` already uses `DesignMetrics.actionBarItemSpacing` (`apps/macos/Views/PostRowView.swift:585`). iPad's `staticActionBar` already uses the constant (`apps/ipados/Views/PostRowView.swift:568`). So macOS's `staticActionBar` is the one lagging behind its own `actionBar` and behind iPad's `staticActionBar`.

## The gallery

A DEBUG-only in-app catalog renders the real production views (`PostRowView`, `ActionBar`, `QuoteCardView`, `LinkCardView`, `VideoPosterView`, and — macOS only — `ToastView`) against deterministic fixtures from `CatalogFixtures` (`core/Sources/YoruMimizukuKit/Catalog/CatalogFixtures.swift`). It never duplicates a component's implementation; adding a sample is one `CatalogVariant` case plus one registry line per app (`2026-07-03-design-catalog-design.md` §ギャラリー).

`CatalogVariant` (`core/Sources/YoruMimizukuKit/Catalog/CatalogVariant.swift`) declares 14 variants across 5 components (PostRow ×9, ActionBar, QuoteCard, LinkCard, VideoPoster, Toast). Each variant declares which platforms it applies to; `Toast` is macOS-only (there is no iPad toast UI), so the iPad catalog and its snapshot suite carry 13 variants. `CatalogVariant.metricsUsed` lists the `DesignMetrics` identifiers each sample exercises, shown as a gallery caption.

### Opening the gallery

- **macOS**: menu ヘルプ (Help) → デザインカタログ opens a dedicated `Window` (`apps/macos/YoruMimizukuApp.swift`, `#if DEBUG`). Left sidebar lists component names; the detail pane stacks every variant of the selected component.
- **iPadOS**: the sidebar in `RootView` carries a DEBUG-only row "デザインカタログ" (there is no settings screen to host it in yet — see [[ipados]] known differences) that presents `DesignCatalogView` as a `.sheet` (`apps/ipados/Views/RootView.swift`).

### Toolbar controls

Both galleries inject a throwaway `UserDefaults(suiteName: "as.ason.YoruMimizuku.catalog")`-backed `ThemeStore`/`DisplaySettingsStore` pair, so toggling density or theme in the catalog never touches the real app's settings.

| Control | macOS | iPadOS | Effect |
|---|---|---|---|
| 密度 (density) segmented picker | ✓ | ✓ | Switches `DisplayDensity` (`.compact`/`.comfortable`), driving `bodyStackSpacing`/`mediaMaxWidth` |
| テーマ (theme) menu | ✓ | — | A small set of named randoma11y presets plus "swap colors", calling the same `ThemeStore.apply(urlString:)`/`reset()`/`swap()` API `SettingsView`'s 外観 tab uses. Dropped on iPad — three controls already fill the sheet's toolbar at iPad width |
| 幅 (width) slider, 320–900pt | ✓ | ✓ | Feeds `contentWidth` into `PostRowView`, crossing the 680pt reflow boundary (`TimelineLayout`) so the vertical ↔ body-left/media-right reflow is visible live |
| 余白注記 (caption) toggle | ✓ | ✓ | Shows/hides the `metricsUsed` caption under each variant's `id` |

## Snapshot operations

Each app has its own XCTest target that renders every catalog variant (filtered by `CatalogVariant.platforms`) at a fixed 560pt width and compares it against a recorded reference PNG with `swift-snapshot-testing` (pinned in `project.yml` as `from: 1.17.0`; test-target-only dependency, never linked into the shipped app).

- **macOS**: `YoruMimizukuTests` (`apps/macosTests/CatalogSnapshotTests.swift`), 14 references under `apps/macosTests/__Snapshots__/CatalogSnapshotTests/`.
- **iPadOS**: `YoruMimizukuPadTests` (`apps/ipadosTests/CatalogSnapshotTests.swift`), 13 references (no `toast`) under `apps/ipadosTests/__Snapshots__/CatalogSnapshotTests/`. The record environment is **pinned to the iPad Pro 13-inch (M5) / iOS 26.5 simulator** — iOS renders at the device's display scale, so recording (or re-recording) on any other simulator produces different bitmaps and fails the comparison. This pin is documented in the test file's header comment.

Both suites compare with `.image(perceptualPrecision: 0.98)` at width 560, which absorbs GPU/antialiasing noise while still catching real layout shifts (the motivating case was the 2026-07-03 two-image grid overlap).

### Determinism

`RemoteImage` decodes off the main actor and publishes a frame later, so a snapshot taken immediately would capture the loading placeholder. Both test files pre-decode the three bundled sample PNGs (`sample-wide`, `sample-wide2`, `sample-tall`) through `ImageDownsampler`, then hand the decoded `CGImage`s to each view via a DEBUG-only `EnvironmentValues.catalogPreloadedImages` table that `RemoteImage` consults synchronously before starting its own async load (`apps/macos/Media/RemoteImage.swift`, `apps/ipados/Media/RemoteImage.swift`). This replaced an earlier runloop-pumping approach that the plan anticipated might not be reliable enough (`2026-07-03-design-catalog.md` Task 9 step 2). Each test also resets a throwaway `ThemeStore` to its built-in palette so recorded colors do not depend on any randoma11y state persisted on the machine running the test.

### Running the suites

```bash
xcodebuild test -scheme YoruMimizuku -project YoruMimizuku.xcodeproj \
  -destination 'platform=macOS' -only-testing:YoruMimizukuTests

xcodebuild test -scheme YoruMimizukuPad -project YoruMimizuku.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  -only-testing:YoruMimizukuPadTests
```

### Re-recording references

`swift-snapshot-testing`'s record mode is controlled by the `SNAPSHOT_TESTING_RECORD` environment variable (read once at process start into `SnapshotTestingConfiguration.Record`, since neither test file passes an explicit `record:` argument to `assertSnapshot`). Set it to `all` to force every snapshot in the run to overwrite its reference, or `missing` (the default) to only write references that don't exist yet:

```bash
# macOS
SNAPSHOT_TESTING_RECORD=all xcodebuild test -scheme YoruMimizuku \
  -project YoruMimizuku.xcodeproj -destination 'platform=macOS' \
  -only-testing:YoruMimizukuTests

# iPadOS — must run on the pinned simulator above
SNAPSHOT_TESTING_RECORD=all xcodebuild test -scheme YoruMimizukuPad \
  -project YoruMimizuku.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  -only-testing:YoruMimizukuPadTests
```

After recording, inspect every changed PNG by eye (no spinner/blank-tile placeholders, grids show equal tiles, no clipped text) and review the diff as an ordinary commit — the repository is public, so only publishable fixture text/images are used (`2026-07-03-design-catalog-design.md` §スナップショット運用). Run the suite a few times afterward to confirm the new references are stable before committing.

**When to re-record:**
- A named `DesignMetrics` value or a component's layout intentionally changes.
- A new `CatalogVariant` case is added (only its own reference is missing, so plain `SNAPSHOT_TESTING_RECORD=missing`, i.e. no env var at all, is enough — it will write only the new PNG and still fail-compare every existing one).
- OS/Xcode updates change font rendering or antialiasing enough that the whole suite fails at once; re-record only after visually confirming the new renders are correct, independent of any release.

Do not re-record to "make a failure go away" without first understanding why the pixels changed — a failing snapshot is the visual-regression signal this system exists to produce.
