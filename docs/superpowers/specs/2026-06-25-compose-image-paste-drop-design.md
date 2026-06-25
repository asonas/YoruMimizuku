# コンポーザの画像ペースト / ドラッグ&ドロップ添付 設計

作成日: 2026-06-25
対象ブランチ: `feature/macos-compose-image-paste-drop`

## 概要

新規投稿（コンポーザ）で、クリップボードからの画像ペースト（Cmd+V）と、Finder などからのファイルのドラッグ&ドロップを、本文への「ファイルパス文字列の挿入」ではなく「画像の添付」として扱う。macOS で本対応を実装し、Windows は実装方針を本ドキュメントに記述して後追い対応できるようにする。iPadOS は現状の `PhotosPicker` で問題がないため対象外。

## 背景と問題

macOS の `ComposerView` は `VStack` に `.onDrop(of: [.image, .fileURL])` を付けているが、本文エディタは `TextEditor`（内部は `NSTextView`）であり、`NSTextView` は自前でドラッグ受け入れ型（ファイル名・画像）とペースト処理を持つ。そのため次の経路で添付ではなくパス文字列の挿入が起きる。

- **Finder からのドラッグ**: テキスト領域上にドロップすると `NSTextView` のドラッグ処理が先に消費し、ファイル URL をパス文字列として挿入する。親 `VStack` の `.onDrop` はテキスト領域外にドロップしたときしか発火しない。
- **クリップボードからのペースト（Cmd+V）**: `NSTextView` の `paste:` が `NSPasteboard` の file-url / テキスト表現を読み、パス文字列を挿入する。画像データは横取りされない。

つまり `.onDrop` 自体は存在するが、内側の `NSTextView` が先にイベントを奪うため、ユーザー体験としてはパスが入ってしまう。

Windows の `ComposerDialog` は `TextBox`（`AllowDrop` 未設定、ペーストのオーバーライド無し）で、画像添付は「画像を追加」ボタンの `FileOpenPicker` のみ。`TextBox` の既定挙動はテキストのみ扱うため、画像ペーストもファイルドロップも**何も起きない**（パス挿入バグは無いが、添付機能も無い）。

## スコープ

### 含むもの
- macOS: コンポーザ本文エディタ上での画像ペースト（Cmd+V）を添付として処理
- macOS: コンポーザ本文エディタ上への画像ファイル / 画像データのドラッグ&ドロップを添付として処理
- macOS: 既存の最大 4 枚制限・`ImageEncoder` による ~1MB 制限・alt text 入力をそのまま踏襲
- Windows: 同等機能の実装方針を本ドキュメントに記述（実装は後追い）

### 含まないもの（今回スコープ外）
- 動画投稿（アップロード）。別プラン `2026-06-25-compose-video-upload.md` として起票
- iPadOS の挙動変更（`PhotosPicker(matching: .images)` のまま。動画除外は全プラットフォーム共通の意図的挙動）
- 本文以外の領域（プレビュー等）への高度なドロップ演出

## 設計

### 共通方針

ペーストボード（クリップボード / ドラッグのペーストボード）の内容を「添付すべき画像（data + mimeType）」へ変換する純粋ロジックを切り出し、ユニットテスト可能にする。実際の `NSPasteboard` / WinUI `DataPackageView` への依存は薄いアダプタ層に閉じる。エンコードは既存の `ImageEncoder`（macOS）/ `ImageProcessing`（Windows）を再利用する。

優先順位は「画像ファイル URL → 生画像データ」の順とする。Finder のドラッグ / コピーはファイル URL と画像データ（tiff 等）を同時に露出するため、ファイル URL があればそれを優先して原本バイトを保持し、無い場合（スクリーンショットやブラウザの画像コピー）のみ生データへフォールバックする。これは既存 `handleDrop` の「file-url が image を shadow する」順序と整合する。

### macOS

```
apps/macos/Media/ComposerMediaIntake.swift   純粋ロジック + ComposerImageSource プロトコル（テスト対象）
apps/macos/Views/ComposerTextView.swift       NSViewRepresentable + AttachingTextView + NSPasteboard アダプタ
apps/macos/Views/ComposerView.swift            TextEditor を ComposerTextView に置換し、添付を model に追加
```

- `ComposerImageSource`: `imageFileURLs()` と `imageDataItems()` を返すプロトコル。`NSPasteboard` を AppKit 非依存のテストから切り離すための抽象。
- `ComposerMediaIntake.attachments(from:)`: 上記優先順位で `ImageEncoder.encodeForUpload` を通し `[(data, mimeType)]` を返す純粋関数。
- `ComposerMediaIntake.canProvideImages(from:)`: ドラッグ中のハイライト判定用の軽量チェック（エンコードしない）。
- `NSPasteboard: ComposerImageSource`（app 内、`#if canImport(AppKit)`）: `readObjects(forClasses:options:)` で画像ファイル URL（`.urlReadingContentsConformToTypes: [UTType.image]`）と `NSImage`（→ `tiffRepresentation`）を取得。
- `AttachingTextView: NSTextView`: `paste(_:)` と `performDragOperation(_:)` をオーバーライド。添付候補があれば `onAttachImages` を呼んで消費し、無ければ `super` に委譲（プレーンテキストは従来どおり）。`draggingEntered/Exited/Ended` でハイライト用バインディングを更新。
- `ComposerView`: 本文を `ComposerTextView` に置換。添付は既存 `handleDrop` と共通の append 経路（`canAddImage` を尊重）に流す。テキスト領域外への `.onDrop` も従来どおり残す。

