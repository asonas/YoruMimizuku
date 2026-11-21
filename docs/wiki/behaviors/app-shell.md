---
title: App Shell (Window, Tabs, Sidebar)
type: behavior
updated: 2026-11-21
sources:
  - core/Sources/YoruMimizukuKit/ThreadViewModel.swift
  - apps/macos/Views/FeedView.swift
  - docs/adr/0022-macos-prototype-detail-pane.md
  - core/Sources/BlueskyCore/Models/Record.swift
  - docs/adr/0023-macos-prototype-rows.md
  - docs/adr/0020-macos-prototype-chrome.md
  - docs/adr/0019-macos-commands-and-lists.md
  - apps/macos/Views/WorkspaceCommands.swift
  - apps/macos/Views/ListMembershipMenu.swift
  - apps/macos/Views/DraggedAuthor.swift
  - apps/macos/Timeline/LiveListMembershipEditor.swift
  - core/Sources/YoruMimizukuKit/ListMembershipModel.swift
  - docs/adr/0024-macos-saved-feeds-sidebar.md
  - core/Sources/YoruMimizukuKit/SavedFeedsModel.swift
  - apps/macos/Timeline/LiveSavedFeedsLoaders.swift
  - apps/windows/Core/ListMembershipModel.cs
  - apps/windows/Core/ListMembershipService.cs
  - apps/windows/App/Views/ListMembershipMenu.cs
  - apps/windows/App/Views/FeedView.xaml
  - apps/windows/App/Views/FeedView.xaml.cs
  - apps/windows/Core/SavedFeedsService.cs
  - apps/windows/Core/SavedFeedsModel.cs
  - apps/macos/Views/SavedFeedInfoButton.swift
  - docs/adr/0026-macos-three-pane.md
  - apps/macos/Views/DetailPaneView.swift
  - core/Sources/YoruMimizukuKit/DetailPaneModel.swift
  - docs/adr/0002-overall-design.md
  - docs/adr/0008-ipados.md
  - apps/macos/Views/NewPostCommand.swift
  - apps/macos/Views/SidebarView.swift
  - apps/macos/Views/FeedView.swift
  - apps/macos/Views/NotificationsView.swift
  - apps/macos/Views/ConversationView.swift
  - apps/macos/Views/PostRowView.swift
  - apps/macos/Views/MainWindowView.swift
  - apps/macos/Views/RootView.swift
  - apps/macos/Views/SettingsView.swift
  - apps/macos/YoruMimizukuApp.swift
  - apps/ipados/Views/PostRowView.swift
  - core/Sources/YoruMimizukuKit/ThreadViewModel.swift
  - core/Sources/YoruMimizukuKit/WorkspaceModel.swift
  - core/Sources/YoruMimizukuKit/WindowTitle.swift
  - apps/windows/App/MainWindow.xaml.cs
  - apps/windows/App/MainWindow.xaml
  - apps/windows/Core/DetailPaneModel.cs
  - apps/windows/Core/SavedFilter.cs
  - apps/windows/App/ViewModels/WorkspaceViewModel.cs
  - apps/windows/App/Services/WindowPlacement.cs
  - apps/windows/App/Services/AppSettings.cs
  - apps/windows/App/Views/RecordView.cs
  - apps/windows/Core/MutedAuthors.cs
  - apps/windows/Core/PostService.cs
