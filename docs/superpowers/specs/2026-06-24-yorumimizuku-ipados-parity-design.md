# YoruMimizuku iPadOS Timeline Parity Design

- Date: 2026-06-24
- Status: Draft for implementation
- Target: `apps/ipados` (the `YoruMimizukuPad` iOS target)
- Builds on: `2026-06-08-yorumimizuku-ipados-design.md` (the iPad MVP), `2026-06-23-timeline-image-reflow-design.md` (the macOS dev.10–12 timeline work)

## 1. Overview

The iPadOS app already logs in, fetches and refreshes the timeline, posts/replies/quotes,
and shows notifications, conversations, and author tabs. Its **timeline rendering and
rich-media support lag well behind macOS**: rows use default SwiftUI styling, a single
image is forced to a fixed 260 pt box, and link cards, quote cards, video posters,
sensitive-media blur, thread grouping, and the wide-column reflow are all absent.

This spec plans bringing the iPadOS timeline to **behavioral and visual parity with
macOS** — the same `PostRowView` semantics, the same `TimelineLayout`-driven image
crop and reflow, the same themed look — while keeping the macOS app untouched and the
shared core (`BlueskyCore` / `YoruMimizukuKit`) free of platform UI.

## 2. Goals

- Rewrite the iPad `PostRowView` to macOS parity: themed typography/colors, the shared
  `DisplayDensity` (compact / comfortable), single-image 5:4 top-anchored crop with the
  「全体表示」 hint, multi-image grid, video poster, external-link (OGP) card, quote-post
  card, and sensitive-media blur.
- Bring the iPad feed (`TimelineListView`) to parity: web-style thread grouping with the
  avatar connector line, themed canvas + divider, focus highlight, classified load-failure
  states (offline / 429 / 5xx) with retry, empty / loading states, the reply marker, the
  delete-own-post action, and copy-link / open-in-browser.
- Apply the shared `TimelineLayout` wide-column reflow (body left / media right) using the
  scene width — iPad landscape is wide, so this is where it matters most.
- Wire the shared `ThemeStore` and density model into the iPad scene so the look matches
  macOS and survives launches.
- Keep parity at the **behavior** level; iPad remains touch-first (visible buttons and
  context menus instead of hover affordances), per `2026-06-08-yorumimizuku-ipados-design.md` §6.

## 3. Non-goals

- No Mac Catalyst; iPad stays a dedicated SwiftUI target.
- Do not move SwiftUI/UIKit view code into `YoruMimizukuKit` (it stays platform-neutral
  display logic only).
- Do not refactor the macOS app's view files in this milestone (zero risk to the shipped
  dev.12 build). Extracting a shared `AppleUI` SPM module is explicitly a **future
  follow-up**, not this work — see §5.
- The font-family picker (custom UI font) is out of scope for v1 iPad parity; iPad uses the
  default Hiragino face. Theme color (randoma11y) settings UI is optional / lower priority.
- Jetstream live updates stay deferred everywhere (interval polling is the v1 mode), per the
  2026-06-11 decision recorded in the wiki.

## 4. Parity checklist (what differs today)

Derived from reading `apps/ipados/Views/PostRowView.swift`, `TimelineListView.swift`,
`RootView.swift` against their macOS counterparts and `docs/wiki/support-matrix.md`.

| Area | macOS | iPad today | Parity target |
|---|---|---|---|
| Typography / colors | `.app(...)` + `ThemeStore` | SwiftUI defaults | Themed, via ported `ThemeStore` + UIFont typography |
| Display density A/B | shared model | none | Apply `DisplayDensity` (default comfortable) |
| Single image | 5:4 cap, top-anchor, 「全体表示」 | fixed 260 pt `scaledToFill` | `TimelineLayout` crop + hint |
| Multi-image grid | `RemoteImage`, downsampled | `AsyncImage` | `RemoteImage` grid |
| Video poster | yes | dropped | port `VideoPosterView` |
| Link card (OGP) | yes + lazy fallback | dropped | port `LinkCardView` / `LazyLinkCardView` |
| Quote-post card | yes | dropped | port `QuoteCardView` |
| Sensitive-media blur | tap-to-reveal curtain | ungated | port blur curtain |
| Reply marker | 「@x への返信」 | none | add |
| Thread grouping | `FeedThreading.arrange` + connector | flat list | apply |
| Wide reflow | body-left / media-right ≥ 680 pt | none | apply via scene width |
| Focus highlight | `theme.rowHover` + accent bar | blue 8% bg | themed parity |
| Load failures | offline / 429 / 5xx + retry | one generic view | classified states |
| Delete own post | context menu + confirm | none | add |
| Settings (density/theme) | full | none | minimal toggle (lower priority) |
| Structured filters | full editor | keyword only | lower priority |
| Notification settings | interval/badge | none | lower priority |

