# コンポーザ 動画投稿（アップロード）Implementation Plan

ステータス: **コア + macOS + iPadOS 実装済み**（ビルド通過 / コア 436 テスト緑。実アップロード経路は実機手動確認待ち）。Windows は後追い。
作成日: 2026-06-25

**Goal:** コンポーザから動画 1 本を添付して投稿できるようにする。getServiceAuth → 動画サービスへ uploadVideo → getJobStatus ポーリング → `app.bsky.embed.video` のフローをコアに実装し、macOS / iPadOS の UI に組み込む。動画は画像と排他。

**設計根拠:** `docs/superpowers/specs/2026-06-25-compose-video-upload-design.md`

**Tech Stack:** Swift 6.0。コア = `core/Sources/BlueskyCore` / `YoruMimizukuKit`（`swift test`）。UI = `apps/macos` / `apps/ipados`（AVFoundation でポスター/aspectRatio）。

---

## Test List（core / swift test）

### モデル & エンコード
- [x] 1. `ServiceAuthResponse` が `{ "token": "..." }` をデコードできる
- [x] 2. `VideoJobStatus` 完了レスポンス（`jobStatus.blob` あり）をデコードし blob を取り出せる
- [x] 3. `VideoJobStatus` 進行中（blob なし、state=JOB_STATE_ENCODING 等）をデコードできる
- [x] 4. `VideoJobStatus` 失敗（state=JOB_STATE_FAILED, error/message）をデコードできる
- [x] 5. `VideoEmbedWrite` が `app.bsky.embed.video`（`$type`/`video` blob/`aspectRatio`/`alt`）に正しくエンコードされる
- [x] 6. `PostEmbedWrite.video` と `recordWithMedia(record, video)` が正しくエンコードされる

### サービス
- [x] 7. `VideoServiceConfig.audience(forPDS:)` が PDS URL から `did:web:<host>` を導出する
- [x] 8. `getServiceAuth` が `aud`/`lxm`/`exp` をクエリに組み立て PDS へ DPoP GET する（fake sender で検証、token を返す）
- [x] 9. `uploadVideo` が動画サービスへ Bearer POST（`did`/`name` クエリ、Content-Type=mime、body=bytes）し JobStatus を返す（fake HTTPClient）
- [x] 10. `pollUntilComplete` が完了で blob を返す（fake status 列 + fake sleeper）
- [x] 11. `pollUntilComplete` が失敗 state で throw する
- [x] 12. `pollUntilComplete` が最大試行超過で throw する

### View モデル
- [x] 13. 動画があると `canAddImage == false`、画像があると `canAddVideo == false`（排他）
- [x] 14. 動画のみでも `canSubmit == true`
- [x] 15. `submit()` で `PostDraft.video` に動画が載る（fake submitter で検証）

## Task 1: コアモデル（テスト 1〜6）

**Files:**
- Add: `core/Sources/BlueskyCore/Models/ServiceAuth.swift`
- Add: `core/Sources/BlueskyCore/Models/VideoJobStatus.swift`
- Modify: `core/Sources/BlueskyCore/Models/PostWrite.swift`（`VideoEmbedWrite`、`PostEmbedWrite` 拡張、aspectRatio エンコード）
- Add tests: `core/Tests/BlueskyCoreTests/VideoModelsTests.swift`

## Task 2: VideoUploadService + getServiceAuth（テスト 7〜12）

**Files:**
- Add: `core/Sources/BlueskyCore/XRPC/VideoUploadService.swift`（`VideoServiceConfig`、`uploadVideo`/`getJobStatus`/`pollUntilComplete`、注入 sleeper）
- Modify: `core/Sources/BlueskyCore/XRPC/PostService.swift`（`getServiceAuth`、`createPost` に `video` パラメータ）
- Add tests: `core/Tests/BlueskyCoreTests/VideoUploadServiceTests.swift`、`PostServiceTests` に getServiceAuth ケース追加

## Task 3: PostDraft / ComposerViewModel（テスト 13〜15）

**Files:**
- Modify: `core/Sources/YoruMimizukuKit/PostDraft.swift`（`ComposeVideo`、`PostDraft.video`）
- Modify: `core/Sources/YoruMimizukuKit/ComposerViewModel.swift`（`video`、排他、`canSubmit`、submit、進捗フェーズ）
- Add/Modify tests: `core/Tests/YoruMimizukuKitTests/ComposerViewModelTests.swift`

## Task 4: 送信オーケストレーション（macOS / iPadOS LiveComposer）

**Files:**
- Modify: `apps/macos/Compose/LiveComposer.swift` / `apps/ipados/Compose/LiveComposer.swift`
- 動画があれば getServiceAuth → uploadVideo → poll → createPost(video:)。進捗を VM に反映。

## Task 5: UI（macOS / iPadOS）

**Files:**
- Modify: `apps/macos/Views/ComposerView.swift`（動画追加ボタン / fileImporter `.movie` 等 / ポスター + alt + 削除 / 排他 / 進捗）
- Add: `apps/macos/Media/VideoAttachment.swift`（AVAsset で aspectRatio / ポスター生成）
- Modify: `apps/ipados/Views/ComposerView.swift`（PhotosPicker 動画対応 / 同等 UI）
- Add: `apps/ipados/Media/VideoAttachment.swift`

## 検証

- コア: `cd core && swift test`
- アプリ: `xcodegen generate` 後 `xcodebuild build`（macOS / iPad スキーム）
- 実アップロード/投稿は実アカウントでユーザー手動確認（実投稿は勝手に行わない）

## Windows 後追い（別作業）

設計 spec「Windows（実装方針）」節に従う。ブリッジに動画アップロード `@_cdecl` を追加し、`ComposerDialog` に動画ピッカー / 進捗 / 排他を実装。Windows マシンでビルド確認。
