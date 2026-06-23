# タイムライン画像レイアウト改善（縦長クロップ＋幅リフロー）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** タイムラインの縦長画像を 5:4 で頭打ちにクロップし、ウィンドウが広いときは本文を左・メディア（画像/動画/リンクカード）を右に並べるリフローで横幅を活用する。

**Architecture:** レイアウト判定とクロップ計算は `YoruMimizukuKit` の純粋ヘルパー `TimelineLayout`（プラットフォーム非依存・`Double` 基底）に切り出してユニットテストする。SwiftUI 側（`apps/macos` の `PostRowView` / `FeedView`）は、フィード列の幅を 1 回だけ測ってプロパティで各行に渡し、ヘルパーの判定で縦積み / リフローを分岐する薄い View に保つ。

**Tech Stack:** Swift 6.0 / SwiftUI（macOS 15+）/ XCTest / XcodeGen / SPM（core パッケージ）

## Global Constraints

- Swift 6.0 / strict concurrency。`MainActor` 隔離と `Sendable` に注意（一行ごとの値型ヘルパーは `Sendable`）。
- `YoruMimizukuKit` は Windows / Linux とも共有されるため Apple フレームワーク非依存に保つ。寸法ヘルパーは `CGFloat`（CoreGraphics 依存）ではなく `Double` で書く。View 側で `CGFloat(...)` に変換する。
- コミットは必ず `/commit` スキル（`git ai-commit`）で作成する。`git commit` を直接実行しない。コミットメッセージは英語・先頭大文字・Conventional Commits 不使用。
- `YoruMimizuku.xcodeproj` と `Info.plist` は生成物（gitignore 済み）。アプリをビルドする前に必ず `xcodegen generate` を実行する。
- TDD（Red → Green → Refactor）。一度に多くのテストを書かず一歩ずつ。
- 寸法の確定値: 閾値 `680` / 右メディア列 `300` / 列間 `16` / 本文列上限 `620` / 単一画像の最小アスペクト比 `0.8`（= 高さ ≤ 1.25×幅）/ 最大アスペクト比 `5.0`。

---

### Task 1: レイアウト計算ヘルパー `TimelineLayout`

レイアウト判定（縦積み / リフロー）、本文列幅、単一画像アスペクト比のクランプ、縦長クロップ判定を行う純粋ヘルパーを追加する。プラットフォーム非依存・テスト可能。

**Files:**
- Create: `core/Sources/YoruMimizukuKit/TimelineLayout.swift`
- Test: `core/Tests/YoruMimizukuKitTests/TimelineLayoutTests.swift`

**Interfaces:**
- Consumes: なし（標準ライブラリのみ）
- Produces:
  - `enum TimelineMediaPlacement: Equatable, Sendable { case vertical, reflow }`
  - `enum TimelineLayout`（名前空間）static 定数:
    - `reflowThreshold: Double = 680`
    - `mediaRailWidth: Double = 300`
    - `columnGap: Double = 16`
    - `maxTextColumnWidth: Double = 620`
    - `minSingleImageRatio: Double = 0.8`
    - `maxSingleImageRatio: Double = 5.0`
  - `static func placement(regionWidth: Double) -> TimelineMediaPlacement`
  - `static func textColumnWidth(regionWidth: Double) -> Double`
  - `static func clampedSingleImageRatio(_ natural: Double) -> Double`
  - `static func isTallCropped(_ natural: Double) -> Bool`

- [ ] **Step 1: Write the failing tests**

`core/Tests/YoruMimizukuKitTests/TimelineLayoutTests.swift`:

