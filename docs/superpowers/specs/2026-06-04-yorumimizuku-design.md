# YoruMimizuku（星月夜）設計書

- 日付: 2026-06-04
- ステータス: 設計合意済み（実装計画はこの後 `writing-plans` で作成）
- 作業リポジトリ: `yorumimizuku`（アプリ名 YoruMimizuku / 星月夜）

## 1. 概要

YoruMimizuku（星月夜）は Bluesky（AT Protocol）のネイティブクライアントである。まず macOS を対象とし、将来 iOS、さらに Windows / Android への展開を視野に入れる。Electron は採用せず、メモリ効率の良いネイティブ実装（macOS は SwiftUI）とする。UI は夜フクロウ（Yorufukurou）に倣い、単一カラムを上部タブで切り替えて複数のタイムラインを読む構成にする。投稿・リプライ・いいね・リポスト・画像添付までを行える本格的なクライアントを目指す。認証は Bluesky の OAuth（PKCE + DPoP）を用い、macOS ではホーム/リストの Jetstream ストリーミングと、OS 通知（通知センターのバナー / Dock バッジ）に対応する。

参照実装として、同一作者の Ruby 製ターミナルクライアント `tempest`（`/Users/asonas/ghq/github.com/asonas/tempest`）を設計図に用いる。tempest は XRPC・セッション/トークンリフレッシュ・複数アカウント（per-DID レイアウト）・Jetstream クライアント（デコーダ / watchdog / バックフィル）・facet 検出・DID 解決などの実証済みロジックを持つ。ただし未完成部分もあるため移植ではなく、Swift として質の高い再実装を行う。

## 2. ゴール / 非ゴール

### v1 のゴール（本設計が対象とする範囲）
- OAuth（PKCE + DPoP）による認証、複数アカウント、トークン自動リフレッシュ
- 単一カラム + 上部タブの UI。タブで以下7種の情報源を開ける
  1. ホーム（`getTimeline`）
  2. 通知（`listNotifications`）
  3. カスタムフィード / feed generator（`getFeed`）
  4. リスト（`getListFeed`）
  5. ユーザーのプロフィール/投稿（`getAuthorFeed`）
  6. 検索（`searchPosts`）
  7. スレッド/会話（`getPostThread`、投稿クリックで開く）
- ホーム / リストの Jetstream リアルタイム更新。その他は定期ポーリング
- 書き込み一式: 新規投稿・リプライ・いいね・リポスト・画像添付
- 通知: アプリ内通知タブ ＋ OS バナー ＋ Dock バッジ
- 複数ウィンドウ（タブを別ウィンドウに分けて並読、夜フクロウ風）
- 表示密度を A（超コンパクト）/ B（ゆとり）から選択。既定は B

### 非ゴール（後続 spec / 将来）
- iOS / Windows / Android の実 UI 実装（コアは共有前提で設計するが、UI は別 spec）
- granular OAuth scope への移行（整備されたら対応。v1 は `transition:generic`）
- 高度なモデレーション（ラベラ設定の細部）、動画投稿、DM 等

## 3. 意思決定ログ（ブレインストーミングでの確定事項）

| 項目 | 決定 |
|---|---|
| v1 スコープ | 全部入り（認証 + マルチタブ + ストリーム + 通知 + 書き込み） |
| 認証方式 | Bluesky OAuth（PKCE + DPoP）。app password は不採用 |
| コア実装方針 | 自前の軽量 Swift コア（案B）。ATProtoKit には乗らない |
| クロスプラットフォーム | Swift で全 OS。まず macOS+iOS 共有の Swift Package。Windows/Android も将来同じ Swift コアを載せる。C++ / Rust コアは不採用 |
| UI レイアウト | 単一カラム + 上部タブ切替（夜フクロウ素直版） |
| 表示密度 | A/B を設定で選択可。既定 B |
| ストリーミング | ホーム/リストは Jetstream、他はポーリング |
| 通知 | アプリ内タブ + OS バナー + Dock バッジ |
| 複数ウィンドウ | 対応（per-window アカウント） |
| client-metadata ホスト | `ason.as`（`https://ason.as/yorumimizuku/client-metadata.json`、path は実装時確定） |
| リダイレクト方式 | カスタムスキーム `as.ason:/callback`（ASWebAuthenticationSession） |
| 永続化 | 機密は Keychain、設定/状態は Codable ファイル（SwiftData 不採用） |
| ターゲット OS | macOS 14+（Observation / 最新 SwiftUI） |

