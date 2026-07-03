# Design Catalog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Named spacing constants (`DesignMetrics`), a shared deterministic fixture set, DEBUG-only in-app design galleries on macOS and iPadOS, and snapshot-based visual regression tests — per `docs/superpowers/specs/2026-07-03-design-catalog-design.md`.

**Architecture:** Fixtures and the variant list live in `YoruMimizukuKit` (single source of truth); each app owns a registry mapping variants to its real views. Galleries and snapshot tests iterate the same registry. Image determinism comes from bundled sample PNGs plus an environment-injected preloaded-image table that `RemoteImage` consults synchronously.

**Tech Stack:** Swift 6.0 (strict concurrency), SwiftUI, XCTest, XcodeGen, swift-snapshot-testing (test targets only).

## Global Constraints

- Swift 6.0 / strict concurrency (`MainActor`, `Sendable`).
- `BlueskyCore` / `YoruMimizukuKit` stay free of Apple-UI framework dependencies (Foundation/CoreGraphics types like `CGFloat` are fine — `TimelineLayout` already uses `Double`).
- Commits via the `/commit` skill (`git ai-commit`); never raw `git commit`. English messages, capitalized, not Conventional Commits.
- Structural changes (constant extraction) commit separately from behavioral ones. Task 2/3 must be pixel-identical refactors.
- Core tests: `cd core && swift test` (456 green at start). App builds: `xcodegen generate` after every `project.yml` or file-list change, then `xcodebuild build -scheme <YoruMimizuku|YoruMimizukuPad> -project YoruMimizuku.xcodeproj`.
- Gallery code is `#if DEBUG` only; nothing ships in release builds.
- The repo is public: fixture text and images must be publishable (no real user data).
- Work in worktree `.worktrees/feature/design-catalog` (branch `feature/design-catalog`).

---

### Task 1: `DesignMetrics` — named spacing/radius constants (Kit)

**Files:**
- Create: `core/Sources/YoruMimizukuKit/DesignMetrics.swift`
- Test: `core/Tests/YoruMimizukuKitTests/DesignMetricsTests.swift`

**Interfaces:**
- Consumes: `DisplayDensity` (`core/Sources/YoruMimizukuKit/DisplayDensity.swift`, cases `.compact` / `.comfortable`).
- Produces: `public enum DesignMetrics` with the exact members below. Tasks 2, 3, 6, 7 reference these names verbatim.

- [ ] **Step 1: Write the failing test**

```swift
// core/Tests/YoruMimizukuKitTests/DesignMetricsTests.swift
import XCTest
@testable import YoruMimizukuKit

final class DesignMetricsTests: XCTestCase {
    // Values must equal today's magic numbers: this is a rename, not a redesign.
    func testConstantsMatchCurrentMagicNumbers() {
        XCTAssertEqual(DesignMetrics.actionBarTopGap, 6)
        XCTAssertEqual(DesignMetrics.actionBarItemSpacing, 26)
        XCTAssertEqual(DesignMetrics.mediaTopGap, 3)
        XCTAssertEqual(DesignMetrics.gridGutter, 5)
        XCTAssertEqual(DesignMetrics.gridTileHeight, 140)
        XCTAssertEqual(DesignMetrics.thumbnailCornerRadius, 10)
    }

    func testDensityDependentValues() {
        XCTAssertEqual(DesignMetrics.bodyStackSpacing(.compact), 2)
        XCTAssertEqual(DesignMetrics.bodyStackSpacing(.comfortable), 4)
        XCTAssertEqual(DesignMetrics.mediaMaxWidth(.compact), 320)
        XCTAssertEqual(DesignMetrics.mediaMaxWidth(.comfortable), 440)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd core && swift test --filter DesignMetricsTests`
Expected: FAIL — `cannot find 'DesignMetrics' in scope`.

- [ ] **Step 3: Implement**

```swift
// core/Sources/YoruMimizukuKit/DesignMetrics.swift
import Foundation

/// Named layout metrics shared by every platform UI. These are the vocabulary
/// used in design discussions ("PostRow の actionBarTopGap を 6→8 に"): the
/// identifier in conversation IS the identifier in code. Values are documented
/// where they apply; changing one here changes every platform.
public enum DesignMetrics {
    /// Gap between the post body/media block and the action bar (PostRow).
    public static let actionBarTopGap: Double = 6
    /// Horizontal spacing between reply / repost / like / link actions.
    public static let actionBarItemSpacing: Double = 26
    /// Gap above inline media, link cards, and quote cards (PostRow).
    public static let mediaTopGap: Double = 3
    /// Gutter between tiles in the 2+ image grid (PostRow imageGrid).
    public static let gridGutter: Double = 5
    /// Fixed tile height in the 2+ image grid.
    public static let gridTileHeight: Double = 140
    /// Corner radius of thumbnails, posters, and media curtains.
    public static let thumbnailCornerRadius: Double = 10

    /// Vertical spacing of the author/body/media/actions stack, by density.
    public static func bodyStackSpacing(_ density: DisplayDensity) -> Double {
        density == .compact ? 2 : 4
    }

    /// Maximum media width in the vertical (non-reflow) layout, by density.
    public static func mediaMaxWidth(_ density: DisplayDensity) -> Double {
        density == .compact ? 320 : 440
    }
}
```

- [ ] **Step 4: Run to verify pass, and run the whole Kit suite**

Run: `cd core && swift test`
Expected: PASS, 456 + 2 tests green.

