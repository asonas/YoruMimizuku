---
title: Saved-Search Filters
type: behavior
updated: 2026-11-20
sources:
  - docs/adr/0019-macos-commands-and-lists.md
  - docs/adr/0006-filter-tabs.md
  - docs/adr/0007-structured-filters.md
  - docs/adr/0008-ipados.md
  - apps/windows/App/ViewModels/SavedFilterModel.cs
  - apps/windows/App/ViewModels/WorkspaceViewModel.cs
  - apps/windows/App/Views/FilterEditorDialog.xaml.cs
  - apps/windows/App/Services/SavedFilterStore.cs
  - apps/windows/Core/FilterSearch.cs
  - apps/windows/App/MainWindow.xaml.cs
features:
  - name: Saved-search filters (structured terms, AND/OR)
    macos: full
    windows: full
    ios: limited
    android: planned
    note: "iPadOS can create and browse saved keyword search tabs, but the full structured multi-row editor is not present yet ([[ipados]])."
---

# Saved-Search Filters

A filter is effectively a "subscription to a saved search". It fetches `app.bsky.feed.searchPosts` for a user-saved condition and keeps a sidebar tab that reads matching posts, including non-follows. Updates use the same 30-second polling + top-merge + infinite scroll as home; Jetstream is not used ([[timeline-streaming]]). Filters are persisted per-account-DID in a local Codable file (`filters-<DID>.json`), and persistence is abstracted behind the `SavedFilterStoring` port so a future iCloud sync can be swapped in (`0006-filter-tabs.md`).

## First version (filter-tabs)

The first version just passed a single raw query to `searchPosts`. It added `SearchService.searchPosts` (the common 401 → refresh → retry-once pattern) and `SearchResponse` (`posts` / `cursor` / `hitsTotal`) to `BlueskyCore`, and `SavedFilter` plus `SavedFilterStore` (CRUD / validation) to `YoruMimizukuKit`. For display, instead of a dedicated view model, a `LiveSearchLoader` that captures the query conforms to `TimelineLoading` and reuses `TimelineViewModel` as-is (to avoid re-implementing the state machine; filter-tabs §3).

## Extension to structured filters (structured-filters)

The filter was later normalized into **multiple typed condition rows + an AND/OR combinator** (`0007-structured-filters.md`).

- 4 term kinds: `keyword` (value as-is) / `user` (`from:`) / `hashtag` (`#`) / `mention` (`mentions:`). The `@` / `#` prefixes are added/stripped internally.
- Combinator: `AND` / `OR` chosen by a segmented control; default is `AND`.
- `SavedFilter` is structured into `terms: [FilterTerm]` + `combinator`. The old `{ query }` persisted file is auto-migrated via a custom `Decodable` (if `terms` is absent, `terms = [.keyword(query)]`, `combinator = .and`), so existing filters are not broken.

### How AND / OR are realized

`searchPosts` does not support OR (space-separated is implicit AND, and `from:` is a single account). Therefore:

- **AND**: a single `searchPosts` with all fragments space-joined.
- **OR**: run `searchPosts(sort: "latest")` per condition and merge client-side by descending `createdAt`, deduplicated by URI. Infinite scroll is preserved with a `CompositeCursor` (an array of per-subquery cursors aligned to the subquery order), JSON-encoded into `TimelinePage.cursor`.

The pure functions (`SavedFilter.subqueries`, the OR merge, and the `CompositeCursor` codec) live in `YoruMimizukuKit` and are unit-tested; the real network is handled by the app-side `LiveSearchLoader`. `SearchService.searchPosts` gained a backward-compatible `sort` argument.

On [[windows]], `SavedFilterModel` mirrors this structured shape (`terms` plus `combinator`) and passes it as JSON to `IAccountClient.SearchLoadAsync`; the C# core's `SavedFilter` / `FilterSearch` compute and run the subqueries. The WinUI shell has `FilterEditorDialog` for arbitrary multi-row keyword/user/hashtag/mention terms, AND/OR selection, editing existing filters, hashtag-tap creation, and per-account JSON persistence under LocalAppData. OR pagination uses the same composite-cursor shape as macOS: the core decodes per-subquery cursors, skips exhausted subqueries on follow-up pages, merges new pages newest-first, and returns the next encoded cursor (`apps/windows/App/Views/FilterEditorDialog.xaml.cs`, `apps/windows/App/Services/SavedFilterStore.cs`, `apps/windows/Core/FilterSearch.cs`).

On [[ipados]], saved-search tabs use the same `SavedFilterStore`,
`TimelineViewModel`, and `LiveSearchLoader`, but the first touch UI only creates a
single keyword term from the sidebar search field. The persisted shape is still
the structured `SavedFilter`, so adding the full editor later does not require a
data migration (`apps/ipados/Views/RootView.swift`).

## Adding from the macOS window

On macOS a filter can also start as a toolbar search ("フィルターとして保存" in the search results header) and gain people by drag and drop: dropping a post's avatar on a filter row adds a `from:` condition. An AND filter that already has a `from:` condition refuses a second person, because both could never match, and says so in a toast (`WorkspaceModel.addAuthor(handle:toFilter:)`, [[app-shell]]).

## Known limitations

- Because each OR subquery pages independently, **cross-page chronological order is not strict** (a dense subquery runs ahead, and a later page may surface a post newer than ones already shown). Within a single page, descending `createdAt` and URI dedup are guaranteed.
- If a subquery fails in OR mode, the behavior is **fail-fast** (`loadPage` throws as a whole and defers to the existing retry UI). The composite cursor cannot distinguish "not yet fetched (nil) / exhausted (nil) / failed", which would cause a permanently skipped first failure or infinite empty pages — hence the change from the original "partial success" idea.

## Non-goals such as nesting

v1 is flat, single-level; nested AND/OR is out of scope. Additional operator UIs such as `since` / `until` / `lang` / `domain` are non-goals too (a raw keyword row can stand in).
