# iPadOS タイムライン parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** iPadOS 版のタイムライン描画とリッチメディアを macOS と同等の振る舞いにする。テーマ／書体、表示密度、単一画像の 5:4 クロップ、複数画像グリッド、動画ポスター、リンクカード、引用カード、センシティブぼかし、返信マーカー、スレッドグルーピング、幅リフロー、読み込み失敗の分類、自分の投稿削除までを `apps/ipados` に実装する。macOS アプリと共有コアは変更しない。

**Architecture:** macOS の表示基盤はほぼ AppKit 非依存の SwiftUI（`ThemeStore` / `RemoteImage` / `ImageDownsampler` / 各カード）であり、唯一 `Typography`（`NSFont`/`NSFontManager`）だけが AppKit に依存する。本計画は設計スペック §5 の決定 (A)「いまは `apps/ipados` に複製、共有モジュール化は後日」に従い、AppKit 非依存ファイルを複製し、`Typography` だけ `UIFont` 版を新規に書く。表示ロジック（`TimelineLayout`・`FeedThreading`）は `YoruMimizukuKit`（テスト済み・共有）をそのまま使う。

**Tech Stack:** Swift 6.0 / SwiftUI（iOS 17+）/ UIKit edges / XcodeGen / SPM（core パッケージ）/ XCTest（core のみ）

ワークツリー: `/Users/asonas/ghq/github.com/asonas/YoruMimizuku/.worktrees/feature/ipados-parity`（ブランチ `feature/ipados-parity`）。

## Global Constraints

- 作業は上記ワークツリー内で行う。`cd` で絶対パスへ移動せず、ワークツリー内でそのままコマンドを実行する。**main では絶対にコミットしない。** 各ステップ冒頭で `git rev-parse --show-toplevel` と `git branch --show-current` を確認する。
- `YoruMimizukuKit` は Windows / Linux と共有されるため Apple フレームワーク非依存に保つ。SwiftUI/UIKit のコードを `YoruMimizukuKit` に入れない。
- **macOS アプリ（`apps/macos`）と共有コアのファイルは変更しない。** 触るのは `apps/ipados/`・`project.yml`（iPad ターゲットのソース追加があれば）・`docs/`。
- コミットは必ず `/commit` スキル（`git ai-commit`）で作成する。`git commit` を直接実行しない。メッセージは英語・先頭大文字・Conventional Commits 不使用。
- `YoruMimizuku.xcodeproj` と各 `Info.plist` は生成物（gitignore 済み）。ビルド前に必ず `xcodegen generate` を実行する。
- iPad のビルド確認コマンド: `xcodebuild build -scheme YoruMimizukuPad -project YoruMimizuku.xcodeproj -destination 'generic/platform=iOS Simulator' 2>&1 | tail -8`。
- 複製ファイルは macOS 版とできるだけ同一に保ち、差分は「AppKit→UIKit の置換」と「不要な機能（randoma11y 設定 UI 等）の除外」に限定する。将来の共有モジュール化（スペック §5 の (B)）を容易にするため、構造を勝手に変えない。

---

## Phase 0 — Presentation foundation on iPad

iPad 上にテーマ・書体・画像基盤を用意し、ルートに環境オブジェクトとして注入する。以降の全フェーズの前提。

### Task 0.1: ベースラインのビルド確認

現状の iPad ターゲットがビルドできること、`PlatformApple` と `ImageDownsampler` が iOS でコンパイルできる前提を検証する（後続の複製の土台）。

**Files:** （変更なし／生成のみ）

- [ ] **Step 1: ワークツリーを確認する**
  Run: `git rev-parse --show-toplevel && git branch --show-current`
  Expected: `.worktrees/feature/ipados-parity` と `feature/ipados-parity`。
- [ ] **Step 2: プロジェクトを生成する**
  Run: `xcodegen generate`
  Expected: `YoruMimizuku.xcodeproj` 生成。
- [ ] **Step 3: 現状の iPad ターゲットをビルドする**
  Run: iPad ビルドコマンド（Global Constraints 参照）。
  Expected: `BUILD SUCCEEDED`。失敗する場合は、まず素のビルドを通すことが Task 0.1 の成果物。エラーを記録する。
