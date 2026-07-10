# iPadOS Parity — Phase 3 (settings, filter editor, post affordances, notification expansion)

Status: In progress (2026-07-10)

Fulfills the deferred follow-ups noted in:
- `docs/superpowers/specs/2026-06-24-yorumimizuku-ipados-parity-design.md` (§3 settings surface, Phase 3)
- `docs/superpowers/plans/2026-07-02-post-interaction-affordances.md` ("Follow-up": bring mention-tap / copy-link toast to iPad)

Branch: `feature/ipad-parity-phase3`. Single branch, commit-per-feature.

## Scope

Bring the iPadOS app closer to macOS parity on four surfaces. All four need **no core (`YoruMimizukuKit`) changes** — the shared models, stores' backing models, `ToastCenter`, `RichText`, `WorkspaceModel`, and `NotificationGroup` grouping already exist and are consumed by the iPad target. The work is confined to `apps/ipados`.

Out of scope (explicit decisions):
- **Sparkle / update settings tab** — iPad ships via TestFlight; no update mechanism.
- **hover performance layer (`.equatable()` / hover highlight)** — iPad is tap-first; intentionally omitted.
- **Font *size* control** — deferred. Reviving the `baseSize` machinery that `apps/ipados/Typography.swift:9-13` intentionally stubbed out is invasive. The font tab ships **family-only** (via `UIFont.familyNames`); the body-size stepper is the remaining settings gap. (User decision 2026-07-10.)
- **Timestamp-only re-anchor (affordance B)** — **already covered** on iPad: the whole row taps through to `workspace.openConversation` (`apps/ipados/Views/PostRowView.swift:105`). Narrowing to the timestamp would regress the broader touch affordance. No change; documented.
- **Video upload** — already implemented on iPad (`d705ca7`); only the wiki record is stale.

## Verification strategy

- Primary: `xcodebuild build -scheme YoruMimizukuPad -destination 'generic/platform=iOS Simulator'` stays green under Swift 6 strict concurrency after each feature.
- `NotificationSettingsStore` gets a unit test (genuine persistence/clamping logic) — TDD red→green — in `apps/ipadosTests`, added to the `YoruMimizukuPadTests` source list in `project.yml`.
- Notification expansion: add a catalog snapshot variant (collapsed multi-actor vs expanded) where cheap; otherwise rely on build + manual check.
- Core logic already unit-tested and reused as-is: `ToastCenter` (`ToastCenterTests`), `SavedFilter.subqueries`, `RichText.mentionDID`, `NotificationGroup.group`.

## Feature 1 — Post interaction affordances (mention tap + copy-link toast)

Test list:
- [ ] Tapping a body `@mention` link opens an author tab instead of the browser.
- [ ] Copying a post's permalink shows a "リンクをコピーしました" toast that auto-dismisses.

Steps:
1. `apps/ipados/Views/RootView.swift` — add a mention branch to the existing `OpenURLAction` closure (currently hashtag-only, ~line 354): `if let did = RichText.mentionDID(from: url) { workspace.openAuthor(did: did, handle: "", displayName: "", avatarURL: nil); return .handled }`. Mirrors `apps/macos/Views/MainWindowView.swift:152-158`.
2. Add `apps/ipados/Views/ToastView.swift` — twin of `apps/macos/Views/ToastView.swift` (pure SwiftUI over the shared `ThemeStore`).
3. `RootView` — add `@StateObject private var toastCenter = ToastCenter()`, a bottom `.overlay(alignment: .bottom)` toast host (sibling of the lightbox overlay, mirroring `MainWindowView.swift:68-76`), and call `toastCenter.show("リンクをコピーしました")` from `copyPermalink(_:)`. No env-object plumbing needed — `copyPermalink` lives in `RootView` on iPad.
4. Build green.

## Feature 2 — Notification actor expansion

Test list:
- [ ] A grouped like/repost row with >1 actor shows a chevron toggle; tapping expands into a per-actor list and collapses back.
- [ ] Single-actor rows show no toggle.

