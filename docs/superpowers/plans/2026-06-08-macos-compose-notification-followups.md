# macOS Compose and Notification Follow-ups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS 版で、返信コンポーザの文脈表示、投稿中ボタン表示、投稿ショートカット、通知から対象投稿を開く導線を改善する。

**Architecture:** 返信表示に必要な親投稿情報は `ComposerViewModel` に `PostDisplay` として保持し、送信時は既存どおり URI だけを `PostDraft` に渡す。投稿中表示とショートカットは macOS SwiftUI の `ComposerView` に閉じ込める。通知から対象投稿を開く導線は、既存の `NotificationGroup.subjectURI` と `WorkspaceModel` の会話タブ機構をつなぐ。

**Tech Stack:** Swift 6.0 / SwiftUI / XCTest。ViewModel の振る舞いは `cd core && swift test`、macOS UI は `xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj CODE_SIGN_IDENTITY="-"` と手動確認で検証する。

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `core/Sources/YoruMimizukuKit/ComposerViewModel.swift` | Modify | 返信先 `PostDisplay` を保持し、既存の `replyParentURI` 互換を維持する。 |
| `core/Tests/YoruMimizukuKitTests/ComposerViewModelTests.swift` | Modify | 返信親投稿を保持しつつ、送信用 draft には URI が入ることを確認する。 |
| `apps/macos/Views/RootView.swift` | Modify | `makeComposer` の引数を `PostDisplay?` に変え、返信作成時に投稿全体を渡す。 |
| `apps/macos/Views/MainWindowView.swift` | Modify | 返信コンポーザ生成と通知行クリックから会話タブを開く処理を結線する。 |
| `apps/macos/Views/ComposerView.swift` | Modify | 返信先プレビュー、投稿ボタン内ローディング、Cmd/Ctrl-Enter 投稿を実装する。 |
| `apps/macos/Views/NotificationsView.swift` | Modify | いいね通知などの対象投稿スニペットをクリック可能にする。 |
| `core/Sources/YoruMimizukuKit/WorkspaceModel.swift` | Modify | URI と表示スニペットだけで会話タブを開ける軽量 API を追加する。 |
| `core/Tests/YoruMimizukuKitTests/WorkspaceModelTests.swift` | Modify | URI ベースの会話タブ作成と重複排除を確認する。 |

---

## Task 1: Reply composer shows the post being replied to

ユーザーが返信モーダルを開いたとき、全文ではなく、返信先のアイコン、ユーザー名、本文冒頭が見えるようにする。

**Files:**
- Modify: `core/Sources/YoruMimizukuKit/ComposerViewModel.swift`
- Modify: `core/Tests/YoruMimizukuKitTests/ComposerViewModelTests.swift`
- Modify: `apps/macos/Views/RootView.swift`
- Modify: `apps/macos/Views/MainWindowView.swift`
- Modify: `apps/macos/Views/ComposerView.swift`

- [ ] **Step 1: 失敗するテストを書く**

`ComposerViewModelTests` に、返信親投稿を保持しつつ送信用 draft には URI が入ることを確認するテストを追加する。

```swift
func testReplyParentPostIsStoredAndDraftUsesItsURI() async {
    let submitter = FakeSubmitter()
    let parent = PostDisplay(
        id: "at://did:plc:parent/app.bsky.feed.post/abc",
        authorDisplayName: "Alice",
        authorHandle: "alice.bsky.social",
        body: "This is the post being replied to",
        createdAt: Date(timeIntervalSince1970: 0)
    )
    let vm = ComposerViewModel(submitter: submitter, replyParent: parent)
    vm.text = "reply"

    XCTAssertEqual(vm.replyParent?.id, parent.id)

    await vm.submit()

    XCTAssertEqual(submitter.received?.replyParentURI, parent.id)
}
```

Run: `cd core && swift test --filter ComposerViewModelTests`

Expected: `replyParent` / `init(... replyParent:)` が未定義でコンパイルエラー。

- [ ] **Step 2: ViewModel を最小実装する**

`ComposerViewModel` に `public let replyParent: PostDisplay?` を追加し、`replyParentURI` は `replyParent?.id` から返す形に寄せる。既存呼び出しが残っている間も壊さないよう、初期化子は `replyParent: PostDisplay? = nil` を受ける。

