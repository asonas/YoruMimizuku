---
title: Saved-Search Filters
type: behavior
updated: 2026-06-06
sources:
  - docs/superpowers/specs/2026-06-05-yorumimizuku-filter-tabs-design.md
  - docs/superpowers/specs/2026-06-05-yorumimizuku-structured-filters-design.md
  - docs/superpowers/plans/2026-06-05-yorumimizuku-filter-tabs.md
  - docs/superpowers/plans/2026-06-05-yorumimizuku-structured-filters.md
---

# Saved-Search Filters

A filter is effectively a "subscription to a saved search". It fetches `app.bsky.feed.searchPosts` for a user-saved condition and keeps a sidebar tab that reads matching posts, including non-follows. Updates use the same 30-second polling + top-merge + infinite scroll as home; Jetstream is not used ([[timeline-streaming]]). Filters are persisted per-account-DID in a local Codable file (`filters-<DID>.json`), and persistence is abstracted behind the `SavedFilterStoring` port so a future iCloud sync can be swapped in (`2026-06-05-yorumimizuku-filter-tabs-design.md`).

## First version (filter-tabs)

The first version just passed a single raw query to `searchPosts`. It added `SearchService.searchPosts` (the common 401 → refresh → retry-once pattern) and `SearchResponse` (`posts` / `cursor` / `hitsTotal`) to `BlueskyCore`, and `SavedFilter` plus `SavedFilterStore` (CRUD / validation) to `YoruMimizukuKit`. For display, instead of a dedicated view model, a `LiveSearchLoader` that captures the query conforms to `TimelineLoading` and reuses `TimelineViewModel` as-is (to avoid re-implementing the state machine; filter-tabs §3).

## Extension to structured filters (structured-filters)

The filter was later normalized into **multiple typed condition rows + an AND/OR combinator** (`2026-06-05-yorumimizuku-structured-filters-design.md`).

- 4 term kinds: `keyword` (value as-is) / `user` (`from:`) / `hashtag` (`#`) / `mention` (`mentions:`). The `@` / `#` prefixes are added/stripped internally.
- Combinator: `AND` / `OR` chosen by a segmented control; default is `AND`.
- `SavedFilter` is structured into `terms: [FilterTerm]` + `combinator`. The old `{ query }` persisted file is auto-migrated via a custom `Decodable` (if `terms` is absent, `terms = [.keyword(query)]`, `combinator = .and`), so existing filters are not broken.

### How AND / OR are realized

`searchPosts` does not support OR (space-separated is implicit AND, and `from:` is a single account). Therefore:

- **AND**: a single `searchPosts` with all fragments space-joined.
- **OR**: run `searchPosts(sort: "latest")` per condition and merge client-side by descending `createdAt`, deduplicated by URI. Infinite scroll is preserved with a `CompositeCursor` (an array of per-subquery cursors aligned to the subquery order), JSON-encoded into `TimelinePage.cursor`.

The pure functions (`SavedFilter.subqueries`, the OR merge, and the `CompositeCursor` codec) live in `YoruMimizukuKit` and are unit-tested; the real network is handled by the app-side `LiveSearchLoader`. `SearchService.searchPosts` gained a backward-compatible `sort` argument.

## Known limitations

- Because each OR subquery pages independently, **cross-page chronological order is not strict** (a dense subquery runs ahead, and a later page may surface a post newer than ones already shown). Within a single page, descending `createdAt` and URI dedup are guaranteed.
- If a subquery fails in OR mode, the behavior is **fail-fast** (`loadPage` throws as a whole and defers to the existing retry UI). The composite cursor cannot distinguish "not yet fetched (nil) / exhausted (nil) / failed", which would cause a permanently skipped first failure or infinite empty pages — hence the change from the original "partial success" idea.

## Non-goals such as nesting

v1 is flat, single-level; nested AND/OR is out of scope. Additional operator UIs such as `since` / `until` / `lang` / `domain` are non-goals too (a raw keyword row can stand in).