features:
  - name: Three-pane window (sidebar / timeline / detail pane)
    macos: full
    windows: full
    ios: differs
    android: planned
    note: "iPadOS keeps conversation and author tabs in its sidebar instead of a detail pane ([[ipados]])."
  - name: Tabbed single-column shell (sidebar / tabs)
    macos: full
    windows: full
    ios: differs
    android: planned
    note: "iPadOS uses a dedicated touch-first `NavigationSplitView` shell under `apps/ipados`, not the macOS AppKit-chrome view ([[ipados]])."
  - name: Pinned feeds and lists in the sidebar
    macos: full
    windows: differs
    ios: none
    android: planned
    note: "macOS and Windows list the account's pinned feeds and lists (`savedFeedsPrefV2`) read-only; only the selected one polls ([[macos]], [[windows]]). Windows timelines have no header and its window title never names a tab, so a pin's description, creator and AT-URI are the sidebar row's tooltip instead of an ⓘ popover, and selecting a pin does not retitle the window (MainWindow.xaml.cs). The shared `WorkspaceTab.savedFeed` exists, but the iPad app does not show pins yet."
  - name: Menu bar commands (⌘1…⌘9, 投稿 menu)
    macos: full
    windows: differs
    ios: none
    android: planned
    note: "macOS View menu ⌘1…⌘9 select the first nine sidebar rows; the 投稿 menu acts on the focused timeline post ([[macos]]). Windows has no menu bar, so the same commands are keys with Ctrl for ⌘ and Alt for ⌥ (Ctrl+1…9, Ctrl+R, Ctrl+Enter, Ctrl+Shift+R/C, Ctrl+Alt+I, L) and the post's right-click menu, which selects its post and shows the keys; with no menu to disable, the keys do nothing until a post is selected, and they act in whichever pane has focus. The menu's この人をミュート is hidden on the viewer's own posts, as in the macOS row menu (MainWindow.xaml.cs, FeedView.xaml)."
  - name: Toolbar search (transient results)
    macos: full
    windows: differs
    ios: none
    android: planned
    note: "Both show a submitted search in the timeline column without saving; 'フィルターとして保存' turns it into a filter and choosing any sidebar row discards it ([[filters]]). Windows has no unified toolbar, so the field is the `NavigationView` AutoSuggestBox at the top of the sidebar (Ctrl+F, the analogue of ⌘F), and its timelines have no header, so 'フィルターとして保存' sits in the timeline's command bar beside 更新 and 投稿 (MainWindow.xaml, MainWindow.xaml.cs)."
  - name: Add a person to a curated list (menu / drag)
    macos: full
    windows: differs
    ios: none
    android: planned
    note: "Both offer 'リストに追加' in a timeline post's right-click menu and add a dragged avatar's author to an own pinned curated list, writing app.bsky.graph.listitem records on the window account after re-reading the server ([[macos]], [[windows]]). A WinUI menu can change while it is open, so Windows reads the author's membership when the menu opens and redraws it when the answer arrives, instead of prefetching on pointer rest; and the Windows post body is selectable text, so right-clicking the body itself shows the text commands (FeedView.xaml, ListMembershipMenu.cs). Both also take a dropped avatar on a saved filter, adding a `from:` condition unless the filter is AND and already names a person, with the same toasts; the Windows rule is a port of `WorkspaceModel.addAuthor(handle:toFilter:)` in `Core/SavedFilter.cs` ([[filters]])."
  - name: Multiple windows
    macos: full
    windows: full
    ios: differs
    android: planned
    note: "macOS opens additional windows of the same `WindowGroup(id: \"main\")` via ⇧⌘N (`apps/macos/Views/NewPostCommand.swift`), matching Windows' Ctrl+Shift+N (only the primary owns the updater / notification polling); each macOS window shows the selected tab as its title (`WorkspaceModel.selectionTitle`) in the toolbar, Mission Control, the Window menu and the Dock, with `@handle` as the toolbar subtitle. Settings (theme/display-density/font/notification) now live-sync across every open window and the `Settings` scene: the four stores are app-level `@StateObject`s owned by `YoruMimizukuApp` and shared by reference rather than independent per-window instances reading `UserDefaults` at their own init, resolving the cross-window settings staleness previously noted here (plan `2026-07-24-apple-hig-remediation` (git history) S7, `apps/macos/YoruMimizukuApp.swift`). iPadOS now permits real OS-level multi-scening (Split View / Slide Over / Stage Manager / App Exposé) since `UIRequiresFullScreen` was dropped, mapping the per-window model to a per-scene `WorkspaceModel` — but two scenes signed into the same account still race on the shared `UserDefaults`-backed conversation-tab and filter persistence (last-writer-wins, no merge) ([[ipados]], [[windows]])."
  - name: Window size persistence
    macos: full
    windows: full
    ios: none
    android: planned
    note: "macOS restores the window frame automatically via SwiftUI WindowGroup scene restoration; Windows persists the Win32 WINDOWPLACEMENT (position, size, maximized state) to AppSettings and reapplies it after Activate ([[windows]]). iPad scene sizing is OS-managed, so nothing is persisted."
  - name: Display density A / B
    macos: full
    windows: full
    ios: none
    android: planned
    note: "The shared density model exists, but the current iPadOS UI does not expose or apply the A/B display-density setting yet ([[ipados]])."
