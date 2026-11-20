# macOS Three-Pane Window Design

- Date: 2026-11-20
- Status: Implemented (PR 1 of the desktop UI update)
- Target: `apps/macos` and a new `YoruMimizukuKit.DetailPaneModel`; `apps/ipados` and `apps/windows` unchanged
- Builds on: `2026-06-04-yorumimizuku-design.md` (tabbed shell), `2026-06-08-yorumimizuku-timeline-ux-enhancements-design.md` (author tab)

## 1. Overview

The macOS window moves from two columns (sidebar + detail, where opening a
conversation or an author replaced the timeline) to three columns: the sidebar,
the selected timeline, and a detail pane. A conversation or author page opens in
the detail pane, so the timeline keeps its scroll position while the reader looks
at a thread. This follows the desktop UI prototype explored on 2026-11-20, whose
first hypothesis was "never lose the reading position".

## 2. Decisions

- The detail pane shows one page at a time with browser-style back / forward.
  The sidebar's conversation tabs and author tabs, and the per-account
  persistence of conversation tabs, are dropped on macOS.
- Author pages open in the detail pane as well, so "back" returns from an author
  to the conversation that led there.
- Hashtags still open a filter in the timeline column; they are a timeline, not a
  page.
- iPadOS keeps the tabbed `WorkspaceModel` unchanged; Windows has its own shell.

## 3. Model

`DetailPaneModel` (`core/Sources/YoruMimizukuKit/DetailPaneModel.swift`) holds the
history as `[DetailEntry]` (`.conversation(ConversationTab)` / `.author(AuthorTab)`)
plus the current index, reusing the existing tab types and their view-model
factories.

- Reopening the page already shown adds no history.
- Opening after going back drops the pages ahead.
- History keeps the latest 30 pages.
- An author feed polls only while its page is shown: the window starts polling
  for the shown author, and the model stops the feed of any author page it
  leaves.
- `close()` empties the pane and its history.
- Pages stay in memory while in the history, so their view models must survive
  being hidden and shown again:
  - A conversation whose load was cancelled because its view went away returns
    to idle, so showing it again loads it instead of an error screen
    (`ThreadViewModel.load`).
  - Restarting polling on an already loaded feed merges fresh posts on top
    instead of reloading, so an author page keeps the older pages already read
    (`TimelineViewModel.startPolling`).
  - Every load carries a generation number, and a newer load supersedes an older
    one: the older one's late result or failure is dropped (`TimelineViewModel`,
    `ThreadViewModel`). A head refresh and an older-page fetch each merge into
    the rows as they are when the response arrives, so finishing out of order
    keeps both.
  - Head-page requests are ordered: a refresh started before the newest applied
    head response is dropped, so it cannot push newer posts down.
  - A refreshed head page that shares no post with the rows held (more than a
    page of new posts arrived while the page was hidden) replaces the rows and
    the cursor, so scrolling continues without a gap.
  - Only `CancellationError` and `URLError.cancelled` count as cancellation; any
    other error is still reported for session expiry.
  - Closing the window stops the shown author's polling.

## 4. Window

- `NavigationSplitView` with sidebar / content / detail columns. Default size
  1240×800, minimum width 900. The timeline column may grow to 960pt so a wide
  window can still reach the media rail layout, which needs a 680pt text region
  (`TimelineLayout.reflowThreshold`).
- The detail pane's top bar has back (⌘[), forward (⌘]) and close.
- The plain-key shortcuts (j / k / f / o / n) belong to the timeline column only.
  A `FeedView` embedded in an author page does not register them, and
  `ConversationView` no longer registers its own f / o.

## 5. Out of scope

Saved feeds and lists in the sidebar, toolbar search, menu commands, list
membership, colors and dark mode, and replacing SF Symbols are separate PRs that
build on this one.