- [ ] **Step 5: Commit** via the `commit` skill (message like "Add DesignMetrics named layout constants").

---

### Task 2: Replace macOS magic numbers with `DesignMetrics` (structural)

**Files:**
- Modify: `apps/macos/Views/PostRowView.swift`

**Interfaces:**
- Consumes: `DesignMetrics` from Task 1 (already `import YoruMimizukuKit` in this file).
- Produces: nothing new — pixel-identical refactor.

- [ ] **Step 1: Replace each site**

`DesignMetrics` members are `Double`; SwiftUI modifiers take `CGFloat`, so wrap with `CGFloat(...)` exactly like the existing `CGFloat(TimelineLayout.columnGap)` usages in this file. Sites (line numbers as of `5127cf3`):

| Site | Before | After |
|---|---|---|
| `content` both VStacks (~262, ~277) | `spacing: density == .compact ? 2 : 4` | `spacing: CGFloat(DesignMetrics.bodyStackSpacing(density))` |
| `verticalMedia` / `linkCardSection` / `quoteSection` paddings (~300, ~303, ~336) | `.padding(.top, 3)` | `.padding(.top, CGFloat(DesignMetrics.mediaTopGap))` |
| `actionBarSection` (~347, ~349) | `.padding(.top, 6)` | `.padding(.top, CGFloat(DesignMetrics.actionBarTopGap))` |
| `actionBar` HStack (~579) | `HStack(spacing: 26)` | `HStack(spacing: CGFloat(DesignMetrics.actionBarItemSpacing))` |
| `imageMaxWidth` (~387) | `density == .compact ? 320 : 440` | `CGFloat(DesignMetrics.mediaMaxWidth(density))` |
| `imageGrid` LazyVGrid (~443-444) | `spacing: 5` (twice: GridItem and grid) | `spacing: CGFloat(DesignMetrics.gridGutter)` |
| `imageGrid` thumbnail call (~447) | `height: 140` | `height: CGFloat(DesignMetrics.gridTileHeight)` |
| `ThumbnailChrome` (~723-725) and `sensitiveMediaOverlay` clip (~403) | `cornerRadius: 10` | `cornerRadius: CGFloat(DesignMetrics.thumbnailCornerRadius)` |

Do NOT touch other literals (avatar size, row paddings, caption paddings) — out of the agreed vocabulary for now.

- [ ] **Step 2: Verify identical build**

Run: `xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED, no warnings about the file.

- [ ] **Step 3: Run core tests** — `cd core && swift test` — all green (no Kit changes, sanity only).

- [ ] **Step 4: Commit** via the `commit` skill ("Use DesignMetrics constants in macOS PostRowView" — note in the body this is a structural, value-preserving change).

---

### Task 3: Replace iPadOS magic numbers with `DesignMetrics` (structural)

**Files:**
- Modify: `apps/ipados/Views/PostRowView.swift`

**Interfaces:** same as Task 2.

- [ ] **Step 1: Replace matching sites**

The iPad row was rewritten to match macOS (commit `63d5067`), so the same semantic sites exist. Apply the same table as Task 2. **Rule for divergences:** replace a literal only when its current value equals the constant's value. If a site's value differs (e.g. a grid gutter of 6 where macOS has 5), leave the literal, and list the divergence in the commit body as a parity finding — do not change values in this task.

- [ ] **Step 2: Verify build**

Run: `xcodebuild build -scheme YoruMimizukuPad -project YoruMimizuku.xcodeproj -destination 'generic/platform=iOS Simulator' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit** via the `commit` skill ("Use DesignMetrics constants in iPad PostRowView").

---

### Task 4: macOS app test target + file-URL image loading proof

**Files:**
- Modify: `project.yml`
- Create: `apps/macos-tests/ImageDownsamplerFileURLTests.swift`

**Interfaces:**
- Consumes: `ImageDownsampler` (`apps/macos/Media/ImageDownsampler.swift`, `actor`, `shared.image(for: URL, maxPixel: CGFloat) async throws -> DecodedImage`).
- Produces: test target `YoruMimizukuTests` that Tasks 6 and 9 add tests to.

- [ ] **Step 1: Add the test target to `project.yml`**

Append under `targets:` (sibling of `YoruMimizuku`):

```yaml
  YoruMimizukuTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - apps/macos-tests
    dependencies:
      - target: YoruMimizuku
    settings:
      base:
        SWIFT_VERSION: "6.0"
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/YoruMimizuku.app/Contents/MacOS/YoruMimizuku"
        BUNDLE_LOADER: "$(TEST_HOST)"
```

Also attach it to the scheme so `xcodebuild test -scheme YoruMimizuku` runs it. XcodeGen generates a default scheme per target; add an explicit scheme for the app:

```yaml
schemes:
  YoruMimizuku:
    build:
      targets:
        YoruMimizuku: all
    test:
      targets:
        - YoruMimizukuTests
```

(`schemes:` is a new top-level key in this project — place it after `targets:`.)

- [ ] **Step 2: Write the failing test**

```swift
// apps/macos-tests/ImageDownsamplerFileURLTests.swift
import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import YoruMimizuku

/// The catalog's determinism rests on ImageDownsampler reading file:// URLs
/// (bundled sample images). This pins that capability.
final class ImageDownsamplerFileURLTests: XCTestCase {
    func testLoadsFileURL() async throws {
        // Write a tiny 4x4 PNG to a temp file.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("catalog-probe-\(UUID().uuidString).png")
        let ctx = CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let image = ctx.makeImage()!
        let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)

        let decoded = try await ImageDownsampler.shared.image(for: url, maxPixel: 8)
        XCTAssertEqual(decoded.cgImage.width, 4)
    }
}
```

