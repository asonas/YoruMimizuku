---
title: App Shell (Window, Tabs, Sidebar)
type: behavior
updated: 2026-06-08
sources:
  - docs/superpowers/specs/2026-06-04-yorumimizuku-design.md
  - docs/superpowers/specs/2026-06-08-yorumimizuku-ipados-design.md
  - docs/superpowers/plans/2026-06-04-yorumimizuku-app-shell.md
  - docs/superpowers/plans/2026-06-05-yorumimizuku-cmux-sidebar.md
features:
  - name: Tabbed single-column shell (sidebar / tabs)
    macos: full
    windows: full
    ios: differs
    android: planned
    note: "iPadOS uses a dedicated touch-first `NavigationSplitView` shell under `apps/ipados`, not the macOS AppKit-chrome view ([[ipados]])."
  - name: Multiple windows
    macos: full
    windows: none
    ios: differs
    android: planned
    note: "macOS opens multiple SwiftUI WindowGroup windows; iPadOS maps the same per-window model to per-scene `WorkspaceModel`, while WinUI is single-window today ([[ipados]], [[windows]])."
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

A window carries an account switcher (top-right of the title bar), a top tab area whose right-edge `+` opens a source picker for a new tab, a single-column feed in the center, and a composer at the bottom (text box + Post). Clicking a post opens its thread (conversation tree). The app is multi-window: it uses SwiftUI `WindowGroup` with per-window state, so each window keeps its own tab set and active account (`2026-06-04-yorumimizuku-design.md` §7.1, §8). Tab composition is persisted per window (§7.3).

The macOS build integrates the window chrome (`.windowStyle(.hiddenTitleBar)`) and ships a two-column default size of 940×720; the brand area is padded to clear the traffic-light buttons (`2026-06-05-yorumimizuku-cmux-sidebar.md`). Apple-specific window wiring lives on the [[macos]] page.

## Display density (A / B)

Post rows render at one of two densities, selectable in settings, defaulting to **B** (`2026-06-04-yorumimizuku-design.md` §7.2):

- **A (ultra-compact)**: small avatar, 1–2 lines, minimal padding; repost/reply context is a small single line. Optimizes scan-ability — the plain Yorufukurou look.
- **B (comfortable)**: large avatar, thumbnails, and per-post reply/repost/like actions with counts.

The density model is UI-framework-agnostic so it can be unit-tested: `DisplayDensity` (`.compact` / `.comfortable`, default `.comfortable`), `RelativeTimeFormatter` (deterministic short timestamps — "now", "30s", "2m", "3h", "2d"), and `PostDisplay` (the timeline-row view model) all live in `YoruMimizukuKit` and are verified with `swift test`. The SwiftUI `PostRowView` branches on the density value, and the bootstrap app shell was built against mock data (`PostDisplay.samples`) before real fetching landed (`2026-06-04-yorumimizuku-app-shell.md`). Thumbnail and action visibility may become independently toggleable from density (decided at implementation time, §7.2).

## Tabs (sources)

A tab is one of the seven v1 sources (home / notifications / custom feed / list / author / search / thread). Every tab runs under the window's active account, and the tab composition is persisted per window (`2026-06-04-yorumimizuku-design.md` §7.3). The data behind each tab is abstracted by the `TimelineSource` protocol — see [[timeline-streaming]]. Tapping a user's avatar opens a view-only author tab for that user, deduplicated by DID and not persisted — see [[author-tab]].

## Sidebar / tab UI

The vertical-tab sidebar (home / notifications / conversations / filters) keeps its tab state in `WorkspaceModel` (`@MainActor ObservableObject`), rendered by the `NavigationSplitView` in `MainWindowView`. The `SidebarRow` component is display-only and receives theme colors from `ThemeStore`. Its look and density follow the reference app cmux (`2026-06-05-yorumimizuku-cmux-sidebar.md`):

- Selection is a **solid fill** (`RoundedRectangle(cornerRadius: 6)` in the accent color) with the foreground forced to white, not a faint tint or a left bar.
- Navigation rows (home / notifications) are icon + title; a conversation row is display name (12.5 semibold) + body snippet (11, up to 2 lines) + `@handle` (10 monospaced). A close `xmark` appears top-right on hover only.
- The accent color is left to `ThemeStore` (cmux's `#0091FF` is not forced); only the selected row fixes "accent fill + white text".

Open questions carried in the plan: whether navigation rows show an unread badge (tied to [[notifications]]), and how much metadata a conversation row should carry.

On [[ipados]], the shell is a separate SwiftUI implementation under
`apps/ipados`. It uses `NavigationSplitView`, visible touch actions, and a simple
search-field path to create saved-search tabs. Hover-only affordances are not
used, and the macOS settings surface (theme / font / display density) is not
replicated yet (`2026-06-08-yorumimizuku-ipados-design.md` §6, [[ipados]]).
