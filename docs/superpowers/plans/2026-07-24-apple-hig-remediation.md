# YoruMimizuku Apple HIG 是正 実装計画（2026-07-24 改訂版）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS/iPadOS 全画面 HIG レビューで確定した P0/P1/P2 指摘（no-op操作・無警告破棄・hover専用操作・フルスクリーン強制・タップターゲット不足・操作経路欠落）を、独立レビュー可能な11サブプロジェクトで是正する。

**Architecture:** テスト可能なロジックは `YoruMimizukuKit`（SPM, XCTest + プロトコル注入）に置き TDD で進める。View 層（`apps/macos` / `apps/ipados`、テストターゲット非包含）は最小差分とし、スナップショットテストと手動検証で担保する。構造変更（Button化・配線）と振る舞い変更は別コミット。

**Tech Stack:** Swift 6（strict concurrency）/ SwiftUI / XCTest / swift-snapshot-testing（macOS 2x・560pt固定、iPad Pro 13-inch (M5)・iOS 26.5 シミュレータ固定）/ XcodeGen / mise（wiki tooling）

**保存先:** 実装開始時に最初の worktree で `docs/superpowers/plans/2026-07-24-apple-hig-remediation.md` として保存し、wiki ingest の対象にする（計画フェーズではリポジトリに書き込まない）。

## Global Constraints

- 新規作業は必ず `git wt feature/xxx` で worktree を作成。main に直接コミットしない。マージ後は `git wt remove <path>` で worktree を削除
- コミットは必ず `/commit` スキル（内部で `git ai-commit`）。`git commit` を直接実行しない。メッセージは英語・先頭大文字・Conventional Commits 不使用
- 構造変更（挙動不変の Button 化・配線・API骨格）と振る舞い変更（テストが変わる変更）は別コミット
- Kit テスト: `swift test --package-path core`（フィルタ例: `--filter ComposerViewModelTests`）。Green のたびに全体回帰
- macOS アプリテスト: `xcodebuild test -scheme YoruMimizuku -project YoruMimizuku.xcodeproj -destination 'platform=macOS'`
- iPad アプリテスト: `xcodebuild test -scheme YoruMimizukuPad -project YoruMimizuku.xcodeproj -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'`
- `xcodegen generate` が必要なのは (a) `project.yml` を変更したとき、(b) `apps/` 配下に新規ファイルを追加したとき（sources がディレクトリ指定のため）。**`core/` 配下の新規 SPM ファイルには不要**
- UI 文言は日本語。⌘N=新規投稿は確立挙動として維持（wiki 記録済み）
- wiki 更新は各サブプロジェクトの最終コミットに含める: 該当ページ更新 → `log.md` 先頭に追記 → `mise run wiki:lint` / `wiki:matrix`（featuresブロック変更時）/ `wiki:index` / `wiki:check`
- テストを書けない箇所は「自動テストなし」と明記し手動検証チェックリストで代替する。**Red にならないテストを書いてはならない**

---

## コンテキスト

P0 は「見た目は操作可能なのに効かない」「破壊的操作が無警告」「OS仕様との矛盾」というユーザー被害が直接あるもの、P1 は操作経路・アクセシビリティ・状態回復の欠落、P2 は検討・棚卸し・実機検証。

重要な仕様判断: `apps/macos/Views/NewPostCommand.swift:3-7` のコメントは「タイムラインクライアントに追加ウィンドウは不要」と主張するが、ground truth の `docs/superpowers/specs/2026-06-04-yorumimizuku-design.md`（L28/L48/L163/L178-181: 複数ウィンドウ・per-window アカウント並読）と `2026-06-08-yorumimizuku-ipados-design.md`（L41: per-scene WorkspaceModel で Stage Manager / multi-window）、`docs/wiki/behaviors/app-shell.md`（Multiple windows: macOS full）は複数ウィンドウを要求する。**仕様を優先し新規ウィンドウ経路を復元する**（⌘N=新規投稿は維持、別ショートカットで追加。コメントも書き換える）。

### 初版からの改訂点（自己レビュー反映）

1. **P0-1**: YAGNI を優先し、公開 API `ThreadViewModel.canInteract(with:)` とテスト5件を削除。現行仕様は「返信行は非操作」で確定しているため、macOS replyRow に `interactiveActions: false` を明示する最小 View 変更のみとする。
2. **P0-4**: 送信キャンセル機能（`startSubmit`/`submitTask`/`cancelSubmission`/`CancellationError`・`URLError(.cancelled)` 分岐）を新設しない。下書き破棄確認と「送信中はキャンセル・interactive dismiss を無効化して結果を待たせる」最小対応に限定。Kit の追加は `hasUnsavedContent` のみ。
3. **S1/S2**: `contentShape` の負 inset が layout bounds 外のヒット領域を確実に拡張する保証はないため採用しない。標準 Button に glyph サイズを保ったまま `frame(minWidth: 44, minHeight: 44)` を与える方針を優先。`touchTargetInset` 関数は不要になったため削除し、**旧S1はサブプロジェクトごと廃止**して `DesignMetrics.minimumTouchTarget` 定数の TDD を S2 の第1コミットに統合。
4. **S5.1**: 「現実装でも Red にならない」state+レンダーテストを削除。既存 SnapshotTesting で空白画面の参照 PNG に対する差分として Red を観測する手順に変更（不安定なら自動テストを捏造せず手動検証のみ）。
5. **xcodegen**: core 配下の新規 SPM ファイル追加では不要（Global Constraints に明記、S4.1 の誤記を修正）。
6. **分割再評価**: 12→11 サブプロジェクト（S1 を S2 に統合）。S3（macOS/構造のみ/スナップショット macOS 側）と S6（両OS/contextMenu 追加/スナップショット非対象）はファイル・検証手段・レビュー観点が異なるため統合しない。

### 調査で確定した前提（実コード検証済み。★は当初想定への訂正）