```swift
import XCTest
@testable import YoruMimizukuKit

final class TimelineLayoutTests: XCTestCase {
    func test_placement_isVerticalBelowThreshold() {
        XCTAssertEqual(TimelineLayout.placement(regionWidth: 679), .vertical)
    }

    func test_placement_isReflowAtAndAboveThreshold() {
        XCTAssertEqual(TimelineLayout.placement(regionWidth: 680), .reflow)
        XCTAssertEqual(TimelineLayout.placement(regionWidth: 1200), .reflow)
    }

    func test_textColumnWidth_fillsRemainderBelowCap() {
        // region 760 -> 760 - 16 - 300 = 444
        XCTAssertEqual(TimelineLayout.textColumnWidth(regionWidth: 760), 444, accuracy: 0.001)
    }

    func test_textColumnWidth_isCappedAtMax() {
        // region 1200 -> 1200 - 16 - 300 = 884, capped to 620
        XCTAssertEqual(TimelineLayout.textColumnWidth(regionWidth: 1200), 620, accuracy: 0.001)
    }

    func test_clampedSingleImageRatio_clampsTallToMinimum() {
        // tall image (portrait) ratio 0.45 -> clamped up to 0.8
        XCTAssertEqual(TimelineLayout.clampedSingleImageRatio(0.45), 0.8, accuracy: 0.001)
    }

    func test_clampedSingleImageRatio_keepsModerateRatio() {
        XCTAssertEqual(TimelineLayout.clampedSingleImageRatio(1.0), 1.0, accuracy: 0.001)
    }

    func test_clampedSingleImageRatio_clampsPanoramaToMaximum() {
        XCTAssertEqual(TimelineLayout.clampedSingleImageRatio(8.0), 5.0, accuracy: 0.001)
    }

    func test_isTallCropped_trueWhenTallerThanCap() {
        XCTAssertTrue(TimelineLayout.isTallCropped(0.45))
    }

    func test_isTallCropped_falseAtOrAboveCap() {
        XCTAssertFalse(TimelineLayout.isTallCropped(0.8))
        XCTAssertFalse(TimelineLayout.isTallCropped(1.0))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd core && swift test --filter TimelineLayoutTests`
Expected: コンパイルエラー（`TimelineLayout` / `TimelineMediaPlacement` 未定義）で FAIL。

- [ ] **Step 3: Write the minimal implementation**

`core/Sources/YoruMimizukuKit/TimelineLayout.swift`:

```swift
/// Where a post row places its media relative to the body text. `vertical` is the
/// narrow, single-column stack (Yorufukurou-style); `reflow` puts the body on the
/// left and media (images / video / link card) in a fixed-width rail on the right.
public enum TimelineMediaPlacement: Equatable, Sendable {
    case vertical
    case reflow
}

/// Pure layout math for the timeline post row. Kept free of CoreGraphics/SwiftUI so
/// it stays platform-neutral (shared with the Windows core) and unit-testable; the
/// macOS view converts these `Double`s to `CGFloat` at the call site.
public enum TimelineLayout {
    /// Region width (the body+media area, excluding avatar column and row padding)
    /// at or above which the row reflows to body-left / media-right.
    /// 680 = textMin(360) + columnGap(16) + mediaRailWidth(300), rounded.
    public static let reflowThreshold: Double = 680
    /// Fixed width of the right-hand media rail in reflow mode.
    public static let mediaRailWidth: Double = 300
    /// Gap between the text column and the media rail in reflow mode.
    public static let columnGap: Double = 16
    /// Upper bound on the body text column width, for readability.
    public static let maxTextColumnWidth: Double = 620
    /// Lowest allowed single-image aspect ratio (width/height); 0.8 == height ≤ 1.25×width.
    public static let minSingleImageRatio: Double = 0.8
    /// Highest allowed single-image aspect ratio (panorama clamp).
    public static let maxSingleImageRatio: Double = 5.0

    public static func placement(regionWidth: Double) -> TimelineMediaPlacement {
        regionWidth >= reflowThreshold ? .reflow : .vertical
    }

    public static func textColumnWidth(regionWidth: Double) -> Double {
        let remainder = regionWidth - columnGap - mediaRailWidth
        return min(maxTextColumnWidth, max(0, remainder))
    }

    public static func clampedSingleImageRatio(_ natural: Double) -> Double {
        min(max(natural, minSingleImageRatio), maxSingleImageRatio)
    }

    public static func isTallCropped(_ natural: Double) -> Bool {
        natural < minSingleImageRatio
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd core && swift test --filter TimelineLayoutTests`
Expected: 全テスト PASS。

