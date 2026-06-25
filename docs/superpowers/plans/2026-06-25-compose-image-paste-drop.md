# コンポーザ 画像ペースト / ドラッグ&ドロップ添付 Implementation Plan

**Goal:** コンポーザ本文エディタ上での画像ペースト（Cmd+V）と画像ファイル / 画像データのドラッグ&ドロップを、パス文字列の挿入ではなく画像添付として処理する。macOS を実装し、Windows は方針を記述して後追い対応とする。

**設計根拠:** `docs/superpowers/specs/2026-06-25-compose-image-paste-drop-design.md`

**Tech Stack:** Swift 6.0 / SwiftUI / AppKit / XCTest（`YoruMimizukuTests`）。新規ロジックは `apps/macos/Media`、View は `apps/macos/Views`。

---

## Test List（macOS / ComposerMediaIntake）

- [x] 1. 画像ファイル URL のみ → エンコード済み添付（data + mimeType）を返す
- [x] 2. 画像でないファイル URL は除外される（空になる）
- [x] 3. ファイル URL 無し・生画像データのみ → フォールバックして添付を返す
- [x] 4. 画像ファイル URL と生データが両方ある → ファイル URL を優先し、データ側は使わない
- [x] 5. 添付候補が無い → 空配列を返す（呼び出し側が super.paste に委譲できる）

## Task 1: ComposerMediaIntake（純粋ロジック）

**Files:**
- Add: `apps/macos/Media/ComposerMediaIntake.swift`（`ComposerImageSource` プロトコル + `attachments(from:)` + `canProvideImages(from:)`）
- Add: `apps/macosTests/ComposerMediaIntakeTests.swift`
- Modify: `project.yml`（`YoruMimizukuTests.sources` に `apps/macos/Media/ComposerMediaIntake.swift` を追加）

TDD で Test List 1〜5 を 1 つずつ Red→Green→Refactor。テストは `ComposerImageSource` の fake を注入。ファイル URL ケースは一時 PNG をディスクに書いて URL を渡す。

## Task 2: NSPasteboard アダプタ + AttachingTextView

**Files:**
- Add: `apps/macos/Views/ComposerTextView.swift`
  - `extension NSPasteboard: ComposerImageSource`（`#if canImport(AppKit)`）
  - `final class AttachingTextView: NSTextView`（`paste(_:)` / `performDragOperation(_:)` / `draggingEntered/Exited/Ended` をオーバーライド）
  - `struct ComposerTextView: NSViewRepresentable`（`NSScrollView` + `AttachingTextView`、text バインディング同期、フォント / 行間を `TextEditor` 相当に）

UI 挙動のためユニットテスト対象外。ビルド + 実機手動確認。

## Task 3: ComposerView 結線

**Files:**
- Modify: `apps/macos/Views/ComposerView.swift`
  - 本文 `TextEditor` を `ComposerTextView` に置換
  - 添付 append を `handleDrop` と共通のヘルパーに集約（`canAddImage` 尊重、off-main でエンコード済みのものを MainActor で追加）
  - テキスト領域外への `.onDrop` は残す
  - ドラッグハイライト（`isDropTargeted`）を `ComposerTextView` のドラッグコールバックからも更新

## 検証

- `xcodegen generate` 後、`xcodebuild test -scheme YoruMimizuku -destination 'platform=macOS'` で `YoruMimizukuTests` を実行。
- アプリをビルドして、(a) スクリーンショットを Cmd+V、(b) ブラウザ画像をコピーして Cmd+V、(c) Finder の画像をテキスト領域へドラッグ、で添付されパスが入らないことを手動確認。

## Windows 後追いチェックリスト（Windows マシンで実施）

設計 spec の「Windows（実装方針）」節に従う。

- [ ] `ComposerDialog.xaml` の `TextBox`/親に `AllowDrop="True"` と `DragOver`/`Drop` を追加
- [ ] `DataPackageView` から画像 bytes を取り出す `TryGetImagesAsync` を実装（StorageItems / Bitmap 両対応）
- [ ] `TextBox.Paste`（`TextControlPasteEventArgs`）で画像クリップボードを横取りし添付経路へ
- [ ] bytes + mime → `ImageProcessing.PrepareAsync` → `_vm.AddImage` → サムネ → カウンタ を 1 メソッドに集約（ボタン経路と共用）
- [ ] `AddImageEntry` に bytes から `BitmapImage` を生成する分岐を追加（パス無しケース）
- [ ] `CanAddImage`（最大 4 枚）を各経路で尊重
- [ ] Unpackaged アプリでの Clipboard / ドラッグ API 制約を実機確認