### ATProtoKit を採用しない根拠
ATProtoKit（v0.x、1.0 前で「非常に不安定」と明言）は app password 認証には対応するが、本件で中核となる OAuth（PKCE/DPoP）に未対応、Jetstream クライアントを持たず、Firehose も未完成。OAuth+DPoP と Jetstream はどの道自前実装が必要であり、不安定な依存を抱えるより UI 非依存の自前コアを持つ方が堅牢で、クロスプラットフォーム展開にも有利。

## 4. アーキテクチャ

### 4.1 2レイヤ構成

- **`BlueskyCore`（Swift Package / UI 非依存）**: AT Protocol のプロトコルロジックを純粋に保持。macOS / iOS をターゲットにし、将来 Windows / Android も同パッケージで狙う。SwiftUI / AppKit / UIKit に依存しない。
- **`BlueskyMac`（macOS アプリ / SwiftUI）**: `BlueskyCore` に薄く乗る UI 層。`WindowGroup` による複数ウィンドウ、`@Observable` ViewModel、async/await。

### 4.2 OS 接点の抽象化（ポータビリティの下ごしらえ）

`BlueskyCore` 内では OS 依存の接点を 6 つのプロトコルに隔離し、Apple 実装を別ファイル群（例: `CoreApplePlatform`）に置く。これにより将来 Windows/Android で Swift コアを載せる際の差し替えが安くなる。

1. セキュアストレージ（Apple: Keychain / Security）
2. 暗号・P-256 署名（Apple: CryptoKit）— DPoP 用
3. WebSocket（Apple: URLSessionWebSocketTask）— Jetstream 用
4. HTTP（Apple: URLSession）
5. ブラウザ認可セッション（Apple: ASWebAuthenticationSession）
6. OS 通知（Apple: UNUserNotificationCenter）

純粋ロジック（OAuth ステートマシン、Jetstream フレーミング/デコード、Codable モデル、facet 解析、ストア）はこれらに依存せず OS 非依存に保つ。

### 4.3 `BlueskyCore` モジュール

- `ATProtoHTTP`: XRPC トランスポート（`/xrpc/<nsid>` の GET/POST、JSON エンコード/デコード、`XRPCError`（`error`/`message`）モデル、DPoP 連携）
- `DPoP`: P-256 鍵の生成/保管、リクエストごとの proof JWT 署名（`htm`/`htu`/`iat`/`jti`/`ath`/`nonce`）、サーバ発行 nonce の捕捉と 1 回リトライ（`use_dpop_nonce` / `DPoP-Nonce`）
- `OAuthClient`: atproto OAuth プロファイル（identity 解決、authz server discovery、PAR、PKCE、ブラウザ認可、DPoP 束縛のトークン交換・リフレッシュ）
- `IdentityResolver`: handle↔DID キャッシュ、DID document → PDS エンドポイント解決
- `AccountManager` / `SessionStore`: per-DID セッション、複数アカウント index、トークン自動リフレッシュ
- `Models`: 必要分の lexicon を Codable で（`FeedViewPost` / `PostView` / `ProfileView` / `Notification` / `FeedGenerator` / `ListView` / `ThreadViewPost` / `Facet` / 各種 embed（images / external / record / recordWithMedia）/ `BlobRef`）
- `BlueskyAPI`: 高レベル型付き API（`getTimeline` / `getFeed` / `getListFeed` / `getAuthorFeed` / `searchPosts` / `getPostThread` / `listNotifications` / `updateSeen` / `getUnreadCount` / `createPost`（reply・embed・facets）/ `deletePost` / `like` / `unlike` / `repost` / `unrepost` / `uploadBlob` / `getProfile`）
- `RichText`: テキスト → facet 解析（mention の DID 解決、link、hashtag）。**UTF-8 バイトオフセット**で index を扱う点が要注意（tempest の facet 実装を参照）
- `Jetstream`: WebSocket クライアント（`wantedCollections` / `wantedDids` フィルタ、カーソル永続化、デコーダ、stall 検知 → 強制再接続する **watchdog**、復帰時バックフィル）
- `Stores`: ソース別 `TimelineStore`、cursor store、メモリ + 軽量ディスクキャッシュ