- [ ] **Step 3: Generate and run**

Run: `xcodegen generate && xcodebuild test -scheme YoruMimizuku -project YoruMimizuku.xcodeproj -destination 'platform=macOS' -only-testing:YoruMimizukuTests -quiet`
Expected first run: build failure until the target wiring is right, then PASS. **If the download path rejects file URLs** (URLCache or response-type assumptions), this test fails — in that case add a guard at the top of `ImageDownsampler.image(for:maxPixel:)` that, for `url.isFileURL`, reads `Data(contentsOf:)` directly and feeds the same ImageIO decode path (spec's fallback decision: loader stays internal; no injection needed).

- [ ] **Step 4: Commit** ("Add macOS app test target with file URL image loading test").

---

### Task 5: `CatalogVariant` + `CatalogFixtures` + bundled sample images (Kit)

**Files:**
- Create: `core/Sources/YoruMimizukuKit/Catalog/CatalogVariant.swift`
- Create: `core/Sources/YoruMimizukuKit/Catalog/CatalogFixtures.swift`
- Create: `core/Sources/YoruMimizukuKit/Catalog/Resources/` (3 PNGs, generated below)
- Modify: `core/Package.swift` (resources)
- Test: `core/Tests/YoruMimizukuKitTests/CatalogFixturesTests.swift`

**Interfaces:**
- Produces (used verbatim by Tasks 6-10):
  - `public enum CatalogPlatform { case macOS, iPadOS }`
  - `public enum CatalogVariant: String, CaseIterable, Identifiable, Sendable` — cases: `postRowStandard, postRowSingleTallImage, postRowTwoImages, postRowFourImages, postRowQuote, postRowVideoPoster, postRowLinkCard, postRowSensitive, postRowLongBody, actionBar, quoteCard, linkCard, videoPoster, toast`; `var id: String` = `"<Component>/<variant>"` (e.g. `"PostRow/two-images"`); `var platforms: Set<CatalogPlatform>` (all cases both platforms except `.toast` → macOS only); `var componentName: String`; `var metricsUsed: [String]` (DesignMetrics identifiers to caption in the gallery).
  - `public enum CatalogFixtures` — `public static let now: Date` (fixed: `Date(timeIntervalSince1970: 1_751_500_000)`); `public static func post(for variant: CatalogVariant) -> PostDisplay` (for PostRow-family variants); `public static func quote() -> QuotedPost`; `public static func linkCard() -> LinkCard`; `public static func video() -> PostVideo`; `public static func imageURL(_ name: String) -> URL` (Bundle.module resource).

- [ ] **Step 1: Generate the sample images** (run once, commit the PNGs)

Write `/tmp/gen-catalog-images.swift`:

```swift
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

func write(_ name: String, _ w: Int, _ h: Int, _ rgb: (CGFloat, CGFloat, CGFloat)) {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Two-tone diagonal so crops/reflows are visually obvious in snapshots.
    ctx.setFillColor(CGColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.85))
    ctx.move(to: .zero); ctx.addLine(to: CGPoint(x: w, y: h))
    ctx.addLine(to: CGPoint(x: w, y: 0)); ctx.closePath(); ctx.fillPath()
    let dir = "core/Sources/YoruMimizukuKit/Catalog/Resources"
    try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let url = URL(fileURLWithPath: "\(dir)/\(name).png")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}
write("sample-wide", 728, 410, (0.20, 0.45, 0.80))   // 16:9-ish, mirrors the two-image case
write("sample-wide2", 960, 540, (0.80, 0.35, 0.25))
write("sample-tall", 400, 640, (0.30, 0.65, 0.40))   // taller than 5:4 → exercises tallCrop
```

Run: `swift /tmp/gen-catalog-images.swift` (from the worktree root). Expected: 3 PNGs under `Catalog/Resources/`, each a few KB.

- [ ] **Step 2: Declare resources in `core/Package.swift`**

Change the Kit target (line ~29) to:

```swift
.target(
    name: "YoruMimizukuKit",
    dependencies: ["BlueskyCore"],
    resources: [.copy("Catalog/Resources")]
),
```

(`.copy`, not `.process`, so file names are stable for `Bundle.module.url(forResource:)` under a directory.)

- [ ] **Step 3: Write the failing tests**

```swift
// core/Tests/YoruMimizukuKitTests/CatalogFixturesTests.swift
import XCTest
@testable import YoruMimizukuKit

final class CatalogFixturesTests: XCTestCase {
    func testEveryVariantHasStableID() {
        XCTAssertEqual(CatalogVariant.postRowTwoImages.id, "PostRow/two-images")
        XCTAssertEqual(Set(CatalogVariant.allCases.map(\.id)).count,
                       CatalogVariant.allCases.count)
    }

    func testToastIsMacOnlyEverythingElseIsBoth() {
        for v in CatalogVariant.allCases {
            if v == .toast {
                XCTAssertEqual(v.platforms, [.macOS])
            } else {
                XCTAssertEqual(v.platforms, [.macOS, .iPadOS], v.id)
            }
        }
    }

    func testBundledImagesExistOnDisk() {
        for name in ["sample-wide", "sample-wide2", "sample-tall"] {
            let url = CatalogFixtures.imageURL(name)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), name)
        }
    }

    func testFixturesAreDeterministic() {
        let a = CatalogFixtures.post(for: .postRowTwoImages)
        let b = CatalogFixtures.post(for: .postRowTwoImages)
        XCTAssertEqual(a.id, b.id)
        XCTAssertEqual(a.createdAt, b.createdAt)
        XCTAssertEqual(a.images.count, 2)
        // Sensitive fixture carries a warning; others don't.
        XCTAssertNotNil(CatalogFixtures.post(for: .postRowSensitive).mediaWarning)
    }
}
```

- [ ] **Step 4: Run to verify failure** — `cd core && swift test --filter CatalogFixturesTests` — FAIL (types missing).

- [ ] **Step 5: Implement `CatalogVariant`**

```swift
// core/Sources/YoruMimizukuKit/Catalog/CatalogVariant.swift
import Foundation

public enum CatalogPlatform: Sendable { case macOS, iPadOS }

/// The single source of truth for which design-catalog samples exist. App-side
/// registries map each case to a real view; a coverage test per app asserts no
/// declared variant is missing. IDs are the names used in design discussions.
public enum CatalogVariant: String, CaseIterable, Identifiable, Sendable {
    case postRowStandard, postRowSingleTallImage, postRowTwoImages
    case postRowFourImages, postRowQuote, postRowVideoPoster
    case postRowLinkCard, postRowSensitive, postRowLongBody
    case actionBar, quoteCard, linkCard, videoPoster, toast

    public var componentName: String {
        switch self {
        case .actionBar: "ActionBar"
        case .quoteCard: "QuoteCard"
        case .linkCard: "LinkCard"
        case .videoPoster: "VideoPoster"
        case .toast: "Toast"
        default: "PostRow"
        }
    }

    public var variantName: String {
        switch self {
        case .postRowStandard: "standard"
        case .postRowSingleTallImage: "single-tall-image"
        case .postRowTwoImages: "two-images"
        case .postRowFourImages: "four-images"
        case .postRowQuote: "quote"
        case .postRowVideoPoster: "video-poster"
        case .postRowLinkCard: "link-card"
        case .postRowSensitive: "sensitive"
        case .postRowLongBody: "long-body"
        case .actionBar, .quoteCard, .linkCard, .videoPoster, .toast: "default"
        }
    }

    public var id: String { "\(componentName)/\(variantName)" }

    public var platforms: Set<CatalogPlatform> {
        self == .toast ? [.macOS] : [.macOS, .iPadOS]
    }

    /// DesignMetrics identifiers this sample exercises — shown as the gallery caption.
    public var metricsUsed: [String] {
        switch self {
        case .postRowTwoImages, .postRowFourImages:
            ["gridGutter", "gridTileHeight", "thumbnailCornerRadius", "mediaTopGap"]
        case .postRowStandard, .postRowLongBody:
            ["bodyStackSpacing", "actionBarTopGap", "actionBarItemSpacing"]
        case .postRowSingleTallImage, .postRowSensitive:
            ["mediaTopGap", "mediaMaxWidth", "thumbnailCornerRadius"]
        case .actionBar: ["actionBarTopGap", "actionBarItemSpacing"]
        case .postRowQuote, .quoteCard: ["mediaTopGap", "thumbnailCornerRadius"]
        case .postRowVideoPoster, .videoPoster, .postRowLinkCard, .linkCard:
            ["mediaTopGap", "mediaMaxWidth", "thumbnailCornerRadius"]
        case .toast: []
        }
    }
}
```

- [ ] **Step 6: Implement `CatalogFixtures`**

```swift
// core/Sources/YoruMimizukuKit/Catalog/CatalogFixtures.swift
import Foundation

/// Deterministic display models for the design catalog and snapshot tests.
/// Everything is pinned: the clock, IDs, text, and image URLs (bundled PNGs),
/// so the same variant renders identically on every run and platform.
public enum CatalogFixtures {
    /// Frozen "current time"; createdAt offsets render stable relative stamps.
    public static let now = Date(timeIntervalSince1970: 1_751_500_000)

    public static func imageURL(_ name: String) -> URL {
        Bundle.module.url(forResource: "Resources/\(name)", withExtension: "png")
            ?? Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Resources")!
    }

    private static func image(_ name: String, w: Double, h: Double, alt: String = "") -> PostImage {
        let url = imageURL(name)
        return PostImage(thumbURL: url, fullsizeURL: url, alt: alt, aspectRatio: w / h)
    }

    public static func linkCard() -> LinkCard {
        LinkCard(url: URL(string: "https://example.com/article")!,
                 title: "サンプル記事のタイトル",
                 description: "OGP カードの見本。実在しない URL です。",
                 thumbURL: imageURL("sample-wide"))
    }

    public static func video() -> PostVideo {
        PostVideo(thumbURL: imageURL("sample-wide2"), playlistURL: nil,
                  alt: "動画の見本", aspectRatio: 16.0 / 9.0)
    }

    public static func quote() -> QuotedPost {
        // QuotedPost is its own memberwise struct (PostDisplay.swift:73-84).
        QuotedPost(
            id: "at://did:plc:catalog/app.bsky.feed.post/quoted",
            cid: "",
            authorDisplayName: "引用元ユーザー",
            authorHandle: "quoted.example.com",
            avatarURL: nil,
            body: "引用される側の投稿本文。",
            createdAt: now.addingTimeInterval(-7200),
            images: [image("sample-wide", w: 728, h: 410)],
            video: nil)
    }

    public static func post(for variant: CatalogVariant) -> PostDisplay {
        let base: (String, String) = ("カタログ 見本", "catalog.example.com")
        switch variant {
        case .postRowStandard, .actionBar, .toast:
            return PostDisplay(
                id: "at://did:plc:catalog/app.bsky.feed.post/standard",
                authorDisplayName: base.0, authorHandle: base.1,
                body: "標準的な投稿の見本。適度な長さの本文が1〜2行入る。",
                createdAt: now.addingTimeInterval(-1440),
                replyCount: 2, repostCount: 5, likeCount: 24)
        case .postRowSingleTallImage:
            return PostDisplay(
                id: "at://did:plc:catalog/app.bsky.feed.post/tall",
                authorDisplayName: base.0, authorHandle: base.1,
                body: "縦長画像1枚（5:4 キャップで全体表示ヒントが出る）。",
                createdAt: now.addingTimeInterval(-3600),
                images: [image("sample-tall", w: 400, h: 640, alt: "縦長の見本画像")])
        case .postRowTwoImages:
            return PostDisplay(
                id: "at://did:plc:catalog/app.bsky.feed.post/two",
                authorDisplayName: base.0, authorHandle: base.1,
                body: "画像2枚グリッドの見本（2026-07-03 のオーバーラップ再発防止）。",
                createdAt: now.addingTimeInterval(-1440),
                images: [image("sample-wide", w: 728, h: 410),
                         image("sample-wide2", w: 960, h: 540)],
                repostCount: 3, likeCount: 25)
        case .postRowFourImages:
            return PostDisplay(
                id: "at://did:plc:catalog/app.bsky.feed.post/four",
                authorDisplayName: base.0, authorHandle: base.1,
                body: "画像4枚グリッドの見本。",
                createdAt: now.addingTimeInterval(-1440),
                images: [image("sample-wide", w: 728, h: 410),
                         image("sample-wide2", w: 960, h: 540),
                         image("sample-tall", w: 400, h: 640),
                         image("sample-wide", w: 728, h: 410)])
        case .postRowQuote, .quoteCard:
            return PostDisplay(
                id: "at://did:plc:catalog/app.bsky.feed.post/quote",
                authorDisplayName: base.0, authorHandle: base.1,
                body: "引用ポストの見本。", createdAt: now.addingTimeInterval(-900),
                quote: quote())
        case .postRowVideoPoster, .videoPoster:
            return PostDisplay(
                id: "at://did:plc:catalog/app.bsky.feed.post/video",
                authorDisplayName: base.0, authorHandle: base.1,
                body: "動画ポスターの見本。", createdAt: now.addingTimeInterval(-600),
                video: video())
        case .postRowLinkCard, .linkCard:
            return PostDisplay(
                id: "at://did:plc:catalog/app.bsky.feed.post/link",
                authorDisplayName: base.0, authorHandle: base.1,
                body: "リンクカードの見本。", createdAt: now.addingTimeInterval(-300),
                linkCard: linkCard())
        case .postRowSensitive:
            return PostDisplay(
                id: "at://did:plc:catalog/app.bsky.feed.post/sensitive",
                authorDisplayName: base.0, authorHandle: base.1,
                body: "センシティブメディアぼかしの見本。",
                createdAt: now.addingTimeInterval(-120),
                mediaWarning: .adult,
                images: [image("sample-wide2", w: 960, h: 540)])
        case .postRowLongBody:
            return PostDisplay(
                id: "at://did:plc:catalog/app.bsky.feed.post/long",
                authorDisplayName: base.0, authorHandle: base.1,
                body: String(repeating: "長文の折返しと行間を確認するための本文。", count: 8),
                createdAt: now.addingTimeInterval(-60))
        }
    }
}
```

Type shapes verified against the current code: `LinkCard(url:title:description:thumbURL:)` (`LinkCard.swift:20`), `QuotedPost` memberwise init (`PostDisplay.swift:84`), `MediaWarning.adult` (`PostDisplay.swift:9`). If `QuotedPost.init` has default arguments for `cid`/`avatarURL`/`video`, the explicit nils can be dropped.

- [ ] **Step 7: Run** — `cd core && swift test` — all green.
- [ ] **Step 8: Commit** ("Add catalog fixtures and variant registry to YoruMimizukuKit").

---

### Task 6: macOS gallery — registry, window, menu entry

**Files:**
- Create: `apps/macos/Catalog/CatalogRegistry.swift`
- Create: `apps/macos/Catalog/DesignCatalogView.swift`
- Modify: `apps/macos/YoruMimizukuApp.swift` (add `Window` scene + Help menu command, both `#if DEBUG`)
- Test: `apps/macos-tests/CatalogRegistryTests.swift`

**Interfaces:**
- Consumes: `CatalogVariant`, `CatalogFixtures` (Task 5); `PostRowView(post:now:)` (defaults cover the callbacks); `ToastView`; `QuoteCardView` / `LinkCardView` / `VideoPosterView` (check each view's memberwise init in `apps/macos/Views/` and pass the fixture + no-op closures).
- Produces: `@MainActor enum CatalogRegistry { static func view(for variant: CatalogVariant) -> AnyView? }` — Task 9's snapshot loop uses exactly this. Returns `nil` for variants whose `platforms` exclude `.macOS` (defensive; on macOS all are present).

- [ ] **Step 1: Write the failing coverage test**

```swift
// apps/macos-tests/CatalogRegistryTests.swift
import XCTest
import YoruMimizukuKit
@testable import YoruMimizuku

final class CatalogRegistryTests: XCTestCase {
    @MainActor
    func testRegistryCoversEveryMacVariant() {
        for variant in CatalogVariant.allCases where variant.platforms.contains(.macOS) {
            XCTAssertNotNil(CatalogRegistry.view(for: variant), variant.id)
        }
    }
}
```

Run: `xcodegen generate && xcodebuild test -scheme YoruMimizuku ... -only-testing:YoruMimizukuTests` → FAIL (`CatalogRegistry` missing).

- [ ] **Step 2: Implement the registry**

```swift
// apps/macos/Catalog/CatalogRegistry.swift
#if DEBUG
import SwiftUI
import YoruMimizukuKit

/// Maps every CatalogVariant to the real macOS view rendering its fixture.
/// The gallery and the snapshot tests iterate this same table.
@MainActor
enum CatalogRegistry {
    static func view(for variant: CatalogVariant) -> AnyView? {
        guard variant.platforms.contains(.macOS) else { return nil }
        let now = CatalogFixtures.now
        switch variant {
        case .actionBar:
            // The action bar is a PostRow slot, so show a standard row focused on it.
            return AnyView(PostRowView(post: CatalogFixtures.post(for: .actionBar), now: now))
        case .quoteCard:
            return AnyView(QuoteCardView(quote: CatalogFixtures.quote(),
                                         density: .comfortable, now: now, onTap: {}))
        case .linkCard:
            return AnyView(LinkCardView(card: CatalogFixtures.linkCard(),
                                        density: .comfortable))
        case .videoPoster:
            return AnyView(VideoPosterView(video: CatalogFixtures.video(),
                                           maxWidth: 440, onTap: {}))
        case .toast:
            return AnyView(ToastView(message: "リンクをコピーしました"))
        default:
            return AnyView(PostRowView(post: CatalogFixtures.post(for: variant), now: now))
        }
    }
}
#endif
```

Match each subview's actual init (open the view file and copy its parameter list; e.g. `ToastView` may take a `ToastCenter` — if so, construct one and post the message before rendering).

- [ ] **Step 3: Implement the gallery window**

```swift
// apps/macos/Catalog/DesignCatalogView.swift
#if DEBUG
import SwiftUI
import YoruMimizukuKit

/// DEBUG-only design catalog: real components rendered from CatalogFixtures.
/// Sidebar = component groups; detail = every variant of the selection with a
/// caption naming the variant and the DesignMetrics constants it exercises.
struct DesignCatalogView: View {
    @StateObject private var theme: ThemeStore
    @StateObject private var display: DisplaySettingsStore
    @State private var selection: String?

    init() {
        // Throwaway defaults suite: toggling density/theme in the catalog must
        // not touch the real app settings.
        let sandbox = UserDefaults(suiteName: "as.ason.YoruMimizuku.catalog")!
        _theme = StateObject(wrappedValue: ThemeStore(defaults: sandbox))
        _display = StateObject(wrappedValue: DisplaySettingsStore(defaults: sandbox))
    }

    private var componentNames: [String] {
        var seen = [String]()
        for v in CatalogVariant.allCases where v.platforms.contains(.macOS) {
            if !seen.contains(v.componentName) { seen.append(v.componentName) }
        }
        return seen
    }

    var body: some View {
        NavigationSplitView {
            List(componentNames, id: \.self, selection: $selection) { Text($0) }
        } detail: {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(CatalogVariant.allCases.filter {
                        $0.componentName == (selection ?? "PostRow")
                            && $0.platforms.contains(.macOS)
                    }) { variant in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(variant.id).font(.headline)
                            if !variant.metricsUsed.isEmpty {
                                Text(variant.metricsUsed.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            CatalogRegistry.view(for: variant)
                                .padding(12)
                                .background(theme.background)
                        }
                    }
                }
                .padding(20)
            }
        }
        .environmentObject(theme)
        .environmentObject(display)
        .frame(minWidth: 720, minHeight: 480)
    }
}
#endif
```

(If `PostRowView` requires more environment objects — check what `FeedView` injects and mirror it with fixture-friendly instances.)

- [ ] **Step 4: Add the scene + menu**

In `apps/macos/YoruMimizukuApp.swift`, inside the `App` body add:

```swift
#if DEBUG
Window("デザインカタログ", id: "design-catalog") {
    DesignCatalogView()
}
#endif
```

and in the existing `.commands { }` block:

```swift
#if DEBUG
CommandGroup(after: .help) {
    OpenCatalogButton()
}
#endif
```

with a small helper struct so `openWindow` has a SwiftUI context:

```swift
#if DEBUG
private struct OpenCatalogButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("デザインカタログ") { openWindow(id: "design-catalog") }
    }
}
#endif
```

- [ ] **Step 5: Run tests and launch**

`xcodegen generate && xcodebuild test -scheme YoruMimizuku ... -only-testing:YoruMimizukuTests` → coverage test PASS. Then build, launch, open ヘルプ > デザインカタログ, click through every component, confirm rendering.

- [ ] **Step 6: Commit** ("Add DEBUG design catalog window to macOS app").

---

### Task 7: macOS gallery toolbar — density / theme / width / annotations

**Files:**
- Modify: `apps/macos/Catalog/DesignCatalogView.swift`

**Interfaces:** consumes `DisplayDensity`, `ThemeStore` (check how `SettingsView` renders its theme picker and reuse the same option source).

- [ ] **Step 1: Add toolbar state and controls**

Add to `DesignCatalogView`:

```swift
@State private var columnWidth: Double = 560
@State private var showMetricsCaptions = true
```

and a `.toolbar { }` on the detail `ScrollView`:

```swift
.toolbar {
    ToolbarItemGroup {
        Picker("密度", selection: $display.density) {
            Text("A (compact)").tag(DisplayDensity.compact)
            Text("B (comfortable)").tag(DisplayDensity.comfortable)
        }.pickerStyle(.segmented)
        // Theme control: reuse the same selection UI SettingsView uses
        // (open SettingsView.swift 外観 tab and copy the picker's option source).
        Slider(value: $columnWidth, in: 320...900) { Text("幅") }
            .frame(width: 180)
        Text("\(Int(columnWidth))pt").monospacedDigit().foregroundStyle(.secondary)
        Toggle("余白注記", isOn: $showMetricsCaptions)
    }
}
```

Constrain each sample to the slider width and pass it as the reflow input:
`CatalogRegistry.view(for: variant).frame(width: columnWidth, alignment: .leading)` — and for PostRow variants pass `contentWidth: columnWidth` by extending `CatalogRegistry.view(for:width:)` with a `width: CGFloat` parameter (default 560) that PostRow cases forward to `PostRowView(post:now:contentWidth:)`. Update Task 6's test call sites accordingly (the coverage test calls `view(for:)` which keeps working via the default).

Gate the caption `Text(variant.metricsUsed...)` on `showMetricsCaptions`.

- [ ] **Step 2: Manual verification** — drag the slider across 680pt and watch a media variant flip between vertical and reflow layouts; toggle density and theme; confirm the main app's settings are untouched afterwards (`defaults read as.ason.YoruMimizuku` unchanged).

- [ ] **Step 3: Run tests** (`-only-testing:YoruMimizukuTests`) — green.

- [ ] **Step 4: Commit** ("Add inspection controls to the design catalog toolbar").

---

### Task 8: iPadOS gallery + spec amendment for the entry point

**Files:**
- Modify: `docs/superpowers/specs/2026-07-03-design-catalog-design.md` (one line)
- Create: `apps/ipados/Catalog/CatalogRegistry.swift`
- Create: `apps/ipados/Catalog/DesignCatalogView.swift`
- Modify: `apps/ipados/Views/RootView.swift` (DEBUG entry)

**Interfaces:** consumes Task 5 types; iPad views (`apps/ipados/Views/PostRowView.swift` etc. — check each init).

- [ ] **Step 1: Amend the spec.** The iPad app has **no settings screen** (see `docs/wiki/platforms/ipados.md` Known differences), so the spec line 「設定画面の末尾に DEBUG のみ表示の『デザインカタログ』項目」 cannot be implemented as written. Edit the spec's ギャラリー section to: 「**iPadOS**: サイドバー末尾に DEBUG のみ表示の『デザインカタログ』行を置き、タップでシート表示する。（設定画面は未実装のため。設定画面が入ったら移設してよい）」. Commit separately ("Amend design catalog spec for missing iPad settings screen").

- [ ] **Step 2: Port the registry and view.** Mirror Task 6 against the iPad view inits (same `CatalogVariant` filtering with `.iPadOS`; no `Window` scenes on iOS — present `DesignCatalogView` as a `.sheet` from RootView's sidebar; wrap in `NavigationSplitView` inside the sheet). The `toast` case is absent on iPad — the registry's platform guard handles it.

- [ ] **Step 3: DEBUG sidebar entry.** In `RootView.swift`'s sidebar list add, inside `#if DEBUG`, a row `Label("デザインカタログ", systemImage: "square.grid.2x2")` that sets `@State private var showsCatalog = true`, with `.sheet(isPresented: $showsCatalog) { DesignCatalogView() }`.

- [ ] **Step 4: Build and manually verify** on the simulator: `xcodebuild build -scheme YoruMimizukuPad -destination 'generic/platform=iOS Simulator' -quiet`, then run in a simulator from Xcode or `xcrun simctl` and open the catalog.

- [ ] **Step 5: Commit** ("Add DEBUG design catalog to the iPad app").

---

### Task 9: swift-snapshot-testing + macOS snapshot suite + initial record

**Files:**
- Modify: `project.yml` (package + test-target dependency)
- Create: `apps/macos-tests/CatalogSnapshotTests.swift`
- Create (recorded): `apps/macos-tests/__Snapshots__/CatalogSnapshotTests/*.png`

**Interfaces:** consumes `CatalogRegistry.view(for:width:)` (Task 7) and `CatalogVariant.allCases`.

- [ ] **Step 1: Add the package** to `project.yml`:

```yaml
packages:
  SnapshotTesting:
    url: https://github.com/pointfreeco/swift-snapshot-testing
    from: 1.17.0
```

and to `YoruMimizukuTests` dependencies:

```yaml
      - package: SnapshotTesting
        product: SnapshotTesting
```

- [ ] **Step 2: Write the snapshot loop**

```swift
// apps/macos-tests/CatalogSnapshotTests.swift
import XCTest
import SwiftUI
import SnapshotTesting
import YoruMimizukuKit
@testable import YoruMimizuku

/// Renders every macOS catalog variant at a fixed width and compares against
/// the recorded reference PNGs. perceptualPrecision absorbs GPU/AA noise while
/// still catching layout shifts like the 2026-07-03 grid overlap.
final class CatalogSnapshotTests: XCTestCase {
    @MainActor
    func testCatalogVariants() async throws {
        // Pre-warm the image cache so RemoteImage's .task finds every fixture
        // image already decoded and the first committed frame is stable.
        for name in ["sample-wide", "sample-wide2", "sample-tall"] {
            _ = try await ImageDownsampler.shared.image(
                for: CatalogFixtures.imageURL(name), maxPixel: 1024)
        }
        for variant in CatalogVariant.allCases where variant.platforms.contains(.macOS) {
            guard let view = CatalogRegistry.view(for: variant, width: 560) else { continue }
            let host = NSHostingView(rootView: view
                .frame(width: 560)
                .fixedSize(horizontal: false, vertical: true))
            host.frame = NSRect(x: 0, y: 0, width: 560,
                                height: host.fittingSize.height)
            // Give RemoteImage's .task one runloop turn to publish the cached image.
            for _ in 0..<3 {
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
            assertSnapshot(of: host,
                           as: .image(perceptualPrecision: 0.98),
                           named: variant.rawValue)
        }
    }
}
```

If placeholder frames still appear in recorded PNGs (async race), switch `CatalogRegistry` to resolve images synchronously in DEBUG: add an optional `preloadedImages: [URL: CGImage]` environment value consulted by `RemoteImage` before its `.task` — this was anticipated in the spec's 未確定事項; implement only if the runloop approach proves flaky over 5 consecutive runs.

- [ ] **Step 3: Record.** `xcodegen generate`, then run the test once — swift-snapshot-testing fails a first run while writing references. Inspect every PNG under `__Snapshots__/` by eye (no spinners, no blank tiles, two-image grid shows two equal tiles). Re-run: all PASS. Run the full suite 3 times to check stability.

- [ ] **Step 4: Commit** ("Add catalog snapshot tests with recorded references for macOS") — include the PNGs.

---

### Task 10: iPad snapshot target

**Files:**
- Modify: `project.yml` (add `YoruMimizukuPadTests` bundle.unit-test target, platform iOS, sources `apps/ipados-tests`, TEST_HOST wiring like Task 4 but for `YoruMimizukuPad`; add a `YoruMimizukuPad` scheme with the test target; SnapshotTesting dependency)
- Create: `apps/ipados-tests/CatalogSnapshotTests.swift` (same loop; render via `UIHostingController`, `as: .image(perceptualPrecision: 0.98, layout: .fixed(width: 560, height: 0))` is not valid — use `.image(on: .iPadPro11)` or host + `sizeToFit`; follow the library's SwiftUI strategy for iOS)
- Record on ONE pinned simulator.

- [ ] **Step 1: Pick and document the simulator.** Choose the newest installed iPad simulator (`xcrun simctl list devices available | grep iPad`), and write the exact device + OS into the test file header AND the spec's 未確定事項 resolution (edit the spec bullet to record the decision, e.g. 「record 環境: iPad Pro 11-inch (M4) / iOS 18.5 シミュレータ固定」). References recorded on a different simulator will differ — the test file comment must say so.

- [ ] **Step 2: Wire the target, write the loop, record, verify 3 stable runs** (mirror Task 9 with `variant.platforms.contains(.iPadOS)`).

Run: `xcodebuild test -scheme YoruMimizukuPad -project YoruMimizuku.xcodeproj -destination 'platform=iOS Simulator,name=<pinned device>' -only-testing:YoruMimizukuPadTests`

- [ ] **Step 3: Commit** ("Add iPad catalog snapshot tests with recorded references").

---

### Task 11: Documentation — wiki design-system page + ingestion

**Files:**
- Create: `docs/wiki/design-system.md` (type: `concept`)
- Modify: behavior/platform pages as the `wiki-update` skill dictates; `AGENTS.md` Coding Conventions (one pointer line)

- [ ] **Step 1: Run the `wiki-update` skill** to ingest `2026-07-03-design-catalog-design.md` + this plan: create `docs/wiki/design-system.md` documenting (a) the naming rule (component = type name minus View; spacing = DesignMetrics identifiers, list them all with values and where they apply), (b) the gallery (how to open on each platform), (c) snapshot operations (record command, the pinned iPad simulator, when to re-record). Cite the spec/plan in `sources:`.
- [ ] **Step 2:** Add one line to `AGENTS.md` Coding Conventions: "Layout spacing/radius values shared across platforms live in `DesignMetrics` (`core/Sources/YoruMimizukuKit/DesignMetrics.swift`); see `docs/wiki/design-system.md` for the vocabulary and the design catalog."
- [ ] **Step 3:** `mise run wiki:lint` (zero warnings) + `mise run wiki:index`.
- [ ] **Step 4: Commit** ("Document the design system vocabulary and catalog in the wiki").

---

## Completion checklist

- `cd core && swift test` green (Kit constants + fixtures tests included)
- `xcodebuild test -scheme YoruMimizuku` green including snapshots (3 consecutive runs)
- `xcodebuild test -scheme YoruMimizukuPad` green on the pinned simulator
- Gallery opens on both platforms; density/theme/width/annotation controls work; real app settings unaffected
- `mise run wiki:lint` zero warnings
- Merge to `main` per AGENTS.md (then `xcodegen generate`, delete the worktree)