- 返信行 no-op（P0-1）: `apps/macos/Views/ConversationView.swift` の返信ツリー行 `replyRow`（152-176行）は `PostRowView` の `interactiveActions`（`apps/macos/Views/PostRowView.swift:21`、デフォルト true）をそのままに `onLike`/`onRepost` を渡すが、`ThreadViewModel.post(id:)`（`core/Sources/YoruMimizukuKit/ThreadViewModel.swift:77-80`）が `thread.focus.id == id` のときだけ解決するため不活性。157-161行に「Phase D: intentionally inert」コメント。祖先行 `parentBlock`（91-106行）は既に `interactiveActions: false` + 行全体 re-anchor ボタン。
- ★iPad 側 `apps/ipados/Views/ConversationView.swift` は祖先行・返信行とも既に `interactiveActions: false`。P0-1 は **macOS のみ**。
- ★macOS の `interactiveActions: false` はタイムスタンプタップ（会話を開く）も殺すため、parentBlock と同じ「行全体 re-anchor ボタン」を同時に行い、現に機能している操作を失わない。
- Sidebar（P0-2）: `apps/macos/Views/SidebarView.swift` の `SidebarRow`（271-384行）が `@State isHovered` + `.onHover`（345行）で close(xmark)/edit(pencil) を hover 時のみ条件描画（349-362行）。contextMenu なし。`accessibilityAction` はリポジトリ全体で0件。
- iPad scene（P0-3）: `project.yml:94` に `UIRequiresFullScreen: true`。`UIApplicationSceneManifest` 未定義。`apps/ipados/Views/RootView.swift` の `MainShellView` は `NavigationSplitView(columnVisibility:)` を `.all` 固定（305行）、detail 側 `.toolbar(.hidden, for: .navigationBar)`（497行）で sidebar toggle も消失。`horizontalSizeClass` 参照ゼロ。★`WorkspaceModel` は `AuthenticatedRootView` の `@StateObject`（RootView.swift:163）で scene ごとの分離は既に成立。★マルチタスキング対応には全4方向 orientation が必要だが `PortraitUpsideDown` が欠落（project.yml:100-103）。
- Composer（P0-4）: `core/Sources/YoruMimizukuKit/ComposerViewModel.swift` に `hasContent` 相当なし。macOS `apps/macos/Views/ComposerView.swift:28` のキャンセル→`onClose()` 即破棄、iPad `apps/ipados/Views/ComposerView.swift:23-25` の `dismiss()` 即破棄（スワイプダウンでも破棄）。macOS のキャンセルボタンは送信中も押せる（disabled 指定なし）。
- ★macOS 通知の empty 状態は実装済み（`apps/macos/Views/NotificationsView.swift:72-80`「通知はまだありません」+ bell.slash）。P1-d の empty 対応は **iPad のみ**。failed→再試行は iPad 実装済み。
- ★アバター取得失敗は `RemoteAvatar` の `person.crop.circle.fill` フォールバックが両OS実装済み → 追加対応不要。動画は `VideoPlayerScreen`（`apps/ipados/Views/PostRowView.swift:633-661`）に失敗監視がない。
- ★macOS アクションバーに Safari ボタンはない（コピーのみ）。「ブラウザで開く」は macOS では contextMenu 新規経路、iPad ではアクションバー既存 + contextMenu 追加。
- 型検証: `WorkspaceTab` は `.home/.notifications/.filter(UUID)/.conversation(UUID)/.author(UUID)`。`FilterTab.title`・`ConversationTab.title` は存在、★`AuthorTab` に `title` はなく `displayName`/`handle` を使う。`NotificationsViewModel.State` は `Equatable`。`DesignMetrics` の定数は全て `Double`。テストは全面 XCTest、`@MainActor final class XxxTests: XCTestCase` + プロトコル注入。
- 設定ストア（ThemeStore/DisplaySettingsStore/FontSettingsStore/NotificationSettingsStore）は macOS RootView の `@StateObject`（RootView.swift:30-33）で永続化は `UserDefaults.standard` 共有。複数ウィンドウ復活後は「ウィンドウ間で設定変更がライブ同期しない」問題が顕在化する（S7 の判断材料）。
- スナップショット: `apps/macosTests/CatalogSnapshotTests.swift` / `apps/ipadosTests/CatalogSnapshotTests.swift`。CatalogVariant は postRow系 + actionBar/quoteCard/linkCard/videoPoster/toast のみで、contextMenu・通知・サイドバー・ウィンドウタイトルは非対象。

### スコープ外（現状維持と確認されたもの）

- macOS の List ベースフィード
- iPad の NavigationStack + Form 構成（Composer/Settings）
- OS 別の動画再生方式
- 既存 Timeline の loading/empty/failure/retry
- **送信中の投稿キャンセル機能**（今回の HIG 修正では「送信中は破棄も dismiss もさせず結果を待たせる」に留める。in-flight キャンセルは将来課題として wiki の既知の制約に記録）
- Windows アプリ（`apps/windows`）への波及なし（wiki の features 表記のみ更新）

## サブプロジェクト構成・依存・推奨順（全11件）

```
P0-1 feature/hig-thread-reply-actions      [macOS View のみ / 独立]
P0-2 feature/hig-sidebar-accessibility     [macOS View / 独立]
P0-3 feature/hig-ipad-multiscene           [project.yml + iPad View / 独立]
P0-4 feature/hig-composer-draft-protection [Kit + 両OS View / 独立]
        │ （P0 を全て main へマージ後に P1 着手。P0-1/P0-4 が PostRowView・ComposerView に触るため）
        ▼
S2 feature/hig-ipados-tap-targets          [P1-a iPad + P1-b。Kit定数を第1コミットに内包]
S3 feature/hig-macos-pointer-buttons       [P1-a macOS / 独立]
S4 feature/hig-macos-windows               [P1-c。Kit + macOS / 独立]
  └─▶ S7 feature/hig-macos-settings-scene  [P2。S4 マージ後が合理的]
S5 feature/hig-notifications-video-recovery[P1-d。iPad のみ / 独立]
S6 feature/hig-open-in-browser-menu        [P1-e。両OS・極小 / 独立]
S8 feature/hig-a11y-inventory              [P2 棚卸し + 実機検証チェックリストの wiki 化]
```

推奨着手順: **P0-4 → P0-1 → P0-2 → P0-3**（被害の大きい順）→ **S6 → S3 → S5 → S2 → S4 → S7 → S8**。P0 の4件は相互独立で並行 worktree 可。S3/S4/S5/S6 も並行可。S2/S3/S6 は PostRowView に触るため P0 マージ後に rebase してから着手。

スナップショット再録の要否: S2（Button 化 + 44pt frame でレイアウト差分が出る想定。差分 PNG を目視レビューして再録）、S3（描画不変を狙うが要確認）、S5（新規参照 PNG 追加）。他は再録不要。

---

# P0-1: Conversation 返信行の no-op アクション縮退（feature/hig-thread-reply-actions）

iPad 側は対応済みのため macOS のみ。現行仕様は「会話ビューで操作できるのはフォーカス投稿のみ、返信行は再アンカー対象」で確定しているため、Kit に新規 API は追加しない（YAGNI）。View が VM の暗黙ルールと食い違っていた点を、View 側の明示指定で解消する。

### Task 1: macOS replyRow を interactiveActions: false へ縮退し re-anchor ボタン化

**Files:**
- Modify: `apps/macos/Views/ConversationView.swift:152-176`（replyRow）、`:157-161`（コメント）
- Modify: `docs/wiki/behaviors/app-shell.md`（conversation tab の返信ツリー挙動を1段落更新）

**Interfaces:**
- Consumes: `PostRowView.interactiveActions: Bool`（`apps/macos/Views/PostRowView.swift:21`、既存）、`onOpenConversation: (PostDisplay) -> Void`（ConversationView 既存クロージャ）
- Produces: なし（View 内部変更のみ）

**自動テストを書かない理由（明記）:** `ConversationView.swift` はどのテストターゲットにも含まれず、スナップショットカタログ（CatalogVariant）にも conversation 系 variant がない。欠陥の本質は「タップしても何も起きない」というヒットテスト挙動であり、XCTest（ユニット/スナップショット）では検証できず、リポジトリに UI テストターゲットは存在しない。カタログ variant を新設しても静的描画（見た目）しか検証できず no-op の再発防止にならないため、手動検証で担保する。

- [ ] **Step 1: replyRow の縮退**

`apps/macos/Views/ConversationView.swift` の replyRow で、`PostRowView(...)` に `interactiveActions: false` を明示し、`onLike:` / `onRepost:` の受け渡しを削除する（`interactiveActions: false` 時は `staticActionBar` が描画され、like/repost クロージャは使われないため）。

- [ ] **Step 2: 行全体の re-anchor ボタン化**

parentBlock（91-106行）に倣い、replyRow の行全体を包む:

```swift
Button {
    onOpenConversation(node.post)
} label: {
    PostRowView(post: node.post, /* 既存引数 */, interactiveActions: false, /* 既存引数 */)
}
.buttonStyle(.plain)
.help("この返信を中心に会話を開く")
```

これによりタイムスタンプタップ喪失の代替（行タップで再アンカー）を与える。

- [ ] **Step 3: コメント書き換え**