- [ ] **Step 5: Commit**

`/commit` スキル（`git ai-commit`）でコミットする（`git commit` を直接実行しない）。対象: `core/Sources/YoruMimizukuKit/TimelineLayout.swift`、`core/Tests/YoruMimizukuKitTests/TimelineLayoutTests.swift`。メッセージ例: `Add TimelineLayout helper for image reflow and tall-image crop`。

---

### Task 2: 単一画像を 5:4 で頭打ちクロップ＋全体表示ヒント

`singleImage` を `TimelineLayout` ベースに置き換える。表示高さの上限を 5:4（アスペクト比下限 0.8）にし、超過分は上寄せクロップ。クロップが発生したときだけ下端にグラデーション＋「全体表示」ヒントを重ねる。横長は現状維持。狭い（縦積み）状態でこの段階から縦長が締まる。

**Files:**
- Modify: `apps/macos/Views/PostRowView.swift`（`singleImage` 353-363 を置換、`imageGrid` の `singleImage` 呼び出し 333、`tallCropHint` を追加）

**Interfaces:**
- Consumes: `TimelineLayout.clampedSingleImageRatio(_:)`, `TimelineLayout.isTallCropped(_:)`（Task 1）, 既存 `imagePhaseContent(_:)`, `ThumbnailChrome`, `openLightbox(at:)`, `imageMaxWidth`
- Produces: `singleImage(_ image: PostImage, maxWidth: CGFloat) -> some View`（第2引数 `maxWidth` が増える）, `tallCropHint: some View`

- [ ] **Step 1: プロジェクトを生成（初回のみ）**

Run: `cd /Users/asonas/ghq/github.com/asonas/YoruMimizuku/.worktrees/feature/timeline-image-reflow && xcodegen generate`
Expected: `YoruMimizuku.xcodeproj` が生成される（既にあれば上書き）。

- [ ] **Step 2: `singleImage` を置換する**

`apps/macos/Views/PostRowView.swift` の既存 `singleImage`（353-363行）を次に置き換える:

```swift
/// A single attached image. Its display height is capped at 5:4 (height ≤ 1.25×
/// width): wider images show in full, taller ones are top-anchored and cropped to
/// the cap so the row never grows absurdly tall. When a crop actually happens, a
/// bottom gradient with a "全体表示" hint signals there is more; the lightbox always
/// shows the full image. The decode size follows the box's longer edge to stay sharp.
private func singleImage(_ image: PostImage, maxWidth: CGFloat) -> some View {
    let natural = image.aspectRatio ?? 4.0 / 3.0
    let boxRatio = CGFloat(TimelineLayout.clampedSingleImageRatio(natural))
    let cropped = TimelineLayout.isTallCropped(natural)
    let decodeEdge = max(maxWidth, maxWidth / boxRatio)
    return Color.clear
        .aspectRatio(boxRatio, contentMode: .fit)
        .frame(maxWidth: maxWidth, alignment: .leading)
        .overlay(alignment: .top) {
            RemoteImage(url: image.thumbURL, maxPointSize: decodeEdge) { phase in
                imagePhaseContent(phase)
            }
        }
        .clipped()
        .overlay(alignment: .bottom) {
            if cropped { tallCropHint }
        }
        .modifier(ThumbnailChrome(alt: image.alt) { openLightbox(at: image) })
}

/// Bottom band shown over a tall image that was cropped to the 5:4 cap. Hit testing
/// is disabled so a tap falls through to `ThumbnailChrome`'s lightbox gesture.
private var tallCropHint: some View {
    HStack(spacing: 4) {
        Spacer()
        Image(systemName: "arrow.up.left.and.arrow.down.right")
        Text("全体表示")
    }
    .font(.app(.caption2))
    .foregroundStyle(.white)
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .frame(maxWidth: .infinity, alignment: .trailing)
    .background(
        LinearGradient(
            colors: [.clear, .black.opacity(0.5)],
            startPoint: .top, endPoint: .bottom
        )
    )
    .allowsHitTesting(false)
}
```

