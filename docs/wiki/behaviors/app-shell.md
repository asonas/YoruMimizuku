---
title: App Shell (Window, Tabs, Sidebar)
type: behavior
updated: 2026-07-24
sources:
  - docs/superpowers/specs/2026-06-04-yorumimizuku-design.md
  - docs/superpowers/specs/2026-06-08-yorumimizuku-ipados-design.md
  - docs/superpowers/plans/2026-06-04-yorumimizuku-app-shell.md
  - docs/superpowers/plans/2026-06-05-yorumimizuku-cmux-sidebar.md
  - docs/superpowers/plans/2026-06-11-yorumimizuku-v1.0.0-roadmap.md
  - docs/superpowers/plans/2026-07-24-apple-hig-remediation.md
  - apps/macos/Views/NewPostCommand.swift
  - apps/macos/Views/SidebarView.swift
  - apps/macos/Views/ConversationView.swift
  - apps/macos/Views/PostRowView.swift
  - apps/ipados/Views/PostRowView.swift
  - core/Sources/YoruMimizukuKit/ThreadViewModel.swift
  - apps/windows/App/MainWindow.xaml.cs
  - apps/windows/App/Services/WindowPlacement.cs
  - apps/windows/App/Services/AppSettings.cs
features:
  - name: Tabbed single-column shell (sidebar / tabs)
    macos: full
    windows: full
    ios: differs
    android: planned
    note: "iPadOS uses a dedicated touch-first `NavigationSplitView` shell under `apps/ipados`, not the macOS AppKit-chrome view ([[ipados]])."
  - name: Multiple windows
    macos: full
    windows: full
    ios: differs
    android: planned
    note: "macOS opens multiple SwiftUI WindowGroup windows; Windows opens additional workspace windows with Ctrl+Shift+N over the same session (only the primary owns bridge init / updater / notification polling); iPadOS now permits real OS-level multi-scening (Split View / Slide Over / Stage Manager / App Exposé) since `UIRequiresFullScreen` was dropped, mapping the per-window model to a per-scene `WorkspaceModel` — but two scenes signed into the same account race on the shared `UserDefaults`-backed conversation-tab and filter persistence (last-writer-wins, no merge) ([[ipados]], [[windows]])."
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

A window carries an account switcher (the design's §7.1 slot is the title bar's top-right; the macOS build places it in the **sidebar footer** instead — see below), a top tab area whose right-edge `+` opens a source picker for a new tab, a single-column feed in the center, and a composer at the bottom (text box + Post). Clicking a post opens its thread (conversation tree). The app is multi-window: it uses SwiftUI `WindowGroup` with per-window state, so each window keeps its own tab set and active account (`2026-06-04-yorumimizuku-design.md` §7.1, §8). Tab composition is persisted per window (§7.3).

The macOS build integrates the window chrome (`.windowStyle(.hiddenTitleBar)`) and ships a two-column default size of 940×720; the brand area is padded to clear the traffic-light buttons (`2026-06-05-yorumimizuku-cmux-sidebar.md`). Apple-specific window wiring lives on the [[macos]] page.

**Window size is remembered across launches.** macOS gets this from SwiftUI `WindowGroup` scene restoration automatically (the 940×720 is only the first-run default). Windows has no equivalent built in — WinUI 3 / `AppWindow` exposes no placement persistence, and a width-only `AppWindow.Resize` mixes DPI units and is overwritten by the default size the first `Activate` applies — so it captures the Win32 `WINDOWPLACEMENT` (normal position, size, and maximized state) on window close into `AppSettings` and reapplies it *after* `Activate` on the next launch. Capture and restore both go through `GetWindowPlacement` / `SetWindowPlacement`, so the round-trip is DPI-consistent. Details are on the [[windows]] page.

On macOS the File menu's default New Window (⌘N) is replaced with **新規投稿**: ⌘N opens the composer sheet over the focused window's current tab instead of spawning another timeline window, matching what timeline clients conventionally bind to ⌘N. The command reaches the window through a `FocusedValues` entry published by `MainWindowView`, is disabled before login, and is a no-op while another sheet is already presented (`apps/macos/Views/NewPostCommand.swift`). The unmodified `n` shortcut inside a feed keeps opening the composer as before ([[timeline-streaming]]).

The standard **⌘, (設定…)** command is wired the same way. Rather than rely on the default settings group, `SettingsCommands` binds ⌘, to a `FocusedValue`-published `OpenSettingsAction` so it opens the focused window's settings sheet (`MainWindowView` publishes the action; the command is disabled when no window owns it). The settings sheet's tabs include the 通知 tab described in [[notifications]] (`apps/macos/Views/NewPostCommand.swift`).

## Display density (A / B)

Post rows render at one of two densities, selectable in settings, defaulting to **B** (`2026-06-04-yorumimizuku-design.md` §7.2):

- **A (ultra-compact)**: small avatar, 1–2 lines, minimal padding; repost/reply context is a small single line. Optimizes scan-ability — the plain Yorufukurou look.
- **B (comfortable)**: large avatar, thumbnails, and per-post reply/repost/like actions with counts.