157-161行の「Phase D: like/repost on a reply node are intentionally inert」コメントを、「返信行は再アンカー対象であり action bar は静的表示。操作できるのはフォーカス投稿のみ（`ThreadViewModel.post(id:)` がフォーカス限定）」という現行仕様の記述に書き換える。

- [ ] **Step 4: ビルド確認**

Run: `xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: 手動検証**

1. 返信行のハート/リポストが静的ラベル（非タップ）表示になっている
2. 返信行のどこをタップしても会話が再アンカーされる
3. フォーカス行の like/repost は従来どおり動く
4. 祖先行の挙動が退行していない

- [ ] **Step 6: wiki 更新とコミット**

`docs/wiki/behaviors/app-shell.md` を更新し `mise run wiki:check` を通す。View 変更 + コメント + wiki を1コミット（振る舞い）として `/commit` スキルで作成。メッセージ例: "Degrade conversation reply rows to static action bars with re-anchor tap"

---

# P0-2: macOS Sidebar close/edit のキーボード/VoiceOver 経路（feature/hig-sidebar-accessibility）

### Task 1: SidebarRow に contextMenu / accessibilityAction / ラベル追加

**Files:**
- Modify: `apps/macos/Views/SidebarView.swift:271-384`（`SidebarRow`。hover 表示 345-362行は不変・純追加）
- Modify: `docs/wiki/behaviors/app-shell.md`、`docs/wiki/platforms/macos.md`

**Interfaces:**
- Consumes: `SidebarRow` の既存 `onEdit: (() -> Void)?` / `onClose: (() -> Void)?`
- Produces: なし（View 内部変更のみ）

**自動テストを書かない理由（明記）:** contextMenu / accessibilityAction は静的レンダリングに現れずスナップショット不可。`SidebarRow` は private で、`SidebarView.swift` はテストターゲット非包含。「この行が持つアクション集合」の純関数抽出は3分岐しかなくトートロジーテストになる。実体ロジック（`WorkspaceModel.closeConversation` / `removeFilter` 等）は既存 `WorkspaceModelTests` が担保済み。

- [ ] **Step 1: contextMenu とアクセシビリティ修飾の追加**

```swift
.contextMenu {
    if let onEdit {
        Button { onEdit() } label: { Label("フィルターを編集", systemImage: "pencil") }
    }
    if let onClose {
        Button(role: .destructive) { onClose() } label: { Label("タブを閉じる", systemImage: "xmark") }
    }
}
.accessibilityElement(children: .combine)
.accessibilityLabel(accessibilityRowLabel)  // title + subtitle を合成した private var を追加
```

`onEdit` / `onClose` が非 nil の場合のみ `.accessibilityAction(named: "フィルターを編集") { onEdit?() }` / `.accessibilityAction(named: "タブを閉じる") { onClose?() }` を `@ViewBuilder` 分岐で付与。`iconButton`（364-373行）に `.accessibilityLabel(help)` を付与。

- [ ] **Step 2: ビルド確認**

Run: `xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: 手動検証**

1. 右クリック（Control+クリック）でフィルター行/会話タブ行にメニューが出て動作する
2. VoiceOver アクションメニュー（VO+Command+Space）に「タブを閉じる」「フィルターを編集」が現れ実行できる
3. Accessibility Inspector で custom actions とラベルを確認
4. hover 時の pencil/xmark の見た目・動作が退行していない

- [ ] **Step 4: wiki 更新とコミット**

wiki 2ページ更新 + `mise run wiki:check`。1コミット（振る舞い・純追加）を `/commit` スキルで作成。メッセージ例: "Add context menu and VoiceOver actions to sidebar rows"

---

# P0-3: iPad UIRequiresFullScreen 廃止とマルチシーン（feature/hig-ipad-multiscene）

### Task 1: project.yml でマルチシーン宣言（構造）

**Files:**
- Modify: `project.yml:84-103`（YoruMimizukuPad ターゲット info.properties）

**Interfaces:**
- Consumes: なし
- Produces: `UIApplicationSupportsMultipleScenes: true` な Info.plist（Task 2 と検証マトリクスの前提）

- [ ] **Step 1: project.yml 編集**

1. `UIRequiresFullScreen: true`（94行）を削除
2. 追加:

```yaml
UIApplicationSceneManifest:
  UIApplicationSupportsMultipleScenes: true
```

（SwiftUI App ライフサイクルのため `UISceneConfigurations` / SceneDelegate は不要）

3. `UISupportedInterfaceOrientations` に `UIInterfaceOrientationPortraitUpsideDown` を追加（マルチタスキング対応アプリは全4方向必須）

- [ ] **Step 2: 再生成とビルド確認**

Run: `xcodegen generate` → `xcodebuild build -scheme YoruMimizukuPad -project YoruMimizuku.xcodeproj -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: コミット**

project.yml のみ1コミット（構造）を `/commit` スキルで作成。メッセージ例: "Enable multiple scenes and drop UIRequiresFullScreen on iPad"

### Task 2: compact 幅適応と sidebar toggle 復帰（振る舞い）

**Files:**
- Modify: `apps/ipados/Views/RootView.swift:272-737`（`MainShellView`）
- Modify: `docs/wiki/platforms/ipados.md`、`docs/wiki/behaviors/app-shell.md`（Multiple windows: ios の note 更新）

**Interfaces:**
- Consumes: Task 1 の Info.plist 変更
- Produces: なし

- [ ] **Step 1: sizeClass 適応の実装**

1. `MainShellView` に `@Environment(\.horizontalSizeClass) private var horizontalSizeClass` を追加
2. detail 側（497行）を条件化:

```swift
.toolbar(horizontalSizeClass == .compact ? .automatic : .hidden, for: .navigationBar)
```

compact（Split View 1/3・Slide Over）では navigation bar を出し、collapse 時の back/sidebar ボタンを確保。regular では現行の chromeless を維持。`columnVisibility = .all` 固定（305行）は regular では維持（compact では NavigationSplitView が単一カラムに折りたたまれ columnVisibility は無視される）。

- [ ] **Step 2: ビルド確認**

Run: `xcodebuild build -scheme YoruMimizukuPad ...`（前掲 destination）
Expected: BUILD SUCCEEDED

- [ ] **Step 3: 検証マトリクス実施（シミュレータ + 実機）**

| 項目 | 期待 |
|---|---|
| フルスクリーン横/縦 | 従来どおり2カラム、detail chromeless |
| Split View 2/3・1/2（regular） | 2カラム維持、崩れなし |
| Split View 1/3・Slide Over（compact） | 単一カラム、sidebar↔detail を行き来できる |
| Stage Manager 各サイズ | compact⇄regular 遷移でタブ選択状態保持 |
| 2シーン同時（App Exposé +） | 各シーンが独立 WorkspaceModel。RefreshGate 経由でトークンリフレッシュが競合しない |
| 同一 DID の2シーンでフィルター/会話タブ操作 | クラッシュなし。永続化は last-writer-wins（既知の制約として wiki に記載） |
| composer sheet を開いたままリサイズ | sheet が破棄されない |
| 4方向回転 | すべて動作 |

Stage Manager の regular 縮小で detail 到達不能が出た場合のみ `.automatic` へ変更（未確定事項3）。

- [ ] **Step 4: wiki 更新とコミット**

`ipados.md`（multi-scene / Stage Manager 対応、compact 挙動、last-writer-wins 制約）と `app-shell.md` を更新 → `mise run wiki:matrix` → `wiki:check`。1コミット（振る舞い）を `/commit` スキルで作成。メッセージ例: "Adapt iPad shell to compact width and multi-scene"

**自動テストを書かない理由（明記）:**「compact なら nav bar を隠さない」の1行関数抽出はトートロジーテストにしかならず見送り。担保は上記マトリクス。

---

# P0-4: Composer 下書き保護（feature/hig-composer-draft-protection）

送信キャンセル機能は新設しない。範囲は (1) 破棄時に `hasUnsavedContent` なら確認ダイアログ、(2) 送信中はキャンセルボタンと interactive dismiss を無効化して結果を待たせる、の2点。Kit の追加は `hasUnsavedContent` のみ。Task 1 → Task 2/3（2と3は並行可）。

### Task 1: `ComposerViewModel.hasUnsavedContent`（Kit・TDD）

**Files:**
- Modify: `core/Sources/YoruMimizukuKit/ComposerViewModel.swift`
- Test: `core/Tests/YoruMimizukuKitTests/ComposerViewModelTests.swift`（既存 `FakeSubmitter: PostSubmitting` を再利用）

**Interfaces:**
- Consumes: 既存 `@Published var text` / `images` / `video`、`init(submitter:replyParentURI:replyParent:quotedPost:)`
- Produces: `public var hasUnsavedContent: Bool`（Task 2/3 の View が参照）

- [ ] **Step 1: 最初の失敗テストを書く**

```swift
func testHasUnsavedContentIsFalseWhenEmpty() {
    let vm = ComposerViewModel(submitter: FakeSubmitter())
    XCTAssertFalse(vm.hasUnsavedContent)
}
```

- [ ] **Step 2: Red を確認**

Run: `swift test --package-path core --filter ComposerViewModelTests/testHasUnsavedContentIsFalseWhenEmpty`
Expected: FAIL（`hasUnsavedContent` 未定義のコンパイルエラー）

- [ ] **Step 3: 最小実装**

```swift
/// Whether discarding the composer would lose something the user produced:
/// non-blank text, attached images, or a video. Reply/quote targets alone
/// don't count — reopening the composer recreates them.
public var hasUnsavedContent: Bool {
    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !images.isEmpty || video != nil
}
```

- [ ] **Step 4: Green を確認**

Run: 同上フィルタ
Expected: PASS

- [ ] **Step 5: 残りのテストを1件ずつ Red→Green で追加**

追加順（各テストは実装済みプロパティに対する仕様固定。書いた時点で失敗しないものは**書く前に一時的に実装を壊して Red を確認するのではなく**、境界仕様を変えるケースのみ追加する。以下は 2 と 5 が仕様上の境界で、書く価値がある）:

```swift
func testHasUnsavedContentIsFalseWithWhitespaceOnlyText() {
    let vm = ComposerViewModel(submitter: FakeSubmitter())
    vm.text = "  \n  "
    XCTAssertFalse(vm.hasUnsavedContent)
}