- [ ] **Step 4: 記録**
  ビルド結果（成功 / 既知の警告）を実装ノートに残す。コミットは不要（生成物のみ）。

### Task 0.2: テーマと密度ストアを複製する

`ThemeStore`（AppKit 非依存）と密度ストアを `apps/ipados` に複製する。`FontSettingsStore`（`NSFontManager` 依存）は複製しない。

**Files:**
- Create: `apps/ipados/Theme.swift`（macOS `apps/macos/Theme.swift` を複製。`import` は SwiftUI + YoruMimizukuKit のまま、AppKit 不要）
- Create: `apps/ipados/DisplaySettings.swift`（macOS 版から `DisplaySettingsStore`（density）だけを抜き出す。`FontSettingsStore` と AppKit `import` は含めない）

**Interfaces:**
- Consumes: `YoruMimizukuKit`（`PaletteColor` / `ThemePalette` / `RandomA11yURLParser` / `DisplayDensity`）
- Produces: `ThemeStore`（`@MainActor ObservableObject`、`canvas` / `primaryText` / `accent` / `divider` / `rowHover` / `hairline` 等）、`DisplaySettingsStore`（`density`）

- [ ] **Step 1: `Theme.swift` を複製する** — macOS 版をそのままコピー。`Color(hex:)` / `Color(_:PaletteColor)` 拡張と `ThemeStore` を含む。AppKit import は元から無いので変更不要。
- [ ] **Step 2: `DisplaySettings.swift` を作る** — macOS 版の `DisplaySettingsStore`（density、SwiftUI + YoruMimizukuKit のみ）だけを移植する。`import AppKit` と `FontSettingsStore`（`NSFontManager` 依存）は除外する。
- [ ] **Step 3: ビルド**（Task 0.4 で `Typography` 追加後にまとめて実施するため、ここではコンパイル単体確認は省略可。複製のみ）。
- [ ] **Step 4: Commit** — `/commit`。対象: 上記2ファイル。例: `Add ThemeStore and density store to the iPad target`。

### Task 0.3: 画像基盤を複製する

`RemoteImage` と `ImageDownsampler` を複製する。両者とも AppKit 非依存（ImageIO/CoreGraphics、`CGImage` を生成）。

**Files:**
- Create: `apps/ipados/Media/RemoteImage.swift`（macOS 版を複製）
- Create: `apps/ipados/Media/ImageDownsampler.swift`（macOS 版を複製。`import Foundation/CoreGraphics/ImageIO/YoruMimizukuKit/PlatformApple` のまま）

**Interfaces:**
- Consumes: `PlatformApple`（`ImageDownsampler` が利用）、`YoruMimizukuKit`
- Produces: `RemoteImage<Content>`、`RemoteImagePhase`、`ImageDownsampler.shared`

- [ ] **Step 1: 2ファイルを複製する。**
- [ ] **Step 2: `PlatformApple` の iOS コンパイルを確認する** — `ImageDownsampler` の依存。Task 0.1 でターゲットに `PlatformApple` が無ければ project.yml の `YoruMimizukuPad` dependencies に既にあること（既存）を確認する。コンパイルエラーが出たら、iOS で使えない API を `#if os(iOS)` で切る（最小限）。
- [ ] **Step 3: Commit** — `/commit`。対象: 上記2ファイル。例: `Add downsampling RemoteImage to the iPad target`。

### Task 0.4: UIFont ベースの Typography を追加する

`Font.app(_:weight:)` / `Font.appSize(_:weight:)` を iPad 用に新規実装する。macOS の `NSFont.preferredFont(forTextStyle:)` を `UIFont.preferredFont(forTextStyle:)` に置き換える。フォントファミリ選択（`NSFontManager`）は持たず、既定の Hiragino Sans を使う。

**Files:**
- Create: `apps/ipados/Typography.swift`

**Interfaces:**
- Produces: `enum AppTypography`（`systemDefaultFamily`、`referenceBodySize`、`sizeRatio`）、`extension Font { static func app(...); static func appSize(...) }`

