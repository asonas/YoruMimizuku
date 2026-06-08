# フェーズA: ポーリング基盤と新着バッジ Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 通知タブとフィルタータブ（および home）に「未読／新着件数」のバッジを表示する。タブが非アクティブでもバックグラウンドでポーリングを継続し、タブをアクティブにするとバッジが 0 に戻る。

**Architecture:** ポーリングのループを View(`.task`) から ViewModel が所有する `Task` に移す。各 ViewModel が新着件数 `unreadCount` を公開し、`MainWindowView` の常駐 `.task` が全バッジ対象モデルのポーリングを起動・選択タブの active 同期を行う。新着件数の算出はリスト先頭基準の純関数 `UnreadCounter` に切り出してテストする。サイドバー各行はバッジ数を受け取り、選択中タブは非表示。

**Tech Stack:** Swift 6.0 / SwiftUI / XCTest。コアは `core/Sources/YoruMimizukuKit`、View は `apps/macos/Views`。テストは `core/Tests/YoruMimizukuKitTests`。`cd core && swift test` で実行。

**設計根拠:** `docs/superpowers/specs/2026-06-08-yorumimizuku-timeline-ux-enhancements-design.md` のアーキテクチャ変更 A と機能 1+2。

---

## 設計メモ（実装者向け前提）

- **新着件数の基準**: 各リストは「新着が先頭に積まれる」（`TimelineViewModel.refresh()` は fresh を head にマージ）。よって「前回見た時点の先頭アイテム ID」がリスト内で何番目かが、その上に積まれた新着件数になる。`createdAt`/`indexedAt` には依存しない（ID 位置で判定）。
- **初回ロード基準**: 起動直後にロードした既存アイテムは「新着」ではない。`load()` 完了時、まだ基準が無ければ現在の先頭 ID を基準に据える（＝初回ロード分は既読扱い、unread=0）。
- **active タブ**: 選択中タブの ViewModel は `isActive = true`。active 中は新着が来ても基準を追従させ unread を 0 に保つ。さらにサイドラインでも選択中行はバッジ非表示にして二重に保証する。
- **ポーリングの所有権**: ループは ViewModel 内の `pollingTask`。`startPolling` は冪等（既に走っていれば何もしない）。View が消えてもループは生き続けるため、裏に回ったタブも新着を貯め続ける。起動は `MainWindowView` の常駐 `.task` から（通知やフィルターを一度も開いていなくてもバッジが出るようにするため、View 個別の `.task` では起動しない）。
- **テスト範囲**: 時間依存のポーリングループ自体はユニットテストしない。`load`/`refresh`/`markSeen`/`setActive` と `UnreadCounter` の組み合わせでバッジ算出を検証する。

---

## Task 1: UnreadCounter（新着件数の純関数）

**Files:**
- Create: `core/Sources/YoruMimizukuKit/UnreadCounter.swift`
- Test: `core/Tests/YoruMimizukuKitTests/UnreadCounterTests.swift`

- [ ] **Step 1: 失敗するテストを書く**

Create `core/Tests/YoruMimizukuKitTests/UnreadCounterTests.swift`:

```swift
import XCTest
@testable import YoruMimizukuKit

final class UnreadCounterTests: XCTestCase {
    func testNoMarkerMeansZero() {
        XCTAssertEqual(UnreadCounter.unread(ids: ["a", "b", "c"], since: nil), 0)
    }

    func testMarkerAtTopMeansZero() {
        XCTAssertEqual(UnreadCounter.unread(ids: ["a", "b", "c"], since: "a"), 0)
    }

    func testMarkerBelowTopCountsItemsAbove() {
        XCTAssertEqual(UnreadCounter.unread(ids: ["x", "y", "a", "b"], since: "a"), 2)
    }

    func testMarkerNotFoundMeansAllAreNew() {
        XCTAssertEqual(UnreadCounter.unread(ids: ["x", "y", "z"], since: "gone"), 3)
    }

    func testEmptyListIsZero() {
        XCTAssertEqual(UnreadCounter.unread(ids: [], since: "a"), 0)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `cd core && swift test --filter UnreadCounterTests`
Expected: コンパイルエラー（`UnreadCounter` が未定義）。

- [ ] **Step 3: 最小実装を書く**

Create `core/Sources/YoruMimizukuKit/UnreadCounter.swift`:

```swift
/// Computes how many items are newer than the last item the viewer saw.
///
/// `ids` are ordered newest-first (the list head is the freshest item). The
/// `marker` is the id of the item that was at the head the last time the tab was
/// seen. The number of ids above the marker is the unread count.
public enum UnreadCounter {
    /// - Returns: 0 when there is no marker yet or the marker is still at the head;
    ///   the index of the marker (how many fresher items sit above it); or the full
    ///   count when the marker has scrolled out of the loaded window.
    public static func unread(ids: [String], since marker: String?) -> Int {
        guard let marker else { return 0 }
        guard let index = ids.firstIndex(of: marker) else { return ids.count }
        return index
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `cd core && swift test --filter UnreadCounterTests`
Expected: PASS（5 tests）。

- [ ] **Step 5: コミット**

`/commit` スキルで以下をコミット（`git ai-commit`、英語・大文字始まり・Conventional Commits 不使用）。
- 対象: `core/Sources/YoruMimizukuKit/UnreadCounter.swift`, `core/Tests/YoruMimizukuKitTests/UnreadCounterTests.swift`
- メッセージ例: `Add UnreadCounter for sidebar badge counts`

---

## Task 2: TimelineViewModel に未読・active 状態を追加

**Files:**
- Modify: `core/Sources/YoruMimizukuKit/TimelineViewModel.swift`
- Test: `core/Tests/YoruMimizukuKitTests/TimelineViewModelTests.swift`

- [ ] **Step 1: 失敗するテストを書く**

`TimelineViewModelTests.swift` の末尾（最後の `}` の前）に追加:

```swift
    func testInitialUnreadCountIsZero() {
        let vm = TimelineViewModel(loader: StubLoader(result: .success([])))
        XCTAssertEqual(vm.unreadCount, 0)
    }

    func testFirstLoadTreatsExistingPostsAsSeen() async {
        let vm = TimelineViewModel(loader: StubLoader(result: .success([sample(id: "p1"), sample(id: "p2")])))
        await vm.load()
        XCTAssertEqual(vm.unreadCount, 0)
    }

    func testRefreshAddsToUnreadWhenInactive() async {
        let loader = StubLoader(pages: [
            .success(TimelinePage(posts: [sample(id: "p2"), sample(id: "p3")], cursor: "c1")),
            .success(TimelinePage(posts: [sample(id: "p0"), sample(id: "p1")], cursor: "c0"))
        ])
        let vm = TimelineViewModel(loader: loader)
        await vm.load()      // baseline: head is p2
        await vm.refresh()   // p0, p1 land above p2
        XCTAssertEqual(vm.unreadCount, 2)
    }

    func testMarkSeenResetsUnread() async {
        let loader = StubLoader(pages: [
            .success(TimelinePage(posts: [sample(id: "p2")], cursor: "c1")),
            .success(TimelinePage(posts: [sample(id: "p0"), sample(id: "p1")], cursor: "c0"))
        ])
        let vm = TimelineViewModel(loader: loader)
        await vm.load()
        await vm.refresh()
        XCTAssertEqual(vm.unreadCount, 2)
        vm.markSeen()
        XCTAssertEqual(vm.unreadCount, 0)
    }

    func testActiveTabStaysAtZeroOnRefresh() async {
        let loader = StubLoader(pages: [
            .success(TimelinePage(posts: [sample(id: "p2")], cursor: "c1")),
            .success(TimelinePage(posts: [sample(id: "p0"), sample(id: "p1"), sample(id: "p2")], cursor: "c0"))
        ])
        let vm = TimelineViewModel(loader: loader)
        await vm.load()
        vm.setActive(true)
        await vm.refresh()
        XCTAssertEqual(vm.unreadCount, 0)
    }
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `cd core && swift test --filter TimelineViewModelTests`
Expected: コンパイルエラー（`unreadCount` / `markSeen` / `setActive` が未定義）。

- [ ] **Step 3: 最小実装を書く**

`TimelineViewModel.swift` の `@Published public private(set) var isLoadingMore = false`（47 行目付近）の直後に追加:

```swift
    /// Count of posts newer than the last item the viewer saw on this tab. Drives
    /// the sidebar badge. Always 0 while the tab is active.
    @Published public private(set) var unreadCount = 0
```

`private var cursor: String?`（51 行目付近）の直後に追加:

```swift
    /// The head post id at the moment the tab was last seen; the unread boundary.
    private var lastSeenTopID: String?
    /// True while this tab is the selected one. Active tabs keep their unread at 0.
    private var isActive = false
```

`load()` の `state = .loaded(page.posts)` 行（118 行目付近）の直後に `onItemsChanged()` を追加:

```swift
            state = .loaded(page.posts)
            onItemsChanged()
```

`refresh()` の `state = .loaded(Self.merging(page.posts, appending: current))` 行（155 行目付近）の直後にも追加:

```swift
            state = .loaded(Self.merging(page.posts, appending: current))
            onItemsChanged()
```

そして `merging(_:appending:)` 静的メソッド（164 行目付近）の直前に、未読管理のメソッド群を追加:

```swift
    /// Mark every loaded post as seen: the head becomes the unread boundary and the
    /// count drops to zero. Called when the tab is shown.
    public func markSeen() {
        lastSeenTopID = posts.first?.id
        unreadCount = 0
    }

    /// Set whether this tab is the selected one. Activating marks it seen so the
    /// active tab never shows a badge for posts the viewer is looking at.
    public func setActive(_ active: Bool) {
        isActive = active
        if active { markSeen() }
    }

    /// Recompute the unread count after the post list changed. On the very first
    /// load (no boundary yet) the existing posts are treated as seen.
    private func onItemsChanged() {
        if lastSeenTopID == nil { lastSeenTopID = posts.first?.id }
        if isActive {
            markSeen()
        } else {
            unreadCount = UnreadCounter.unread(ids: posts.map(\.id), since: lastSeenTopID)
        }
    }
```

- [ ] **Step 4: テストが通ることを確認**

Run: `cd core && swift test --filter TimelineViewModelTests`
Expected: PASS（既存テスト＋新規 5 件）。

- [ ] **Step 5: コミット**

`/commit` スキルでコミット。
- 対象: `core/Sources/YoruMimizukuKit/TimelineViewModel.swift`, `core/Tests/YoruMimizukuKitTests/TimelineViewModelTests.swift`
- メッセージ例: `Track unread count and active state in TimelineViewModel`

---

## Task 3: NotificationsViewModel に未読・active 状態を追加

**Files:**
- Modify: `core/Sources/YoruMimizukuKit/NotificationsViewModel.swift`
- Test: `core/Tests/YoruMimizukuKitTests/NotificationsViewModelTests.swift`

- [ ] **Step 1: 失敗するテストを書く**

`NotificationsViewModelTests.swift` の末尾（最後の `}` の前）に追加。`sample(id:)` は既存ヘルパを使う。可変 `StubLoader.result` を差し替えて新着を表現する:

```swift
    func testInitialUnreadCountIsZero() {
        let vm = NotificationsViewModel(loader: StubLoader(result: .success([])))
        XCTAssertEqual(vm.unreadCount, 0)
    }