func testHasUnsavedContentIsTrueWithText() {
    let vm = ComposerViewModel(submitter: FakeSubmitter())
    vm.text = "hi"
    XCTAssertTrue(vm.hasUnsavedContent)
}

func testHasUnsavedContentIsTrueWithImage() { /* images に1件追加して true */ }
func testHasUnsavedContentIsTrueWithVideo() { /* video を設定して true */ }

func testHasUnsavedContentIsFalseWithOnlyQuoteTarget() {
    // canSubmit は true（引用のみ投稿可）でも破棄確認は不要、という区別を固定する
    let vm = ComposerViewModel(submitter: FakeSubmitter(), quotedPost: samplePost())
    XCTAssertFalse(vm.hasUnsavedContent)
}

func testHasUnsavedContentIsFalseWithOnlyReplyTarget() {
    let vm = ComposerViewModel(submitter: FakeSubmitter(), replyParent: samplePost())
    XCTAssertFalse(vm.hasUnsavedContent)
}
```

（`samplePost()` は既存テストファイルのフィクスチャヘルパを再利用。ComposeImage/ComposeVideo の生成も既存テストの書き方に合わせる。）

- [ ] **Step 6: 全体回帰**

Run: `swift test --package-path core`
Expected: 全件 PASS

- [ ] **Step 7: コミット**

1コミット(振る舞い)を `/commit` スキルで作成。メッセージ例: "Add hasUnsavedContent to ComposerViewModel"

### Task 2: macOS 破棄確認 + 送信中の操作無効化（View）

**Files:**
- Modify: `apps/macos/Views/ComposerView.swift`（キャンセルボタン 28行、body）

**Interfaces:**
- Consumes: Task 1 の `hasUnsavedContent`、既存 `isSubmitting` / `onClose`
- Produces: なし

- [ ] **Step 1: キャンセルボタンの分岐と確認ダイアログ**

```swift
@State private var confirmingDiscard = false

Button("キャンセル") {
    if model.hasUnsavedContent {
        confirmingDiscard = true
    } else {
        onClose()
    }
}
.disabled(model.isSubmitting)   // 送信中は破棄もキャンセルもさせず結果を待たせる
.confirmationDialog("下書きを破棄しますか？", isPresented: $confirmingDiscard,
                    titleVisibility: .visible) {
    Button("破棄する", role: .destructive) { onClose() }
    Button("編集を続ける", role: .cancel) {}
}
```

body に `.interactiveDismissDisabled(model.hasUnsavedContent || model.isSubmitting)` を付与（Esc/シート外操作での無警告破棄と送信中 dismiss を防止）。`MainWindowView.swift` の sheet 本体は変更不要。

- [ ] **Step 2: ビルド確認**

Run: `xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: 手動検証**

1. 空 composer は即閉じ
2. テキスト/画像ありで確認ダイアログ（破棄する/編集を続ける）
3. 送信中はキャンセルボタンが disabled、Esc でも閉じない、完了/失敗後に操作が戻る
4. 引用のみ・返信ターゲットのみでは確認なしで閉じる

- [ ] **Step 4: コミット**

1コミット（振る舞い）を `/commit` スキルで作成。メッセージ例: "Confirm draft discard and lock composer while submitting on macOS"

### Task 3: iPad 破棄確認 + スワイプ破棄防止（View）

**Files:**
- Modify: `apps/ipados/Views/ComposerView.swift:23-25`（キャンセル）、`NavigationStack` 直下
- Modify: `docs/wiki/behaviors/compose-post.md`、`docs/wiki/platforms/ipados.md`

**Interfaces:**
- Consumes: Task 1 の `hasUnsavedContent`、既存 `isSubmitting` / `@Environment(\.dismiss)`
- Produces: なし

- [ ] **Step 1: Task 2 と同じ分岐を iPad に適用**

`onClose()` の代わりに `dismiss()`。キャンセルボタンに `.disabled(model.isSubmitting)`。`NavigationStack` に `.confirmationDialog(...)`（Task 2 と同一文言）と `.interactiveDismissDisabled(model.hasUnsavedContent || model.isSubmitting)` を付与（スワイプダウン即破棄の防止 — iPad の本丸）。

- [ ] **Step 2: ビルド確認**

Run: `xcodebuild build -scheme YoruMimizukuPad ...`（前掲 destination）
Expected: BUILD SUCCEEDED

- [ ] **Step 3: 手動検証**

1. 内容ありでスワイプダウンが無効化される
2. 確認ダイアログ経由でのみ破棄できる
3. 送信中はキャンセル disabled・スワイプ dismiss 不可、完了後に閉じる

- [ ] **Step 4: wiki 更新とコミット**

`compose-post.md` の features に「Draft discard confirmation」を macos/ios: full で追加し、note に `hasUnsavedContent` の定義（reply/quote ターゲットは対象外）と「送信中はキャンセル不可（in-flight キャンセルは未実装・既知の制約）」を記載 → `mise run wiki:matrix` → `wiki:check`。1コミット（振る舞い・wiki 含む）を `/commit` スキルで作成。メッセージ例: "Confirm draft discard and block swipe dismiss on iPad composer"