- [ ] **Step 1: `Typography.swift` を書く** — 構成は macOS 版に合わせつつ AppKit を UIKit に置換:
  - `import SwiftUI` + `import UIKit`
  - `AppTypography.systemDefaultFamily = "Hiragino Sans"`、`family` は固定（picker なし）。
  - `referenceBodySize = UIFont.preferredFont(forTextStyle: .body).pointSize`
  - `sizeRatio` は当面 `1`（baseSize 変更 UI を持たないため）。将来の拡張余地としてプロパティは残す。
  - `Font.app(_ style:weight:)`: `standardSize(style)` を `UIFont.preferredFont(forTextStyle: uiTextStyle(style)).pointSize` から取り、`Font.custom(family, size:relativeTo: style).weight(...)`。
  - `uiTextStyle(_:)`: SwiftUI `Font.TextStyle` → `UIFont.TextStyle`（`.largeTitle/.title1/.title2/.title3/.headline/.subheadline/.body/.callout/.footnote/.caption1/.caption2`）。
  - `defaultWeight`: `.headline` は `.semibold`、他は `.regular`。
- [ ] **Step 2: ビルド** — iPad ビルドコマンド。Expected: `BUILD SUCCEEDED`（Theme/RemoteImage/Typography が揃ってコンパイル）。
- [ ] **Step 3: Commit** — `/commit`。対象: `apps/ipados/Typography.swift`。例: `Add UIFont-based app typography to the iPad target`。

### Task 0.5: ルートにテーマ・密度を注入し canvas を適用する

`RootView`（または `MainShellView`）に `ThemeStore` と `DisplaySettingsStore` を `@StateObject` で持たせ、`environmentObject` で配下に流し、背景に `theme.canvas` を敷く。

**Files:**
- Modify: `apps/ipados/Views/RootView.swift`

**Interfaces:**
- Consumes: `ThemeStore`、`DisplaySettingsStore`、`theme.canvas`
- Produces: 環境オブジェクトとして配下のビューが `@EnvironmentObject theme` / `displaySettings` を参照可能になる

- [ ] **Step 1: ストアを生成する** — `RootView` に `@StateObject private var theme = ThemeStore()` と `@StateObject private var displaySettings = DisplaySettingsStore()` を追加。
- [ ] **Step 2: environment に流す** — トップの `Group { ... }` に `.environmentObject(theme).environmentObject(displaySettings)` を付与。`MainShellView` の `NavigationSplitView` 背景またはルートに `theme.canvas` を `.background { }` で適用（`List` 側は後フェーズで `scrollContentBackground(.hidden)` 化）。
- [ ] **Step 3: ビルド** — iPad ビルド。Expected: `BUILD SUCCEEDED`。現行の簡易 `PostRowView` はまだ `theme` を参照しないので見た目は大きく変わらない（背景のみ）。
- [ ] **Step 4: Commit** — `/commit`。対象: `apps/ipados/Views/RootView.swift`。例: `Inject ThemeStore and density into the iPad scene`。

---

## Phase 1 — Row + media parity

カード類を複製し、iPad `PostRowView` を macOS 構造に書き換える。

### Task 1.1: カード／ライトボックスを複製する

`LinkCardView`・`QuoteCardView`・`VideoPosterView` を複製する（いずれも `ThemeStore` + `.app()` + `RemoteImage` のみに依存、AppKit 非依存）。iPad には既に `ImageLightboxView` があるため、macOS 版との差分を確認し、必要なら寄せる。`LazyLinkCardView` の実体（OGP 取得）が macOS 側のどこにあるかを確認し、依存（OGP ローダ）ごと複製する。

**Files:**
- Create: `apps/ipados/Views/LinkCardView.swift`、`apps/ipados/Views/QuoteCardView.swift`、`apps/ipados/Views/VideoPosterView.swift`
- Investigate/Modify: `apps/ipados/Views/ImageLightboxView.swift`（macOS 版と揃える）
- Investigate: `LazyLinkCardView` と OGP ローダの所在（`apps/macos` 配下か `YoruMimizukuKit` か）を確認し、UI 部分のみ複製・コア部分は共有

**Interfaces:**
- Consumes: `ThemeStore`、`Font.app`、`RemoteImage`、`YoruMimizukuKit`（`EmbedCard` / `QuotedPost` / `PostVideo` 等のモデル）
- Produces: `LinkCardView`、`QuoteCardView`、`VideoPosterView`、（必要なら）`LazyLinkCardView`