### 4.4 並行性モデル

- ネットワーク / ストリーム / ストアは `actor` ベースでスレッド安全に。
- 各タブのデータ源を `TimelineSource` プロトコルで抽象化する。
  - `loadLatest() async`、`loadOlder(cursor:) async`
  - `liveUpdates`（任意。ホーム/リストのみ Jetstream 由来のストリームを提供）
  - 実装: `HomeSource` / `FeedSource` / `ListSource` / `AuthorSource` / `SearchSource` / `NotificationSource` / `ThreadSource`

## 5. 認証（OAuth + DPoP）

### 5.1 client-metadata.json（ホスト要件）

native の OAuth クライアントは `client_id` として HTTPS 上に静的 JSON 1 枚を公開する必要がある。YoruMimizuku は `ason.as` 上に配置する。

```json
{
  "client_id": "https://ason.as/yorumimizuku/client-metadata.json",
  "client_name": "YoruMimizuku",
  "application_type": "native",
  "dpop_bound_access_tokens": true,
  "grant_types": ["authorization_code", "refresh_token"],
  "response_types": ["code"],
  "scope": "atproto transition:generic",
  "redirect_uris": ["as.ason:/callback"],
  "token_endpoint_auth_method": "none"
}
```

- 実装着手時に確定する項目: 公開パス（`/yorumimizuku/...` で良いか）、`client_name`、必要なら `transition:email` の追加。

### 5.2 ログインフロー

1. **Identity 解決**: 入力 handle → DID（`com.atproto.identity.resolveHandle` または DNS/`.well-known`）→ DID document から PDS エンドポイント取得
2. **Authz server discovery**: PDS の `/.well-known/oauth-protected-resource` → authorization server を特定 → `/.well-known/oauth-authorization-server` メタデータ取得
3. **PAR（Pushed Authorization Request）**: PKCE challenge・scope・DPoP proof を付けて POST、`request_uri` を受領
4. **ブラウザ認可**: `ASWebAuthenticationSession` で authorize エンドポイントを開く（ユーザーはブラウザで承認。app password を手入力しない）
5. **トークン交換**: 認可コードを DPoP 束縛で交換（nonce 再試行込み）。access / refresh トークンと DPoP nonce を取得
6. **保管**: トークンと DPoP 秘密鍵を Keychain に per-DID で保存

### 5.3 DPoP の要点

- P-256 鍵を Keychain（署名用途。Secure Enclave 利用は実装時に検討）
- 各リクエストに `Authorization: DPoP <token>` ＋ DPoP proof ヘッダ（`ath` = アクセストークンハッシュ、`nonce`）を付与
- `401 use_dpop_nonce` 受信時、返却された `DPoP-Nonce` で proof を作り直し 1 回だけリトライ。この往復は専用ラッパで一元化
- リフレッシュも DPoP 束縛

### 5.4 スコープ

v1 は `atproto` ＋ `transition:generic`（読み書き全般）。granular scope が整備されたら絞る方針をコメントで残す。

## 6. ストリーミング

### 6.1 ホーム / リスト（Jetstream ライブ）

- 初期ページは XRPC（`getTimeline` / `getListFeed`）で取得
- 以後、Jetstream を購読対象 DID（ホーム = フォロー中、リスト = メンバー）＋ `app.bsky.feed.post` でフィルタして購読し、新着を先頭にマージ
- Jetstream は生レコードのみを流すため、新着投稿は `getPosts` でバッチ hydrate（著者プロフィール・カウントを補完）してから挿入する。カウントは多少遅延するが許容
- tempest 由来の知見を流用: カーソル永続化、復帰時バックフィル、cursor-replay 由来の like/repost の抑制、**watchdog による stall 検知 → 強制再接続**（macOS の sleep/wake 後の典型故障対策）

