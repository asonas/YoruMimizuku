# 投稿行の操作性改善（会話導線・コピー通知・メンション遷移）設計

- 日付: 2026-07-02
- 対象: macOS / iPadOS アプリ（`apps/macos`, `apps/ipados`）の投稿行 `PostRowView` と
  その周辺（`MainWindowView` のルーティング）、および共有コア `YoruMimizukuKit`
- 状態: 設計合意済み（実装計画はこれから）

## 背景と問題

投稿行まわりの操作性に、関連する3つの穴がある。

1. **会話（親投稿）へ辿る導線が弱い。** タイムラインの投稿から会話ビュー
   `ConversationView` へ行けるのは、返信件数ボタン・「@X への返信」マーカー
   （`PostRowView.replyMarker`）・引用カードのタップだけである。とりわけ
   `replyMarker` は表示条件が `showReplyMarker && !connectsToPrevious && replyParent != nil`
   のため、直上に同スレッドの投稿が並ぶと冗長として消える。本文中の `@メンション` は
   accent 色のリンクとして「押せる場所」が視認できるのに対し、返信関係そのもの
   （この投稿がぶら下がっている親投稿）を開く手掛かりは条件次第で失われ、安定した
   アフォーダンスがない。

2. **リンクコピーにフィードバックがない。** 右クリックメニューの「リンクをコピー」と
   アクションバーの link アイコンから `NSPasteboard.general` にパーマリンクを書き込むが
   （`FeedView.copyPermalink` / `ConversationView.copyPermalink`）、コピーが成功したこと
   をユーザーに知らせる一時通知（トースト）がない。リポジトリ全体を検索してもトースト /
   スナックバー等の再利用可能な一時通知の仕組みは存在しない。

3. **本文メンションがブラウザに逃げる。** `RichText.swift` はメンション facet を
   `https://bsky.app/profile/<did>` に変換する。ハッシュタグは `MainWindowView` の
   `openURL` アクションでアプリ内フィルタタブに流れるが、メンションは分岐がなく
   `.systemAction` に渡り、既定ブラウザでプロフィールが開く。アプリ内 author タブへ
   入れるのはアバタータップのみで、本文メンションはアプリ内遷移しない。

## 目標

1. どの投稿からでも、常に同じ位置にある安定したターゲットで会話ビューを開けるようにする。
   具体的には**時刻表示のクリックでその投稿をアンカーにした会話ビューを開く**。
2. リンクコピー時に「リンクをコピーしました」を短時間のトーストで知らせる。将来の
   他フィードバック（削除完了・失敗など）にも使える最小の横断基盤を用意する。
3. 本文中の `@メンション` タップをアプリ内 author タブに流し、ブラウザに逃がさない。

非目標:
- 返信件数ボタン・`replyMarker`・引用カードの既存導線の挙動変更（時刻導線を足すだけ）。
- トーストのスタイル種別（成功/失敗/警告の色分け等）や積み重ね表示。今回は文言テキスト
  1件のみ。
- メンション以外の通常リンク（`.link` facet）のアプリ内処理化。従来どおりブラウザ。
- ライトボックス・メディアレイアウト・密度設定の変更。

## 決定事項（合意済み）

### A. 時刻クリックで会話ビューを開く

- `PostRowView.authorLine` 内の相対時刻 `Text(relativeTime)` をタップ可能にする。
  新しいクロージャ `onOpenConversation: () -> Void`（`FeedView` / `ConversationView`
  が注入）を呼び、注入側で `WorkspaceModel.openConversation(_ post:)` を実行する。
- 挙動は返信件数ボタン（`onReplyTap`）とは独立で、**時刻は常にその投稿をアンカーにした
  会話ビューを開く**（「自分の投稿なら返信・他人なら会話」という `FeedView` の分岐は
  時刻には適用しない）。
