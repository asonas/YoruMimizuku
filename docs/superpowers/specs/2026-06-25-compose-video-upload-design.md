# コンポーザ 動画投稿（アップロード）設計

作成日: 2026-06-25
対象ブランチ: `feature/compose-video-upload`

## 概要

コンポーザから動画を 1 本添付して投稿できるようにする。UI は画像添付に揃える（ピッカー / サムネ / alt / 削除）が、アップロード経路は画像（`uploadBlob` 一発）とは根本的に異なり、サービス認証 → 動画サービスへのアップロード → ジョブ完了ポーリング → `app.bsky.embed.video` という多段フローになる。コア基盤を新設し、macOS と iPadOS に組み込む。Windows は実装方針を記述して後追いとする。

## 背景: 動画アップロードのプロトコル

公式手順（`https://docs.bsky.app/docs/tutorials/video`）に従う。

1. **getServiceAuth**（ユーザーの PDS、DPoP 認証）: `GET com.atproto.server.getServiceAuth`
   - `aud = did:web:<PDS のホスト名>`（PDS URL のホストから導出）
   - `lxm = com.atproto.repo.uploadBlob`
   - `exp = 現在 + 30 分`（Unix 秒）
   - レスポンス `{ "token": "<JWT>" }`
2. **uploadVideo**（動画サービス `https://video.bsky.app`、Bearer 認証・**DPoP ではない**）:
   - `POST https://video.bsky.app/xrpc/app.bsky.video.uploadVideo?did=<ユーザーDID>&name=<ファイル名>`
   - ヘッダ: `Authorization: Bearer <serviceAuth token>`, `Content-Type: video/mp4`（mime に応じる）
   - 本体: 生の動画バイト
   - レスポンス: ジョブ状態 `{ jobId, did, state, progress?, blob?, error?, message? }`
3. **getJobStatus**（動画サービス）: `GET https://video.bsky.app/xrpc/app.bsky.video.getJobStatus?jobId=<id>`
   - `jobStatus.blob` が得られる（`state == JOB_STATE_COMPLETED`）まで一定間隔でポーリング。`state == JOB_STATE_FAILED` ならエラー。
4. **embed**: `app.bsky.embed.video { video: <blob>, aspectRatio?: {width,height}, alt? }` を `app.bsky.feed.post` レコードに入れて `createRecord`。

排他ルール: AT Protocol では 1 投稿に動画は 1 本、かつ画像とは併用不可。引用 + 動画は `app.bsky.embed.recordWithMedia`（media = video）になる。

注意点:
- uploadVideo / getJobStatus は PDS ではなく**動画サービスホスト**宛てで、**Bearer**（DPoP なし）。getServiceAuth のみ PDS 宛てで DPoP。よって動画サービス呼び出しは生の `HTTPClient`（`Ports/HTTP.swift`）を直接使い、`DPoPRequestSender` は使わない。
- getJobStatus の認証はアップロードで得た Bearer トークンを再利用する（サービス側が公開 GET を許す場合もあるが、トークン付与は無害）。
- 実サービスにアクセスできない環境では結合確認ができないため、純粋ロジック（デコード / ポーリング状態機械 / embed エンコード / 排他制御 / aud 導出）を fake 注入でユニットテストし、実経路はユーザーの実アカウント手動確認とする（実投稿は勝手に行わない）。

## スコープ

### 含むもの
- コア: `getServiceAuth`、動画サービスへの `uploadVideo`、`getJobStatus` ポーリング、`app.bsky.embed.video` 送信
- コア: `PostDraft` / `ComposerViewModel` に動画状態（1 本）と画像との排他、送信フロー
- macOS: `fileImporter` で動画選択、サムネ（ポスター）+ alt + 削除、アップロード進捗表示
- iPadOS: `PhotosPicker(matching: .videos を含む)` で動画選択、同等 UI
- Windows: 実装方針を本ドキュメントに記述（実装は後追い）

### 含まないもの（今回スコープ外）
- クライアント側トランスコード（mp4 へ変換）。元ファイルを mime そのままで送る（mov 等はサービス側処理に委ねる）
- 動画の尺・サイズの厳密なクライアント検証（`getUploadLimits`）。サービスのエラーを表示する方針。将来追加余地は残す
- 動画への字幕（captions）添付、複数動画
- 投稿後のインライン再生（既存の表示側は別途）

## 設計

### コア（BlueskyCore）

```
Models/PostWrite.swift          VideoEmbedWrite を追加、PostEmbedWrite に .video / recordWithMedia(video) を拡張
Models/ServiceAuth.swift        ServiceAuthResponse { token }
Models/VideoJobStatus.swift     VideoJobStatus（jobStatus ラッパ）/ JobState、blob 取り出し
XRPC/PostService.swift          getServiceAuth(...) を追加、createPost に video パラメータ追加
XRPC/VideoUploadService.swift   uploadVideo / getJobStatus / pollUntilComplete（HTTPClient + 注入クロックで純粋にテスト可能）
```

