# YoruMimizuku 投稿機能（コンポーザ）設計

作成日: 2026-06-05
対象ブランチ: `feature/compose-post`

## 概要

アプリから Bluesky に投稿できるようにする。本文に加えて、URL（link facet）・ハッシュタグ（tag facet）・メンション（mention facet）を含む RichText 投稿と、画像投稿（最大 4 枚、alt text 付き）に対応する。新規投稿（トップレベル）とリプライの両方をサポートする。

facet は AT Protocol の `app.bsky.richtext.facet` に従い、**UTF-8 バイトオフセット**で範囲を表現する。検出ロジックは参照実装 tempest（`lib/tempest/post.rb`）の実証済みアルゴリズムを Swift に再実装する。

## スコープ

### 含むもの
- トップレベル投稿の作成（`com.atproto.repo.createRecord` / `app.bsky.feed.post`）
- リプライ投稿（会話ルート・親参照を保持）
- facet 自動検出: link（本文中の URL）・tag（`#hashtag`）・mention（`@handle` を DID 解決）
- 画像投稿: 最大 4 枚、各画像に alt text、`uploadBlob` → `app.bsky.embed.images`
- 本文 300 グラフェムの文字数制限と残数表示
- 送信中・成功・失敗の状態管理とエラー表示
- コンポーザをシートで表示。ホームで `n` キー（修飾キーなし）で新規投稿、投稿行の返信ボタンでリプライ

### 含まないもの（今回スコープ外）
- external embed（OGP リンクカード）。URL は link facet によるリンク化のみ
- 引用投稿（quote / record embed）、動画投稿
- 下書き保存、投稿予約、スレッド連投
- 投稿の編集・削除（atproto に編集は存在しない。削除は別途）
- 言語タグ（`langs`）の UI 入力（将来拡張余地は残す）

## アーキテクチャ

既存の XRPC サービス（`TimelineService` / `ProfileService`）のパターンを踏襲する。副作用は protocol で抽象化し、core は OS 非依存・テスト可能に保つ。

```
core/BlueskyCore (OS非依存)
├── XRPC/PostService.swift        createRecord / uploadBlob / getRecord、401→refresh リトライ
├── Models/PostRecordWrite.swift  createRecord 送信用 Encodable モデル（facet/embed/reply）
├── Models/BlobRef.swift          uploadBlob のレスポンス（blob 参照）
└── RichText/FacetDetector.swift  純粋ロジック: link / tag / mention候補 のバイト範囲検出

core/YoruMimizukuKit (表示・VM)
├── PostSubmitting.swift          投稿実行の protocol（fake 注入でテスト）
├── PostDraft.swift               下書き値（本文・画像・リプライ対象）
└── ComposerViewModel.swift       本文/画像/alt/送信状態、文字数、canSubmit

apps/macos (Apple 依存の結線)
├── Compose/LiveComposer.swift    PostSubmitting 実装。LiveServiceContext 経由で PostService を駆動
└── Views/ComposerView.swift      シート UI（本文・画像・alt・送信）
```

### モジュール責務の境界
- `FacetDetector`（純粋）: 文字列を受け取り link / tag を完成した facet として、mention は「`@handle` のバイト範囲＋handle 文字列」を候補として返す。ネットワーク非依存でユニットテストする。
- `PostService`（ネットワーク）: 候補 mention の handle を `getProfile` で DID 解決し、解決できたものだけ mention facet に変換。link/tag と結合してバイト開始順にソートし、record を組み立てて送信。画像があれば先に `uploadBlob`。
- `ComposerViewModel`（VM）: 入力状態と文字数・送信可否のみ。facet 検出やネットワークは持たず、`PostSubmitting` に委譲。
- `LiveComposer`（結線）: `LiveServiceContext` で sender/metadataResolver を組み立て、`PostService` を呼び、refresh されたトークンを永続化。

## データフロー

新規投稿（画像あり）の例:

1. ユーザーが `n` でシートを開き、本文・画像（最大 4 枚）・各 alt を入力。
2. 送信ボタン押下 → `ComposerViewModel.submit()` が `PostDraft` を作り `PostSubmitting.submit(_:)` を呼ぶ。
3. `LiveComposer` が `LiveServiceContext` を構築し `PostService.createPost(...)` を実行。
4. `PostService`:
   a. 画像があれば各画像を `uploadBlob` し `BlobRef` を取得（DPoP 経由）。
   b. `FacetDetector.detect(text:)` で link/tag facet と mention 候補を取得。
   c. mention 候補の handle を `getProfile` で DID 解決し mention facet を追加。
   d. facet を `byteStart` 昇順にソート。
   e. `record`（text, createdAt, facets?, embed?, reply?）を組み立て `createRecord` を送信。
   f. 401（nonce challenge 以外）なら refresh→1 回リトライ。refresh したトークンを返す。
5. `LiveComposer` が refresh トークンを永続化し、結果を VM に返す。
6. VM が成功状態にし、シートを閉じる。ホームフィードは次回 refresh（30 秒間隔の既存タイマー、または明示 refresh）で反映。

リプライの場合は 4 の前に、親 URI から `getRecord` で `reply.root` / `reply.parent`（uri/cid）を解決して `record.reply` に詰める。親自身がリプライならその `reply.root` を引き継ぎ、トップレベルなら親をルートに使う（tempest `fetch_reply_refs` に準拠）。

## facet 検出仕様

すべて UTF-8 バイトオフセットで範囲を表現する（`byteStart`/`byteEnd`）。表示側 `RichText.segments` と対称。

### link
- パターン: `https?://` で始まり空白までの連続。
- 末尾の句読点・閉じ括弧（`. , ; : ! ?` および対応しない `)` 等）はリンク範囲から除外する（atproto 公式 `@atproto/api` 準拠）。tempest は末尾処理をしていないため、ここは公式挙動に合わせて改善する。
- feature: `app.bsky.richtext.facet#link`、`uri` は検出した URL 文字列。

### tag（ハッシュタグ）
- tempest `TAG_PATTERN` 準拠。半角 `#` と全角 `＃` の両方を受理。
- テキスト先頭または空白に続くこと。tag 本体は数字・記号のみを除外（`#123` のような数字だけは無視）。
- 末尾の句読点を剥がす。tag の grapheme 長が 64 を超えるものは無視。ゼロ幅・書式制御コードポイントは tag に含めない。
- バイト範囲は `#`（または `＃`）と tag 本体を合わせた範囲。`tag` 値は先頭の `#` を除いた文字列。
- feature: `app.bsky.richtext.facet#tag`、`tag` は `#` 抜きの本体。

### mention（`@handle`）
- tempest `MENTION_PATTERN` 準拠: テキスト先頭、空白、`(`、`[` のいずれかに続く `@` の後、`[a-zA-Z0-9._-]+\.[a-zA-Z]{2,}`（ドメイン形式の handle）。
- `FacetDetector` は handle のバイト範囲（`@` 含む）と handle 文字列を候補として返す（DID 解決はしない）。
- `PostService` が各候補 handle を `getProfile`（`actor=handle`）で DID 解決。解決成功時のみ mention facet を追加。解決失敗（未存在・エラー）はプレーンテキストのまま（facet を追加しない）。
- feature: `app.bsky.richtext.facet#mention`、`did` は解決した DID。

### 結合
link/tag/mention を結合し `byteStart` 昇順にソートして `record.facets` に格納。空なら `facets` を省略する。

## 画像アップロード仕様

- 入力上限 4 枚。超過分はコンポーザで受け付けない。
- 各画像は `com.atproto.repo.uploadBlob` にバイナリ本体を送信（`Content-Type` は画像 MIME）。レスポンスの `blob` を `BlobRef` として取得。
- `record.embed` は `app.bsky.embed.images`、`images: [{ image: <BlobRef>, alt: <String> }]`。alt 未入力時は空文字。
- `BlobRef` は `{ $type: "blob", ref: { $link: <cid> }, mimeType, size }`。createRecord 送信時にそのまま埋め込む。
- 画像のリサイズ・再エンコード・サイズ上限（Bluesky は 1MB 上限）への対応は、apps/macos 側で読み込み時に必要なら縮小する（既存 `ImageDownsampler` を活用検討）。core はバイト列と MIME を受け取るだけに留める。