- アフォーダンス（macOS）: `#if os(macOS)` で `.onHover` によりカーソルを
  `.pointingHand` にし、ホバー中のみ相対時刻に下線を付ける。常時のリンク色付けはしない
  （本文リンクと視覚的に競合させないため）。iPadOS ではホバーがないため、タップ可能で
  あることのみ（見た目は据え置き、タップ領域として機能させる）。
- 会話ビュー内の投稿行でも同じクロージャを注入し、時刻タップでその投稿へ再アンカー
  （`openConversation`）する。挙動をプラットフォーム・画面をまたいで統一する。
- 対象ファイル: `apps/macos/Views/PostRowView.swift`, `apps/ipados/Views/PostRowView.swift`,
  各 `FeedView.swift` / `ConversationView.swift`（クロージャ注入）。

### B. コピー時トースト（自前オーバーレイ基盤）

- **基盤（コア）**: `YoruMimizukuKit` に `@MainActor` の観測可能クラス `ToastCenter` を新設。
  - 状態: `current: ToastMessage?`。`ToastMessage` は `id`（一意）と `text: String` を持つ
    値型。今回は `text` のみでスタイルは持たせない。
  - `show(_ text: String)`: 単調増加する内部トークンをインクリメントして `current` を
    差し替え、そのトークンを捕捉した破棄タスクを起動する。破棄タスクは約 1.8 秒
    スリープ後、`current` のトークンが自分と一致するときだけ `current = nil` にする
    （新しい `show` が来ていたら何もしない）。連続コピーで前のトーストが即座に新しい
    文言へ置き換わる。
  - `dismiss()`: `current = nil` にして即消し（タップ用）。
- **表示（各アプリ）**: `MainWindowView` のルートに `.overlay(alignment: .bottom)` を1つ
  重ね、`toastCenter.current` が非 nil のとき `ToastView(message:)` をフェードで表示する
  （`.transition(.opacity)`、下端中央、下からのわずかな移動を添えてよい）。トーストの
  タップで `toastCenter.dismiss()`。`ToastCenter` は環境（`@Environment` / `environmentObject`
  相当）で `FeedView` / `ConversationView` から参照できるよう注入する。
- **発火**: `FeedView.copyPermalink(_:)` と `ConversationView.copyPermalink(_:)` が
  ペーストボードへ書き込んだ直後に `toastCenter.show("リンクをコピーしました")` を呼ぶ。
- **将来拡張**: 削除完了・失敗などにも `show(_:)` を流用できる。スタイル種別が必要に
  なった段階で `ToastMessage` に enum を追加すればよく、今回は入れない（YAGNI）。
- 対象ファイル: 新規 `core/Sources/YoruMimizukuKit/ToastCenter.swift`, 新規
  `apps/macos/Views/ToastView.swift`（および iPadOS 版）, `MainWindowView.swift`（overlay と
  環境注入）, 各 `FeedView.swift` / `ConversationView.swift`（`show` 呼び出し）。

### C. 本文メンションをアプリ内 author タブで開く

- `RichText` に、ハッシュタグの `hashtag(from:)` と対になる逆引き
  `mentionDID(from url: URL) -> String?` を追加する。`url.host == "bsky.app"` かつ
  パスが `["profile", <did>]`（2要素、`post` を含まない）のとき、その識別子（DID）を返す。
  それ以外は nil。
- `MainWindowView` の `openURL` アクションに分岐を追加する。判定順は
  ハッシュタグ（既存 → `openHashtagFilter`）→ **メンション（新規 → `openAuthor`）** →
  それ以外（従来どおり `.systemAction`）。