```swift
public let replyParent: PostDisplay?
public var replyParentURI: String? { replyParent?.id }

public init(submitter: PostSubmitting, replyParent: PostDisplay? = nil, quotedPost: PostDisplay? = nil) {
    self.submitter = submitter
    self.replyParent = replyParent
    self.quotedPost = quotedPost
}
```

`submit()` の draft 作成は `replyParentURI` を使い続ける。

- [ ] **Step 3: macOS のコンポーザ生成を `PostDisplay?` に変更する**

`RootView` / `AuthenticatedRootView` / `MainWindowView` の `makeComposer` を `@MainActor (PostDisplay?) -> ComposerViewModel` に変更する。新規投稿は `makeComposer(nil)`、返信は `makeComposer(post)` を渡す。

- [ ] **Step 4: `ComposerView` に返信先プレビューを追加する**

`TextEditor` の前、または直後に `replyPreview(_:)` を置く。表示要素は avatar、表示名、handle、本文冒頭 2 行まで。引用プレビューより軽く、ヒットテストは無効にする。

```swift
if let parent = model.replyParent {
    replyPreview(parent)
}
```

プレビューは `PostRowView` 全体を再利用せず、小さな `HStack` と `RemoteImage` で作る。本文は `lineLimit(2)` とし、シートの幅は既存の `460` を維持する。

- [ ] **Step 5: 検証**

Run:
```bash
cd core && swift test --filter ComposerViewModelTests
xcodegen generate
xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj CODE_SIGN_IDENTITY="-"
```

Manual check: ホーム / フィルター / ユーザータブから返信を開き、返信先のアイコン、ユーザー名、本文冒頭が表示されることを確認する。新規投稿と引用投稿では返信先プレビューが出ないことも確認する。

---

## Task 2: Replace the Post button with a loading state while submitting

投稿ボタン押下後の `ProgressView` がモーダル最下部に追加され、シート高さが変わる問題を直す。投稿中はボタン領域そのものをローディング表示に差し替える。

**Files:**
- Modify: `apps/macos/Views/ComposerView.swift`

- [ ] **Step 1: `ComposerView` のフッターを分解する**

画像ボタン、残文字数、投稿ボタンを含む `HStack` を `composerFooter` に切り出す。切り出しだけなら動作は変えない。

- [ ] **Step 2: 投稿中表示をボタン内に移す**

既存のフッター直下の `if model.isSubmitting { ProgressView().controlSize(.small) }` を削除し、投稿ボタンの label を状態で切り替える。

```swift
Button { Task { await model.submit() } } label: {
    if model.isSubmitting {
        ProgressView().controlSize(.small)
            .frame(minWidth: 44)
    } else {
        Text("Post")
            .frame(minWidth: 44)
    }
}
.buttonStyle(.borderedProminent)
.disabled(!model.canSubmit)
```

`canSubmit` は `isSubmitting` 中に false になるため、二重送信は既存ロジックで防げる。ボタン幅を固定し、シート高さが変わらないようにする。

- [ ] **Step 3: 検証**

Run:
```bash
xcodegen generate
xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj CODE_SIGN_IDENTITY="-"
```

Manual check: 投稿ボタン押下中、シート下部に新しい行が増えず、Post ボタン位置に小さいローディングが出ることを確認する。

---

## Task 3: Submit with Cmd-Enter or Ctrl-Enter

macOS のコンポーザで `Command-Return` または `Control-Return` を押すと投稿する。本文入力中でも動くことを重視する。

**Files:**
- Modify: `apps/macos/Views/ComposerView.swift`

- [ ] **Step 1: 隠しボタンのショートカットを追加する**

`ComposerView.body` の末尾に、ゼロサイズの `submitShortcuts` を `.background` で配置する。

```swift
.background { submitShortcuts }
```

`submitShortcuts` は `Button` を 2 つ持ち、両方とも `submitIfPossible()` を呼ぶ。

```swift
private var submitShortcuts: some View {
    ZStack {
        Button("") { submitIfPossible() }
            .keyboardShortcut(.return, modifiers: [.command])
        Button("") { submitIfPossible() }
            .keyboardShortcut(.return, modifiers: [.control])
    }
    .opacity(0)
    .frame(width: 0, height: 0)
    .accessibilityHidden(true)
}

private func submitIfPossible() {
    guard model.canSubmit else { return }
    Task { await model.submit() }
}
```

既存の Post ボタンも `submitIfPossible()` を使うようにして、条件判定を 1 箇所に寄せる。

- [ ] **Step 2: 検証**

