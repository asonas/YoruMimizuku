# macOS Colors and Dark Mode from the Desktop Prototype

- Date: 2026-11-20
- Status: Implemented (PR 4 of the desktop UI update)
- Target: `YoruMimizukuKit` (`DesignTokens`, `PaletteColor` luminance, `ThemePalette.oriented`), `apps/macos` (`ThemeStore`, settings, typography default); `apps/ipados` and `apps/windows` unchanged
- Builds on: `2026-11-20-macos-three-pane-design.md`

## 1. Overview

From this PR the desktop prototype (Lenses, transferred to Figma) is the visual
source of truth for the macOS window. Its color tokens replace the monochrome
"Nocturne" palette, in a light and a dark set that follow the system appearance.

## 2. Decisions

- `DesignTokens.light` / `.dark` hold the prototype's tokens: content, chrome,
  side, fg / fg2 / fg3, separator, hover, selection, accent (system blue
  `#0068da` / `#2f8cff`) with its foreground and tint, like, repost, warn, proto
  and field. `ThemeStore` resolves each color per appearance at draw time
  (dynamic `NSColor`), so switching appearance needs no state.
- fg3 is `#6e6e73` (light) / `#8e8e93` (dark) instead of the prototype's
  `#85858b` / `#7f7f85`, which fall below WCAG AA's 4.5:1 for small text; a test
  checks every text token on the content background in both appearances.
- A randoma11y URL replaces only the background and text (and the neutrals
  derived from them). The pair is oriented to the appearance: the lighter color
  is the background in light and the darker one in dark, which randoma11y pairs
  allow because they read at the same contrast either way. The accent and
  reaction colors stay the prototype's. The "swap" button is gone.
- Like is the prototype's pink and repost its green, instead of gray.
- The default font is the system font (San Francisco, with Hiragino for
  Japanese) at body 14pt, as in the prototype. A family the user chose is kept;
  "システム" is added to the family picker.
- Debug builds accept `-YMAppearance dark|light` to check a theme without
  switching the whole system.

## 3. Not in this PR

- The prototype's toolbar, sidebar, row and detail-pane parts (PR 5 to 7).
- Re-recording the catalog snapshots, deferred until the rows and panes are
  rebuilt in PR 6 and 7.
