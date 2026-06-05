# YoruMimizuku App Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ビルドして起動できる最小の macOS ネイティブアプリ `YoruMimizuku` を立ち上げる。夜フクロウ風の単一カラム UI（上部タブ・モックタイムライン・下部コンポーザ・アカウントチップ）をモックデータで表示し、表示密度 A/B（既定 B）を切り替えられる状態にする。

**Architecture:** 表示ロジック（密度・相対時刻・`PostDisplay`）は UI フレームワーク非依存の SPM ターゲット `YoruMimizukuKit`（`BlueskyCore` に依存）に置き `swift test` で検証する。SwiftUI ビューは XcodeGen で定義する macOS アプリターゲット `YoruMimizuku`（`BlueskyCore` と `YoruMimizukuKit` に依存）に置き、`xcodebuild build` でビルドを検証する。`.xcodeproj` は `project.yml` から生成し、gitignore する。

**Tech Stack:** Swift 6 / SwiftUI / Swift Package Manager / XcodeGen 2.45.4 / Xcode 26.5 / XCTest。ターゲット macOS 14+。

このプランは設計書 `docs/superpowers/specs/2026-06-04-yorumimizuku-design.md` の §4.1（`BlueskyMac` アプリ層）・§7（UI: 単一カラム+タブ、投稿行 A/B、コンポーザ、アカウントチップ）に対応する。実際の OAuth・タイムライン取得・ストリームは後続プラン。本プランはモックデータで「動くネイティブアプリの殻」を作る。

## 前提・作業ルール

- リポジトリ: `/Users/asonas/workspace/yorumimizuku`（main に Plan 1/2 マージ済み。`BlueskyCore` パッケージあり）
- 実装は worktree で：
  ```bash
  git -C /Users/asonas/workspace/yorumimizuku wt feature/app-shell
  ```
  worktree: `/Users/asonas/workspace/yorumimizuku/.worktrees/feature/app-shell`。以降の `<wt>` はこのパスを指す。
- コミットは `git ai-commit`（`/commit` スキル）。`git commit` 直接実行は禁止。
- パッケージのビルド/テスト: `swift test --package-path BlueskyCore`（`<wt>` 内で実行）。
- アプリのプロジェクト生成: `xcodegen generate --spec <wt>/project.yml --project <wt>`。
- アプリのビルド検証: `xcodebuild -project <wt>/YoruMimizuku.xcodeproj -scheme YoruMimizuku -destination 'platform=macOS,arch=arm64' -configuration Debug build CODE_SIGNING_ALLOWED=NO`（GUI 起動は不要、コンパイル成功を確認する）。
- 1テストずつ Red → Green → Refactor。

## 補足: パッケージ構成のメモ
既存パッケージのディレクトリ名は `BlueskyCore/` だが、本プランで同パッケージ内に表示ロジック用ターゲット `YoruMimizukuKit` を追加する（1パッケージ・複数プロダクト）。ディレクトリ名と内容が完全一致しない軽微な不整合は許容し、必要なら後のプランでパッケージ名を中立化する（本プランでは行わない）。

## File Structure

- `BlueskyCore/Package.swift` — `YoruMimizukuKit` ライブラリターゲットと `YoruMimizukuKitTests` を追加（変更）
- `BlueskyCore/Sources/YoruMimizukuKit/DisplayDensity.swift` — 表示密度
- `BlueskyCore/Sources/YoruMimizukuKit/RelativeTimeFormatter.swift` — 相対時刻文字列
- `BlueskyCore/Sources/YoruMimizukuKit/PostDisplay.swift` — 投稿行の表示モデル＋サンプル
- `BlueskyCore/Tests/YoruMimizukuKitTests/DisplayDensityTests.swift`
- `BlueskyCore/Tests/YoruMimizukuKitTests/RelativeTimeFormatterTests.swift`
- `BlueskyCore/Tests/YoruMimizukuKitTests/PostDisplayTests.swift`
- `project.yml` — XcodeGen のプロジェクト定義（リポジトリルート）
- `.gitignore` — `*.xcodeproj` を追加
- `app/YoruMimizuku/YoruMimizukuApp.swift` — `@main` SwiftUI App
- `app/YoruMimizuku/Views/ContentView.swift` — Task 4 の最小ルート（Task 5 で `MainWindowView` に差し替え）
- `app/YoruMimizuku/Views/PostRowView.swift` — 投稿行（密度 A/B）
- `app/YoruMimizuku/Views/MainWindowView.swift` — タブ＋リスト＋コンポーザ＋アカウントチップ
- `app/YoruMimizuku/Theme.swift` — 色などの最小テーマ定数

