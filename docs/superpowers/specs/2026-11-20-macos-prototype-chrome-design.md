# macOS Toolbar, Sidebar, Headers and Menus from the Desktop Prototype

- Date: 2026-11-20
- Status: Implemented (PR 5 of the desktop UI update)
- Target: `apps/macos` (window chrome, `SidebarView`, `FeedView` header, `NotificationsView`, `WorkspaceCommands`), `YoruMimizukuKit` (`WorkspaceModel.homeTitle`); `apps/ipados` and `apps/windows` unchanged
- Builds on: `2026-11-20-macos-prototype-colors-design.md`, `2026-11-20-macos-commands-and-lists-design.md`

## 1. Overview

The window's frame now follows the desktop prototype (the visual source of
truth since PR 4): a unified toolbar, the prototype's sidebar groups and rows,
a header on every timeline (with a "新着 n 件" bar on post lists), and the
prototype's menus.

## 2. Decisions

- **Toolbar.** The window uses the standard unified toolbar instead of a hidden
  title bar with content running to the top edge. It shows the selected source
  as the title and `@handle` as the subtitle on the left, and search and compose
  on the right; posts start below it.
- **Sidebar.** Groups フィード (フォロー中, 通知, pinned feeds), リスト and
  フィルター with 11pt group labels. Rows are one 13pt line, 28pt tall, with an
  accent icon; the selected row has a dim fill and semibold text in the normal
  color; unread counts are plain numbers. Filter rows show only their name (the
  query is the tooltip), with 編集… and 削除 on right-click and hover. 通知 is
  not in the prototype; it sits under フォロー中 so ⌘1 stays フォロー中 as in the
  prototype and ⌘1…⌘9 still follow the sidebar from the top.
- **Home is named フォロー中** (`WorkspaceModel.homeTitle`), as in the prototype.
- **Header and new-posts bar.** Every timeline, including フォロー中 and 通知,
  shows its name (14pt bold) under the toolbar. In post lists, when posts arrive
  above what the viewer last saw at the top, an accent-tinted "↑ 新着 n 件" bar
  appears; clicking it scrolls to the top. `TimelineViewModel.newArrivals`
  counts head posts in arrival order that were not loaded when the top was last
  on screen, so it survives tab switches, ignores the thread grouping of the
  display, and a deleted post does not turn older posts into new ones. 通知
  (not in the prototype) gets the header only.
- **Menus.** 表示: ⌘1…⌘9, 新着を読み込む ⌘R, the standard sidebar toggle ⌃⌘S.
  編集: 検索 ⌘F focuses the toolbar search. 投稿: 返信 ⌘↩, リポスト ⇧⌘R,
  引用して投稿, いいね (L), リンクをコピー ⇧⌘C and リストに追加. Like moves from
  the f key to l; "ブラウザで開く" leaves the menu bar (the o key and the
  right-click menu keep it). Reply and quote do nothing while a composer is
  open, since ⌘↩ is also its send key. Overlapping notification refreshes (a
  poll and ⌘R) keep the newer answer.

## 3. Not in this PR

- 「レコードを表示」(⌥⌘I) with the detail pane's レコード tab (PR 7), and 「この人を
  ミュート」 and 「反応の数を表示／隠す」 with the post rows (PR 6).
- The Window menu now lists windows by the source name only; the account is the
  toolbar subtitle.