- [ ] **Step 1: macOS の3カードと `LazyLinkCardView` / OGP ローダの依存を洗い出す**（`grep` で import と型参照を確認）。コアにある OGP ローダは複製せず共有する。
- [ ] **Step 2: 3カードを複製する。** AppKit が出てこないことを確認。
- [ ] **Step 3: `LazyLinkCardView`（OGP フォールバック）を iPad に用意する** — UI は複製、ローダはコア共有。
- [ ] **Step 4: `ImageLightboxView` を macOS と揃える**（差分があれば）。
- [ ] **Step 5: ビルド** — iPad ビルド。Expected: `BUILD SUCCEEDED`（カードはまだ未使用でも単体でコンパイル可）。
- [ ] **Step 6: Commit** — `/commit`。例: `Port link, quote, and video embed cards to the iPad target`。

### Task 1.2: iPad `PostRowView` を macOS 構造に書き換える（縦積み版）

iPad の `PostRowView` を macOS 版の構造に置き換える。この段階では **縦積みレイアウトのみ**（リフローは Phase 2）。テーマ／密度／5:4 クロップ／グリッド／動画／リンク／引用／センシティブぼかし／返信マーカー／コンテキストラベル／アクションバー／コピー／削除メニューを揃える。ホバーは無し（タッチ向け）、フォーカス背景はテーマ色に。

**Files:**
- Modify: `apps/ipados/Views/PostRowView.swift`（全面改稿）

**Interfaces:**
- Consumes: `ThemeStore`、`DisplayDensity`、`Font.app`、`RemoteImage`、`TimelineLayout`（`clampedSingleImageRatio` / `isTallCropped`）、`LinkCardView` / `QuoteCardView` / `VideoPosterView`（Task 1.1）、`RelativeTimeFormatter`、`PostPermalink`、`ATURI`、`MediaWarning`
- Produces: 既存の呼び出し側コールバック（`onImageTap` / `onOpenThread` / `onOpenAuthor` / `onReply` / `onQuote` / `onToggleLike` / `onToggleRepost` / `onCopyPermalink` / `onOpenPermalink`）は保持。macOS の `density`・`canDelete`・`onDelete`・`showReplyMarker`・`contextLabel`・`replyParent` 対応を追加。

- [ ] **Step 1: macOS `PostRowView` を土台に iPad 版を書く。** 主な置換:
  - 書体は `.app(...)`、色は `theme.*`。
  - `density` プロパティを受け取り（`DisplayDensity`、`@EnvironmentObject displaySettings` から呼び出し側で渡す）、アバターサイズ・間隔・パディングを密度依存に。
  - 単一画像は `TimelineLayout.clampedSingleImageRatio` + `isTallCropped` + `tallCropHint`（macOS の `singleImage` を移植、`RemoteImage` 使用）。
  - 複数画像は `RemoteImage` グリッド。
  - `VideoPosterView` / `LinkCardView`（+`LazyLinkCardView`）/ `QuoteCardView` を組み込む。
  - センシティブメディアのぼかしカーテン（`post.mediaWarning` + `revealMedia` State）を移植。
  - 返信マーカー（`replyMarker`）・コンテキストラベル（`contextHeader`）を移植。
  - アクションバーは可視ボタン（reply / repost(+quote) / like / copy / open）。iPad は macOS のポップオーバーではなく、`Menu` か可視ボタン+確認で repost/quote を出す（タッチ向け）。
  - 削除: `canDelete` のとき context menu に「削除」を追加（実際の確認ダイアログは Phase 2 の feed 側）。
  - macOS 固有の `onHover` / `help(...)` / `NSPasteboard` 等は使わない。
- [ ] **Step 2: `TimelineListView` 側の `PostRowView(...)` 呼び出しを更新する** — `density: displaySettings.density` を渡す（`@EnvironmentObject` を `TimelineListView` に追加）。`canDelete` の判定（`ATURI.repo(post.id) == currentDID`）に必要な `currentDID` を配線（無ければ後続で追加、本タスクでは false 固定でも可）。
- [ ] **Step 3: ビルド** — iPad ビルド。Expected: `BUILD SUCCEEDED`。
- [ ] **Step 4: シミュレータで見た目を確認する** — テーマ色・書体、縦長画像の 5:4 クロップ + 「全体表示」、複数画像グリッド、動画ポスター、リンクカード、引用カード、センシティブぼかし、返信マーカーが macOS 同等に出ること。
- [ ] **Step 5: Commit** — `/commit`。対象: `apps/ipados/Views/PostRowView.swift`、`apps/ipados/Views/TimelineListView.swift`。例: `Rewrite the iPad post row to match macOS rendering`。