---

# S2: iPad タップターゲット是正（feature/hig-ipados-tap-targets）

P1-a（onTapGesture→Button/アクセシビリティ経路）と P1-b（44pt 化）は同一ファイル群のため1ブランチ。ヒット領域拡張は **`frame(minWidth: 44, minHeight: 44)` を Button に与え、glyph（アイコン/アバター）の見た目サイズは内側 frame で維持**する方式。contentShape の負 inset には layout bounds 外のヒット判定が保証されない懸念があるため採用しない。レイアウトへの影響（行高・列幅の変化）はスナップショット差分と実機で確認する。

### Task 1: `DesignMetrics.minimumTouchTarget`（Kit・TDD）

**Files:**
- Modify: `core/Sources/YoruMimizukuKit/DesignMetrics.swift`
- Test: `core/Tests/YoruMimizukuKitTests/DesignMetricsTests.swift`

**Interfaces:**
- Consumes: なし
- Produces: `public static let minimumTouchTarget: Double`（Task 2/3 の View が参照）

- [ ] **Step 1: 失敗テストを書く**

```swift
func testMinimumTouchTargetIs44() {
    XCTAssertEqual(DesignMetrics.minimumTouchTarget, 44)
}
```

- [ ] **Step 2: Red を確認**

Run: `swift test --package-path core --filter DesignMetricsTests/testMinimumTouchTargetIs44`
Expected: FAIL（コンパイルエラー: `minimumTouchTarget` 未定義）

- [ ] **Step 3: 最小実装**

```swift
/// Minimum tappable area on touch platforms (Apple HIG: 44×44pt). macOS
/// pointer targets are exempt; iPadOS controls reach this by giving the
/// Button a 44pt minimum frame while keeping the glyph at its visual size.
public static let minimumTouchTarget: Double = 44
```

- [ ] **Step 4: Green と全体回帰**

Run: `swift test --package-path core`
Expected: 全件 PASS

- [ ] **Step 5: コミット**

1コミット（純追加）を `/commit` スキルで作成。メッセージ例: "Add minimumTouchTarget to DesignMetrics"

### Task 2: onTapGesture → Button / アクセシビリティ経路（構造・ヒット領域は従来のまま）

**Files:**
- Modify: `apps/ipados/Views/PostRowView.swift:105`（行全体）、`:196`（アバター）、`:362`（センシティブカーテン）、`:600`（`ThumbnailChrome`）

**Interfaces:**
- Consumes: 既存コールバック `onOpenThread` / `onOpenAuthor` / `onOpenPermalink`、`revealMedia`
- Produces: なし

- [ ] **Step 1: 変更を適用**

1. **行全体タップ（105行）**: List 行内で行を Button 化すると内包アクションバー Button と入れ子になるため、onTapGesture を維持しつつ `.accessibilityAddTraits(.isButton)` + `.accessibilityAction(named: "スレッドを開く") { onOpenThread?(post) }` を追加する最小対応（未確定事項4）。
2. **アバター（196行）**:

```swift
Button {
    onOpenAuthor?(post.authorDID, post.authorHandle, post.authorDisplayName, post.authorAvatarURL)
    // 引数は既存 onTapGesture 内の呼び出しをそのまま移す
} label: {
    avatarImage  // 既存の RemoteImage 構成。frame(width: avatarSize, height: avatarSize) は維持
}
.buttonStyle(.plain)
.accessibilityLabel("@\(post.authorHandle) のプロフィール")
```

3. **センシティブカーテン（362行）**: `Color.clear.contentShape(...).onTapGesture` → `Button { revealMedia = true } label: { Color.clear.contentShape(Rectangle()) }.buttonStyle(.plain)` + `.accessibilityLabel("閲覧注意メディアを表示")`
4. **`ThumbnailChrome`（600行）**: `.onTapGesture(perform: onTap)` を廃し content を `Button(action: onTap)` でラップ（`.buttonStyle(.plain)` + `.accessibilityAddTraits(.isButton)`、alt 由来のラベルは既存のまま）

- [ ] **Step 2: スナップショットで描画不変を確認**

Run: `xcodebuild test -scheme YoruMimizukuPad ...`（前掲 destination）
Expected: 全件 PASS（Button 化のみでは描画不変のはず。差分が出た variant は差分 PNG を目視レビューし、無害なら再録）

- [ ] **Step 3: コミット**

1コミット（構造）を `/commit` スキルで作成。メッセージ例: "Convert iPad tap gestures to buttons with accessibility actions"

### Task 3: 44pt 操作領域の確保（振る舞い）

**Files:**
- Modify: `apps/ipados/Views/RootView.swift:797-809`（サイドバー xmark、22pt）、`:789`（予約スペーサ）
- Modify: `apps/ipados/Views/NotificationsListView.swift:117-127`（通知展開 chevron、22pt）
- Modify: `apps/ipados/Views/PostRowView.swift`（compact アバター 24pt）
- Modify: `docs/wiki/platforms/ipados.md`、`docs/wiki/design-system.md`（minimumTouchTarget の適用先）

**Interfaces:**
- Consumes: `DesignMetrics.minimumTouchTarget`（Task 1）、Task 2 の Button 化
- Produces: なし

- [ ] **Step 1: 44pt frame の適用**

各 Button の label 側 glyph サイズ（22pt アイコン、24pt アバター）は維持したまま、Button 自体に最小 frame を与える:

```swift
// サイドバー xmark（RootView.swift:803。glyph の frame(width: 22, height: 22) は label 内に残す）
.frame(minWidth: CGFloat(DesignMetrics.minimumTouchTarget),
       minHeight: CGFloat(DesignMetrics.minimumTouchTarget))
.contentShape(Rectangle())
```

同様に通知展開 chevron、compact アバターの Button に適用。789行の予約スペーサ（22pt）は xmark ボタンの実サイズと揃うよう同じ minWidth に更新し、行内の整列を保つ。

- [ ] **Step 2: レイアウト影響の確認**

Run: `xcodebuild test -scheme YoruMimizukuPad ...`（前掲 destination）
Expected: PostRow 系 variant（compact アバター）に差分が出る想定。差分 PNG を目視レビューし、意図どおり（アバター列幅/行余白の増加のみ、崩れなし）なら再録。サイドバー・通知はカタログ非対象のため実機/シミュレータのスクリーンショットで前後比較する。行高が過大に伸びる等の許容できない崩れが出た場合は、当該コントロールを未確定事項8として持ち帰り、黙って negative inset 等の回避策に切り替えない。

- [ ] **Step 3: 実機検証**

Accessibility Inspector の Hit Target 表示で xmark / chevron / compact アバターが 44pt に達していることを確認。

- [ ] **Step 4: wiki 更新とコミット**

wiki 2ページ更新 + `mise run wiki:check`。1コミット（振る舞い）を `/commit` スキルで作成。メッセージ例: "Expand small iPad controls to 44pt touch targets"

---

# S3: macOS ポインタ操作の Button 化（feature/hig-macos-pointer-buttons）

### Task 1: アバター onTapGesture の Button 化

**Files:**
- Modify: `apps/macos/Views/PostRowView.swift:230`（アバター）
- Modify: `apps/macos/Views/NotificationsView.swift:254`（`avatarCircle`）
- Modify: `docs/wiki/platforms/macos.md`（1行追記）

**Interfaces:**
- Consumes: 既存 `onAvatarTap` 等のコールバック
- Produces: なし

- [ ] **Step 1: 変更を適用**

