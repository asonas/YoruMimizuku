# Hoshidukiyo cmux 風サイドバー再設計プラン

**Goal:** 縦タブサイドバー（ホーム / 通知 / 会話タブ）の見た目と密度を、参照アプリ [cmux](https://github.com/manaflow-ai/cmux) のサイドバーに合わせて作り直す。会話タブを「表示名 + 本文スニペット + `@handle`」のリッチ行にし、選択スタイル・タイトルバー周りも cmux に倣って統合する。

**Architecture:** サイドバーのタブ状態は `WorkspaceModel`（`@MainActor ObservableObject`）が保持し、`MainWindowView` の `NavigationSplitView` がそれを描画する。行コンポーネント `SidebarRow` は表示専用で、テーマ色は `ThemeStore`（`@EnvironmentObject`）から受け取る。会話タブ 1 件は `ConversationTab`（`ThreadViewModel` を所有）。

**Tech Stack:** Swift 6 / SwiftUI / XcodeGen / 対象 macOS 26.0。表示ロジックは `HoshidukiyoKit`、ビューはアプリターゲット `Hoshidukiyo`。

このプランは UI レイヤ（サイドバー）のみを対象とし、配色パレット（randoma11y 由来の `ThemeStore`）やタイムライン取得・スレッド取得のロジックは変更しない。

## 背景

直前の縦タブ再設計（`NavigationSplitView` + `SidebarView`）に対して「期待する見た目と違う」とフィードバックがあり、目標として cmux のサイドバーが提示された。cmux は OSS のネイティブ macOS アプリなので、実装を読んで設計言語を移植する方針とした。

## cmux 調査の知見（実測値）

cmux はネイティブ SwiftUI 製。サイドバー行の本体は `Sources/ContentView.swift` の `struct TabItemView`、色は `Sources/Sidebar/SidebarAppearanceSupport.swift`。

- アクセント色: dark で `rgb(0,145,255)` = `#0091FF`、light で `#0088FF`。
- 選択行は**ソリッド塗り**（`RoundedRectangle(cornerRadius: 6)` をアクセントで塗る）。薄塗り tint や左バーだけではない。前景は背景に対して読める色（暗い背景なら白）へ反転（`sidebarSelectedWorkspaceForegroundNSColor`）。
- 行レイアウト: `VStack(alignment:.leading, spacing: 4)`、`padding(.horizontal:10, .vertical:8)`、リスト外周は `padding(.horizontal:6)`。
- タイポ:
  - タイトル `font(.system(size: 12.5, weight: .semibold))`
  - サブタイトル/説明 `size 10`、最大 2 行、`secondary` 0.8
  - ブランチ/メタ `size 10, design: .monospaced`
  - ピン `pin.fill` `size 9 .semibold`
- 閉じる: `xmark` `size 9 .medium` を **hover 時のみ右上**（`.overlay(alignment:.topTrailing)`）に表示。
- 未読バッジ: 円 + 数字（`size 9 .semibold`）。
- アクティブ表示スタイルは `leftRail`（左の細いバー）と `solidFill`（全面塗り）の 2 種。今回参照したスクショは `solidFill`。
- ウィンドウは大きなタイトル文字を持たない統合タイトルバー。

## 設計方針（cmux → Hoshidukiyo マッピング）

| cmux | Hoshidukiyo |
| --- | --- |
| ワークスペース行（title + description + branch） | 会話タブ行（表示名 + 本文スニペット + `@handle`） |
| ソリッド塗り選択 + 前景反転 | 選択時は `theme.accent` 塗り + 文字を白に固定 |
| ピン留めワークスペース | ホーム / 通知（アイコン + タイトルのみのナビ行） |
| hover で閉じる | 会話タブのみ hover で `xmark` |
| 統合タイトルバー | `.windowStyle(.hiddenTitleBar)` |

- 配色は `ThemeStore` を尊重し、cmux の `#0091FF` は強制しない。選択行のみ「アクセント塗り + 白文字」を固定する（indigo/blue いずれのパレットでも白文字が読める前提）。
- 角丸・余白・タイポは cmux の実測値にほぼ合わせる（タイトル 12.5、サブ 11、メタ 10 monospaced、角丸 6、行余白 H10/V8、外周 H6）。

## File Structure

- `app/Hoshidukiyo/Workspace/WorkspaceModel.swift` — `ConversationTab` に `subtitle`(本文) と `handle` を追加（変更）
- `app/Hoshidukiyo/Views/SidebarView.swift` — `SidebarRow` を cmux 流に再設計（変更）
- `app/Hoshidukiyo/HoshidukiyoApp.swift` — `.windowStyle(.hiddenTitleBar)` と既定サイズ 940×720（変更）
- `app/Hoshidukiyo/Diagnostics/FPSOverlay.swift` — オーバーレイ位置を左上→右下へ（変更）

## 実装タスク（実施済み）

- [x] **Task 1: `ConversationTab` の情報拡張**
  - `subtitle`（アンカー投稿の本文、トリム済み）と `handle`（`@handle`）を追加。`title` は表示名（空なら `@handle` フォールバック）。
- [x] **Task 2: `SidebarView` の行を cmux 流に**
  - 選択 = `RoundedRectangle(cornerRadius: 6)` の**ソリッド塗り + 白文字**（旧: 薄塗り + 左キャップバー）。
  - ナビ行（ホーム/通知）= アイコン + タイトル。会話行 = 表示名(12.5 semibold) + 本文(11, 最大2行) + `@handle`(10 monospaced)。
  - 閉じるは hover 時のみ右上。余白・角丸を cmux 実測値に合わせる。
- [x] **Task 3: ウィンドウクローム統合**
  - `.windowStyle(.hiddenTitleBar)` で大きなタイトルを廃止、既定サイズを 2 カラム向け 940×720 に。
  - ブランドに `padding(.top, 30)` を入れて信号機ボタンとの重なりを回避。
- [x] **Task 4: FPS オーバーレイの退避**
  - DEBUG 専用オーバーレイを `.topLeading` → `.bottomTrailing` に移し、ブランドと被らないようにした。
- [x] **Task 5: 検証**
  - `xcodegen generate` → `xcodebuild build -scheme Hoshidukiyo`（エラーなし）。

## 残課題 / 次の判断ポイント

- **配色（テーマ）は本プラン対象外**。「本文が青い / 全体がネイビー」は randoma11y 由来のパレットによるもの。設定画面の reset で既定の warm-stone に戻せる。cmux の青を既定にするかは別途判断。
- **統合タイトルバーの実機確認が必要**。`hiddenTitleBar` + `NavigationSplitView` でのサイドバートグルの有無・信号機との余白は GUI で微調整したい。
- 会話タブの**メタ行の情報量**（`@handle` のみか、ルート投稿者やリプライ数も出すか）は要検討。
- ナビ行（ホーム/通知）に**未読バッジ**を出すか（cmux は数字バッジあり）。通知実装と合わせて検討。

## 検証手順

```bash
cd /Users/asonas/workspace/hoshidukiyo
xcodegen generate
xcodebuild build -scheme Hoshidukiyo -project Hoshidukiyo.xcodeproj -destination 'platform=macOS'
```

GUI での見た目（選択行のソリッド塗り、会話タブの 3 行レイアウト、タイトルバー周り）は実機起動で確認する。