### Windows（実装方針 / 後追い）

`apps/windows/App/Views/ComposerDialog.xaml(.cs)` に対し、以下を実装する。エンコードは既存 `Services/ImageProcessing.PrepareAsync` を再利用する。

1. **ドラッグ&ドロップ**
   - `ComposerDialog.xaml` の本文 `TextBox`（または親 `StackPanel`）に `AllowDrop="True"` を設定し、`DragOver` と `Drop` ハンドラを追加する。
   - `DragOver`: `e.DataView.Contains(StandardDataFormats.StorageItems)` または `Bitmap` の場合に `e.AcceptedOperation = DataPackageOperation.Copy` とし、キャプション表示を設定する。
   - `Drop`: `await e.DataView.GetStorageItemsAsync()` で `StorageFile` を取得し、拡張子が画像（.png/.jpg/.jpeg、必要なら .gif/.webp）のものだけ `File.ReadAllBytesAsync` → `ImageProcessing.PrepareAsync` → `_vm.AddImage` → `AddImageEntry`。`StorageItems` が無く `Bitmap` がある場合は `await e.DataView.GetBitmapAsync()` の `OpenReadAsync` から bytes を取り出して同経路へ。
2. **ペースト（Ctrl+V）**
   - `TextBox` は標準でテキストのみ貼り付けるため、画像貼り付けを横取りする必要がある。`TextBox.Paste` イベント（`TextControlPasteEventArgs`）を購読し、`Clipboard.GetContent()` の `DataPackageView` が `Bitmap` または画像 `StorageItems` を含む場合に `e.Handled = true` として既定のテキスト貼り付けを抑止し、画像添付経路へ振り分ける。テキストのみの場合は `e.Handled` を立てず既定動作に委ねる。
   - 取得経路はドロップと共通化する（`DataPackageView` から画像 bytes を取り出すヘルパー `TryGetImagesAsync(DataPackageView)` を 1 つ用意し、Drop と Paste の両方から呼ぶ）。
3. **共通化**
   - 「bytes + mime を受け取り `ImageProcessing.PrepareAsync` → `_vm.AddImage` → サムネイル UI 追加 → カウンタ更新」を 1 メソッドに集約し、ボタン / ドロップ / ペーストの 3 経路から共用する（現状ボタン経路 `OnAddImageClick` と重複させない）。
   - `_vm.CanAddImage`（最大 4 枚）を各経路で尊重する。
   - サムネイル表示は現状 `new Uri(file.Path)` を使うが、ペースト / Bitmap ドロップにはファイルパスが無い。bytes から `BitmapImage`（`InMemoryRandomAccessStream` 経由 `SetSourceAsync`）を生成する分岐を `AddImageEntry` に追加する。
   - 注意: Unpackaged アプリでは `Clipboard` / ドラッグの一部 API に制約があり得るため、実機（Windows マシン）で動作確認すること。

### iPadOS（変更なし・調査結果）

`PhotosPicker(matching: .images)` が動画を除外しているのは意図的で、全プラットフォームで一貫した挙動。アプリには動画の「投稿（アップロード）」経路が存在しない（`PostDraft` / `ComposeImage` は画像専用、macOS の `fileImporter` は画像型のみ、Windows のピッカーは png/jpg のみ）。コード中の `EmbedVideo` / `PostVideo` は受信タイムラインの動画「表示」専用であり投稿側に関与しない。したがってバグではなく、動画投稿が未実装であることの反映。動画投稿は別プランで起票する。

## テスト方針

- `ComposerMediaIntake` を純粋ロジックとしてユニットテスト（`apps/macosTests`、`YoruMimizukuTests` ターゲット）。
  - 画像ファイル URL → エンコード済み添付を返す
  - 画像でないファイル URL → 除外
  - ファイル URL が無く生画像データのみ → フォールバックして添付を返す
  - ファイル URL と生データが両方ある → ファイル URL を優先（データ側は使わない）
  - 添付不能（空）→ 空配列（呼び出し側で `super.paste` にフォールバックできる）
- `NSTextView` のペースト / ドロップ横取りそのものは AppKit UI 挙動のため、ビルドの上で実機での手動確認とする。

## 参考

- 既存設計: `docs/superpowers/specs/2026-06-05-yorumimizuku-compose-post-design.md`
- 実装プラン: `docs/superpowers/plans/2026-06-25-compose-image-paste-drop.md`
- 動画投稿（別タスク）: `docs/superpowers/plans/2026-06-25-compose-video-upload.md`
</invoke>