両箇所とも `.onTapGesture { ... }` を `Button { ... } label: { /* 既存のアバター描画 */ }.buttonStyle(.plain)` に置き換え、`.accessibilityLabel("@\(handle) のプロフィール")` を付与。macOS はポインタ環境のため 44pt 拡張は行わない。

- [ ] **Step 2: スナップショットで描画不変を確認**

Run: `xcodebuild test -scheme YoruMimizuku -project YoruMimizuku.xcodeproj -destination 'platform=macOS'`
Expected: 全件 PASS（描画不変）

- [ ] **Step 3: wiki 更新とコミット**

1コミット（構造のみ・挙動不変）を `/commit` スキルで作成。メッセージ例: "Convert macOS avatar tap gestures to buttons"

---

# S4: macOS 新規ウィンドウ経路とウィンドウタイトル復元（feature/hig-macos-windows）

### Task 1: タイトル導出（Kit・TDD）

**Files:**
- Modify: `core/Sources/YoruMimizukuKit/WorkspaceModel.swift`（`selectionTitle` 追加）
- Create: `core/Sources/YoruMimizukuKit/WindowTitle.swift`（SPM 配下のため xcodegen 不要）
- Test: `core/Tests/YoruMimizukuKitTests/WorkspaceModelTests.swift`（既存に追加）、Create: `core/Tests/YoruMimizukuKitTests/WindowTitleTests.swift`

**Interfaces:**
- Consumes: 既存 `WorkspaceModel.selection: WorkspaceTab`、`filter(id:) -> FilterTab?`、`conversation(id:) -> ConversationTab?`、`author(id:) -> AuthorTab?`（`AuthorTab` は `displayName`/`handle` を持ち `title` は無い）
- Produces: `WorkspaceModel.selectionTitle: String`、`WindowTitle.compose(tabTitle:accountHandle:) -> String`（Task 2 が参照）

- [ ] **Step 1: WindowTitle の最初の失敗テストを書く**

```swift
func testComposeJoinsTabAndHandle() {
    XCTAssertEqual(WindowTitle.compose(tabTitle: "ホーム", accountHandle: "asonas.bsky.social"),
                   "ホーム — @asonas.bsky.social")
}
```

- [ ] **Step 2: Red を確認**

Run: `swift test --package-path core --filter WindowTitleTests`
Expected: FAIL（型未定義のコンパイルエラー）

- [ ] **Step 3: 最小実装**

```swift
/// Composes the macOS window title shown in Mission Control / the Window menu /
/// the Dock, even under `.hiddenTitleBar`.
public enum WindowTitle {
    /// "ホーム — @asonas.bsky.social"; the handle part is dropped when empty.
    public static func compose(tabTitle: String, accountHandle: String) -> String {
        let trimmed = accountHandle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return tabTitle }
        let handle = trimmed.hasPrefix("@") ? trimmed : "@\(trimmed)"
        return "\(tabTitle) — \(handle)"
    }
}
```

- [ ] **Step 4: 残りの WindowTitle テストを1件ずつ Red→Green**

`testComposeOmitsEmptyHandle`（handle が "" → "ホーム" のみ）、`testComposeDoesNotDoubleAtPrefix`（"@a.bsky.social" → "@" が二重にならない）。※上記 Step 3 を最小実装（連結のみ）に留めて Step 1 だけ通し、空 handle・@ 重複の分岐はそれぞれのテストの Red を見てから足す。

- [ ] **Step 5: selectionTitle のテストを1件ずつ Red→Green**

`WorkspaceModelTests` に追加: `testSelectionTitleForHome` / `...ForNotifications` / `...ForFilterTab` / `...ForConversationTab` / `...ForAuthorTabUsesDisplayNameThenHandle` / `...FallsBackToHomeWhenTabClosed`。実装:

```swift
/// The selected tab's human-readable title, e.g. for the macOS window title.
/// Pinned tabs use their fixed labels; a closed tab id falls back to ホーム.
public var selectionTitle: String {
    switch selection {
    case .home: return "ホーム"
    case .notifications: return "通知"
    case let .filter(id): return filter(id: id)?.title ?? "ホーム"
    case let .conversation(id): return conversation(id: id)?.title ?? "ホーム"
    case let .author(id):
        guard let tab = author(id: id) else { return "ホーム" }
        return tab.displayName.isEmpty ? tab.handle : tab.displayName
    }
}
```

- [ ] **Step 6: 全体回帰**

Run: `swift test --package-path core`
Expected: 全件 PASS

- [ ] **Step 7: コミット**

Kit のみ1コミット（振る舞い）を `/commit` スキルで作成。メッセージ例: "Add window title derivation to WorkspaceModel"

### Task 2: 新規ウィンドウコマンドとタイトル配線（macOS View）

**Files:**
- Modify: `apps/macos/YoruMimizukuApp.swift:14-19`（`WindowGroup(id: "main")` に id 付与）
- Modify: `apps/macos/Views/NewPostCommand.swift:3-18`（コメント修正 + 新規ウィンドウボタン）
- Modify: `apps/macos/Views/MainWindowView.swift`（`.navigationTitle` 配線）
- Modify: `docs/wiki/behaviors/app-shell.md`（⌘N/⇧⌘N、Multiple windows 欄）、`docs/wiki/platforms/macos.md`

**Interfaces:**
- Consumes: Task 1 の `selectionTitle` / `WindowTitle.compose`、既存 `MainWindowView.accountHandle`
- Produces: なし

- [ ] **Step 1: コマンド追加とコメント修正**

`NewPostCommands` の冒頭コメントを「仕様は複数ウィンドウ対応（per-window アカウント並読、design.md §8）。⌘N はクライアント慣習で新規投稿、複数ウィンドウは ⇧⌘N（Windows 版 Ctrl+Shift+N と一致）」に修正し、`CommandGroup(replacing: .newItem)` 内に追加:

```swift
struct NewPostCommands: Commands {
    @FocusedValue(\.newPost) private var newPost
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新規投稿") { newPost?.run() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(newPost == nil)
            Button("新規ウィンドウ") { openWindow(id: "main") }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
    }
}
```

- [ ] **Step 2: タイトル配線**

`MainWindowView` の本体ビューに:

```swift
.navigationTitle(WindowTitle.compose(tabTitle: workspace.selectionTitle,
                                     accountHandle: accountHandle))
```

（`.hiddenTitleBar` でも Mission Control / Dock / ウィンドウメニューに反映される。）

- [ ] **Step 3: ビルド + スナップショット確認**

Run: `xcodebuild test -scheme YoruMimizuku ... -destination 'platform=macOS'`
Expected: 全件 PASS（カタログにウィンドウ chrome は含まれず描画不変）

- [ ] **Step 4: 手動検証**

1. ⇧⌘N で新ウィンドウが開く
2. ウィンドウメニュー / Mission Control に「ホーム — @handle」等の意味あるタイトル
3. タブ切替でタイトルが追随する
4. 新ウィンドウでアカウント切替 → 別アカウント並読が成立（spec §8）

- [ ] **Step 5: wiki 更新とコミット**

既知の制約（会話タブ等の永続化ストアがウィンドウ間で単一共有なら last-writer-wins。設定ストアのライブ同期問題は S7 で扱う）を wiki に記録 → `mise run wiki:matrix` → `wiki:check`。1コミット（振る舞い）を `/commit` スキルで作成。メッセージ例: "Restore new window command and meaningful window titles"

---

# S5: 通知 empty と動画失敗回復（feature/hig-notifications-video-recovery、iPad のみ）

### Task 1: 通知 empty 状態（スナップショット先行）