- メンションタップ時は取り出した DID を使い
  `workspace.openAuthor(did: did, handle: "", displayName: "", avatarURL: nil)` を呼ぶ。
  `openAuthor` は DID で既存タブを重複排除し、`makeAuthorModel(did)` / `makeAuthorHeader(did, …)`
  がプロフィールを解決するため、handle・表示名・アバターは後追いで埋まる。
  - トレードオフ: `openURL` アクションは URL しか受け取れず、タップ時点で `@handle`
    表示テキストを取得できない（`bodyText` は `Text(bodyAttributed)` にネイティブ
    `.link` 処理を委ねており、セグメント単位のタップ処理ではない）。そのため author
    タブのラベルは解決までごく短時間ブランクになりうる。これは許容する。ブランクを
    避けたくなった場合は、メンションのみ専用タップ経路に切り出す別設計が必要になるが、
    今回はやらない。
- 対象ファイル: `core/Sources/YoruMimizukuKit/RichText.swift`（`mentionDID(from:)` 追加）,
  `apps/macos/Views/MainWindowView.swift` / `apps/ipados/Views/MainWindowView.swift`
  （`openURL` 分岐）。

## テスト方針

TDD（Red → Green → Refactor）で1ステップずつ進める。ロジックはコア側の純粋関数・
観測可能クラスに寄せ、View 層は薄く保つ。

- **`RichText.mentionDID(from:)`（`BlueskyCoreTests` もしくは `YoruMimizukuKitTests`）**
  - `https://bsky.app/profile/did:plc:xxxx` → `did:plc:xxxx` を返す。
  - handle 形式のプロフィール URL（`bsky.app/profile/alice.bsky.social`）→ その識別子を返す。
  - `https://bsky.app/profile/<id>/post/<rkey>`（投稿パーマリンク）→ nil。
  - `bsky.app/hashtag/<tag>` や外部リンク → nil。
  - ホスト違い（`example.com/profile/x`）→ nil。
- **`ToastCenter`（`YoruMimizukuKitTests`）**
  - `show(_:)` 後に `current?.text` が渡した文言と一致する。
  - 2回連続 `show` すると `current` が2件目に置き換わる（`id` が異なる）。
  - `dismiss()` 後に `current == nil`。
  - 自動破棄のトークン一致ロジックは、実時間タイマーに依存させず、破棄処理を検証可能な
    形（トークン比較関数を分離、あるいは破棄間隔を注入可能に）にして単体で確認する。
- View 層（時刻タップ、overlay 表示）は挙動が薄いため、クロージャ結線と overlay の
  存在確認にとどめ、重い UI テストは追加しない。

## 実装順序（TDD、1ステップずつ）

1. C の `RichText.mentionDID(from:)` をテスト先行で追加（純粋関数、副作用なし）。
2. `MainWindowView.openURL` にメンション分岐を足し、`openAuthor(did:…)` へ結線。
3. B の `ToastCenter` をテスト先行で追加（`show` / `dismiss` / トークン破棄）。
4. `ToastView` と `MainWindowView` の overlay・環境注入を追加。
5. `FeedView` / `ConversationView` の `copyPermalink` から `show("リンクをコピーしました")`。
6. A の `PostRowView` 時刻タップ＋ホバー下線・カーソル、`onOpenConversation` 注入を
   macOS → iPadOS の順に追加。
7. 会話ビュー内の時刻タップ結線（再アンカー）。

各ステップ後に `cd core && swift test` を通し、必要に応じて
`xcodebuild build -scheme YoruMimizuku` で app 込みビルドを確認する。macOS 実装の後に
iPadOS 版へ同じ変更を反映する（両者は同構造の並行実装で、ロジックは `core` 共有）。

## リスクと留意点

- `openAuthor` を空 handle で呼ぶ際の author タブ初期表示ブランク（C のトレードオフ参照）。
- 時刻タップと本文リンクタップは別 `Text` のため衝突しないが、`.onHover` の下線が
  リフローレイアウト（本文左・メディア右）でも著者行に正しく載ることを目視確認する。
- トースト overlay が会話ビュー・フィード・設定など全画面のルートに1つだけ存在し、
  タブ切替やウィンドウリサイズで多重表示・取り残しが起きないこと。