## 5. Architecture decision — duplicate vs. share

The macOS presentation foundation is **almost entirely platform-neutral SwiftUI**, which
makes parity cheap:

- **No AppKit at all:** `Theme.swift` (`ThemeStore`), `Media/RemoteImage.swift`,
  `Media/ImageDownsampler.swift` (CoreGraphics/ImageIO, emits a `CGImage`),
  `Views/LinkCardView.swift`, `Views/QuoteCardView.swift`, `Views/VideoPosterView.swift`,
  `Views/ImageLightboxView.swift`, and the density half of `DisplaySettings.swift`.
- **AppKit-bound (the only real blocker):** `Typography.swift` and the font-picker half of
  `DisplaySettings.swift` use `NSFont` / `NSFontManager`. `NSFont.preferredFont(forTextStyle:)`
  has a direct `UIFont.preferredFont(forTextStyle:)` equivalent.

Two ways to reach parity:

- **(A) Duplicate into `apps/ipados`** — copy the AppKit-free files verbatim and add an iOS
  `Typography` using `UIFont`. Fast, **zero risk to the shipped macOS app**, no cross-module
  churn. Cost: ~7 small stable files duplicated (tracked tech debt).
- **(B) Extract a shared `AppleUI` SPM target** — move the neutral files into a new
  Apple-only SwiftUI library both apps import, with `#if canImport(UIKit)` in `Typography`.
  Architecturally cleaner (no drift) but touches ~20 macOS view files (every `ThemeStore`
  reference needs the new `import`), risking the released build.

**Decision: (A) for this milestone, (B) as a recorded follow-up.** The duplicated files are
small and behaviorally frozen; the macOS app must not regress. Once iPad parity ships and
both apps are stable, a separate refactor can lift the shared files into `AppleUI` and delete
the duplicates. This keeps each step low-risk and reviewable.

> Open decision for the human partner to confirm before implementation: accept (A) duplicate-now /
> extract-later, or prefer (B) shared module up front.

## 6. Phasing

- **Phase 0 — Presentation foundation on iPad.** Baseline simulator build; copy `ThemeStore`,
  density store, `RemoteImage`, `ImageDownsampler` into `apps/ipados`; add a UIFont-based
  `Typography` (`Font.app(...)`); wire `ThemeStore` + density as environment objects at the
  scene root and apply `theme.canvas`. Verify `PlatformApple` compiles for iOS.
- **Phase 1 — Row + media parity.** Port the four card/lightbox views; rewrite the iPad
  `PostRowView` to the macOS structure (themed, density, 5:4 crop + hint, `RemoteImage` grid,
  video poster, link card + lazy OGP, quote card, sensitive blur, reply marker, context label,
  action bar, copy-link, delete context menu).
- **Phase 2 — Feed shell parity.** `FeedThreading.arrange` thread grouping + connector line +
  divider rules; themed canvas/focus highlight; classified load-failure / empty / loading
  states; delete confirmation dialog; scene-width measurement → `TimelineLayout` reflow.
- **Phase 3 — Settings & remaining features (lower priority).** Density toggle UI, optional
  theme settings, structured filter editor, notification settings. Detailed only after
  Phases 0–2 land.
- **Phase 4 — Docs & verification.** Update `docs/wiki/platforms/ipados.md` and flip the iOS
  cells on the behavior pages; regenerate the support matrix and index; iPad-simulator smoke
  build.

The detailed, code-level task list lives in the companion plan
(`docs/superpowers/plans/2026-06-24-yorumimizuku-ipados-parity.md`). Phases 0–2 are specified
task-by-task; Phases 3–4 are outlined and elaborated once the foundation lands, since their
exact shape depends on how the ported foundation settles.

## 7. Testing

- Pure layout / threading logic already lives in `YoruMimizukuKit` (`TimelineLayout`,
  `FeedThreading`) and is unit-tested there; the iPad views consume it without new core tests.
- iPad app-side side effects stay behind the existing small wrappers (pasteboard, URL opener,
  image encoder, browser session) per `2026-06-08-yorumimizuku-ipados-design.md` §11.
- Each phase ends with an iPad-simulator build through the XcodeGen scheme:
  `xcodebuild build -scheme YoruMimizukuPad -project YoruMimizuku.xcodeproj -destination 'generic/platform=iOS Simulator'`.
- Visual behavior that cannot be unit-tested is verified by simulator smoke testing and noted
  in the implementation notes.

## 8. Documentation impact

When parity lands, update `docs/wiki/platforms/ipados.md`'s "Known differences" and flip the
iOS feature statuses on the behavior pages (`timeline-media-layout`, `timeline-streaming`,
`sensitive-media`, `app-shell`) from `none`/`differs` toward `full`/`differs` as appropriate,
then regenerate the matrix and index (`mise run wiki:matrix`, `mise run wiki:index`) — never
hand-edit the generated files.
