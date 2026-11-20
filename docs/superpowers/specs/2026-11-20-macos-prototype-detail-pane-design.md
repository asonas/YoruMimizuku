# macOS Detail Pane from the Desktop Prototype

- Date: 2026-11-20
- Status: Implemented (PR 7 of the desktop UI update)
- Target: `apps/macos` (`DetailPaneView`, `ConversationView`, reply field, record loading), `YoruMimizukuKit` (`DetailPaneModel`), `BlueskyCore` (`RecordResponse`, `JSONValue`); `apps/ipados` and `apps/windows` unchanged
- Builds on: `2026-11-20-macos-three-pane-design.md`, `2026-11-20-macos-prototype-rows-design.md`

## 1. Overview

The detail pane follows the desktop prototype: a 38pt bar with close, the
title and the スレッド / レコード switch; the thread with the anchor post at full
size and the replies as an indented tree; the record as stored; and a reply
field at the bottom.

## 2. Decisions

- **One page at a time.** As the user decided, the pane drops the back/forward
  history of PR 1 (and ⌘[ / ⌘]): `DetailPaneModel` holds the shown page only,
  opening another replaces it, and close (×) empties it.
- **スレッド.** Ancestors as compact rows (each re-anchors the pane), then the
  anchor: 38pt avatar, name with the verified check, "@handle ・ time", the body
  at 15.5pt (selectable), a warn box with 表示する / 隠す for labeled media,
  full-width images with their alt text under them, video, link card, a quote
  box, and the counts (reply, repost, like, which also act, and copy link).
  Replies are indented 20pt per level with a 24pt avatar, a connector line and
  a fold control showing the folded count; a subtree cut at the depth limit
  offers さらに表示, which re-anchors.
- **レコード.** Handle, DID, URI (and the media label), then the record fetched
  with `com.atproto.repo.getRecord` and pretty-printed with sorted keys.
  投稿 > レコードを表示 (⌥⌘I) opens the selected post on this tab; any other
  newly opened page starts on its thread.
- **Reply field.** Under a loaded conversation; return sends a short reply to
  the anchor as the window's composer would and reloads the thread, and the
  button opens the full composer with what was typed.
- Author pages keep their content, with the bar's title showing the name; a
  conversation's title is its anchor's author.
- Replies and quotes from the composer and the reply field are posted as the
  window's account (`LiveComposer` gets the window's DID); a reply only reloads
  the conversation it was sent from.
- The anchor keeps the lazily resolved link card for a bare link and the full
  quote card with its media; its body is not selectable, because selection on
  linked text blanks the links after a relayout.
- In timeline rows a click on the name, why-line or body text also selects the
  row and opens it here (text otherwise takes the click before the row).

## 3. Not in this PR

- Records from other AT Protocol apps embedded in posts.
- Re-recording the catalog snapshots (light and dark) now that the rows and
  the pane are rebuilt.