    func testFirstLoadTreatsExistingNotificationsAsSeen() async {
        let vm = NotificationsViewModel(loader: StubLoader(result: .success([sample(id: "n1"), sample(id: "n2")])))
        await vm.load()
        XCTAssertEqual(vm.unreadCount, 0)
    }

    func testRefreshAddsToUnreadWhenInactive() async {
        let loader = StubLoader(result: .success([sample(id: "n2")]))
        let vm = NotificationsViewModel(loader: loader)
        await vm.load()                                   // baseline: head is n2
        loader.result = .success([sample(id: "n0"), sample(id: "n1"), sample(id: "n2")])
        await vm.refresh()
        XCTAssertEqual(vm.unreadCount, 2)
    }

    func testMarkSeenResetsUnread() async {
        let loader = StubLoader(result: .success([sample(id: "n2")]))
        let vm = NotificationsViewModel(loader: loader)
        await vm.load()
        loader.result = .success([sample(id: "n0"), sample(id: "n2")])
        await vm.refresh()
        XCTAssertEqual(vm.unreadCount, 1)
        vm.markSeen()
        XCTAssertEqual(vm.unreadCount, 0)
    }

    func testActiveTabStaysAtZeroOnRefresh() async {
        let loader = StubLoader(result: .success([sample(id: "n2")]))
        let vm = NotificationsViewModel(loader: loader)
        await vm.load()
        vm.setActive(true)
        loader.result = .success([sample(id: "n0"), sample(id: "n2")])
        await vm.refresh()
        XCTAssertEqual(vm.unreadCount, 0)
    }
```

注: 既存の `StubLoader` は `var result` を持つので差し替え可能。`refresh()` は `loaded` 状態でのみ新着取得する点に注意（`load()` 後に呼ぶ）。

- [ ] **Step 2: テストが失敗することを確認**

Run: `cd core && swift test --filter NotificationsViewModelTests`
Expected: コンパイルエラー（`unreadCount` / `markSeen` / `setActive` が未定義）。

- [ ] **Step 3: 最小実装を書く**

`NotificationsViewModel.swift` の `@Published public private(set) var state: State = .idle`（28 行目付近）の直後に追加:

```swift