## ViewModel / UI

### PostDraft（YoruMimizukuKit）
- `text: String`
- `images: [ComposeImage]`（`ComposeImage = { data: Data, mimeType: String, alt: String }`）
- `reply: ReplyTarget?`（`ReplyTarget = { parentURI: String }`）

### PostSubmitting（protocol）
```
func submit(_ draft: PostDraft) async throws -> PostResult
```
`PostResult` は作成された投稿の uri/cid（将来の楽観的反映に使える）。

### ComposerViewModel（@MainActor ObservableObject）
- 入力: `text`、`images`（追加/削除/alt 編集）、`reply`。
- 算出: `graphemeCount`（`text` の grapheme 数）、`remaining`（300 - count）、`canSubmit`（本文または画像が 1 つ以上あり、かつ 300 グラフェム以内、かつ送信中でない）。
- 状態: `isSubmitting`、`errorMessage`。
- `submit()` で `PostSubmitting` を呼び、成功で `onPosted` コールバック（シートを閉じてホーム refresh をトリガ）、失敗で `errorMessage` を設定。

### ComposerView（apps/macos、シート）
- 複数行テキストエディタ、残り文字数表示（超過時は警告色）、画像サムネイル＋alt 入力、画像追加ボタン（最大 4 枚）、送信ボタン（`canSubmit` で活性）。
- 送信中は ProgressView、失敗時はメッセージ表示。
- ホームで `n` キー（修飾なし）で新規投稿シート。`PostRowView` の返信ボタンから `reply` 付きでシートを開く。
- 既存の `n` を含むキー入力との衝突はホームのフォーカス文脈で確認する（j/k と同じ background ボタン方式）。

## エラーハンドリング

- ネットワーク・XRPC エラーは `XRPCError` を VM がユーザー向けメッセージに変換して表示。シートは閉じず再送信可能。
- mention DID 解決の失敗は致命的にしない（該当箇所をプレーンテキストにして投稿継続）。
- `uploadBlob` 失敗時は投稿全体を中断しエラー表示（部分送信しない）。
- 401（nonce challenge 以外）は既存パターンで refresh→1 回リトライ。リトライ後も失敗ならエラー。

## テスト計画（TDD）

純粋ロジックを厚く、ネットワークは fake で。

`BlueskyCoreTests`
- `FacetDetectorTests`: link（末尾句読点トリム含む）、tag（全角・64 上限・`#123` 除外）、mention 候補、複数 facet のバイトオフセットとソート、マルチバイト（日本語・絵文字）境界。
- `PostRecordWriteTests`: createRecord 送信 JSON のエンコード（facet の `$type`/`index`、embed.images、reply）。
- `BlobRefTests`: uploadBlob レスポンスのデコードと createRecord への埋め込み。
- `PostServiceTests`: fake sender で createPost（facet 結合・mention 解決・401 refresh リトライ・refresh トークン返却）、uploadBlob、リプライ ref 解決。

`YoruMimizukuKitTests`
- `ComposerViewModelTests`: 文字数・残数・canSubmit 境界（300 グラフェム、空、画像のみ）、送信成功/失敗の状態遷移、fake `PostSubmitting`。

apps/macos のビュー結線は手動確認（既存方針に準拠）。

## 実装順序（概略）

TDD で 1 ステップずつ。構造変更と振る舞い変更を分離してコミットする。

1. `FacetDetector`（link → tag → mention 候補）
2. 送信用モデル（`PostRecordWrite` / `BlobRef`）のエンコード/デコード
3. `PostService.uploadBlob`
4. `PostService.createPost`（facet 結合・mention 解決・401 リトライ）
5. リプライ ref 解決（`getRecord`）
6. `PostSubmitting` / `PostDraft` / `ComposerViewModel`
7. apps/macos: `LiveComposer` 結線、`ComposerView` シート、`n` キーと返信導線

各ステップごとに `cd core && swift test` を実行する。