---

## Phase 2 — Feed shell parity

`TimelineListView`（と関連）を macOS `FeedView` 同等にする。

### Task 2.1: スレッドグルーピングとテーマ化リスト

`FeedThreading.arrange` で同一スレッドを束ね、アバター下のコネクタ線・ブロック内ディバイダ省略・テーマ色 canvas/divider を適用する。フォーカス強調をテーマ色に。

**Files:**
- Modify: `apps/ipados/Views/TimelineListView.swift`、`apps/ipados/Views/PostRowView.swift`（`connectsToPrevious/Next` とコネクタ線描画を移植）

**Interfaces:**
- Consumes: `FeedThreading.arrange`（`YoruMimizukuKit`、テスト済み）、`ThemeStore`
- Produces: スレッドブロック表示、`PostRowView` の `connectsToPrevious` / `connectsToNext`

- [ ] **Step 1:** `TimelineListView` の `List` を `FeedThreading.arrange(posts)` ベースに変更し、各行に `connectsToPrevious/Next` を渡す。ブロック末尾以外は divider を省略（macOS `FeedView` の構造を移植）。
- [ ] **Step 2:** `PostRowView` にアバター下コネクタ線を移植（macOS `avatarColumn` / `threadLine`）。
- [ ] **Step 3:** `.listStyle(.plain)` + `.scrollContentBackground(.hidden)` + `theme.canvas` 背景、`theme.divider`、フォーカス背景 `theme.rowHover` + 左 accent バー。
- [ ] **Step 4:** ビルド + シミュレータ確認（返信チェーンが束ねて表示・コネクタ線が出る）。
- [ ] **Step 5: Commit** — 例: `Group reply chains and theme the iPad feed list`。

### Task 2.2: 読み込み失敗の分類・空・ローディング状態と削除確認

macOS `FeedView` の `failedState`（offline/429/5xx アイコン + 再試行）・`emptyState`・`loadingState`・削除確認ダイアログを移植する。

**Files:**
- Modify: `apps/ipados/Views/TimelineListView.swift`

**Interfaces:**
- Consumes: `LoadFailure`（`kind` / `title` / `message`、`YoruMimizukuKit`）、`TimelineViewModel.deletePost`
- Produces: 分類された失敗表示、確認ダイアログ

- [ ] **Step 1:** `model.state == .failed(failure)` を `LoadFailure` の `kind` でアイコン分岐（`wifi.slash` / `hourglass` / `exclamationmark.icloud` / `exclamationmark.triangle`）+ タイトル/本文 + 「再試行」。
- [ ] **Step 2:** 空・ローディング状態を macOS 同等の文言（「まだ投稿がありません」「夜空を眺めています…」）に。
- [ ] **Step 3:** 自分の投稿削除の `confirmationDialog`（「この投稿を削除しますか？」）を移植し、`PostRowView` の削除メニューと配線。`currentDID` を `RootView` から `TimelineListView` まで渡す。
- [ ] **Step 4:** ビルド + シミュレータ確認（機内モードで失敗表示、自分の投稿で削除確認）。
- [ ] **Step 5: Commit** — 例: `Classify load failures and add delete confirmation on iPad`。

### Task 2.3: シーン幅で幅リフロー

シーン（detail 列）の幅を測って `PostRowView.contentWidth` に渡し、`TimelineLayout.placement` で縦積み／リフローを分岐する。iPad 横画面で本文左・メディア右になる。

**Files:**
- Modify: `apps/ipados/Views/TimelineListView.swift`（幅計測）、`apps/ipados/Views/PostRowView.swift`（`contentWidth` プロパティと `content` の分岐・`mediaColumn`/`verticalMedia`/`regionWidth` を macOS から移植）