    /// Count of notification groups newer than the last the viewer saw. Drives the
    /// sidebar badge. Always 0 while the tab is active.
    @Published public private(set) var unreadCount = 0

    private var lastSeenTopID: String?
    private var isActive = false
```

`load()` の `state = .loaded(items)` 行（47 行目付近）の直後に追加:

```swift
            state = .loaded(items)
            onItemsChanged()
```

`refresh()` の `state = .loaded(try await loader.loadLatest())` 行（63 行目付近）を次に置き換える:

```swift
            state = .loaded(try await loader.loadLatest())
            onItemsChanged()
```

そしてクラス末尾の最後の `}` の直前に追加:

```swift
    /// Mark every loaded notification as seen and reset the badge to zero.
    public func markSeen() {
        lastSeenTopID = items.first?.id
        unreadCount = 0
    }

    /// Set whether this tab is the selected one; activating marks it seen.
    public func setActive(_ active: Bool) {
        isActive = active
        if active { markSeen() }
    }

    /// Recompute the unread count; the first load's notifications are treated as seen.
    private func onItemsChanged() {
        if lastSeenTopID == nil { lastSeenTopID = items.first?.id }
        if isActive {
            markSeen()
        } else {
            unreadCount = UnreadCounter.unread(ids: items.map(\.id), since: lastSeenTopID)
        }
    }
```

- [ ] **Step 4: テストが通ることを確認**

Run: `cd core && swift test --filter NotificationsViewModelTests`
Expected: PASS（既存テスト＋新規 5 件）。

- [ ] **Step 5: コミット**

`/commit` スキルでコミット。
- 対象: `core/Sources/YoruMimizukuKit/NotificationsViewModel.swift`, `core/Tests/YoruMimizukuKitTests/NotificationsViewModelTests.swift`
- メッセージ例: `Track unread count in NotificationsViewModel`

---

## Task 4: 両 ViewModel に冪等なポーリングのライフサイクルを追加

**Files:**
- Modify: `core/Sources/YoruMimizukuKit/TimelineViewModel.swift`
- Modify: `core/Sources/YoruMimizukuKit/NotificationsViewModel.swift`

ポーリングループはこれまで View(`.task`) が持っていた。それを ViewModel に移す。時間依存のため自動テストはせず、後続タスクの手動確認（アプリ実行）で検証する。

- [ ] **Step 1: TimelineViewModel にポーリングを追加**

`TimelineViewModel.swift` の `isActive` プロパティ（Task 2 で追加した行）の直後に追加:

```swift
    /// The running refresh loop, or nil when not polling.
    private var pollingTask: Task<Void, Never>?