注: `image.aspectRatio` は `Double?`。`?? 4.0 / 3.0` は `Double` を返すのでそのまま `clampedSingleImageRatio` / `isTallCropped` に渡せる。`CGFloat(...)` への変換は View の寸法計算側で行う。

- [ ] **Step 3: `imageGrid` の単一画像呼び出しを更新する**

同ファイルの `imageGrid`（332-333行付近）の単一画像分岐を次に変更:

```swift
if post.images.count == 1, let image = post.images.first {
    singleImage(image, maxWidth: imageMaxWidth)
}
```

- [ ] **Step 4: ビルドして確認する**

Run: `cd /Users/asonas/ghq/github.com/asonas/YoruMimizuku/.worktrees/feature/timeline-image-reflow && xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`。

- [ ] **Step 5: 実機の見た目を確認する**

アプリを起動し、縦長画像つきの投稿が 5:4 で頭打ちになり、下端に「全体表示」ヒントが出ること、サムネイルをタップするとライトボックスで全体が見えること、横長画像は従来どおりであることを目視確認する。

- [ ] **Step 6: Commit**

`/commit` スキルでコミット。対象: `apps/macos/Views/PostRowView.swift`。メッセージ例: `Cap tall timeline images at 5:4 with a crop hint`。

---

### Task 3: メディア幅をパラメータ化し本文を抽出（構造変更のみ）

`mediaSection` / `imageGrid` を `maxWidth` 引数で受けられるようにし、本文テキストを `bodyText` に抽出する。**縦積みの見た目は一切変えない**（Tidy First の構造変更）。後続タスクでリフローの右レール幅を渡すための下準備。

**Files:**
- Modify: `apps/macos/Views/PostRowView.swift`（`content` 216-263 / `mediaSection` 285-309 / `imageGrid` 327-345）

**Interfaces:**
- Consumes: `imageMaxWidth`, `singleImage(_:maxWidth:)`（Task 2）, `VideoPosterView(video:maxWidth:onTap:)`
- Produces:
  - `bodyText: some View`
  - `mediaSection(maxWidth: CGFloat) -> some View`（旧 `mediaSection` 計算プロパティを関数化）
  - `imageGrid(maxWidth: CGFloat) -> some View`（旧 `imageGrid` を関数化）

- [ ] **Step 1: `bodyText` を抽出する**

`content`（216-263行）内の本文 `Text(bodyAttributed)...fixedSize(...)` ブロックを `bodyText` プロパティに切り出し、`content` 内ではそれを参照する。`bodyText` を追加:

```swift
private var bodyText: some View {
    Text(bodyAttributed)
        .font(.app(density == .compact ? .callout : .body))
        .foregroundStyle(theme.primaryText)
        .tint(theme.accent)
        .lineSpacing(density == .compact ? 1 : 2)
        .fixedSize(horizontal: false, vertical: true)
}
```

`content` の本文部分を `bodyText` 呼び出しに置換（コメント 220-228行はそのまま `bodyText` 上に移してよい）。

- [ ] **Step 2: `mediaSection` / `imageGrid` を関数化する**

`mediaSection`（計算プロパティ）を `private func mediaSection(maxWidth: CGFloat) -> some View` に変更し、内部の `imageGrid` 参照を `imageGrid(maxWidth: maxWidth)` に、`VideoPosterView(video: video, maxWidth: imageMaxWidth, ...)` を `maxWidth: maxWidth` に変更する。`imageGrid` を `private func imageGrid(maxWidth: CGFloat) -> some View` に変更し、`singleImage(image, maxWidth: maxWidth)` と、複数枚グリッドの `.frame(maxWidth: maxWidth, alignment: .leading)` にする。

`content` 内のメディア呼び出しを `mediaSection(maxWidth: imageMaxWidth)` にする（呼び出し位置・`.padding(.top, 3)`・条件 `if !post.images.isEmpty || post.video != nil` は据え置き）。リンクカード・引用・アクションバーは**この段階では変更しない**（インラインのまま）。