---

# App Shell (Window, Tabs, Sidebar)

The app shell is the Yorufukurou-style frame that hosts every timeline: one window, a vertical-tab sidebar, a single content column, and a bottom composer. It is the navigation and layout layer; what fills the column is described in [[timeline-streaming]], and the account the shell operates under is described in [[accounts]].

## Window layout

A window carries an account switcher (the design's §7.1 slot is the title bar's top-right; the macOS build places it in the **sidebar footer** instead — see below), a top tab area whose right-edge `+` opens a source picker for a new tab, a single-column feed in the center, and a composer at the bottom (text box + Post). Clicking a post opens its thread (conversation tree). The app is multi-window: it uses SwiftUI `WindowGroup` with per-window state, so each window keeps its own tab set and active account (`0002-overall-design.md` §7.1, §8). Tab composition is persisted per window (§7.3).

The macOS build uses the standard unified toolbar (`.windowToolbarStyle(.unified)`; before 2026-11-20 it hid the title bar and ran content to the top edge) and three columns: the sidebar, the selected timeline, and a detail pane where conversations and author pages open (see "Detail pane" below). The default size is 1240×800 and the minimum width 900 (`docs/adr/0026-macos-three-pane.md`). The toolbar shows the selected source as the title and `@handle` as the subtitle, with search and compose on the right; the standard sidebar toggle (⌃⌘S) remains. Every timeline, including フォロー中 and 通知, starts below the toolbar with a header (its name, 14pt bold); post lists also show an accent-tinted "↑ 新着 n 件" bar when posts arrived above what the viewer last saw at the top (`TimelineViewModel.newArrivals`, counted in arrival order), which scrolls back up (`docs/adr/0020-macos-prototype-chrome.md` (`apps/macos/Views/SidebarView.swift`, `FeedView.swift`, `NotificationsView.swift`). Apple-specific window wiring lives on the [[macos]] page.

**Window size is remembered across launches.** macOS gets this from SwiftUI `WindowGroup` scene restoration automatically (the 1240×800 is only the first-run default). Windows has no equivalent built in — WinUI 3 / `AppWindow` exposes no placement persistence, and a width-only `AppWindow.Resize` mixes DPI units and is overwritten by the default size the first `Activate` applies — so it captures the Win32 `WINDOWPLACEMENT` (normal position, size, and maximized state) on window close into `AppSettings` and reapplies it *after* `Activate` on the next launch. Capture and restore both go through `GetWindowPlacement` / `SetWindowPlacement`, so the round-trip is DPI-consistent. Details are on the [[windows]] page.

On macOS the File menu's ⌘N is **新規投稿**: it opens the composer sheet over the focused window's current tab, matching what timeline clients conventionally bind to ⌘N. The command reaches the window through a `FocusedValues` entry published by `MainWindowView`, is disabled before login, and is a no-op while another sheet is already presented (`apps/macos/Views/NewPostCommand.swift`). The unmodified `n` shortcut inside a feed keeps opening the composer as before ([[timeline-streaming]]). The spec requires multi-window support (per-window account viewing, `0002-overall-design.md` §8), so the File menu also keeps a **新規ウィンドウ** command on **⇧⌘N** (matching the Windows build's Ctrl+Shift+N) that opens another `WindowGroup(id: "main")` window via `openWindow(id:)`; ⌘N itself was deliberately left on 新規投稿 rather than reverted to New Window, since that is this client's established convention (plan `2026-07-24-apple-hig-remediation` (git history) S4). Real multi-window verification (Mission Control / Window menu / Dock titles, ⇧⌘N, per-window account viewing) is pending — see [[manual-verification]] "S4".

The standard **⌘, (設定…)** command now opens a native SwiftUI `Settings { }` scene (`apps/macos/YoruMimizukuApp.swift`) rather than a per-window sheet: once an app declares a `Settings` scene, SwiftUI wires ⌘, to it automatically, so the custom `SettingsCommands` `CommandGroup` and the `FocusedValue`-published `OpenSettingsAction` that used to route the shortcut to the focused window's sheet were removed. The scene injects the same app-level settings-store instances (theme / display density / font / notifications) described on [[macos]] as `.environmentObject`s, so the settings window and every open timeline window always agree. Its tabs include the 通知 tab described in [[notifications]] (`apps/macos/Views/SettingsView.swift`, plan `2026-07-24-apple-hig-remediation` (git history) S7).

## Display density (A / B)

Post rows render at one of two densities, selectable in settings, defaulting to **B** (`0002-overall-design.md` §7.2). On macOS since 2026-11-20 this applies only to conversations in the detail pane; timeline and author-page lists use the desktop prototype's fixed row (see "Timeline rows (macOS)"):

- **A (ultra-compact)**: small avatar, 1–2 lines, minimal padding; repost/reply context is a small single line. Optimizes scan-ability — the plain Yorufukurou look.
- **B (comfortable)**: large avatar, thumbnails, and per-post reply/repost/like actions with counts.

The density model is UI-framework-agnostic so it can be unit-tested: `DisplayDensity` (`.compact` / `.comfortable`, default `.comfortable`), `RelativeTimeFormatter` (deterministic short timestamps — "now", "30s", "2m", "3h", "2d"), and `PostDisplay` (the timeline-row view model) all live in `YoruMimizukuKit` and are verified with `swift test`. The SwiftUI `PostRowView` branches on the density value, and the bootstrap app shell was built against mock data (`PostDisplay.samples`) before real fetching landed (plan `2026-06-04-yorumimizuku-app-shell` (git history)). Thumbnail and action visibility may become independently toggleable from density (decided at implementation time, §7.2).

## Tabs (sources)

A tab is one of the seven v1 sources (home / notifications / custom feed / list / author / search / thread). Every tab runs under the window's active account, and the tab composition is persisted per window (`0002-overall-design.md` §7.3). The data behind each tab is abstracted by the `TimelineSource` protocol — see [[timeline-streaming]]. Tapping a user's avatar opens a view-only author tab for that user, deduplicated by DID and not persisted — see [[author-tab]].

## Conversation tab (thread view)

Opening a post's conversation anchors the thread on that post: ancestors render above it and replies render below, but only the focused post is interactive — `ThreadViewModel.post(id:)` (`core/Sources/YoruMimizukuKit/ThreadViewModel.swift`) resolves a post only when its id matches the current focus, so like/repost/quote never reach anything else in the tree. Ancestor rows and reply rows are accordingly rendered with `PostRowView(interactiveActions: false)`, which turns their action bar into static labels, and each row is wrapped in a plain button that re-anchors the tab on that post when tapped; this also stands in for the timestamp tap that `interactiveActions: false` otherwise disables (`apps/macos/Views/ConversationView.swift`, `parentBlock` / `replyRow`). [[ipados]] already renders both ancestor and reply rows this way; on macOS the reply rows previously left the action bar live even though it had no effect, until the row was brought in line with the ancestor rows. Manual verification of this behavior on a real macOS session is pending — see [[manual-verification]] "P0-1".

## Detail pane

On macOS a conversation or author page opens in the window's third column instead of replacing the timeline, so the timeline keeps its scroll position. The pane shows one page at a time, as in the desktop prototype (the back/forward history and ⌘[ / ⌘] of the first version were dropped on 2026-11-20): opening another page replaces it and close (×) empties it. Its 38pt bar has close, the title and, for a conversation, the スレッド / レコード switch. スレッド shows the ancestors as compact rows, the anchor at full size (media with alt text, a warn box for labeled media, link card, quote box, counts that also act) and the replies as a tree indented 20pt per level with fold controls; レコード shows Handle / DID / URI and the record as stored (`com.atproto.repo.getRecord`), also reachable with 投稿 > レコードを表示 (⌥⌘I). If the thread fails to load, the anchor stays and the replies area shows the error with 再試行. A reply field under the conversation (available as soon as the anchor shows) sends a short reply with return or opens the composer with what was typed (`docs/adr/0022-macos-prototype-detail-pane.md`). `DetailPaneModel` holds the shown page and reuses `ConversationTab` / `AuthorTab`; an author feed polls only while its page is shown. Conversation tabs and author tabs are no longer listed in the macOS sidebar or persisted. The plain-key shortcuts (j/k/f/r/⇧R/l/s/o/n since 2026-11-21, [[timeline-streaming]]) belong to the timeline column only, so the feed inside an author page does not register them and the conversation view binds none of them. [[ipados]] keeps the tabbed model unchanged (`docs/adr/0026-macos-three-pane.md`, `apps/macos/Views/DetailPaneView.swift`, `core/Sources/YoruMimizukuKit/DetailPaneModel.swift`).

On [[windows]] the window has the same three panes (ADR 0026, Phase 7 of `docs/adr/0027-windows-csharp-core.md`): the `NavigationView` sidebar (210 wide), the selected timeline and the detail pane, split 2 : 3 as in the prototype's 400 : 628. The timeline column is 360 to 960 wide and the detail pane at least 320, and the window keeps at least 900 × 540. Clicking a post, its reply count, a reply marker or a quote opens the conversation in the pane; an avatar, author name or `@mention` opens the author page there; a hashtag still opens a filter in the timeline column. The sidebar no longer lists conversation or author tabs. As on macOS, the pane shows one page at a time with no back / forward history (`docs/adr/0022-macos-prototype-detail-pane.md`): `DetailPaneModel` (`apps/windows/Core/DetailPaneModel.cs`, a port of the Swift model) keeps the shown page when it is opened again and replaces it when another is opened. The bar (39 high) has close (×), the page's title and, for a conversation, the スレッド / レコード switch (see "Commands, search and lists"). An author feed polls only while its view is on screen. In a conversation the parent and each reply re-anchor the pane, opening that post's conversation in place of the shown one, as macOS's ancestor and reply rows do; a reply button opens the composer, since the timeline's reply count now opens the conversation. Settings take the timeline and detail columns together. Switching accounts or signing in again empties the pane, whose pages were built on the previous account client. With nothing open the pane shows the prototype's faint two-lens mark. The plain-key shortcuts stay focus-scoped as before: they act on whichever pane has keyboard focus, so nothing needs to be unregistered as on macOS (`apps/windows/App/MainWindow.xaml`, `apps/windows/App/MainWindow.xaml.cs`).

## Post row action paths

Every post row's right-click (macOS) or long-press (iPadOS) context menu offers the same three paths regardless of platform: 「リンクをコピー」(copy the public permalink), 「ブラウザで開く」(open that permalink in the default browser), and — only on the viewer's own posts — 「削除」(destructive), which still goes through the existing `confirmationDialog` unchanged (`apps/macos/Views/FeedView.swift`, `apps/ipados/Views/TimelineListView.swift`). On iPadOS the action bar already carries a visible `safari` button wired to the same `onOpenPermalink` closure, so the context-menu entry is a second, more discoverable route to an action that already existed; on macOS there is no visible action-bar Safari button, so the context menu is the only browser-open path for now — adding a visible macOS action-bar button was deliberately left open for later reconsideration (`apps/macos/Views/PostRowView.swift`, `apps/ipados/Views/PostRowView.swift`, plan `2026-07-24-apple-hig-remediation` (git history) S6).

## Timeline rows (macOS)

Timeline lists use the prototype's compact row (`TimelineRowView`): why-line (repost / reply), name with a check for verified authors, @handle and a Japanese relative time, the body clamped to four lines, thumbnails, tags and the reactions (counts only above zero, hidden by 表示 > 反応の数を隠す). Clicking a row, or moving to it with j/k, shows it in the detail pane at once: the pane draws the anchor from the row's own post (`ThreadViewModel.preview`), fetches the thread 0.25 s after the page appears so a run of j/k does not start a fetch per post, and shows the ancestors and replies when it arrives, keeping the anchor in view when a deep reply's older ancestors are added above it. The row's copy is for reading only: its like and repost buttons work once the thread arrives, since the copy may predate the viewer's last change. Each j/k also decodes the full-size images of the next two posts in the direction of travel at the pane's size, so they come from the image cache. この人をミュート (post menu and right-click) mutes the author for the window's account and drops their posts from every timeline in the window ([[timeline-media-layout]], `docs/adr/0023-macos-prototype-rows.md`).

## Commands, search and lists (macOS)

The View menu's ⌘1…⌘9 select the first nine sidebar rows of the key window, in the order ⌘⇧J/K cycles (`WorkspaceModel.shortcutTabs`). A 投稿 menu acts on the post focused in the timeline column: reply ⌘↩, repost ⇧⌘R (the plain R key; undoing asks first), 引用して投稿 (⇧R), like (the plain F key), copy link ⇧⌘C and リストに追加, following the desktop prototype; it is disabled until a post is focused, and the plain keys stay with the timeline column. The View menu also has 新着を読み込む ⌘R, and the Edit menu 検索 ⌘F, which focuses the toolbar search (`apps/macos/Views/WorkspaceCommands.swift`).

[[windows]] has no menu bar, so the same commands are keys, with Ctrl for ⌘, and a timeline post's right-click menu. Ctrl+1…Ctrl+9 select the first nine sidebar rows in the order Ctrl+Shift+J/K cycles (home, 通知, pinned feeds, pinned lists, filters; the フィルターを追加 row is not counted), and Ctrl+R reloads the shown timeline as its 更新 button does (`apps/windows/App/MainWindow.xaml.cs`). The right-click menu reads 返信 (Ctrl+Enter), リポスト or リポストを取り消す (Ctrl+Shift+R), 引用して投稿, いいね or いいねを取り消す (L), リンクをコピー (Ctrl+Shift+C), レコードを表示 (Ctrl+Alt+I, the macOS ⌥⌘I), リストに追加 and この人をミュート, and opening it selects the post, as the macOS row menu does. The keys act on the post j/k or the menu last selected and do nothing before one is: there is no menu to show as disabled. 返信 opens the reply composer, as ⌘↩ does, while the row's reply count still opens the conversation. Like moved from f to l on Windows too, in the timeline and in the conversation pane. The keys are focus-scoped like the plain keys, so they also act on an author page's feed in the detail pane when it has focus; the plain keys now ignore Ctrl and Alt, which leaves Ctrl+Shift+J/K and Ctrl+Shift+N to the window while a timeline has focus. The commands reuse the action bar's handlers (`apps/windows/App/Views/FeedView.xaml`, `apps/windows/App/Views/FeedView.xaml.cs`).

On Windows レコードを表示 opens the post's conversation in the detail pane on its レコード tab, and the pane's bar has the macOS スレッド / レコード switch for every conversation (a `SelectorBar`). The tab shows Handle, DID, URI and, for labeled media, Label, then the record as stored (`com.atproto.repo.getRecord`), indented with sorted keys, or "レコードを読み込めませんでした". Opening the shown post again from a row returns it to its thread, and any other page opens on its thread (`DetailPaneModel.OpenRecord` in `apps/windows/Core/DetailPaneModel.cs`, ported with the Swift tests). Windows reads the record the first time the tab shows and keeps it while the switch moves between the tabs, where macOS reads it again each time (`apps/windows/App/Views/RecordView.cs`).

この人をミュート mutes the author for the window's account (`app.bsky.graph.muteActor`), with no confirmation and the macOS toasts, "@handle をミュートしました" or "ミュートできませんでした". Windows builds a timeline each time it is shown, so the window remembers who was muted (`MutedAuthors` in `apps/windows/Core/MutedAuthors.cs`): the timeline column and an author page in the detail pane drop the author's posts at once, every timeline leaves them out of each page it fetches afterwards, and a first page made only of their posts fetches the next one, as on macOS. Signing the window in as another account forgets them. This is the same result as macOS, which drops the posts from each timeline model the window keeps (`TimelineViewModel.removePosts(byAuthor:)`).

The toolbar has a search field and the compose button. A submitted search shows its results in the timeline column as `WorkspaceTab.search` without saving anything; the header's "フィルターとして保存" keeps it as a filter, and choosing any sidebar row discards it ([[filters]]).

On [[windows]] the search field is the `NavigationView` AutoSuggestBox at the top of the sidebar, and Ctrl+F focuses it. The typed text becomes the search by the macOS rule: trimmed, ignored when blank, and run as one keyword term named after itself (`SavedFilter.ForSearch` in `apps/windows/Core/SavedFilter.cs`, a port of `WorkspaceModel.openSearch(query:)`). The results show in the timeline column with no sidebar row selected and nothing written to the filters file. "フィルターとして保存" sits in the timeline's command bar beside 更新 and 投稿, because Windows timelines have no header; it adds the search as a filter and selects it. The search is never a sidebar row, so choosing any row, or switching accounts, discards it. The query text stays in the field, as it does in the macOS toolbar (`apps/windows/App/ViewModels/WorkspaceViewModel.cs`, `apps/windows/App/MainWindow.xaml.cs`).

A post's right-click menu offers "リストに追加": the window account's curated lists (`app.bsky.graph.getListsWithMembership`, `purposes=curatelist`), checked where the author is on them, ending with a note that lists are public. Because a menu is built synchronously, membership comes from a cache that is filled once focus rests on a post; every change re-reads the server before writing, since the PDS accepts duplicate list items. Dragging a post's avatar onto one of the window account's own pinned curated lists adds the author to it; dropping it on a filter adds a `from:` condition, except on an AND filter that already names a person (`docs/adr/0019-macos-commands-and-lists.md`, `core/Sources/YoruMimizukuKit/ListMembershipModel.swift`, `apps/macos/Views/DraggedAuthor.swift`).

On [[windows]] a timeline post's right-click menu has the same "リストに追加" submenu, with the same empty and loading states, checks and public-list note, and the same toasts after a change. The cache, the one-change-at-a-time rule, the re-read before writing and the 30 s trust in a change the appview has not indexed are a port of the Swift model (`apps/windows/Core/ListMembershipModel.cs`, reads and writes in `apps/windows/Core/ListMembershipService.cs`); each account has one model, shared by its windows (`IAccountClient.ListMembership`). Windows reads an author's membership when the menu opens, at most once a minute per author, and redraws the open submenu when the answer arrives, because a WinUI `MenuFlyout` can change while it is open; macOS cannot, so it prefetches when the pointer rests. The post body is selectable text on Windows, so right-clicking the body shows the text commands and the rest of the row shows the post menu. A post's avatar drags its author (the app format `as.ason.YoruMimizuku.author`, and `@handle` text for other apps); one of the account's own pinned curated lists in the sidebar accepts the drop, outlines itself while the drag is over it, and adds the author. A saved filter row accepts the same drop and, as on macOS, adds a `from:` condition for the author's handle and saves the filter, unless the filter is AND and already names a person; the toasts are the macOS ones (`SavedFilter.AddingAuthor` in `apps/windows/Core/SavedFilter.cs`, `apps/windows/App/Views/ListMembershipMenu.cs`, `apps/windows/App/Views/FeedView.xaml.cs`, `apps/windows/App/MainWindow.xaml.cs`).

## Sidebar / tab UI

### Pinned feeds and lists (macOS, Windows)

The macOS sidebar follows the desktop prototype: groups フィード (フォロー中 — the home timeline, renamed via `WorkspaceModel.homeTitle` — then 通知, then pinned feeds), リスト and フィルター; rows are one line with an accent icon, a dim fill and semibold text when selected, and plain unread counts; filter rows show only their name, with the query as tooltip and 編集… / 削除 on right-click. フィード and リスト list the feeds and lists the account pinned in Bluesky (`app.bsky.actor.getPreferences`, `savedFeedsPrefV2`), in pin order; a section with no pins is hidden, and the pinned following timeline is the home row rather than a second entry. Selecting one shows its timeline (`app.bsky.feed.getFeed` / `app.bsky.feed.getListFeed`) in the middle column, titles the window, and gives the header an ⓘ popover with the description, the creator's handle and the AT-URI. Pins are read-only in the app and are re-read whenever the app becomes active: a reload replaces them, a feed unpinned elsewhere stops polling, and if it was selected the window falls back to home. Only the selected pinned feed polls and pinned feeds carry no unread badge. Deleted feeds and unresolvable lists are skipped (`docs/adr/0024-macos-saved-feeds-sidebar.md`, `core/Sources/YoruMimizukuKit/SavedFeedsModel.swift`, `apps/macos/Timeline/LiveSavedFeedsLoaders.swift`, `apps/macos/Views/SavedFeedInfoButton.swift`).

Windows shows the same pins in the same order in its `NavigationView` sidebar: pinned feeds after 通知, then a リスト header over the pinned lists (absent with none), then the filters. It reads them with the same calls and skips the same items (`apps/windows/Core/SavedFeedsService.cs`, `apps/windows/Core/SavedFeedsModel.cs`), re-reads them whenever the window comes forward and when its account changes, falls back to home when the selected pin is gone, and opens a pin's timeline in the timeline column; only the selected pin polls, because a feed view polls only while it is on screen. Two details differ on purpose because Windows timelines have no header and the window title never names a tab: the description, creator handle and AT-URI are the sidebar row's tooltip instead of an ⓘ popover, and selecting a pin does not retitle the window (`apps/windows/App/MainWindow.xaml.cs`).

The vertical-tab sidebar (home / notifications / filters; on macOS also pinned feeds and lists; on iPadOS also conversations and authors) keeps its tab state in `WorkspaceModel` (`@MainActor ObservableObject`), rendered by the `NavigationSplitView` in `MainWindowView`. The `SidebarRow` component is display-only and receives theme colors from `ThemeStore`. Its look and density follow the reference app cmux (plan `2026-06-05-yorumimizuku-cmux-sidebar` (git history)):

- Selection is a **solid fill** (`RoundedRectangle(cornerRadius: 6)` in the accent color) with the foreground forced to white, not a faint tint or a left bar.
- Navigation rows (home / notifications) are icon + title; a conversation row is display name (12.5 semibold) + body snippet (11, up to 2 lines) + `@handle` (10 monospaced). A close `xmark` appears top-right on hover only.
- The accent color is left to `ThemeStore` (cmux's `#0091FF` is not forced); only the selected row fixes "accent fill + white text".

Open questions carried in the plan: whether navigation rows show an unread badge (tied to [[notifications]]), and how much metadata a conversation row should carry.

The sidebar ends in a **footer** that doubles as the macOS account switcher: the current avatar + `@handle` open a borderless menu of stored accounts plus add-account / log-out, and a gear button (carrying the update-available dot) opens the native `Settings` scene via `@Environment(\.openSettings)` (previously a per-window sheet — see above). This is where the design's top-right switcher actually lives on macOS; the menu's behavior and the `summaries()` / `removeAndAdvance(did:)` plumbing are in [[accounts]] (`apps/macos/Views/SidebarView.swift`).

Close/edit are not hover-only: `SidebarRow` also exposes a `.contextMenu` (Control-click or right-click) with the same "フィルターを編集" / "タブを閉じる" actions, and VoiceOver users reach them through `.accessibilityActions` (the row is one combined element labeled with title + subtitle, so a rotor/VO+Command+Space custom-actions sweep surfaces both without needing the hover-revealed icon buttons at all) (plan `2026-07-24-apple-hig-remediation` (git history) P0-2). Real VoiceOver / Accessibility Inspector verification of this is pending — see [[manual-verification]] "P0-2".

On [[ipados]], the shell is a separate SwiftUI implementation under
`apps/ipados`. It uses `NavigationSplitView`, visible touch actions, and a simple
search-field path to create saved-search tabs. Hover-only affordances are not
used, and the macOS settings surface (theme / font / display density) is not
replicated yet (`0008-ipados.md` §6, [[ipados]]).