**Files:**
- Modify: `apps/ipados/Views/NotificationsListView.swift:25-31`（loaded ケース）
- Create: `apps/ipadosTests/NotificationsEmptySnapshotTests.swift`（apps/ 配下のため `xcodegen generate` 必要）
- Modify: `docs/wiki/behaviors/notifications.md`

**Interfaces:**
- Consumes: 既存 `NotificationsViewModel(loader:)` / `NotificationsLoading`、既存 SnapshotTesting 基盤（`apps/ipadosTests/CatalogSnapshotTests.swift` の record/perceptual precision 設定を踏襲）
- Produces: なし

**テスト戦略:** 初版案の「state + レンダー成立確認」は現実装でも Red にならないため廃止。空白画面の参照 PNG に対する**画素差分**として Red を観測する。手順が想定どおり動かない場合（`ContentUnavailableView` / `.refreshable` の非同期レイアウトで描画が非決定的になる等）は、自動テストを捏造せず削除し「手動検証のみ」と明記してコミットする。

- [ ] **Step 1: スナップショットテストを書く**

```swift
import SnapshotTesting
import XCTest
import YoruMimizukuKit
@testable import YoruMimizukuPad

@MainActor
final class NotificationsEmptySnapshotTests: XCTestCase {
    private struct EmptyLoader: NotificationsLoading {
        func loadLatest() async throws -> [NotificationGroup] { [] }
    }

    func testEmptyNotificationsShowsPlaceholder() async throws {
        let model = NotificationsViewModel(loader: EmptyLoader())
        await model.load()
        let view = NotificationsListView(model: model /* 既存 init に合わせる */)
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 560, height: 700)
        assertSnapshot(of: host, as: .image)
    }
}
```

（環境固定・precision は `CatalogSnapshotTests` と同じ設定を流用。）

- [ ] **Step 2: 現状の空白画面を記録し欠陥を確認（Red の準備）**

Run: `xcodegen generate` → iPad の xcodebuild test（初回は参照なしで FAIL → record して再実行）
Expected: 参照 PNG に**空白の List** が写っていることを目視確認（= 欠陥のエビデンス）。この空白 PNG はコミットしない。

- [ ] **Step 3: empty 分岐を実装**

```swift
case let .loaded(items):
    if items.isEmpty {
        ScrollView {
            ContentUnavailableView("通知はまだありません", systemImage: "bell.slash")
                .padding(.top, 80)
        }
        .refreshable { await model.refresh() }
    } else {
        // 既存 List
    }
```

（文言は macOS `NotificationsView.swift:76` と統一。）

- [ ] **Step 4: Red を観測**

Run: iPad の xcodebuild test
Expected: `testEmptyNotificationsShowsPlaceholder` が **FAIL**（空白参照 PNG との画素差分 — ContentUnavailableView が現れたため）。この失敗が「実装で描画が変わった」ことの証跡。

- [ ] **Step 5: 参照を更新し Green を確認**

record で参照 PNG を再録 → 「通知はまだありません」+ bell.slash が写っていることを**目視レビュー** → 再実行で PASS。以後は回帰ガードとして機能する。

- [ ] **Step 6: コミット**

テスト + 最終参照 PNG + 実装を1コミット（振る舞い）で `/commit` スキルにより作成。メッセージ例: "Show placeholder for empty notifications on iPad"

### Task 2: 動画再生失敗のフォールバック

**Files:**
- Modify: `apps/ipados/Views/PostRowView.swift:633-661`（`VideoPlayerScreen`）と呼び出し側 `:107-109`
- Modify: `docs/wiki/platforms/ipados.md`（動画再生失敗経路）

**Interfaces:**
- Consumes: 既存 `onOpenPermalink` コールバック、AVKit の `AVPlayerItem.status`
- Produces: なし

- [ ] **Step 1: 失敗監視とフォールバック UI**

```swift
private struct VideoPlayerScreen: View {
    let url: URL
    /// Opens the post in the browser when in-app playback fails.
    var onOpenExternally: (() -> Void)?
    @State private var failed = false
    // AVPlayerItem を保持し .onReceive(item.publisher(for: \.status)) で監視、
    // status == .failed で failed = true。
    // failed 時はプレイヤーの上にオーバーレイ:
    //   Text("動画を再生できませんでした")
    //   Button("ブラウザで開く") { dismiss(); onOpenExternally?() }
    //   既存の閉じるボタンは維持
}
```

呼び出し側（107-109行）で `onOpenExternally: { onOpenPermalink?(post) }` を渡す。

- [ ] **Step 2: ビルド確認**

Run: `xcodebuild build -scheme YoruMimizukuPad ...`
Expected: BUILD SUCCEEDED

**自動テストを書かない理由（明記）:** AVPlayer の失敗を XCTest で決定的に再現する手段が不安定（ネットワーク遮断・不正 URL とも実行環境依存）。実機チェックリストへ「機内モードで HLS 再生 → エラー表示と『ブラウザで開く』の動作」を追加して担保する。

- [ ] **Step 3: wiki 更新とコミット**

1コミット（振る舞い）を `/commit` スキルで作成。メッセージ例: "Fall back to browser when iPad video playback fails"

---

# S6: 「ブラウザで開く」contextMenu 統一（feature/hig-open-in-browser-menu、両OS・極小）

### Task 1: rowContextMenu への追加

**Files:**
- Modify: `apps/ipados/Views/PostRowView.swift:119-134`（rowContextMenu）
- Modify: `apps/macos/Views/PostRowView.swift:147-164`（rowContextMenu）
- Modify: `docs/wiki/behaviors/app-shell.md`（行操作の経路一覧）

**Interfaces:**
- Consumes: iPad 既存 `onOpenPermalink`、macOS 既存 private `openInBrowser()`（79-82行）と `onSelect()`
- Produces: なし

- [ ] **Step 1: 変更を適用**

iPad —「リンクをコピー」の直後に:

```swift
Button { onOpenPermalink?(post) } label: { Label("ブラウザで開く", systemImage: "safari") }
```

macOS — 同じ Label で:

```swift
Button { onSelect(); openInBrowser() } label: { Label("ブラウザで開く", systemImage: "safari") }
```

削除経路は既存の confirmationDialog（macOS `FeedView.swift:77` / iPad `TimelineListView.swift:48`）のまま変更なし。macOS アクションバーへの Safari ボタン追加は行わない（未確定事項5）。

- [ ] **Step 2: 両スイートの Green 維持を確認**

Run: macOS / iPad の xcodebuild test（前掲）
Expected: 全件 PASS（contextMenu はスナップショット非対象・分岐ロジックなし）

- [ ] **Step 3: wiki 更新とコミット**

1コミット（振る舞い・純追加）を `/commit` スキルで作成。メッセージ例: "Add open-in-browser to post context menus"

---

# S7: macOS Settings scene 検討（P2、feature/hig-macos-settings-scene、S4 後）

判断材料（確定事実）:
- 4つの設定ストアは全て `UserDefaults.standard` 永続化 = 設定値はグローバル。per-window なのはインスタンスだけ
- spec の per-window 要素は「アカウント」のみ（design.md §8）。設定が per-window である仕様根拠はない
- S4 で複数ウィンドウが復活すると「ウィンドウ1でテーマ変更 → ウィンドウ2は再起動まで旧テーマ」という不整合が顕在化する
- `NewPostCommand.swift:38-41` の「settings live in a per-window sheet」コメントは単一ウィンドウ前提の歴史的経緯

推奨案: ストア4つ（ThemeStore/DisplaySettingsStore/FontSettingsStore/NotificationSettingsStore）を `YoruMimizukuApp` の `@StateObject` へリフトし、`WindowGroup` と新設 `Settings { SettingsView() }` scene の両方に `.environmentObject` 注入。`SettingsCommands`（`CommandGroup(replacing: .appSettings)`）を削除して標準 ⌘, へ戻し、サイドバー歯車と旧シート経路は `openSettings` 環境アクションに差し替え。