- [ ] **Step 3: ビルドして確認する**

Run: `cd /Users/asonas/ghq/github.com/asonas/YoruMimizuku/.worktrees/feature/timeline-image-reflow && xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`。

- [ ] **Step 4: 見た目が変わっていないことを確認する**

アプリを起動し、狭いウィンドウでの投稿表示（本文・画像・リンクカード・引用・アクションバーの位置と間隔）が Task 2 完了時と同一であることを目視確認する。Task 3 は構造変更のみで見た目は不変。

- [ ] **Step 5: Commit**

`/commit` スキルでコミット。対象: `apps/macos/Views/PostRowView.swift`。メッセージ例: `Parameterize media width and extract body text in PostRowView`。

---

### Task 4: 幅でリフロー（本文 左 / メディア 右）

フィード列の幅を `FeedView` で 1 回測って `PostRowView` にプロパティで渡し、`TimelineLayout.placement` で縦積み / リフローを分岐する。リフロー時は本文・引用・アクションを左の本文列（上限 620）に、画像・動画・リンクカードを右の固定 300pt レールに置く。引用は本文列に残す。

**Files:**
- Modify: `apps/macos/Views/FeedView.swift`（`postList` 113-195：幅計測と `contentWidth` の引き渡し）
- Modify: `apps/macos/Views/PostRowView.swift`（`contentWidth` プロパティ追加、`==` 更新、`content` の分岐、`mediaColumn` / `verticalMedia` / `linkCardSection` / `quoteSection` / `actionBarSection` / `regionWidth(forContentWidth:)` 追加）

**Interfaces:**
- Consumes: `TimelineLayout.placement(regionWidth:)`, `TimelineLayout.textColumnWidth(regionWidth:)`, `TimelineLayout.mediaRailWidth`, `TimelineLayout.columnGap`（Task 1）, `bodyText`, `mediaSection(maxWidth:)`（Task 3）, `imageMaxWidth`, `avatarSize`, `columnSpacing`, `actionBar`, `staticActionBar`, `QuoteCardView`, `LinkCardView`, `LazyLinkCardView`
- Produces: `PostRowView.contentWidth: CGFloat`（デフォルト 0、`FeedView` から注入）

- [ ] **Step 1: `PostRowView` に `contentWidth` プロパティを追加し `==` に含める**

`apps/macos/Views/PostRowView.swift` のプロパティ群（`connectsToNext` の直後、54行付近）に追加:

```swift
/// The feed column's measured width (the List row width), injected by `FeedView`
/// once per layout pass. Drives the vertical/reflow decision via `TimelineLayout`.
/// Default 0 keeps the row vertical until the first measurement arrives.
var contentWidth: CGFloat = 0
```

`static func ==`（91-105行）の末尾（`canDelete` 比較の後）に追加:

```swift
            && lhs.contentWidth == rhs.contentWidth
```

- [ ] **Step 2: 抽出ピース（引用・アクション・リンクカード・メディア列）と幅計算を追加する**

`apps/macos/Views/PostRowView.swift` に追加（`mediaSection(maxWidth:)` の近く）:

