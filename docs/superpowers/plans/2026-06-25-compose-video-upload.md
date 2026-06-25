# 動画投稿（アップロード）対応 Implementation Plan（起票・未着手）

ステータス: **未着手（起票のみ）**
作成日: 2026-06-25

**Goal:** コンポーザから動画を投稿（アップロード）できるようにする。現状、動画は受信タイムラインの「表示」のみ対応で（`app.bsky.embed.video#view`）、投稿側の経路は全プラットフォームで未実装。

## 背景

画像ペースト / ドラッグ対応（`2026-06-25-compose-image-paste-drop`）の調査中に、iPadOS の `PhotosPicker(matching: .images)` が動画を除外している点が「意図的か」と問われた。結論は意図的であり、アプリに動画投稿経路が無いことの反映。動画投稿は機能規模が大きいため別タスクとして切り出す。

## 想定スコープ

- `PostDraft` / コンポーザモデルに動画添付（画像とは排他: Bluesky は 1 投稿に動画 1 本、画像との併用不可）を表現
- `app.bsky.video.uploadVideo`（ジョブ投入）→ ジョブ状態ポーリング → `app.bsky.embed.video` で投稿、というアップロードフロー（参照実装 tempest / 公式アプリの挙動を確認）
- アップロード上限・対応コーデック / 尺・サムネイル（poster）の扱い
- 各プラットフォーム UI:
  - iPadOS: `PhotosPicker` の `matching` に `.videos` を追加（画像/動画の排他制御）
  - macOS: `fileImporter` の許可型に動画を追加、または専用導線
  - Windows: `FileOpenPicker` の型追加 + アップロード経路
- 進捗表示（エンコード / アップロードに時間がかかるため）とエラー / リトライ

## 未決事項

- 動画変換（再エンコード / トランスコード）をクライアントで行うか、サーバ任せか
- 上限超過時の UX（尺・サイズ）

## 参考

- 表示側の既存実装: `docs/superpowers/plans/2026-06-11-quote-and-video-embeds.md`
- 画像投稿の既存設計: `docs/superpowers/specs/2026-06-05-yorumimizuku-compose-post-design.md`