---

### Task 1: YoruMimizukuKit ターゲットと DisplayDensity

**Files:**
- Modify: `BlueskyCore/Package.swift`
- Create: `BlueskyCore/Sources/YoruMimizukuKit/DisplayDensity.swift`
- Create: `BlueskyCore/Tests/YoruMimizukuKitTests/DisplayDensityTests.swift`

- [ ] **Step 0: worktree 作成**

Run: `git -C /Users/asonas/workspace/yorumimizuku wt feature/app-shell`

- [ ] **Step 1: Package.swift に新ターゲットを追加**

`BlueskyCore/Package.swift` を次の内容に置き換える（既存 BlueskyCore はそのまま、YoruMimizukuKit と YoruMimizukuKitTests を追加）:
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BlueskyCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "BlueskyCore", targets: ["BlueskyCore"]),
        .library(name: "YoruMimizukuKit", targets: ["YoruMimizukuKit"])
    ],
    targets: [
        .target(name: "BlueskyCore"),
        .target(name: "YoruMimizukuKit", dependencies: ["BlueskyCore"]),
        .testTarget(name: "BlueskyCoreTests", dependencies: ["BlueskyCore"]),
        .testTarget(name: "YoruMimizukuKitTests", dependencies: ["YoruMimizukuKit"])
    ]
)
```

- [ ] **Step 2: 失敗するテストを書く**

Create `BlueskyCore/Tests/YoruMimizukuKitTests/DisplayDensityTests.swift`:
```swift
import XCTest
@testable import YoruMimizukuKit

final class DisplayDensityTests: XCTestCase {
    func test_hasCompactAndComfortableCases() {
        XCTAssertEqual(DisplayDensity.allCases, [.compact, .comfortable])
    }

    func test_defaultIsComfortable() {
        XCTAssertEqual(DisplayDensity.default, .comfortable)
    }

    func test_rawValuesAreStable() {
        XCTAssertEqual(DisplayDensity.compact.rawValue, "compact")
        XCTAssertEqual(DisplayDensity.comfortable.rawValue, "comfortable")
    }
}
```

- [ ] **Step 3: 失敗を確認**

Run: `swift test --package-path BlueskyCore --filter DisplayDensityTests`
Expected: FAIL（`DisplayDensity` 未定義でビルドエラー）。

- [ ] **Step 4: 実装**

Create `BlueskyCore/Sources/YoruMimizukuKit/DisplayDensity.swift`:
```swift
/// How densely a post row is rendered. `compact` is the Yorufukurou-style tight
/// layout; `comfortable` adds avatars, thumbnails and action counts. Default is
/// `comfortable`.
public enum DisplayDensity: String, CaseIterable, Sendable {
    case compact
    case comfortable

    public static let `default`: DisplayDensity = .comfortable
}
```

- [ ] **Step 5: テストが通ることを確認**

Run: `swift test --package-path BlueskyCore --filter DisplayDensityTests`
Expected: PASS（3 テスト）。既存 BlueskyCore テストも壊れていないことを後の Task で確認する。

- [ ] **Step 6: Commit**

```bash
git -C /Users/asonas/workspace/yorumimizuku/.worktrees/feature/app-shell add BlueskyCore/Package.swift BlueskyCore/Sources/YoruMimizukuKit BlueskyCore/Tests/YoruMimizukuKitTests
git -C /Users/asonas/workspace/yorumimizuku/.worktrees/feature/app-shell ai-commit
```
`git ai-commit` が使えない場合は中断して報告。メッセージ例: `Add YoruMimizukuKit target with DisplayDensity`

---

### Task 2: RelativeTimeFormatter

**Files:**
- Create: `BlueskyCore/Tests/YoruMimizukuKitTests/RelativeTimeFormatterTests.swift`
- Create: `BlueskyCore/Sources/YoruMimizukuKit/RelativeTimeFormatter.swift`

- [ ] **Step 1: 失敗するテストを書く**

Create `BlueskyCore/Tests/YoruMimizukuKitTests/RelativeTimeFormatterTests.swift`:
```swift
import XCTest
@testable import YoruMimizukuKit