```swift
/// The available width for the body+media region: the row width minus the row's
/// horizontal padding, the avatar column, and the column spacing.
private func regionWidth(forContentWidth width: CGFloat) -> CGFloat {
    let horizontalPadding = (density == .compact ? 12.0 : 16.0) * 2
    return width - CGFloat(horizontalPadding) - avatarSize - columnSpacing
}

/// Media for the narrow vertical layout: image/video then link card, with the
/// original top paddings preserved so the stacked appearance is unchanged.
@ViewBuilder
private var verticalMedia: some View {
    if !post.images.isEmpty || post.video != nil {
        mediaSection(maxWidth: imageMaxWidth).padding(.top, 3)
    }
    if post.linkCard != nil
        || (post.images.isEmpty && post.video == nil && post.quote == nil && post.firstLinkURL != nil) {
        linkCardSection.padding(.top, 3)
    }
}

/// Media for the wide reflow layout's right rail: image/video then link card,
/// stacked at the rail width.
@ViewBuilder
private func mediaColumn(maxWidth: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        if !post.images.isEmpty || post.video != nil {
            mediaSection(maxWidth: maxWidth)
        }
        linkCardSection
    }
}

/// The post's external-link (OGP) card: the post's own embed, or a lazily resolved
/// preview for a text-only post that carries a bare link.
@ViewBuilder
private var linkCardSection: some View {
    if let card = post.linkCard {
        LinkCardView(card: card, density: density)
    } else if post.images.isEmpty, post.video == nil, post.quote == nil,
              let url = post.firstLinkURL {
        LazyLinkCardView(url: url, density: density)
    }
}

/// The quoted post card. Stays in the body (left) column in both layouts.
@ViewBuilder
private var quoteSection: some View {
    if let quote = post.quote {
        QuoteCardView(quote: quote, density: density, now: now) {
            onQuoteTap(quote)
        }
        .padding(.top, 3)
    }
}

/// The action bar (comfortable density only): interactive or static counts.
@ViewBuilder
private var actionBarSection: some View {
    if density == .comfortable {
        if interactiveActions {
            actionBar
        } else {
            staticActionBar
        }
    }
}
```

- [ ] **Step 3: `content` を縦積み / リフローで分岐する**

`content`（216-263行）の `VStack { ... }` 本体を次に置き換える。リンクカード・引用・アクションバーのインライン記述は上の抽出ピースに置き換わる:

```swift
@ViewBuilder
private var content: some View {
    let region = regionWidth(forContentWidth: contentWidth)
    switch TimelineLayout.placement(regionWidth: Double(region)) {
    case .reflow:
        let textWidth = CGFloat(TimelineLayout.textColumnWidth(regionWidth: Double(region)))
        HStack(alignment: .top, spacing: CGFloat(TimelineLayout.columnGap)) {
            VStack(alignment: .leading, spacing: density == .compact ? 2 : 4) {
                authorLine
                bodyText
                quoteSection
                actionBarSection
            }
            .frame(maxWidth: textWidth, alignment: .leading)
            mediaColumn(maxWidth: CGFloat(TimelineLayout.mediaRailWidth))
                .frame(width: CGFloat(TimelineLayout.mediaRailWidth), alignment: .top)
        }
    case .vertical:
        VStack(alignment: .leading, spacing: density == .compact ? 2 : 4) {
            authorLine
            bodyText
            verticalMedia
            quoteSection
            actionBarSection
        }
    }
}
```

- [ ] **Step 4: `FeedView` でフィード列の幅を測り `contentWidth` を渡す**

`apps/macos/Views/FeedView.swift` の `FeedView` 本体に状態を追加（既存の `@State` 群の近く）:

```swift
@State private var contentWidth: CGFloat = 0
```

`postList(_:)`（113-195行）の `PostRowView(...)` 呼び出しに引数を追加する（`post:` の直後でよい）:

```swift
                    PostRowView(
                        post: post, density: displaySettings.density, now: now,
                        contentWidth: contentWidth,
                        onImageTap: { urls, index in
```

同 `postList` の `List { ... }` チェーン末尾（`.environment(\.defaultMinListRowHeight, 0)` の後、194行付近）に幅計測を追加:

```swift
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            contentWidth = newWidth
        }
```

注: `onGeometryChange(for:of:action:)` は macOS 14+ で利用可能（本アプリのターゲットは macOS 15）。List 自体の幅 = 行の幅なので、これがそのまま行の `contentWidth` になる。

- [ ] **Step 5: ビルドして確認する**

Run: `cd /Users/asonas/ghq/github.com/asonas/YoruMimizuku/.worktrees/feature/timeline-image-reflow && xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`。

- [ ] **Step 6: 狭い／広いの両方を実機確認する**