```

`markSeen()` メソッドの直前に追加:

```swift
    /// Start the periodic refresh loop if it is not already running (idempotent).
    /// The loop is owned by the view model, so it keeps running—and keeps
    /// accumulating the unread count—after the view that started it disappears.
    public func startPolling(every interval: Duration) {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            await self?.load()
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                if Task.isCancelled { break }
                await self?.refresh()
            }
        }
    }

    /// Stop the refresh loop. Called when a filter tab is closed.
    public func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
```

- [ ] **Step 2: NotificationsViewModel にポーリングを追加**

`NotificationsViewModel.swift` の `isActive` プロパティ（Task 3 で追加）の直後に追加:

```swift
    private var pollingTask: Task<Void, Never>?
```

`markSeen()` メソッドの直前に追加:

```swift
    /// Start the periodic refresh loop if not already running (idempotent). Owned by
    /// the view model so it survives the view and keeps the badge fresh in the
    /// background.
    public func startPolling(every interval: Duration) {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            await self?.load()
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                if Task.isCancelled { break }
                await self?.refresh()
            }
        }
    }

    public func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
```

- [ ] **Step 3: ビルドが通ることを確認**

Run: `cd core && swift build`
Expected: ビルド成功。

- [ ] **Step 4: テストが通ることを確認（リグレッション無し）**

Run: `cd core && swift test`
Expected: 全 PASS。

- [ ] **Step 5: コミット**

`/commit` スキルでコミット。
- 対象: `core/Sources/YoruMimizukuKit/TimelineViewModel.swift`, `core/Sources/YoruMimizukuKit/NotificationsViewModel.swift`
- メッセージ例: `Add idempotent polling lifecycle to feed view models`

---

## Task 5: ポーリング起動と active 同期を MainWindowView に移す

**Files:**
- Modify: `apps/macos/Views/MainWindowView.swift`
- Modify: `apps/macos/Views/FeedView.swift`
- Modify: `apps/macos/Views/NotificationsView.swift`

ポーリングの起動を View 個別の `.task` から `MainWindowView` の常駐 `.task` に一元化する。通知やフィルターを一度も開いていなくてもバッジが出るようにするため。フィルタータブの動的な増減にも追従し、閉じたフィルターはポーリングを止める。

- [ ] **Step 1: FeedView の `.task` をポーリング起動に置き換える**

`FeedView.swift` の `body` 内 `.task { await runFeed() }`（38 行目）を次に置き換える:

```swift
        .background { postNavShortcuts }
        .onChange(of: model.state) { _, _ in
            if focusedPostID == nil { focusedPostID = model.posts.first?.id }
        }
```

（`.task { await runFeed() }` の行を削除し、上記 `onChange` に差し替える。`postNavShortcuts` の `.background` 行は既存のものを残す。）

そして `runFeed()` メソッド（163–171 行目）と未使用になる `private let refreshInterval: Duration = .seconds(30)`（28 行目）を削除する。`FeedView` はポーリングを起動しなくなり、フォーカスの初期化だけを担う。

- [ ] **Step 2: NotificationsView の `.task` を削除**

`NotificationsView.swift` の `body` から `.task { await runNotifications() }`（23 行目）を削除する。あわせて `runNotifications()` メソッド（28–35 行目）と `private let refreshInterval: Duration = .seconds(30)`（14 行目）を削除する。

- [ ] **Step 3: MainWindowView にポーリング起動と active 同期を追加**

`MainWindowView.swift` の `private let clock = ...`（33 行目）の直後に追加:

```swift
    /// How often every badge-bearing tab polls for new content.
    private let pollInterval: Duration = .seconds(30)
```

`body` の `.onReceive(clock) { now = $0 }`（45 行目）の直後に、ポーリング起動・フィルター追従・選択同期の修飾子を追加:

```swift
        .onReceive(clock) { now = $0 }
        .task {
            model.startPolling(every: pollInterval)
            notifications.startPolling(every: pollInterval)
            for tab in workspace.filters { tab.model.startPolling(every: pollInterval) }
            syncActiveTab()
        }
        .onChange(of: workspace.filters.map(\.id)) { _, _ in
            for tab in workspace.filters { tab.model.startPolling(every: pollInterval) }
        }
        .onChange(of: workspace.selection) { _, _ in syncActiveTab() }
