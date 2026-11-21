---
status: accepted
---

# macOS Commands, Toolbar Search and Curated Lists

- Date: 2026-11-20
- Status: Implemented (PR 3 of the desktop UI update)
- Target: `apps/macos`, `BlueskyCore` (list membership models, listitem record), `YoruMimizukuKit` (`ListMembershipModel`, `WorkspaceModel` search / shortcut tabs / author drop); `apps/ipados` and `apps/windows` unchanged
- Builds on: `0026-macos-three-pane.md`, `0024-macos-saved-feeds-sidebar.md`

## 1. Overview

The window gains the operations a desktop client is expected to have: menu
bar commands with shortcuts, a toolbar search, and two ways to put a person on
one of the viewer's curated lists (the right-click menu and drag and drop).

## 2. Decisions

- **Post menu.** "リストに追加" lists the window account's curated lists
  (`app.bsky.graph.getListsWithMembership`, `purposes=curatelist`) with a
  check where the author is on them, and ends with a note that lists are public.
  Moderation lists are excluded. A menu is built synchronously, so membership
  comes from a cache filled once the pointer rests on a post (0.3 s) or focus
  does (0.5 s), at most once a minute per author; until it is filled the lists
  are shown disabled under "所属を確認中…" rather than as unchecked (per list,
  so a list that appeared later stays unknown). Changes run one at a time per
  account (the windows of an account share one model) and re-read the server
  first, because the PDS accepts duplicate list items; a change made here is
  trusted over a read for 30 s while the appview has not indexed it (a removal
  remembers the removed item, so a different item added elsewhere still shows),
  a read that answers after a newer read or change is dropped, and a list the
  server did not return is not written to. Known limit: if another device
  removes someone within 30 s of this Mac adding them, this Mac still shows them
  on the list until the window passes, since an empty answer cannot be told apart
  from indexing lag.
  Adding creates an `app.bsky.graph.listitem` record (subject = the author's
  DID) and removing deletes it, on the window account's repo.
- **Drag and drop.** A post's avatar drags its author (DID and handle, in the
  app-declared UTType `as.ason.YoruMimizuku.author`; other apps get `@handle`).
  Dropping on one of the window account's own pinned curated lists adds the
  person to it; dropping on a filter adds a `from:` condition. An AND filter
  that already names a person, as a `from:` condition or inside a keyword,
  refuses a second one (two `from:` conditions never both match) and the toast
  says why. An OR filter searches each row on its own, so it gains a row for the
  person unless one row is exactly that person.
- **View menu.** ⌘1…⌘9 select the first nine sidebar rows, in the same order as
  ⌘⇧J/K (home, notifications, pinned feeds, pinned lists, filters).
- **投稿 menu.** Reply ⌘R, repost ⇧⌘R, quote ⌥⌘R, like ⌘L, copy link ⇧⌘C,
  open in browser ⇧⌘O act on the post focused in the timeline column and are
  disabled until a post is focused. The plain-key shortcuts (j/k/f/o/n) stay
  with the timeline column.
- **Toolbar search.** Submitting the search field shows the results in the
  timeline column without saving anything; the header's "フィルターとして保存"
  turns it into a filter. Choosing any sidebar row leaves the search. Filters
  and searches read and write as the window's account, so like and repost work
  in them (before this they had no writer and the buttons did nothing). The
  compose button sits beside the sidebar toggle, because the timeline column
  runs to the top edge and a toolbar item there would cover posts.

## 3. Not in this PR

- Creating or renaming lists, and paging past 100 curated lists.
- Dropping on lists that are not pinned (only pinned lists are in the sidebar).
- iPadOS: the shared model gains `WorkspaceTab.search`, but the iPad app never
  selects it.