final class RelativeTimeFormatterTests: XCTestCase {
    let formatter = RelativeTimeFormatter()
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    func string(secondsAgo: Int) -> String {
        formatter.string(for: now.addingTimeInterval(TimeInterval(-secondsAgo)), now: now)
    }

    func test_underFiveSecondsIsNow() {
        XCTAssertEqual(string(secondsAgo: 0), "now")
        XCTAssertEqual(string(secondsAgo: 4), "now")
    }

    func test_secondsMinutesHoursDays() {
        XCTAssertEqual(string(secondsAgo: 30), "30s")
        XCTAssertEqual(string(secondsAgo: 120), "2m")
        XCTAssertEqual(string(secondsAgo: 3 * 3600), "3h")
        XCTAssertEqual(string(secondsAgo: 2 * 86_400), "2d")
    }

    func test_futureDatesClampToNow() {
        XCTAssertEqual(formatter.string(for: now.addingTimeInterval(60), now: now), "now")
    }
}
```

- [ ] **Step 2: 失敗を確認**

Run: `swift test --package-path BlueskyCore --filter RelativeTimeFormatterTests`
Expected: FAIL（`RelativeTimeFormatter` 未定義）。

- [ ] **Step 3: 実装**

Create `BlueskyCore/Sources/YoruMimizukuKit/RelativeTimeFormatter.swift`:
```swift
import Foundation

/// Renders a short relative timestamp ("now", "30s", "2m", "3h", "2d") for a
/// post, given an explicit `now` so it is deterministic and testable.
public struct RelativeTimeFormatter: Sendable {
    public init() {}

    public func string(for date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 5 { return "now" }
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        return "\(days)d"
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `swift test --package-path BlueskyCore --filter RelativeTimeFormatterTests`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git -C /Users/asonas/workspace/yorumimizuku/.worktrees/feature/app-shell add BlueskyCore/Sources/YoruMimizukuKit/RelativeTimeFormatter.swift BlueskyCore/Tests/YoruMimizukuKitTests/RelativeTimeFormatterTests.swift
git -C /Users/asonas/workspace/yorumimizuku/.worktrees/feature/app-shell ai-commit
```
メッセージ例: `Add RelativeTimeFormatter`

---

### Task 3: PostDisplay モデルとサンプル

**Files:**
- Create: `BlueskyCore/Tests/YoruMimizukuKitTests/PostDisplayTests.swift`
- Create: `BlueskyCore/Sources/YoruMimizukuKit/PostDisplay.swift`

- [ ] **Step 1: 失敗するテストを書く**

Create `BlueskyCore/Tests/YoruMimizukuKitTests/PostDisplayTests.swift`:
```swift
import XCTest
@testable import YoruMimizukuKit

final class PostDisplayTests: XCTestCase {
    func test_initStoresAllFields() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let post = PostDisplay(
            id: "p1",
            authorDisplayName: "あそなす",
            authorHandle: "asonas.bsky.social",
            body: "hello",
            createdAt: date,
            contextLabel: "Reposted by you",
            replyCount: 1,
            repostCount: 2,
            likeCount: 3
        )

        XCTAssertEqual(post.id, "p1")
        XCTAssertEqual(post.authorDisplayName, "あそなす")
        XCTAssertEqual(post.authorHandle, "asonas.bsky.social")
        XCTAssertEqual(post.body, "hello")
        XCTAssertEqual(post.createdAt, date)
        XCTAssertEqual(post.contextLabel, "Reposted by you")
        XCTAssertEqual(post.replyCount, 1)
        XCTAssertEqual(post.repostCount, 2)
        XCTAssertEqual(post.likeCount, 3)
    }

    func test_samples_returnNonEmptyDeterministicData() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = PostDisplay.samples(now: now)

        XCTAssertGreaterThanOrEqual(samples.count, 3)
        // ids are unique
        XCTAssertEqual(Set(samples.map(\.id)).count, samples.count)
        // all timestamps are at or before `now`
        XCTAssertTrue(samples.allSatisfy { $0.createdAt <= now })
        // the first sample is the most recent (sorted newest-first)
        XCTAssertEqual(samples, samples.sorted { $0.createdAt > $1.createdAt })
    }
}
```

- [ ] **Step 2: 失敗を確認**

Run: `swift test --package-path BlueskyCore --filter PostDisplayTests`
Expected: FAIL（`PostDisplay` 未定義）。

- [ ] **Step 3: 実装**

Create `BlueskyCore/Sources/YoruMimizukuKit/PostDisplay.swift`:
```swift
import Foundation