The density model is UI-framework-agnostic so it can be unit-tested: `DisplayDensity` (`.compact` / `.comfortable`, default `.comfortable`), `RelativeTimeFormatter` (deterministic short timestamps — "now", "30s", "2m", "3h", "2d"), and `PostDisplay` (the timeline-row view model) all live in `YoruMimizukuKit` and are verified with `swift test`. The SwiftUI `PostRowView` branches on the density value, and the bootstrap app shell was built against mock data (`PostDisplay.samples`) before real fetching landed (`2026-06-04-yorumimizuku-app-shell.md`). Thumbnail and action visibility may become independently toggleable from density (decided at implementation time, §7.2).

## Tabs (sources)

A tab is one of the seven v1 sources (home / notifications / custom feed / list / author / search / thread). Every tab runs under the window's active account, and the tab composition is persisted per window (`2026-06-04-yorumimizuku-design.md` §7.3). The data behind each tab is abstracted by the `TimelineSource` protocol — see [[timeline-streaming]]. Tapping a user's avatar opens a view-only author tab for that user, deduplicated by DID and not persisted — see [[author-tab]].

## Conversation tab (thread view)

Opening a post's conversation anchors the thread on that post: ancestors render above it and replies render below, but only the focused post is interactive — `ThreadViewModel.post(id:)` (`core/Sources/YoruMimizukuKit/ThreadViewModel.swift`) resolves a post only when its id matches the current focus, so like/repost/quote never reach anything else in the tree. Ancestor rows and reply rows are accordingly rendered with `PostRowView(interactiveActions: false)`, which turns their action bar into static labels, and each row is wrapped in a plain button that re-anchors the tab on that post when tapped; this also stands in for the timestamp tap that `interactiveActions: false` otherwise disables (`apps/macos/Views/ConversationView.swift`, `parentBlock` / `replyRow`). [[ipados]] already renders both ancestor and reply rows this way; on macOS the reply rows previously left the action bar live even though it had no effect, until the row was brought in line with the ancestor rows.

## Post row action paths

Every post row's right-click (macOS) or long-press (iPadOS) context menu offers the same three paths regardless of platform: 「リンクをコピー」(copy the public permalink), 「ブラウザで開く」(open that permalink in the default browser), and — only on the viewer's own posts — 「削除」(destructive), which still goes through the existing `confirmationDialog` unchanged (`apps/macos/Views/FeedView.swift`, `apps/ipados/Views/TimelineListView.swift`). On iPadOS the action bar already carries a visible `safari` button wired to the same `onOpenPermalink` closure, so the context-menu entry is a second, more discoverable route to an action that already existed; on macOS there is no visible action-bar Safari button, so the context menu is the only browser-open path for now — adding a visible macOS action-bar button was deliberately left open for later reconsideration (`apps/macos/Views/PostRowView.swift`, `apps/ipados/Views/PostRowView.swift`, `2026-07-24-apple-hig-remediation.md` S6).

## Sidebar / tab UI

The vertical-tab sidebar (home / notifications / conversations / filters) keeps its tab state in `WorkspaceModel` (`@MainActor ObservableObject`), rendered by the `NavigationSplitView` in `MainWindowView`. The `SidebarRow` component is display-only and receives theme colors from `ThemeStore`. Its look and density follow the reference app cmux (`2026-06-05-yorumimizuku-cmux-sidebar.md`):

- Selection is a **solid fill** (`RoundedRectangle(cornerRadius: 6)` in the accent color) with the foreground forced to white, not a faint tint or a left bar.
- Navigation rows (home / notifications) are icon + title; a conversation row is display name (12.5 semibold) + body snippet (11, up to 2 lines) + `@handle` (10 monospaced). A close `xmark` appears top-right on hover only.
- The accent color is left to `ThemeStore` (cmux's `#0091FF` is not forced); only the selected row fixes "accent fill + white text".

Open questions carried in the plan: whether navigation rows show an unread badge (tied to [[notifications]]), and how much metadata a conversation row should carry.

The sidebar ends in a **footer** that doubles as the macOS account switcher: the current avatar + `@handle` open a borderless menu of stored accounts plus add-account / log-out, and a gear button (carrying the update-available dot) opens settings. This is where the design's top-right switcher actually lives on macOS; the menu's behavior and the `summaries()` / `removeAndAdvance(did:)` plumbing are in [[accounts]] (`apps/macos/Views/SidebarView.swift`).

Close/edit are not hover-only: `SidebarRow` also exposes a `.contextMenu` (Control-click or right-click) with the same "フィルターを編集" / "タブを閉じる" actions, and VoiceOver users reach them through `.accessibilityActions` (the row is one combined element labeled with title + subtitle, so a rotor/VO+Command+Space custom-actions sweep surfaces both without needing the hover-revealed icon buttons at all) (`2026-07-24-apple-hig-remediation.md` P0-2).

On [[ipados]], the shell is a separate SwiftUI implementation under
`apps/ipados`. It uses `NavigationSplitView`, visible touch actions, and a simple
search-field path to create saved-search tabs. Hover-only affordances are not
used, and the macOS settings surface (theme / font / display density) is not
replicated yet (`2026-06-08-yorumimizuku-ipados-design.md` §6, [[ipados]]).