### 6.2 既知の制約

Jetstream の `wantedDids` フィルタには上限がある。フォロー数が上限を超えるユーザーでは、全 DID 購読 + クライアント側フィルタは重すぎる。**上限超過時はホームを短間隔ポーリングにフォールバック**する（v1 の割り切り。実装時に Jetstream の上限値を確認して閾値を決める）。

### 6.3 その他のソース

カスタムフィード / 検索 / 著者 / 通知はサーバ計算または非フォロー対象のため、一定間隔ポーリング + バックオフ + pull-to-refresh。通知はバッジ用に `getUnreadCount` を併用。

## 7. UI

### 7.1 ウィンドウ構成

- タイトルバー右にアカウント切替。上部にタブ（右端の `+` で新タブ＝情報源選択）。中央に単一カラムのフィード。下部にコンポーザ（投稿ボックス + Post）
- 投稿クリックでスレッド（会話ツリー）を開く
- 複数ウィンドウ対応。`WindowGroup` + per-window state

### 7.2 投稿行（表示密度）

設定で 2 種を選択可能。既定は B。

- **A（超コンパクト）**: アバター小・1〜2 行・余白最小。リポスト/リプライ文脈は小さな 1 行。高密度・一覧性重視（夜フクロウ素直版）
- **B（ゆとり）**: アバター大・サムネイル表示・各投稿に返信/リポスト/いいねのアクションとカウント

サムネイル表示・アクション表示は密度とは独立に設定で切替可能にしてもよい（実装時に詳細決定）。

### 7.3 タブ（情報源）

§2 の 7 種。タブはウィンドウのアクティブアカウントで動作する。タブ構成はウィンドウ単位で永続化する。

## 8. 複数アカウント & 複数ウィンドウ

- **ウィンドウ単位でアクティブアカウントを持つ**。タブはそのウィンドウのアカウントで動作。右上の切替でウィンドウのアカウントを変更
- 別アカウントのウィンドウをもう 1 枚開けば複数アカウントを並読できる
- 全アカウントのセッションは Keychain にキャッシュ済みで切替は即時。`AccountManager` が現在アカウントとトークンリフレッシュを管理（tempest の per-DID / accounts index を参考）

## 9. 通知

- **アプリ内「通知」タブ**: `listNotifications` を取得し種別（like / repost / follow / reply / mention / quote）でグルーピング表示。既読化は `updateSeen`
- **OS バナー + Dock バッジ**: バックグラウンドのポーリング actor が一定間隔で `getUnreadCount` / `listNotifications` を叩き、前回既読以降の新着を `UNUserNotificationCenter` でバナー通知、Dock バッジに未読数。初回に通知許可をリクエスト
- ポーリング間隔は設定可能（既定 30–60s）。過剰ポーリングを避けるバックオフ

## 10. 永続化 & 機密

- **Keychain（per-DID）**: OAuth アクセス/リフレッシュトークン、DPoP 秘密鍵 ＝ 機密はすべてここ
- **設定/状態（Application Support 配下の Codable ファイル）**: アカウント index、ウィンドウ/タブ構成、表示設定（密度 A/B・サムネ表示・アクション表示）、Jetstream カーソル、（任意）タイムラインスナップショット（起動高速化用、tempest の timeline_store 相当）
- **SwiftData は不採用**。設定永続化も含め Swift 全プラットフォームで再利用でき、Apple 専用 API への依存を避けるため Codable ファイルベースにする

## 11. テスト戦略（TDD）

Kent Beck / t-wada 流の Red → Green → Refactor を 1 テストずつ。コアは UI 非依存で高テスト容易性。実ネットワークは使わず `URLProtocol` スタブ / フェイクで検証する。

- DPoP proof 生成（クレーム・署名）
- OAuth ステートマシン（discovery → PAR → 交換 → リフレッシュ、nonce 再試行）
- facet のバイトオフセット解析（mention / link / hashtag、マルチバイト境界）
- XRPC エラーデコード
- Jetstream デコーダ ＆ watchdog 再接続ロジック
- トークンリフレッシュ
- モデルの fixture JSON デコード（実レスポンス断片を fixture 化）