- `getServiceAuth`: `PostService` に追加。PDS 宛て DPoP GET。`aud`/`lxm`/`exp` をクエリに組み立て、401→refresh リトライは既存 `perform` を流用。`aud` は `VideoServiceConfig.audience(forPDS:)`（`did:web:<host>`）で導出。
- `VideoUploadService`: 生 `HTTPClient` と動画サービス URL（既定 `https://video.bsky.app`）、注入可能な `sleep`（ポーリング間隔）を持つ。
  - `uploadVideo(serviceToken, did, name, data, mimeType) -> VideoJobStatus`
  - `getJobStatus(jobId, serviceToken) -> VideoJobStatus`
  - `pollUntilComplete(jobId, serviceToken, maxAttempts, interval) -> BlobRef`: completed で blob を返し、failed で throw、上限超過で throw。
- `createPost`: 既存の画像経路に加え、`video: (blob: BlobRef, aspectRatio: AspectRatio?, alt: String)?` を受け取り、embed を組み立てる。排他は呼び出し側（VM）で担保するが、createPost も video 優先で images を無視する防御を入れる。

### 送信オーケストレーション（apps の LiveComposer）

`PostSubmitting.submit(_:)` 実装（macOS / iPadOS の `LiveComposer`）で、`draft.video` があれば:
1. `serviceToken = postService.getServiceAuth(...)`（リフレッシュtrほか既存どおり）
2. `job = videoUpload.uploadVideo(serviceToken, did, name, data, mime)`
3. `blob = videoUpload.pollUntilComplete(job.jobId, serviceToken)`
4. `postService.createPost(..., video: (blob, draft.video.aspectRatio, draft.video.alt))`
進捗（アップロード中 / 変換中）は `ComposerViewModel` の状態として表現し、UI に出す。

### View モデル（YoruMimizukuKit）

- `PostDraft` に `video: ComposeVideo?` を追加。`ComposeVideo { id, data, mimeType, alt, aspectRatio? , filename }`。
- `ComposerViewModel`:
  - `@Published var video: ComposeVideo?`
  - `canAddImage`: 既存条件 + `video == nil`
  - `canAddVideo`: `video == nil && images.isEmpty && !isSubmitting`
  - `canSubmit`: 本文 or 画像 or 引用 or **動画** のいずれか
  - `submit()`: draft に video を載せる
  - 動画アップロードの進捗フェーズ（`uploading` / `processing`）を表す状態を追加し、submit 中に更新

### UI

- **macOS**（`apps/macos/Views/ComposerView.swift`）: 動画追加ボタン（`film` 系 SF Symbol）。`fileImporter` の許可型に `.movie` / `.mpeg4Movie` / `.quickTimeMovie`。選択後 `AVAsset` で `aspectRatio` を取得し `ComposeVideo` を作る。サムネ（ポスター）は `AVAssetImageGenerator` の 1 フレーム。画像と排他なので、動画があるときは画像追加を無効化（逆も同様）。
- **iPadOS**（`apps/ipados/Views/ComposerView.swift`）: `PhotosPicker` を画像用と動画用に分ける、または `matching: .any(of: [.images, .videos])` + 選択結果の種別判定。動画は `loadTransferable(type: Movie.self)`（カスタム `Transferable`）で URL を得てバイト化、`AVAsset` で aspectRatio / ポスター。
- 進捗: 送信中に「アップロード中…」「変換中…」を表示。

### Windows（実装方針 / 後追い）

`apps/windows`（WinUI / C# + Bridge DLL 経由）で同等に実装する。要点:
- ブリッジに動画アップロード経路を追加（`PostDraft` 相当の JSON に `video` フィールド: `dataBase64` / `mimeType` / `alt` / `aspectRatio` / `name`）。コアの `VideoUploadService` を `YoruMimizukuBridge` から駆動する `@_cdecl` を追加。
- `ComposerDialog` に `FileOpenPicker`（`.mp4`/`.mov`）と動画サムネ、進捗表示、画像との排他を追加。
- 進捗が長くなる（変換待ち）ため、ブリッジ呼び出しは非同期 + 進捗コールバック（または段階的ステータス取得）を検討。
- 詳細は後続の Windows 作業時に詰める。

## テスト方針（TDD 対象）

純粋ロジックを `core` で TDD（`swift test`、`BlueskyCoreTests` / `YoruMimizukuKitTests`）:
- `ServiceAuthResponse` のデコード（`{ "token": ... }`）
- `VideoJobStatus` のデコード: 進行中（blob なし）/ 完了（blob あり）/ 失敗（state, error）。`jobStatus` ラッパの有無両対応
- `VideoUploadService.pollUntilComplete`: 完了で blob 返却 / 失敗で throw / 上限超過で throw（fake status 列 + fake sleeper 注入）
- `getServiceAuth` のリクエスト組み立て（URL クエリ `aud`/`lxm`/`exp`、DPoP ヘッダ）を fake sender で検証
- `aud` 導出: PDS URL → `did:web:<host>`
- `VideoEmbedWrite` / `PostEmbedWrite.video` の JSON エンコード（`$type` / `video` blob / `aspectRatio`）
- `ComposerViewModel`: 動画と画像の排他（`canAddImage`/`canAddVideo`）、`canSubmit`、submit で draft に video が載る

UI と AVFoundation（ポスター / aspectRatio 取得）、実アップロード経路はビルド + 実機手動確認。

## 参考

- 公式: https://docs.bsky.app/docs/tutorials/video
- 既存画像投稿: `docs/superpowers/specs/2026-06-05-yorumimizuku-compose-post-design.md`
- 受信側動画表示: `docs/superpowers/plans/2026-06-11-quote-and-video-embeds.md`