現状維持案を採る場合も、ストアの app-level リフトだけは必要（ライブ同期バグ回避）。コミット境界:

- [ ] **Step 1（構造）**: ストアのリフト（挙動不変）。Run: macOS xcodebuild test → Expected: 全件 PASS。1コミットを `/commit` スキルで作成
- [ ] **Step 2（振る舞い）**: Settings scene 化（採否は未確定事項2の決定に従う）。手動検証: ⌘, で設定ウィンドウ、複数ウィンドウ間でテーマ変更がライブ反映。1コミット
- [ ] **Step 3**: wiki 更新（`docs/wiki/platforms/macos.md`、`app-shell.md` の ⌘, 記述）+ `mise run wiki:check`

---

# S8: P2 棚卸しと実機検証チェックリスト（feature/hig-a11y-inventory）

- [ ] **Step 1: 棚卸しコマンドを実行し対象一覧を作る**

```bash
grep -rn 'Text("[A-Za-z]' apps/macos apps/ipados         # 未翻訳（例: ipados RootView.swift:609 "Author not found"）
grep -rn 'Color\.blue\|Color\.white\|Color\.pink\|foregroundStyle(\.white)\|Color(red:' apps/ipados apps/macos
  # 固定色（例: ipados RootView.swift:784-785 バッジ、NotificationsListView.swift:191-195 iconColor。macOS は theme.star/theme.accent が正）
grep -rn 'Image(systemName:' apps | grep -v accessibilityLabel   # アイコンのみボタンの候補
```

- [ ] **Step 2: 修正を3コミットに分けて適用**（すべて振る舞い、各コミット後に該当 OS の xcodebuild test）

1. 未翻訳 → 日本語化
2. 固定色 → ThemeStore のセマンティック色へ（macOS 実装が手本）。スナップショット差分が出た variant のみ目視レビューして再録
3. アクションバーのカウントラベル等に `accessibilityLabel("返信 \(count)件")` を付与

- [ ] **Step 3: 実機検証チェックリストを消化し、結果を wiki の手動検証節へ転記**（下記リスト参照）+ `mise run wiki:check` + 1コミット

---

## 未確定事項（実装前にユーザー判断が必要なもの）

1. **新規ウィンドウのショートカット**: 推奨は ⇧⌘N（Windows 版 Ctrl+Shift+N と一致、⌘N=新規投稿を維持）。⌘N を新規ウィンドウに戻す案は wiki/既存ユーザー挙動と衝突するため非推奨。
2. **S7 の採否**: Settings scene へ移行（推奨）か、per-window シート維持 + ストアリフトのみか。
3. **P0-3 の columnVisibility**: regular で `.all` 固定を維持する前提だが、Stage Manager 検証で detail 到達不能が出た場合 `.automatic` へ変更するか。
4. **S2 の行全体タップ**: accessibilityAction による最小対応（推奨）か、行の完全 Button 化（アクションバーとの入れ子ボタン問題の解決が必要で工数増）か。
5. **macOS アクションバーへの Safari ボタン追加**（S6 の範囲外とした）: contextMenu 統一で十分か、iPad と同じ可視ボタンも足すか。
6. **通知 empty の文言**: 「通知はまだありません」（macOS と統一)で確定してよいか。
7. **VoiceOver トースト読み上げ**（P2）: 実機検証で問題があれば `UIAccessibility.post(notification: .announcement)` / `NSAccessibility.post` の別タスク起票でよいか。
8. **S2 の 44pt frame でレイアウト崩れが出た場合の扱い**: 当該コントロールのみ据え置いて持ち帰るか、行レイアウト自体の再設計に進むか（黙って negative inset 等に切り替えない）。
9. **送信中キャンセル機能**（今回スコープ外とした）: 「送信中は待たせる」で当面十分か、将来 in-flight キャンセル（協調キャンセル + LiveComposer/VideoUploadService の対応）を別スペックとして起こすか。

## 実機・シミュレータ検証項目（自動テスト対象外、S8 完了時に wiki の手動検証節へ転記）

- P0-1: 返信行の静的アクションバー表示と行タップ再アンカー（macOS）
- P0-2: VoiceOver アクションメニュー・Accessibility Inspector（macOS 実機）
- P0-3: 検証マトリクス全項目（Split View / Slide Over / Stage Manager / 2シーン / 回転 / composer sheet リサイズ）
- P0-4: 両OS の破棄確認・送信中の操作無効化・iPad スワイプダウン抑止
- S2: Accessibility Inspector の Hit Target 表示で 44pt 確認（xmark / chevron / compact アバター）、44pt frame によるレイアウト変化の前後比較
- S4: Mission Control / ウィンドウメニュー / Dock のタイトル表示、⇧⌘N、複数ウィンドウ並読
- S5: 機内モードで HLS 再生失敗 → エラー表示と「ブラウザで開く」
- P2: Reduce Motion 有効時のアニメーション、最大 Dynamic Type（AX5）での折返し、VoiceOver でのトースト読み上げ、iPad フローティング/ハードウェアキーボードと Composer の干渉

## 自己レビュー結果（改訂版）

- **仕様カバレッジ**: P0 の4件（返信行縮退・Sidebar 代替経路・UIRequiresFullScreen/マルチシーン + 狭幅適応・Composer 下書き保護）、P1 の5件（Button 化・44pt・新規ウィンドウ/タイトル・状態回復・操作経路整理）、P2 の3群（Settings scene・棚卸し・実機検証）をすべてタスク化。NewPostCommand コメントの仕様矛盾は S4 で spec 優先に解消。「現状維持」指定項目と、意図的に外した送信キャンセルはスコープ外節に明記。
- **Red にならないテストの排除**: 旧 S5.1 の state+レンダーテスト（現実装でも通る）を削除し、空白参照 PNG との画素差分で Red を観測する手順に置換（不成立時は手動のみと明記）。P0-4 Task 1 Step 5 の派生テスト群は境界仕様（空白のみ text / quote・reply ターゲット除外）を固定するもので、実装後に追加しても仕様回帰ガードとして意味を持つことを本文に明記。
- **不要な公開 API の排除**: `canInteract(with:)`（利用者が返信行の false 定数評価のみ）と `touchTargetInset`（negative inset 方式の廃止で不要）を削除。残る公開 API 追加は `hasUnsavedContent`（P0-4 Task 2/3 が参照）、`minimumTouchTarget`（S2 Task 3 が参照）、`selectionTitle` / `WindowTitle.compose`（S4 Task 2 が参照）の4つで、いずれも参照元タスクが同計画内に存在する。
- **プレースホルダー**: 全ステップに具体コード・実行コマンド・期待結果を記載。「既存 init に合わせる」「フィクスチャヘルパを再利用」等は対象ファイルと既存パターンを明示した上での参照であり、TBD ではない。
- **型名整合性**: `hasUnsavedContent` / `minimumTouchTarget` / `selectionTitle` / `WindowTitle.compose` の名称は定義タスクと参照タスクで一致。`AuthorTab.title` 不在（`displayName`/`handle` 使用）、`NotificationsViewModel.State: Equatable`、`DesignMetrics` の `Double` 統一は実コード検証済み。
- **xcodegen**: 必要箇所は project.yml 変更（P0-3 Task 1）と apps/ 配下の新規テストファイル（S5 Task 1）のみ。core 配下の新規 SPM ファイル（`WindowTitle.swift`）では不要と修正済み。
