# YoruMimizuku iPadOS Design

- Date: 2026-06-08
- Status: Draft for implementation
- Target: iPadOS app target, separate from the macOS app target

## 1. Overview

The iPadOS version of YoruMimizuku is a native SwiftUI client that reuses the existing Swift core and view-model layer while presenting a touch-first iPad interface. It is not a Mac Catalyst build and does not share the macOS AppKit-bound view files directly. The first iPadOS milestone targets near macOS parity, with iPadOS-specific limitations documented for background execution, OS notifications, and live streaming continuity.

## 2. Goals

- Add a dedicated iPadOS app target under `apps/ipados`.
- Reuse `BlueskyCore`, `YoruMimizukuKit`, and Apple platform adapters wherever they build on iOS.
- Support OAuth login with PKCE + DPoP using `ASWebAuthenticationSession` and the existing `as.ason:/callback` redirect.
- Support the daily client surface: home, notifications, filters/search, author tabs, conversation tabs, posting, replies, quote posts, likes, reposts, image attachment, copy permalink, and open permalink.
- Treat Jetstream as foreground/active-scene live behavior. On background resume, refresh and backfill rather than assuming the stream remained alive.
- Treat OS-level notifications and badges as limited in the MVP unless backed by APIs that work reliably under iPadOS background rules.

## 3. Non-goals

- Do not merge the macOS and iPadOS apps into a universal UI target in this milestone.
- Do not introduce Mac Catalyst.
- Do not add push notifications in this milestone.
- Do not move platform-specific UI code into `YoruMimizukuKit`.
- Do not introduce SwiftData; keep the existing Codable-file and secure-storage direction.

## 4. Architecture

The iPadOS app attaches to the existing ports-and-adapters structure:

- `BlueskyCore` remains UI-independent and owns OAuth, DPoP, XRPC, Jetstream, models, rich text, and write services.
- `YoruMimizukuKit` remains the shared display and view-model layer.
- `PlatformApple` supplies Apple secure storage, random bytes, and signpost tracing where those adapters compile on iOS.
- `apps/ipados` owns UIKit/iPadOS edges such as `UIPasteboard`, `openURL`, `PhotosPicker`, document picking, scene lifecycle, and `ASWebAuthenticationSession` presentation anchoring.

The macOS app keeps using `apps/macos`. iPadOS may copy UI ideas from macOS, but any code shared between the two app folders must first have AppKit/UIKit dependencies pushed to small edge adapters.

## 5. Scene, account, and tabs

Each iPadOS scene owns its own `WorkspaceModel` and active account, matching the macOS per-window model. This allows Stage Manager or multi-window iPad use to show different account/tab contexts side by side. Account sessions remain stored globally through `AccountManager` and secure storage, and token refresh must use the shared `RefreshGate` path so simultaneous scene polling does not race rotated refresh tokens.

Tabs follow the existing model: home, notifications, filters/search, author, and conversation. The iPad shell uses `NavigationSplitView` where possible and collapses to a single-column navigation stack in compact presentations.

## 6. UI principles

The iPadOS UI is touch-first:

- Hover-only affordances are replaced with visible buttons, context menus, or toolbar actions.
- Hardware keyboard shortcuts are supported opportunistically for parity (`j`, `k`, `n`, `f`, `o`) but are not the only way to reach an action.
- Copy permalink uses `UIPasteboard`.
- Open permalink uses SwiftUI's `openURL` environment.
- Image attachment uses `PhotosPicker` and document picker style inputs rather than AppKit drag/drop.
- Compose is presented as a sheet or form-style modal rather than a bottom desktop composer.

Display density uses the shared `DisplayDensity` model. The initial iPad default is comfortable density.

## 7. OAuth

The iPadOS app uses the existing OAuth client metadata and redirect URI:

- `client_id`: `https://ason.as/yorumimizuku/client-metadata.json`
- `redirect_uri`: `as.ason:/callback`
- scopes: `atproto transition:generic`

The browser authorization adapter is iPadOS-specific because the presentation anchor is a `UIWindow`. The token exchange and storage flow remains shared through `BlueskyCore` and `AccountManager`.

## 8. Timeline and Jetstream

Foreground timelines behave like macOS where the underlying source supports it. Home/list Jetstream live updates are allowed while the scene is active. When the app backgrounds, the app should assume the socket may be suspended or closed. On foreground resume, the current tab refreshes and Jetstream-backed sources reconnect through the existing watchdog/backfill behavior.

If follow/list size exceeds Jetstream limits, the existing polling fallback applies.

## 9. Notifications

The in-app notifications tab is in scope and uses the shared `NotificationsViewModel` behavior. App badge or OS banners are limited in the MVP because iPadOS background polling is not guaranteed. The app may update in-app badges while foregrounded and may clear them when the notifications tab becomes active. Push notifications are a separate future spec.

## 10. Compose and images

Posting, replies, quotes, likes, and reposts use the existing write path. Images are capped at four attachments, keep alt text support, and are resized/re-encoded app-side before `uploadBlob` when necessary. The first iPadOS implementation should prefer `PhotosPicker` for photo-library input, with document picking as a follow-up if needed.

## 11. Testing

Core and view-model changes follow Red → Green → Refactor in `core/Tests`. iPadOS app-side logic should keep side effects behind small wrappers where possible:

- pasteboard writer
- URL opener
- image picker/encoder boundary
- browser authorization session

The required smoke verification is an iPad simulator build through XcodeGen-generated schemes. UI behavior that cannot be unit-tested should be verified by simulator smoke testing and documented in the implementation notes.

## 12. Documentation impact

When the iPadOS target lands, add a platform wiki page for iPadOS and update the generated support matrix by changing each behavior page's iOS feature statuses from `planned` to `full`, `differs`, or `limited` as appropriate. Regenerate the wiki index and matrix rather than hand-editing generated files.