```

そして `tabShortcuts` 計算プロパティ（166 行目付近）の直前に `syncActiveTab()` を追加:

```swift
    /// Mark the selected badge-bearing tab active (badge stays 0 while viewed) and
    /// the others inactive. Conversation/author tabs carry no badge and are ignored.
    private func syncActiveTab() {
        model.setActive(workspace.selection == .home)
        notifications.setActive(workspace.selection == .notifications)
        for tab in workspace.filters {
            tab.model.setActive(workspace.selection == .filter(tab.id))
        }
    }
```

- [ ] **Step 4: 閉じたフィルターのポーリングを止める**

`WorkspaceModel.swift` の `removeFilter(id:)` 内、`filters.removeAll { $0.id == id }`（185 行目）の直前に、対象タブのポーリング停止を追加:

```swift
        filterStore.remove(id: id)
        filters.first { $0.id == id }?.model.stopPolling()
        filters.removeAll { $0.id == id }
```

- [ ] **Step 5: アプリを含めてビルドする**

Run: `cd /Users/asonas/ghq/github.com/asonas/YoruMimizuku/.worktrees/feature/timeline-ux-enhancements && xcodegen generate && xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj CODE_SIGN_IDENTITY="-"`
Expected: ビルド成功（`.xcodeproj` は gitignore 対象。生成し忘れに注意）。

- [ ] **Step 6: コミット**

`/commit` スキルでコミット。
- 対象: `apps/macos/Views/MainWindowView.swift`, `apps/macos/Views/FeedView.swift`, `apps/macos/Views/NotificationsView.swift`, `core/Sources/YoruMimizukuKit/WorkspaceModel.swift`
- メッセージ例: `Drive polling and active-tab sync from MainWindowView`

---

## Task 6: サイドバーのタブにバッジを表示する

**Files:**
- Modify: `apps/macos/Views/SidebarView.swift`
- Modify: `apps/macos/Views/MainWindowView.swift`

home/notifications 行のバッジ数は `MainWindowView` から値で渡す（`@ObservedObject` の変化で再描画される）。フィルター行は各 `TimelineViewModel` を個別に購読する小さなサブビューに切り出してバッジを観測する。選択中の行はバッジを表示しない。

- [ ] **Step 1: SidebarRow にバッジ引数とラベルを追加**

`SidebarView.swift` の `SidebarRow` 構造体に、プロパティ `var action: () -> Void` の直前へバッジ数を追加:

```swift
    var onEdit: (() -> Void)? = nil
    /// Unread/new count shown as a pill. Hidden when 0 or when the row is selected.
    var badge: Int = 0
    let action: () -> Void