Run:
```bash
xcodegen generate
xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj CODE_SIGN_IDENTITY="-"
```

Manual check: `TextEditor` にフォーカスした状態で `Cmd-Enter` と `Ctrl-Enter` のどちらでも投稿できること、空本文では投稿されないこと、投稿中に連打しても二重投稿されないことを確認する。

---

## Task 4: Open the liked post from a like notification

通知タブで「いいね」通知に表示されている対象投稿を開けるようにする。対象は通知行全体ではなく、対象投稿スニペットをクリックしたときに会話タブを開くのが最小の導線。

**Files:**
- Modify: `core/Sources/YoruMimizukuKit/WorkspaceModel.swift`
- Modify: `core/Tests/YoruMimizukuKitTests/WorkspaceModelTests.swift`
- Modify: `apps/macos/Views/MainWindowView.swift`
- Modify: `apps/macos/Views/NotificationsView.swift`

- [ ] **Step 1: URI だけで会話タブを開く Workspace API のテストを書く**

`WorkspaceModelTests` に、`openConversation(anchorID:title:handle:subtitle:)` が同じ URI を重複作成せず再選択することを確認するテストを追加する。

Run: `cd core && swift test --filter WorkspaceModelTests`

Expected: API 未定義でコンパイルエラー。

- [ ] **Step 2: `WorkspaceModel` に軽量会話タブ API を追加する**

`ConversationTab` に表示情報を直接渡す initializer を追加する。

```swift
public init(anchorID: String, title: String, handle: String, subtitle: String, model: ThreadViewModel) {
    self.anchorID = anchorID
    self.title = title
    self.handle = handle
    self.subtitle = subtitle
    self.model = model
}
```

`WorkspaceModel` に次を追加する。

```swift
public func openConversation(anchorID: String, title: String, handle: String, subtitle: String) {
    if let existing = conversations.first(where: { $0.anchorID == anchorID }) {
        selection = .conversation(existing.id)
        return
    }
    let tab = ConversationTab(anchorID: anchorID, title: title, handle: handle, subtitle: subtitle, model: makeThreadModel(anchorID))
    conversations.append(tab)
    selection = .conversation(tab.id)
}
```

- [ ] **Step 3: 通知ビューに `onOpenSubject` を渡す**

`NotificationsView` に `var onOpenSubject: (NotificationGroup) -> Void = { _ in }` を追加し、`NotificationRowView` へ渡す。`NotificationRowView` の `subjectSnippet` を `Button` または `contentShape + onTapGesture` でクリック可能にする。対象 URI がある行だけ有効にする。

`MainWindowView` の通知タブでは、`group.subjectURI` があるときだけ `workspace.openConversation(anchorID:title:handle:subtitle:)` を呼ぶ。タイトルは先頭 actor の表示名、handle は `@handle`、subtitle は `subjectText` または `"画像"` を使う。

- [ ] **Step 4: いいね以外の対象付き通知も同じ導線にする**

最初の目的は「いいね」の対象投稿だが、`NotificationGroup.subjectURI` は repost / reply / mention / quote でも入りうる。対象 URI がある通知は同じ処理で開けるようにし、follow など URI がない通知はクリック不可にする。

- [ ] **Step 5: 検証**

Run:
```bash
cd core && swift test --filter WorkspaceModelTests
cd core && swift test
xcodegen generate
xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj CODE_SIGN_IDENTITY="-"
```

Manual check: 通知タブの「いいね」対象投稿スニペットをクリックすると、その投稿の会話タブが開くことを確認する。同じ通知を再度クリックしてもタブが重複しないこと、フォロー通知では対象投稿が開かないことも確認する。

---

## Requirement-to-task map

| Requirement | Task |
|-------------|------|
| 返信モーダルに、返信する投稿のアイコン、ユーザー名、本文冒頭を表示する | Task 1 |
| 投稿中のローディングをモーダル最下部ではなく投稿ボタン部分に出す | Task 2 |
| `Ctrl-Enter` / `Cmd-Enter` で投稿する | Task 3 |
| いいね通知の対象投稿を開けるようにする | Task 4 |

## Definition of Done

- `cd core && swift test` が PASS。
- `xcodegen generate` 後、`xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj CODE_SIGN_IDENTITY="-"` が成功。
- macOS アプリで 4 つの手動確認が完了。
- 変更後の振る舞いを `docs/wiki/behaviors/compose-post.md` と `docs/wiki/behaviors/notifications.md` に反映する。