/// A post as shown in a timeline row. UI-framework-agnostic so it can be unit
/// tested and reused by macOS/iOS views. Real posts map into this from
/// `BlueskyCore` models in a later plan; for now `samples` provides mock data.
public struct PostDisplay: Identifiable, Equatable, Sendable {
    public let id: String
    public let authorDisplayName: String
    public let authorHandle: String
    public let body: String
    public let createdAt: Date
    public let contextLabel: String?
    public let replyCount: Int
    public let repostCount: Int
    public let likeCount: Int

    public init(
        id: String,
        authorDisplayName: String,
        authorHandle: String,
        body: String,
        createdAt: Date,
        contextLabel: String? = nil,
        replyCount: Int = 0,
        repostCount: Int = 0,
        likeCount: Int = 0
    ) {
        self.id = id
        self.authorDisplayName = authorDisplayName
        self.authorHandle = authorHandle
        self.body = body
        self.createdAt = createdAt
        self.contextLabel = contextLabel
        self.replyCount = replyCount
        self.repostCount = repostCount
        self.likeCount = likeCount
    }

    /// Deterministic mock timeline for the app shell, newest first.
    public static func samples(now: Date) -> [PostDisplay] {
        [
            PostDisplay(
                id: "p1",
                authorDisplayName: "あそなす",
                authorHandle: "asonas.bsky.social",
                body: "夜フクロウみたいなクライアントを作っている。行は詰まってる方が一覧性が高くて好き。",
                createdAt: now.addingTimeInterval(-120),
                replyCount: 3, repostCount: 12, likeCount: 48
            ),
            PostDisplay(
                id: "p2",
                authorDisplayName: "bob",
                authorHandle: "bob.bsky.social",
                body: "AT Protocol の Jetstream、思ったより素直な JSON で扱いやすい。",
                createdAt: now.addingTimeInterval(-14 * 60),
                contextLabel: "Reposted by you",
                replyCount: 1, repostCount: 5, likeCount: 20
            ),
            PostDisplay(
                id: "p3",
                authorDisplayName: "carol",
                authorHandle: "carol.bsky.social",
                body: "DPoP の nonce 再試行さえ通れば認証は山を越える。",
                createdAt: now.addingTimeInterval(-31 * 60),
                contextLabel: "Reply to @alice",
                replyCount: 0, repostCount: 1, likeCount: 7
            ),
            PostDisplay(
                id: "p4",
                authorDisplayName: "dave",
                authorHandle: "dave.bsky.social",
                body: "SwiftUI の WindowGroup で複数ウィンドウ、macOS だと相性いい。",
                createdAt: now.addingTimeInterval(-60 * 60),
                replyCount: 2, repostCount: 4, likeCount: 15
            )
        ]
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `swift test --package-path BlueskyCore --filter PostDisplayTests`
Expected: PASS。

- [ ] **Step 5: 既存テストの非回帰を確認**

Run: `swift test --package-path BlueskyCore`
Expected: BlueskyCore の 19 テスト＋ YoruMimizukuKit の新規テストがすべて PASS。

- [ ] **Step 6: Commit**

```bash
git -C /Users/asonas/workspace/yorumimizuku/.worktrees/feature/app-shell add BlueskyCore/Sources/YoruMimizukuKit/PostDisplay.swift BlueskyCore/Tests/YoruMimizukuKitTests/PostDisplayTests.swift
git -C /Users/asonas/workspace/yorumimizuku/.worktrees/feature/app-shell ai-commit
```
メッセージ例: `Add PostDisplay model with sample data`

---

### Task 4: XcodeGen プロジェクトと最小アプリ（ビルド到達点）

**Files:**
- Create: `project.yml`
- Modify: `.gitignore`
- Create: `app/YoruMimizuku/YoruMimizukuApp.swift`
- Create: `app/YoruMimizuku/Views/ContentView.swift`

- [ ] **Step 1: `.gitignore` に生成物を追加**

`/Users/asonas/workspace/yorumimizuku/.worktrees/feature/app-shell/.gitignore` の末尾に追記（既存行は残す）:
```
*.xcodeproj
```

- [ ] **Step 2: XcodeGen の `project.yml` を作成**

Create `project.yml`（リポジトリ＝worktree ルート）:
```yaml
name: YoruMimizuku
options:
  bundleIdPrefix: as.ason
  deploymentTarget:
    macOS: "14.0"
  createIntermediateGroups: true
packages:
  BlueskyCore:
    path: BlueskyCore
targets:
  YoruMimizuku:
    type: application
    platform: macOS
    sources:
      - app/YoruMimizuku
    dependencies:
      - package: BlueskyCore
        product: BlueskyCore
      - package: BlueskyCore
        product: YoruMimizukuKit
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: as.ason.YoruMimizuku
        PRODUCT_NAME: YoruMimizuku
        MARKETING_VERSION: "0.1.0"
        CURRENT_PROJECT_VERSION: "1"
        SWIFT_VERSION: "6.0"
        ENABLE_HARDENED_RUNTIME: YES
    info:
      path: app/YoruMimizuku/Info.plist
      properties:
        CFBundleDisplayName: YoruMimizuku
        LSMinimumSystemVersion: "14.0"
        CFBundleURLTypes:
          - CFBundleURLName: as.ason.YoruMimizuku
            CFBundleURLSchemes:
              - as.ason
schemes:
  YoruMimizuku:
    build:
      targets:
        YoruMimizuku: all
    run:
      config: Debug
```

- [ ] **Step 3: `@main` アプリと最小ルートビューを作成**

Create `app/YoruMimizuku/YoruMimizukuApp.swift`:
```swift
import SwiftUI

@main
struct YoruMimizukuApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 420, height: 720)
    }
}
```

Create `app/YoruMimizuku/Views/ContentView.swift`:
```swift
import SwiftUI
import YoruMimizukuKit

/// Minimal root used to prove the app builds and links YoruMimizukuKit.
/// Replaced by `MainWindowView` in the next task.
struct ContentView: View {
    private let posts = PostDisplay.samples(now: Date())

    var body: some View {
        List(posts) { post in
            VStack(alignment: .leading, spacing: 2) {
                Text(post.authorDisplayName).font(.headline)
                Text(post.body).font(.body)
            }
        }
        .frame(minWidth: 360, minHeight: 480)
    }
}
```

- [ ] **Step 4: プロジェクト生成とビルド**

Run:
```bash
xcodegen generate --spec /Users/asonas/workspace/yorumimizuku/.worktrees/feature/app-shell/project.yml --project /Users/asonas/workspace/yorumimizuku/.worktrees/feature/app-shell
xcodebuild -project /Users/asonas/workspace/yorumimizuku/.worktrees/feature/app-shell/YoruMimizuku.xcodeproj -scheme YoruMimizuku -destination 'platform=macOS,arch=arm64' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```
Expected: `xcodegen` が `YoruMimizuku.xcodeproj` を生成し、`xcodebuild` が `** BUILD SUCCEEDED **` を出力する。これで「ネイティブアプリがビルドできる」状態に到達。

- [ ] **Step 5: Commit**

```bash
git -C /Users/asonas/workspace/yorumimizuku/.worktrees/feature/app-shell add project.yml .gitignore app/YoruMimizuku/YoruMimizukuApp.swift app/YoruMimizuku/Views/ContentView.swift
git -C /Users/asonas/workspace/yorumimizuku/.worktrees/feature/app-shell ai-commit
```
メッセージ例: `Add YoruMimizuku macOS app target via XcodeGen`

注: 生成された `YoruMimizuku.xcodeproj` は gitignore 済みのためコミットされない（`git status` で追跡対象外であることを確認する）。

---

### Task 5: 投稿行（密度A/B）とメインウィンドウ

**Files:**
- Create: `app/YoruMimizuku/Theme.swift`
- Create: `app/YoruMimizuku/Views/PostRowView.swift`
- Create: `app/YoruMimizuku/Views/MainWindowView.swift`
- Modify: `app/YoruMimizuku/YoruMimizukuApp.swift`（ルートを `MainWindowView` に差し替え）

- [ ] **Step 1: テーマ定数を作成**

Create `app/YoruMimizuku/Theme.swift`:
```swift
import SwiftUI

/// Minimal dark theme constants for the Yorufukurou-style UI.
enum Theme {
    static let background = Color(red: 0.11, green: 0.11, blue: 0.13)
    static let surface = Color(red: 0.14, green: 0.15, blue: 0.17)
    static let accent = Color(red: 0.36, green: 0.56, blue: 0.93)
    static let primaryText = Color(red: 0.87, green: 0.89, blue: 0.93)
    static let secondaryText = Color(red: 0.55, green: 0.58, blue: 0.64)
    static let divider = Color.white.opacity(0.06)
}
```

- [ ] **Step 2: 投稿行ビューを作成**

Create `app/YoruMimizuku/Views/PostRowView.swift`:
```swift
import SwiftUI
import YoruMimizukuKit

/// One timeline row, rendered compact (Yorufukurou-tight) or comfortable
/// (avatars + action counts) per `DisplayDensity`.
struct PostRowView: View {
    let post: PostDisplay
    let density: DisplayDensity
    let now: Date

    private let timeFormatter = RelativeTimeFormatter()

    private var relativeTime: String {
        timeFormatter.string(for: post.createdAt, now: now)
    }

    var body: some View {
        switch density {
        case .compact:
            compactBody
        case .comfortable:
            comfortableBody
        }
    }

    private var compactBody: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Theme.accent).frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                if let context = post.contextLabel {
                    Text(context).font(.caption2).foregroundStyle(Theme.secondaryText)
                }
                HStack(spacing: 4) {
                    Text(post.authorDisplayName).font(.caption).bold().foregroundStyle(Theme.primaryText)
                    Text("@\(post.authorHandle) · \(relativeTime)").font(.caption2).foregroundStyle(Theme.secondaryText)
                }
                Text(post.body).font(.callout).foregroundStyle(Theme.primaryText)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
    }

    private var comfortableBody: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(Theme.accent).frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                if let context = post.contextLabel {
                    Text(context).font(.caption).foregroundStyle(Theme.secondaryText)
                }
                HStack(spacing: 5) {
                    Text(post.authorDisplayName).font(.subheadline).bold().foregroundStyle(Theme.primaryText)
                    Text("@\(post.authorHandle) · \(relativeTime)").font(.subheadline).foregroundStyle(Theme.secondaryText)
                }
                Text(post.body).font(.body).foregroundStyle(Theme.primaryText)
                HStack(spacing: 22) {
                    Label("\(post.replyCount)", systemImage: "arrowshape.turn.up.left")
                    Label("\(post.repostCount)", systemImage: "arrow.2.squarepath")
                    Label("\(post.likeCount)", systemImage: "heart")
                }
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .labelStyle(.titleAndIcon)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
    }
}
```

- [ ] **Step 3: メインウィンドウビューを作成**

Create `app/YoruMimizuku/Views/MainWindowView.swift`:
```swift
import SwiftUI
import YoruMimizukuKit

/// The single-column main window: account chip, top tab bar, mock timeline,
/// and a bottom composer placeholder. Density toggle is added in the next step.
struct MainWindowView: View {
    @State private var density: DisplayDensity = .default
    @State private var selectedTab = "Home"

    private let now = Date()
    private let tabs = ["Home", "通知", "tech list", "検索"]
    private var posts: [PostDisplay] { PostDisplay.samples(now: now) }

    var body: some View {
        VStack(spacing: 0) {
            accountChip
            tabBar
            Divider().overlay(Theme.divider)
            timeline
            composer
        }
        .background(Theme.background)
        .frame(minWidth: 360, minHeight: 480)
    }

    private var accountChip: some View {
        HStack {
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(Theme.accent).frame(width: 16, height: 16)
                Text("@asonas.bsky.social").font(.caption).foregroundStyle(Theme.secondaryText)
                Image(systemName: "chevron.down").font(.caption2).foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.surface)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(tabs, id: \.self) { tab in
                Text(tab)
                    .font(.callout)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(selectedTab == tab ? Theme.accent : Color.clear)
                    .foregroundStyle(selectedTab == tab ? .white : Theme.secondaryText)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onTapGesture { selectedTab = tab }
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.surface)
    }

    private var timeline: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(posts) { post in
                    PostRowView(post: post, density: density, now: now)
                    Divider().overlay(Theme.divider)
                }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            Text("いまどうしてる?")
                .font(.callout)
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Theme.background)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            Text("Post")
                .font(.callout).bold()
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .padding(8)
        .background(Theme.surface)
    }
}
```

- [ ] **Step 4: アプリのルートを差し替え**

`app/YoruMimizuku/YoruMimizukuApp.swift` の `ContentView()` を `MainWindowView()` に変更:
```swift
import SwiftUI

@main
struct YoruMimizukuApp: App {
    var body: some Scene {
        WindowGroup {
            MainWindowView()
        }
        .defaultSize(width: 420, height: 720)
    }
}
```
（`ContentView.swift` は削除してよいが、残しても害はない。削除する場合は `git rm` し、project.yml の sources はディレクトリ指定なので再生成不要。）

- [ ] **Step 5: 再生成とビルド**

Run:
```bash
xcodegen generate --spec /Users/asonas/workspace/yorumimizuku/.worktrees/feature/app-shell/project.yml --project /Users/asonas/workspace/yorumimizuku/.worktrees/feature/app-shell
xcodebuild -project /Users/asonas/workspace/yorumimizuku/.worktrees/feature/app-shell/YoruMimizuku.xcodeproj -scheme YoruMimizuku -destination 'platform=macOS,arch=arm64' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```
Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 6: Commit**

```bash
git -C /Users/asonas/workspace/yorumimizuku/.worktrees/feature/app-shell add app/YoruMimizuku
git -C /Users/asonas/workspace/yorumimizuku/.worktrees/feature/app-shell ai-commit
```
メッセージ例: `Add Yorufukurou-style main window and post row`

---

### Task 6: 密度トグル（既定B）と仕上げ

**Files:**
- Modify: `app/YoruMimizuku/Views/MainWindowView.swift`（密度切替 UI を追加）

- [ ] **Step 1: 密度トグルを追加**

`MainWindowView` の `tabBar` の `Spacer()` の直後（`ForEach` の外、`HStack` 内の末尾）に密度切替の Picker を追加する。`tabBar` プロパティを次の実装に置き換える:
```swift
    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(tabs, id: \.self) { tab in
                Text(tab)
                    .font(.callout)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(selectedTab == tab ? Theme.accent : Color.clear)
                    .foregroundStyle(selectedTab == tab ? .white : Theme.secondaryText)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onTapGesture { selectedTab = tab }
            }
            Spacer()
            Picker("表示密度", selection: $density) {
                Text("コンパクト").tag(DisplayDensity.compact)
                Text("ゆとり").tag(DisplayDensity.comfortable)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 120)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.surface)
    }
```
`@State private var density: DisplayDensity = .default` は既存のまま（既定は `.comfortable` = B）。Picker で `.compact`（A）に切り替えると `timeline` の各行が即座に密表示になる（`PostRowView` は `density` を受け取って分岐済み）。

- [ ] **Step 2: 再生成とビルド**

Run:
```bash
xcodegen generate --spec /Users/asonas/workspace/yorumimizuku/.worktrees/feature/app-shell/project.yml --project /Users/asonas/workspace/yorumimizuku/.worktrees/feature/app-shell
xcodebuild -project /Users/asonas/workspace/yorumimizuku/.worktrees/feature/app-shell/YoruMimizuku.xcodeproj -scheme YoruMimizuku -destination 'platform=macOS,arch=arm64' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```
Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 3: 全パッケージテストの非回帰確認**

Run: `swift test --package-path BlueskyCore`
Expected: すべて PASS（BlueskyCore + YoruMimizukuKit）。

- [ ] **Step 4: Commit**

```bash
git -C /Users/asonas/workspace/yorumimizuku/.worktrees/feature/app-shell add app/YoruMimizuku/Views/MainWindowView.swift
git -C /Users/asonas/workspace/yorumimizuku/.worktrees/feature/app-shell ai-commit
```
メッセージ例: `Add display density toggle to main window`

- [ ] **Step 5: 起動確認（任意・ユーザー向け）**

ビルド成功で完了。手元で起動して見た目を確認する場合:
```bash
open /Users/asonas/workspace/yorumimizuku/.worktrees/feature/app-shell/build/Build/Products/Debug/YoruMimizuku.app 2>/dev/null \
  || open "$(xcodebuild -project /Users/asonas/workspace/yorumimizuku/.worktrees/feature/app-shell/YoruMimizuku.xcodeproj -scheme YoruMimizuku -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2}')/YoruMimizuku.app"
```
あるいは生成済みの `YoruMimizuku.xcodeproj` を Xcode で開いて Run。

- [ ] **Step 6: ブランチ仕上げ**

`superpowers:finishing-a-development-branch` に従い `feature/app-shell` の取り込み方法を選ぶ。

---

## Self-Review

**1. Spec coverage:**
- §4.1 `BlueskyMac` アプリ層（SwiftUI、WindowGroup）→ Task 4/5（`YoruMimizukuApp`, `MainWindowView`）。
- §7.1 ウィンドウ構成（アカウントチップ・上部タブ・単一カラム・下部コンポーザ）→ Task 5（`MainWindowView`）。
- §7.2 投稿行の密度 A/B、既定 B → Task 1（`DisplayDensity`、default=comfortable）＋ Task 5（`PostRowView` の分岐）＋ Task 6（トグル）。
- OS バンドル/URL スキーム（OAuth 準備）→ Task 4（`project.yml` の `CFBundleURLTypes` に `as.ason`）。
- 本プラン対象外（後続）: 実 OAuth・実タイムライン取得・ストリーム・通知・複数ウィンドウ/アカウント。モックデータで殻のみ。スコープ逸脱なし。

**2. Placeholder scan:** プレースホルダなし。各コードステップは完全なコードを含む。モックデータ（`PostDisplay.samples`）は本プランの意図的な範囲。

**3. Type consistency:**
- `DisplayDensity`（`.compact`/`.comfortable`/`.default`）は Task 1 定義、Task 5 `PostRowView` の `switch`、Task 6 Picker の `.tag` で一致。
- `RelativeTimeFormatter().string(for:now:)` は Task 2 定義、Task 5 `PostRowView` で一致。
- `PostDisplay`（`id`/`authorDisplayName`/`authorHandle`/`body`/`createdAt`/`contextLabel`/`replyCount`/`repostCount`/`likeCount`）は Task 3 定義、Task 4/5 ビューのプロパティ参照で一致。`samples(now:)` も同様。
- `project.yml` の依存（`product: BlueskyCore` / `product: YoruMimizukuKit`）は Task 1 の `Package.swift` products と一致。アプリの `import YoruMimizukuKit` が解決可能。
- アプリのエントリは Task 4 で `ContentView`、Task 5 で `MainWindowView` に差し替え（`YoruMimizukuApp` の body を更新）。整合済み。

## 次プランへの申し送り
- 本プランはモックデータの殻。Plan: OAuth（識別子解決・discovery・PAR・PKCE・トークン交換・`use_dpop_nonce` 再試行・`ASWebAuthenticationSession`・Keychain・`AccountManager`）で実ログインを実装し、`MainWindowView` のアカウントチップとサインイン導線を実データに接続する。
- `project.yml` に登録済みの URL スキーム `as.ason` を OAuth コールバック（`as.ason:/callback`）受けに使う。`ASWebAuthenticationSession` はバンドル化された本アプリで動作する。
- `PostDisplay` への実データマッピング（`BlueskyCore` の `PostView` → `PostDisplay`）は読み取り API プラン（getTimeline 等）で追加する。
- パッケージ名 `BlueskyCore` が `YoruMimizukuKit` も含む点は、将来パッケージ名を中立化する際に整理する。
