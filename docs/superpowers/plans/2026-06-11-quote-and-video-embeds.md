# 引用ポスト表示と動画ポスター表示 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** v1.0.0 ロードマップの B-1（引用ポスト表示）と B-2（動画 embed のポスター表示）を実装する。`app.bsky.embed.record#view` / `app.bsky.embed.recordWithMedia#view` を持つ投稿はセル内に引用カード（作者行 + 本文 + 画像サムネ）を描画し、クリックで引用先の会話タブを開く。`app.bsky.embed.video#view` を持つ投稿はポスター画像 + 再生バッジを描画し、クリックでポストの permalink をブラウザで開く（インライン再生は post-1.0）。

**Architecture:** `PostEmbed`（`BlueskyCore/Models/Timeline.swift`）に `video: EmbedVideo?` と `record: EmbedRecord?` を追加する。デコードは既存方針どおり tolerant: `playlist` キーがあれば video、`record` キーは viewRecord 直接（record#view）と `{record: viewRecord}` ラッパ（recordWithMedia#view）の両方を試し、notFound / blocked / detached / 非ポスト record は `try?` で nil に落とす。recordWithMedia の `media` キーは `PostEmbed` 自身を再帰デコードして images / external / video をマージする（既存の画像グリッド・リンクカードがそのまま機能する）。表示層は `PostDisplay` に `quote: QuotedPost?` と `video: PostVideo?` を追加し、macOS は `QuoteCardView`（LinkCardView と同系のボーダー枠）と `PostRowView` 内のポスター描画で表示する。

**Tech Stack:** Swift 6.0 / SwiftUI / XCTest。コアは `core/Sources/BlueskyCore` と `core/Sources/YoruMimizukuKit`、View は `apps/macos/Views`。テストは `cd core && swift test`。

**設計根拠:** `docs/superpowers/plans/2026-06-11-yorumimizuku-v1.0.0-roadmap.md` B-1 / B-2。

---

## 設計メモ（実装者向け前提）

- **lexicon の形**: `record#view` は `{ "record": <viewRecord | viewNotFound | viewBlocked | viewDetached | ...> }`。viewRecord は `{ uri, cid, author(profileViewBasic), value(投稿レコード), embeds?: [embed view], indexedAt, ... }`。`recordWithMedia#view` は `{ "record": <record#view 全体>, "media": <images#view | external#view | video#view> }`。`video#view` は `{ cid, playlist(m3u8 URL), thumbnail?, alt?, aspectRatio? }`。
- **tolerant デコードの基準**: viewRecord 以外のバリアント（notFound 等）や `value` がポストでない record（リスト・フィードジェネレータの引用）は引用カードなし（`record == nil`）でデコード成功させる。既存の images / external のデコードを壊さない。
- **再帰**: `EmbedRecord.embeds: [PostEmbed]` と `PostEmbed.record: EmbedRecord?` は Array 経由の再帰なので struct で成立する。引用の中の引用はカード化しない（embeds からは images / external / video のみ拾う）。
- **表示**: 引用カードは作者行（小アバター + 表示名 + ハンドル + 相対時刻）、本文（lineLimit 6 程度）、引用先の画像サムネ（横並び小サムネ、最大 2）。クリックで `WorkspaceModel.openConversation(anchorID:)`（通知と同じ URI ベースの導線）。動画ポスターは画像グリッドと同じ幅制約で aspectRatio を尊重し、中央に再生バッジ、クリックで `PostPermalink.url(for:)` をブラウザで開く。
- **PostRowView の Equatable**: 行の `==` は id + 可変フィールドの比較なので、quote / video は immutable（id にキーされる）につき追加不要。

## Test List

- [ ] 1. video#view を持つ embed が `EmbedVideo`（playlist / thumbnail / aspectRatio / alt）にデコードされる
- [ ] 2. record#view（viewRecord、value がポスト）が `EmbedRecord`（uri / author / value.text / value.createdAt）にデコードされる
- [ ] 3. record#view の viewNotFound / viewBlocked は `record == nil` でデコード成功する
- [ ] 4. record の `value` がポストでない（text 欠落）場合も `record == nil` で成功する
- [ ] 5. recordWithMedia#view（media = images）で images と record の両方が取れる
- [ ] 6. recordWithMedia#view（media = external / video）で external / video と record が取れる
- [ ] 7. viewRecord の `embeds`（images#view）が `EmbedRecord.embeds` に入る
- [ ] 8. 既存: images#view / external#view のデコードが回 regress しない（既存テスト green 維持）
- [ ] 9. mapping: video embed → `PostDisplay.video`（thumbURL / aspectRatio）
- [ ] 10. mapping: record embed → `PostDisplay.quote`（作者 / 本文 / createdAt / 画像サムネ）
- [ ] 11. mapping: embed なし・record なしでは quote / video が nil

## Task 1: BlueskyCore — EmbedVideo と EmbedRecord のデコード（テスト 1〜8）

**Files:**
- Modify: `core/Sources/BlueskyCore/Models/Timeline.swift`
- Test: `core/Tests/BlueskyCoreTests/TimelineResponseTests.swift`

## Task 2: YoruMimizukuKit — PostVideo / QuotedPost と mapping（テスト 9〜11）

**Files:**
- Modify: `core/Sources/YoruMimizukuKit/PostDisplay.swift`, `PostDisplay+Mapping.swift`
- Test: `core/Tests/YoruMimizukuKitTests/PostDisplayMappingTests.swift`

## Task 3: macOS UI — QuoteCardView と動画ポスター

**Files:**
- Create: `apps/macos/Views/QuoteCardView.swift`
- Modify: `apps/macos/Views/PostRowView.swift`（画像グリッドの後・リンクカードの前後に挿入、`onQuoteTap` コールバック追加）、`apps/macos/Views/FeedView.swift` ほか PostRowView 利用箇所（必要なら）で会話タブを開く配線
- 検証: `xcodegen generate` + `xcodebuild build`、/tmp のプレビューアプリでスクリーンショット確認

## Task 4: wiki 更新とリリース

- [ ] wiki: `timeline-streaming.md` に引用カード・動画ポスターの behavior 追記、features 行追加、`mise run wiki:matrix` / `lint` / `index`
- [ ] `mise run bump 1.0.0-dev.1` → commit → tag → 両リモート push → `release:dev` → `publish:dev` → gh-pages `appcast-dev.xml` 更新 → Pages 反映確認