Steps:
1. `apps/ipados/Views/NotificationsListView.swift` — in the private `NotificationRowView`, add `@State isExpanded`, `canExpand = actors.count > 1`, swap the fixed avatar strip for collapsed `avatarRow` vs expanded `actorList`, add an `expandToggle` chevron. Port the layout from `apps/macos/Views/NotificationsView.swift:150-185`. Keep the iPad `List` structure and `RemoteAvatar`/`Button` tap convention; drop macOS `.help(...)` tooltips.
2. (Optional) Register a notification-row catalog variant for a snapshot of collapsed vs expanded.
3. Build green.

## Feature 3 — Structured filter editor

Test list:
- [ ] The Filters "+" opens a structured editor (multi-row terms, kind picker, AND/OR combinator) instead of the single keyword field.
- [ ] Saving with a blank name falls back to the generated `fallbackName`.
- [ ] An existing filter row can be edited and re-saved.

Steps:
1. Add `apps/ipados/Views/FilterEditorView.swift` — port `apps/macos/Views/FilterEditorView.swift` verbatim, dropping `.frame(width: 460)`; adjust padding for an iPad sheet. Same `onSubmit: (String, [FilterTerm], FilterCombinator) -> Void` signature; compiles against shared `YoruMimizukuKit` + iPad `ThemeStore`.
2. `RootView` — add `EditorRequest { case new; case edit(SavedFilter) }` + `@State editorRequest` + `.sheet(item:)` mapping `.new`→`addFilter`, `.edit`→`updateFilter` with `fallbackName` (mirror `apps/macos/Views/SidebarView.swift:34-77`). Change the "+" to open `.new`; add an edit affordance to filter rows via `workspace.savedFilter(id:)`.
3. Keep the inline quick keyword field or retire it (decide during impl; keep for now as a fast path).
4. Build green.

## Feature 4 — Settings screen

Test list:
- [ ] `NotificationSettingsStore` persists poll interval and unread-badge toggle; interval is one of the allowed choices. (unit test)
- [ ] A gear entry opens a settings sheet with 配色 / 表示 / 通知 tabs.
- [ ] Changing the poll interval restarts polling; toggling badges off hides sidebar badges.

Steps:
1. Add `apps/ipados/NotificationSettings.swift` — verbatim copy of `apps/macos/NotificationSettings.swift` (no framework deps). Add to `YoruMimizukuPadTests` sources in `project.yml`. Write the unit test first (red), then confirm green.
2. Add `apps/ipados/Views/SettingsView.swift` — iPad-native `NavigationStack` + `Form`/`List` (not the macOS fixed 640×440 two-pane). Tabs: 配色 (randoma11y `ThemeStore`), 表示 (`DisplaySettingsStore` density), 通知 (`NotificationSettingsStore` interval + badge toggle), フォント (family-only via `UIFont.familyNames`, no size stepper — needs a `FontSettingsStore` iPad variant that drives `AppTypography`'s family). No update tab.
3. `RootView` — add `@StateObject notificationSettings`, inject `.environmentObject` (main + add-account sheet), add a `gearshape` entry (sidebar toolbar next to compose, or account section), a `.sheet(isPresented: $showsSettings)`. Drive polling from `notificationSettings.pollIntervalSeconds` (replace hardcoded `.seconds(30)`, add `onChange` restart mirroring `MainWindowView.swift:100`), and gate sidebar badges on `showsUnreadBadges`.
4. Build green.

## Feature 5 — Regenerate project + update wiki

1. `xcodegen generate` (new files under `apps/ipados`).
2. Update `docs/wiki/platforms/ipados.md`:
   - Correct the compose record — video upload is implemented (parity with macOS).
   - Move settings surface, structured filter editor, mention-tap + copy-link toast, and notification actor expansion out of "Known differences" into the parity sections.
   - Keep as remaining differences: font settings tab (deferred), Jetstream live updates (interval polling everywhere), timestamp-only re-anchor (iPad uses whole-row tap by design), OS banners / app badge.
3. `mise run wiki:lint` and `mise run wiki:index`.