アプリを起動し、(a) ウィンドウが狭いとき従来どおり縦積み、(b) 横に広げると閾値で本文左・メディア（画像/動画/リンクカード）右に切り替わり、縦長画像が右レールに収まって投稿の縦が暴れない、(c) さらに広げると本文が 620pt で頭打ちになり行全体が左寄せで右に余白が出る、(d) 引用投稿は本文列（左）に残る、ことを目視確認する。リサイズでカクつかないことも確認する。

- [ ] **Step 7: Commit**

`/commit` スキルでコミット。対象: `apps/macos/Views/PostRowView.swift`、`apps/macos/Views/FeedView.swift`。メッセージ例: `Reflow timeline rows to body-left / media-right when wide`。

---

### Task 5: ドキュメント（wiki）更新と最終検証

挙動が変わったので LLM-wiki を更新し、core テストとアプリビルドを通して仕上げる。

**Files:**
- Modify: `docs/wiki/` 配下（`wiki-update` スキルが選定。タイムライン表示の behavior ページが対象になる見込み）
- 参照: `docs/wiki/conventions.md`, `docs/wiki/index.md`

- [ ] **Step 1: core テストを全件実行する**

Run: `cd /Users/asonas/ghq/github.com/asonas/YoruMimizuku/.worktrees/feature/timeline-image-reflow/core && swift test 2>&1 | tail -15`
Expected: 全テスト PASS（`TimelineLayoutTests` を含む）。

- [ ] **Step 2: アプリをビルドする**

Run: `cd /Users/asonas/ghq/github.com/asonas/YoruMimizuku/.worktrees/feature/timeline-image-reflow && xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`。

- [ ] **Step 3: wiki を更新する**

`wiki-update` スキルを起動し、本 spec/plan（`docs/superpowers/specs/2026-06-23-timeline-image-reflow-design.md` と本プラン）と実装後の挙動を取り込む。タイムラインの画像表示・幅リフローの behavior ページを追記/新規作成し、`mise run wiki:lint` と `mise run wiki:index` を実行する（`docs/wiki/index.md` は手編集しない）。

- [ ] **Step 4: wiki lint を確認する**

Run: `cd /Users/asonas/ghq/github.com/asonas/YoruMimizuku/.worktrees/feature/timeline-image-reflow && mise run wiki:lint 2>&1 | tail -10`
Expected: lint が通る（致命的エラーなし）。

- [ ] **Step 5: Commit**

`/commit` スキルでコミット。対象: `docs/wiki/` 配下の変更。メッセージ例: `Document timeline image reflow behavior in wiki`。

---

## Self-Review

- **Spec coverage:** 縦長 5:4 クロップ＝Task 2 / 上寄せ＋フェード＋全体表示ヒント＝Task 2（`tallCropHint`, `.overlay(alignment: .top)`）/ ライトボックス全体表示＝既存 `openLightbox` 流用（Task 2 で維持）/ 閾値 680・右列 300・列間 16・本文上限 620＝Task 1 定数 + Task 4 で適用 / 引用は本文列に残す＝Task 4 `quoteSection` を本文列に配置 / 画像・動画・リンクカードを右へ＝Task 4 `mediaColumn` / 幅をフィード列で 1 回測る＝Task 4 `onGeometryChange` / グリッド・センシティブぼかし維持＝Task 3 で `mediaSection(maxWidth:)` に内包したまま。全項目に対応タスクあり。
- **Placeholder scan:** TBD/TODO や「適切に処理」等の曖昧表現なし。各コードステップに実コードを記載。
- **Type consistency:** `singleImage(_:maxWidth:)`・`mediaSection(maxWidth:)`・`imageGrid(maxWidth:)`・`mediaColumn(maxWidth:)`・`regionWidth(forContentWidth:)`・`contentWidth`・`TimelineLayout.placement/textColumnWidth/clampedSingleImageRatio/isTallCropped` の名称・引数・型（core は `Double`、View は `CGFloat` 変換）がタスク間で一致。`TimelineMediaPlacement` の `.vertical/.reflow` を Task 4 の `switch` で網羅。