```

`body` の `Spacer(minLength: 0)`（232 行目付近、`VStack` の後ろ）の直後にバッジを追加:

```swift
                Spacer(minLength: 0)

                if badge > 0, !isSelected {
                    Text(badge > 99 ? "99+" : "\(badge)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(theme.accent))
                }
```

- [ ] **Step 2: SidebarView に home/notifications のバッジ数を受け取る引数を追加**

`SidebarView` の `var onOpenSettings: () -> Void`（12 行目）の直後に追加:

```swift
    var onOpenSettings: () -> Void
    /// Unread counts for the pinned tabs, supplied by the owner.
    var homeUnread: Int = 0
    var notificationsUnread: Int = 0
```

`tabList` 内の home 行と通知行に `badge` を渡す:

```swift
                SidebarRow(
                    icon: "house",
                    title: "ホーム",
                    isSelected: workspace.selection == .home,
                    badge: homeUnread
                ) { workspace.selection = .home }

                SidebarRow(
                    icon: "bell",
                    title: "通知",
                    isSelected: workspace.selection == .notifications,
                    badge: notificationsUnread
                ) { workspace.selection = .notifications }
```

- [ ] **Step 3: フィルター行をモデル購読サブビューに切り出す**

`SidebarView.swift` の末尾（`SidebarRow` 構造体定義の後）に、フィルター行サブビューを追加:

```swift
/// One filter row that observes its own `TimelineViewModel` so the unread badge
/// updates as the backing feed polls in the background.
private struct FilterSidebarRow: View {
    @ObservedObject var model: TimelineViewModel
    let title: String
    let meta: String
    let isSelected: Bool
    let onClose: () -> Void
    let onEdit: () -> Void
    let onSelect: () -> Void

    var body: some View {
        SidebarRow(
            icon: "line.3.horizontal.decrease",
            title: title,
            meta: meta,
            isSelected: isSelected,
            onClose: onClose,
            onEdit: onEdit,
            badge: model.unreadCount,
            action: onSelect
        )
    }
}
```

`filterSection` 内の `ForEach(workspace.filters) { tab in SidebarRow(...) }`（118–131 行目）を、このサブビュー呼び出しに置き換える:

```swift
            ForEach(workspace.filters) { tab in
                FilterSidebarRow(
                    model: tab.model,
                    title: tab.title,
                    meta: tab.summary,
                    isSelected: workspace.selection == .filter(tab.id),
                    onClose: { workspace.removeFilter(id: tab.id) },
                    onEdit: {
                        if let saved = workspace.savedFilter(id: tab.id) {
                            editorRequest = .edit(saved)
                        }
                    },
                    onSelect: { workspace.selection = .filter(tab.id) }
                )
            }
```

- [ ] **Step 4: MainWindowView から home/notifications のバッジ数を渡す**

`MainWindowView.swift` の `splitView` 内 `SidebarView(...)` 呼び出し（66–71 行目）に 2 引数を追加:

```swift
            SidebarView(
                workspace: workspace,
                accountHandle: accountHandle,
                accountAvatarURL: accountAvatarURL,
                onOpenSettings: { showSettings = true },
                homeUnread: model.unreadCount,
                notificationsUnread: notifications.unreadCount
            )
```

- [ ] **Step 5: アプリを含めてビルドする**

Run: `cd /Users/asonas/ghq/github.com/asonas/YoruMimizuku/.worktrees/feature/timeline-ux-enhancements && xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj CODE_SIGN_IDENTITY="-"`
Expected: ビルド成功。

- [ ] **Step 6: コミット**

`/commit` スキルでコミット。
- 対象: `apps/macos/Views/SidebarView.swift`, `apps/macos/Views/MainWindowView.swift`
- メッセージ例: `Show unread badges on sidebar tabs`

---

## Task 7: 全体の検証

- [ ] **Step 1: コアの全テスト**

Run: `cd core && swift test`
Expected: 全 PASS。

- [ ] **Step 2: アプリのビルド**

Run: `cd /Users/asonas/ghq/github.com/asonas/YoruMimizuku/.worktrees/feature/timeline-ux-enhancements && xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj CODE_SIGN_IDENTITY="-"`
Expected: ビルド成功。

- [ ] **Step 3: 手動確認（実機/シミュレータ起動）**

実際にアプリを起動して以下を確認:
1. 起動直後、どのタブにもバッジが出ない（初回ロード分は既読扱い）。
2. 通知タブを開かずに放置し、新しい通知が来ると通知行にバッジが付く（最大 30 秒）。
3. フィルタータブを開かずに放置し、新着投稿が来るとフィルター行にバッジが付く。
4. バッジの付いたタブを選択するとバッジが消える。
5. 選択中タブには新着が来てもバッジが付かない。
6. フィルタータブを閉じてもクラッシュしない（ポーリングが停止する）。

> 手動確認は計画実行者が行い、結果を報告する。問題があれば該当タスクに戻る。

---

## 完了の定義
- `cd core && swift test` 全 PASS。
- アプリがビルドできる。
- 上記の手動確認 6 項目が満たされる。
- フェーズ B/C/D（`f`・permalink・`o`・ユーザータブ・会話子ツリー）は別プランで扱う。
