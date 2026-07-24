---
title: Manual Verification Checklist (Apple HIG Remediation)
type: reference
updated: 2026-07-25
sources:
  - docs/superpowers/plans/2026-07-24-apple-hig-remediation.md
---

# Manual Verification Checklist (Apple HIG Remediation)

This page consolidates every device/simulator-only verification item from the Apple HIG remediation plan (`2026-07-24-apple-hig-remediation.md`) — VoiceOver, Accessibility Inspector, Stage Manager, airplane mode, Reduce Motion, and maximum Dynamic Type all require an interactive human session with real hardware or a running simulator, none of which an agent session can drive. Every item below is **still pending human verification** — no agent has executed VoiceOver, Accessibility Inspector, Stage Manager, airplane-mode playback, Reduce Motion, or Dynamic Type checks for this plan. This page is the single consolidated location for that checklist (created by the plan's S8 subproject, which exists specifically to gather it); per-page sections elsewhere in this wiki (see [[app-shell]], [[ipados]], [[macos]], [[compose-post]]) cite the relevant items and link back here rather than duplicating them.

Each subproject's automated coverage (unit tests, snapshot tests) already passed before merge — see the cited page/plan section for what *is* covered. What follows is only the remainder that automated tests cannot reach.

## P0-1 — Conversation reply row degrade (macOS)

See [[app-shell]] "Conversation tab (thread view)".

- [ ] Reply row heart/repost render as static (non-tappable) labels, not live buttons
- [ ] Tapping anywhere on a reply row re-anchors the conversation on that post
- [ ] The focused row's like/repost/quote still work as before
- [ ] Ancestor row behavior has not regressed

## P0-2 — Sidebar keyboard/VoiceOver access (macOS)

See [[app-shell]] "Sidebar / tab UI" and [[macos]] "Accessibility".

- [ ] Control-click / right-click on a filter or conversation-tab row shows a context menu, and its actions work
- [ ] VoiceOver's Actions menu (VO+Command+Space) on a sidebar row surfaces "タブを閉じる" / "フィルターを編集" and executes them
- [ ] Accessibility Inspector shows the row's custom actions and combined label correctly
- [ ] The hover-reveal pencil/xmark icons still appear and work as before (unregressed)

## P0-3 — iPad multi-scene and UIRequiresFullScreen removal

See [[ipados]] "Multi-scene and Stage Manager".

Full verification matrix:

| Scenario | Expected |
|---|---|
| Full screen, portrait/landscape | Unchanged two-column layout, chromeless detail |
| Split View 2/3 or 1/2 (regular width) | Two columns maintained, no layout breakage |
| Split View 1/3 or Slide Over (compact width) | Single column; sidebar ↔ detail navigable via the now-visible nav bar |
| Stage Manager, every window size | Tab selection survives compact ⇄ regular transitions |
| Two scenes open simultaneously (App Exposé, etc.) | Each scene has its own independent `WorkspaceModel`; token refresh via `RefreshGate` does not race between scenes |
| Two scenes on the same account, editing filters/conversation tabs in each | No crash; persistence is last-writer-wins (a documented known limitation, not a bug to fix here) |
| Resizing the window while a composer sheet is open | The sheet is not dismissed/destroyed |
| All four device orientations | All work, including the newly-declared Portrait-Upside-Down |

## P0-4 — Composer draft protection (macOS + iPad)

See [[compose-post]] "Draft discard protection".

macOS:
- [ ] An empty composer closes immediately with no dialog
- [ ] With text or images present, Cancel shows the confirmation dialog ("破棄する" / "編集を続ける")
- [ ] While a post is submitting, Cancel is disabled, Esc does not dismiss, and control returns after the submission completes or fails
- [ ] A quote-only or reply-only composer (no other content) closes without a confirmation dialog

iPad:
- [ ] With content present, swipe-down-to-dismiss is blocked
- [ ] The draft can only be discarded via the confirmation dialog
- [ ] While a post is submitting, Cancel is disabled, swipe dismiss is blocked, and the sheet closes after completion

## S2 — iPad 44pt touch targets

See [[ipados]] "Tap targets and tap accessibility (S2)".

- [ ] Accessibility Inspector's Hit Target overlay confirms the sidebar close `xmark`, the notification-expand `chevron`, and the compact-density avatar all reach 44×44pt
- [ ] Before/after visual comparison of the layout changes introduced by the 44pt `frame` expansions (row height, avatar column width) looks correct, not just "different"

## S4 — macOS new-window command and window titles

See [[app-shell]] "Window layout" and [[macos]] "New windows and window titles".

- [ ] ⇧⌘N opens a new window
- [ ] Mission Control, the Window menu, and the Dock all show a meaningful title (e.g. "ホーム — @handle")
- [ ] The title updates live as the sidebar tab selection changes
- [ ] Switching accounts in a second window achieves real per-window account viewing (design spec §8)

## S5 — iPad video playback failure fallback

See [[ipados]] "Inline video playback (iPad-only, ahead of macOS/Windows)".

- [ ] With the simulator/device in Airplane Mode, playing an HLS video shows the "動画を再生できませんでした" error overlay and its "ブラウザで開く" button opens the post's permalink externally

## P2 — Cross-cutting accessibility and interaction checks

Not tied to a single subproject; apply across the whole app.

- [ ] Animations respect Reduce Motion when enabled in system settings
- [ ] Text wraps correctly at the maximum Dynamic Type size (AX5) without clipping or overlap
- [ ] VoiceOver announces toast notifications (e.g. post-submission confirmations) when they appear, not just when focus happens to land on them
- [ ] iPad floating keyboard and external hardware keyboard do not interfere with or break the Composer's layout or input handling

## Why this can't be automated

`CatalogSnapshotTests` (see [[design-system]]) only renders static component snapshots at a fixed size on a fixed simulator/display; it cannot drive VoiceOver, Accessibility Inspector, Stage Manager window resizing, Airplane Mode, Reduce Motion, or Dynamic Type settings, and there is no UI-automation test target in this repository. Each subproject above shipped with unit/snapshot test coverage where that was possible (cited on its own page) and an explicit "no automated test" note in the plan for the parts that are inherently interactive or environment-dependent — this page exists so those notes are tracked in one place instead of scattered across commit messages and `log.md` entries.