**Interfaces:**
- Consumes: `TimelineLayout.placement(regionWidth:)`、`TimelineLayout.mediaRailWidth`、`TimelineLayout.columnGap`
- Produces: `PostRowView.contentWidth`

- [ ] **Step 1:** `PostRowView` に `contentWidth` を追加し、macOS の `content` 分岐・`mediaColumn(maxWidth:)`・`verticalMedia`・`regionWidth(forContentWidth:)` を移植（dev.12 の C 案＝本文 fill / メディア右ピン）。
- [ ] **Step 2:** `TimelineListView` の `List` に `.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }` を付け、各行へ渡す。
- [ ] **Step 3:** ビルド + シミュレータ確認（縦向き=縦積み、横向き/広い split=リフロー、縦長画像が右レールに収まる）。
- [ ] **Step 4: Commit** — 例: `Reflow iPad timeline rows to media-right when wide`。

---

## Phase 3 — Settings & remaining features（優先度低・後日詳細化）

Phases 0–2 着地後に、必要に応じて詳細タスク化する。候補:

- 表示密度トグル（comfortable / compact）の設定 UI。
- テーマ（randoma11y）設定 UI（任意）。
- 構造化フィルタエディタ（現状はキーワード検索タブのみ）。
- 通知設定（ポーリング間隔・バッジ）。
- カスタムフォントファミリ選択（`UIFont` ファミリ列挙が必要、最後）。

各項目は macOS の対応ビュー（`SettingsView` / `FilterEditorView` / `NotificationSettings`）を touch-first に移植する方針。

---

## Phase 4 — Docs & verification

### Task 4.1: wiki 更新と最終検証

挙動が変わったので LLM-wiki を更新し、ビルドで仕上げる。

**Files:**
- Modify: `docs/wiki/platforms/ipados.md`、関連 behavior ページ（`timeline-media-layout` / `timeline-streaming` / `sensitive-media` / `app-shell`）の `features:` frontmatter（iOS ステータス）
- 参照: `docs/wiki/conventions.md`

- [ ] **Step 1:** core テスト全件（`cd core && swift test`）。Expected: 既存テスト全 PASS（本計画は core を変更しない想定なので緑のまま）。
- [ ] **Step 2:** iPad シミュレータビルド。Expected: `BUILD SUCCEEDED`。
- [ ] **Step 3:** `wiki-update` スキルで本 spec/plan と実装後挙動を取り込み、`docs/wiki/platforms/ipados.md` の Known differences を更新、behavior ページの iOS ステータスを実態（`full`/`differs`）に更新。
- [ ] **Step 4:** `mise run wiki:lint` と `mise run wiki:matrix` / `mise run wiki:index`（生成物は手編集しない）。
- [ ] **Step 5: Commit** — 例: `Document iPad timeline parity in the wiki`。

### Task 4.2: ブランチ仕上げ

- [ ] superpowers:finishing-a-development-branch に従い、main へのマージ可否・PR 作成をユーザーに確認する。リリース（バージョン採番・配信）は macOS と異なり iPad は App Store 経路のため、別途方針確認。

---

## Self-Review

- **Spec coverage:** スペック §4 のパリティ表の各行に対応タスクあり — 書体/色=Task 0.2/0.4/1.2、密度=0.2/0.5/1.2、5:4 クロップ=1.2、グリッド=1.2、動画/リンク/引用=1.1/1.2、ぼかし=1.2、返信マーカー=1.2、スレッドグルーピング=2.1、リフロー=2.3、フォーカス=2.1、失敗分類=2.2、削除=1.2(メニュー)/2.2(確認)、設定=Phase 3、フィルタ/通知設定=Phase 3。
- **Architecture decision:** スペック §5 の (A) 複製方針に一貫。macOS と共有コアは不変。`Typography` のみ UIFont で新規。
- **Risk-first:** Task 0.1 で iPad ビルドと `PlatformApple`/`ImageDownsampler` の iOS コンパイルを先に検証してから深い移植に入る。
- **Placeholder scan:** TBD/TODO・曖昧表現なし。Phases 3–4 は意図的に概要のみで、0–2 着地後に詳細化する旨を明記。
- **Working-directory discipline:** Global Constraints と各 Task 冒頭でワークツリー/ブランチ確認を要求（過去の main 誤コミット対策）。