OS 接点（§4.2）はプロトコルのフェイクを注入してテストする。

## 12. 実装フェーズの見通し（詳細は writing-plans で確定）

1. `BlueskyCore` の足場 + `ATProtoHTTP` + `XRPCError` + モデル基盤
2. OAuth + DPoP 認証（client-metadata.json の用意含む）+ `AccountManager` + Keychain
3. 読み取り API（timeline / feed / list / author / search / thread / notifications）+ `TimelineSource`
4. `BlueskyMac` の足場: 単一ウィンドウ + 単一タブ（ホーム）+ 投稿行 A/B
5. タブ機構（7 情報源）+ タブ構成の永続化
6. Jetstream（ホーム/リスト）+ watchdog + フォールバック
7. 書き込み（投稿・リプライ・いいね・リポスト・画像 uploadBlob）+ RichText facet
8. 通知タブ + OS バナー + Dock バッジ
9. 複数アカウント + 複数ウィンドウ
10. 仕上げ（設定画面、キャッシュ、エラー表示、空状態）

## 13. 未確定事項（実装着手時に確定）

- bundle id の確定（案: `as.ason.YoruMimizuku`）
- client-metadata.json の公開パスと最終内容、ason.as リポジトリへの配置手順
- Jetstream の `wantedDids` 上限値と、ホームのポーリングフォールバック閾値
- 表示密度とサムネ/アクション表示の設定粒度
- 通知ポーリング間隔の既定値と、アプリ非アクティブ時の挙動

## 14. 追記: v1.0.0 スコープの再定義（2026-06-11）

v0.8.0 時点のギャップ分析（`docs/superpowers/plans/2026-06-11-yorumimizuku-v1.0.0-roadmap.md`）に基づき、本設計書の v1 スコープ（§2）を次のとおり再定義した。

- **Jetstream ストリーミング（§2.3 / §6）は見送る。** §6.2 のフォールバックとして規定していたポーリングを恒常の動作モードとし、v1.0.0 はポーリングのみで成立させる。再検討する場合は専用の設計スペックを新たに書く。
- **OS 通知バナー + Dock バッジ（§2.5 / §9.2）、カスタムフィードタブ・リストタブ（§2.2）は v1.x 系に先送りする。** v1.0.0 のタブソースは home / notifications / author / search / thread の 5 種とする。
- v1.0.0 に含めるのは、引用ポスト（record / recordWithMedia embed）の表示、動画 embed のポスター表示、自分のポストの削除 UI、アカウントセレクタ / ログアウト UI、通知設定（アプリ内ポーリング間隔）、エラー UX の整備である。
- **センシティブメディアのぼかし（最小版）を v1.0.0 に含める。** コンテンツラベル（セルフラベル + ラベラーのラベル）の `porn` / `sexual` / `nudity`（アダルト）と `graphic-media` / `gore`（過激）を判定し、該当ポストの画像・動画ポスターを「閲覧注意」カーテンでぼかしてタップで表示する（macOS のみ UI 実装、ラベルのデコードと判定は共有コア）。`getPreferences` による閲覧者ごとのラベル設定・購読ラベラー・per-label の hide/warn/show・アカウントレベルラベルといった完全なモデレーション（§13）は引き続き v1.x 以降に先送りする。

## 15. 追記: 動画アップロードのスコープ変更（2026-06-25）

§2 の非ゴールで対象外としていた動画アップロード（動画投稿）を、v1.0.0 スコープに含める決定に変更した。設計・実装は次を参照。

- spec: `docs/superpowers/specs/2026-06-25-compose-video-upload-design.md`
- plan: `docs/superpowers/plans/2026-06-25-compose-video-upload.md`
- フロー: `getServiceAuth` → 動画サービスへ `uploadVideo` → `getJobStatus` ポーリング → `app.bsky.embed.video`。動画は画像と排他。
- 実装範囲: コア + macOS + iPadOS（実装済み）。Windows は後追い。
- **§2 非ゴールの他の項目（granular OAuth scopes、DM、高度なモデレーション）は引き続き対象外。**
