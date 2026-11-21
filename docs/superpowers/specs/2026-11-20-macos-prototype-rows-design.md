# macOS Timeline Rows from the Desktop Prototype

- Date: 2026-11-20
- Status: Implemented (PR 6 of the desktop UI update)
- Target: `apps/macos` (`TimelineRowView`, `FeedView`, menus, muting), `BlueskyCore` (verification, `muteActor`), `YoruMimizukuKit` (`authorIsVerified`, Japanese relative time, `removePosts(byAuthor:)`); `apps/ipados` and `apps/windows` unchanged except the shared repost label
- Builds on: `2026-11-20-macos-prototype-chrome-design.md`

## 1. Overview

Timeline lists (フォロー中, filters, pinned feeds, search, author pages) use the
prototype's compact row. Full media, link cards and quoted posts are read in the
detail pane, which follows the selected row as in the prototype.

## 2. Decisions

- **Row.** A 32pt avatar beside one column: the why-line ("X がリポスト" or
  "@x への返信", 11pt), the header (name, a check for verified authors in the
  proto color, @handle, a Japanese relative time such as "2分"), the body
  clamped to four lines, up to four 64×44 thumbnails (an ALT badge when the
  image has alt text; a play mark on video), tags (sensitive media in the warn
  colors; the quoted author, which opens the quote), and the reactions.
  Rows are separated by an inset line, hidden next to the selection; the
  selected row has a rounded dim fill.
- **Reactions.** Reply, repost (repost / 引用して投稿) and like show a count
  only when above zero; liked is pink and reposted green. 表示 > 反応の数を隠す
  hides the counts (`DisplaySettingsStore.showsReactionCounts`). Copy-link
  leaves the row and stays in the menus.
- **Selection opens the detail pane.** A click selects the row and shows it in
  the detail pane; j/k selection opens it after resting 0.3 s. Any click on a
  row (a quote tag, an avatar, a reaction) cancels a pending j/k open, so an
  explicit navigation is never overridden. (Superseded on 2026-11-21 at the
  user's request: j/k opens the pane at once with the row's post, and only the
  thread fetch waits; see `docs/wiki/behaviors/app-shell.md`.)
- **Muting.** 投稿 > この人をミュート and the row's right-click menu mute the
  author for the window's account (`app.bsky.graph.muteActor`, private to the
  viewer) and drop their posts from every timeline in the window, including the
  author page in the detail pane; fetches already under way are filtered too,
  and an unread boundary on one of their posts moves to the next post. The
  notifications list and an open conversation keep them until reloaded.
- **Density.** The list rows (timelines and author pages) have the
  prototype's fixed sizes; the density setting now applies to conversations in
  the detail pane only (its description says so).
- A list whose first page is only muted posts fetches the next page, and muted
  posts are dropped from author pages anywhere in the detail pane's history.
- Known gap: a j/k open still pending in the timeline (0.3 s) can replace what
  a click inside the detail pane's author page just opened.
- Search results carry no reply parent, so their replies show no
  "@x への返信" line. The Japanese repost label also reaches the Windows app
  through the bridge.
- **Names.** A blank display name falls back to the handle; the repost label is
  Japanese ("X がリポスト"), also on iPadOS.
- Verification is read from `verification.verifiedStatus == "valid"`.

## 3. Not in this PR

- The detail pane's own rebuild (thread tree, レコード tab, reply field) is
  PR 7; until then it keeps the earlier `PostRowView`.
- Records from other AT Protocol apps (the prototype's proto tag) are not
  decoded yet.
