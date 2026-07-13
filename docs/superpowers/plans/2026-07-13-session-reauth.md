# Session Expiry Re-authentication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On OAuth session expiry, keep the account and offer a one-step re-authentication of the same account instead of deleting it and forcing a full re-add.

**Architecture:** A pure helper in `YoruMimizukuKit` turns an expiry event into a re-auth intent (idempotent). Each app's `RootView` holds the intent as in-memory state, auto-presents a handle-pre-filled login sheet, keeps a stale-timeline banner as the cancel fallback, and on success rebuilds the authenticated subtree via a generation-stamped `.id`. Core (`SessionExpiry`, `RefreshGate`, `AccountManager`) is unchanged.

**Tech Stack:** Swift 6.0, SwiftUI (macOS + iPadOS), XCTest, XcodeGen, `os.Logger`.

**Spec:** `docs/superpowers/specs/2026-07-13-session-reauth-design.md`

## Global Constraints

- Swift 6.0 / strict concurrency; `LoginViewModel` and views are `@MainActor`.
- Never log token material (access/refresh token, code, DPoP key). Log DID/handle only.
- `YoruMimizukuKit` stays UI-framework-free (no SwiftUI/AppKit/UIKit imports); the pure helper lives there, all SwiftUI wiring lives in `apps/`.
- Do not change `SessionExpiry`'s detection rule (`invalid_grant` only) or `AccountManager`.
- User-initiated logout keeps deleting via `removeAndAdvance` — only the expiry path changes.
- After editing `project.yml`, run `xcodegen generate` before building.
- Commit with `git ai-commit` (English message, capitalized, not Conventional Commits).
- Run `cd core && swift test` for core tests; build apps with `xcodebuild`.

---

### Task 1: Pure re-auth decision helper (`SessionReauth`)

**Files:**
- Create: `core/Sources/YoruMimizukuKit/SessionReauth.swift`
- Test: `core/Tests/YoruMimizukuKitTests/SessionReauthTests.swift`

**Interfaces:**
- Produces:
  - `struct ReauthRequest: Equatable, Sendable { let did: String; let handle: String }`
  - `enum SessionReauth { static func onExpiry(currentDID: String?, currentHandle: String?, isPending: Bool) -> ReauthRequest? }`

- [ ] **Step 1: Write the failing tests**

Create `core/Tests/YoruMimizukuKitTests/SessionReauthTests.swift`:

```swift
import XCTest
@testable import YoruMimizukuKit

final class SessionReauthTests: XCTestCase {
    func testFirstExpiryProducesRequestForCurrentAccount() {
        let req = SessionReauth.onExpiry(currentDID: "did:plc:alice", currentHandle: "alice.bsky.social", isPending: false)
        XCTAssertEqual(req, ReauthRequest(did: "did:plc:alice", handle: "alice.bsky.social"))
    }

    func testExpiryWhileAlreadyPendingIsNoOp() {
        let req = SessionReauth.onExpiry(currentDID: "did:plc:alice", currentHandle: "alice.bsky.social", isPending: true)
        XCTAssertNil(req)
    }

    func testExpiryWithNoCurrentAccountIsNoOp() {
        let req = SessionReauth.onExpiry(currentDID: nil, currentHandle: nil, isPending: false)
        XCTAssertNil(req)
    }

    func testNilHandleFallsBackToEmptyString() {
        let req = SessionReauth.onExpiry(currentDID: "did:plc:alice", currentHandle: nil, isPending: false)
        XCTAssertEqual(req, ReauthRequest(did: "did:plc:alice", handle: ""))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd core && swift test --filter SessionReauthTests`
Expected: FAIL — `cannot find 'SessionReauth' in scope` / `ReauthRequest`.

- [ ] **Step 3: Write minimal implementation**

Create `core/Sources/YoruMimizukuKit/SessionReauth.swift`:

```swift
import Foundation

/// A request to re-authenticate an existing account whose OAuth session expired.
/// `handle` pre-fills the login field (empty when the stored account has no handle).
public struct ReauthRequest: Equatable, Sendable {
    public let did: String
    public let handle: String

    public init(did: String, handle: String) {
        self.did = did
        self.handle = handle
    }
}

/// Pure decision for turning a session-expiry event into a re-auth intent. Kept
/// UI-free and out of the views so the idempotency rule is unit-testable.
public enum SessionReauth {
    /// The re-auth request to present, or nil for a no-op. Returns nil when a
    /// re-auth is already pending (so repeated poll-driven `invalid_grant`
    /// notifications never re-present the sheet) or when there is no current
    /// account. A nil handle pre-fills as empty text.
    public static func onExpiry(currentDID: String?, currentHandle: String?, isPending: Bool) -> ReauthRequest? {
        guard !isPending, let did = currentDID else { return nil }
        return ReauthRequest(did: did, handle: currentHandle ?? "")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd core && swift test --filter SessionReauthTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add core/Sources/YoruMimizukuKit/SessionReauth.swift core/Tests/YoruMimizukuKitTests/SessionReauthTests.swift
git ai-commit
```
Message: `Add pure session re-auth decision helper`

---

### Task 2: macOS re-auth banner view + render test

**Files:**
- Create: `apps/macos/Views/SessionReauthBanner.swift`
- Create: `apps/macosTests/SessionReauthBannerRenderTests.swift`
- Modify: `project.yml` (add the banner source to the `YoruMimizukuTests` target)

**Interfaces:**
- Consumes: `ThemeStore` (existing, from `YoruMimizukuKit`, injected as an `@EnvironmentObject`).
- Produces: `struct SessionReauthBanner: View { init(onReauth: @escaping () -> Void) }`

- [ ] **Step 1: Write the banner view**

Create `apps/macos/Views/SessionReauthBanner.swift`:

```swift
import SwiftUI
import YoruMimizukuKit

/// A slim banner shown above the timeline while the current account's session is
/// expired and awaiting re-authentication. Tapping "再ログイン" re-opens the login
/// sheet. Kept as a standalone view so it renders in isolation for tests.
struct SessionReauthBanner: View {
    let onReauth: () -> Void
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.accent)
            Text("セッションが期限切れです")
                .font(.app(.caption))
                .foregroundStyle(theme.primaryText)
            Spacer(minLength: 8)
            Button("再ログイン", action: onReauth)
                .font(.app(.caption))
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.surface)
        .overlay(alignment: .bottom) { Divider().overlay(theme.divider) }
    }
}
```

- [ ] **Step 2: Add the banner source to the macOS test target**

In `project.yml`, under `targets: YoruMimizukuTests: sources:`, add the line (alongside the existing `apps/macos/Views/ToastView.swift` etc.):

```yaml
      - apps/macos/Views/SessionReauthBanner.swift
```

- [ ] **Step 3: Write the failing render test**

Create `apps/macosTests/SessionReauthBannerRenderTests.swift`:

```swift
import XCTest
import SwiftUI
import YoruMimizukuKit
@testable import YoruMimizuku

/// Renders the banner in a hosting view with its environment object, catching a
/// missing-EnvironmentObject crash the way SettingsRenderTests does for settings.
@MainActor
final class SessionReauthBannerRenderTests: XCTestCase {
    func testBannerRendersWithThemeStore() {
        var tapped = false
        let banner = SessionReauthBanner(onReauth: { tapped = true })
            .environmentObject(ThemeStore())
        let host = NSHostingView(rootView: banner)
        host.frame = NSRect(x: 0, y: 0, width: 480, height: 44)
        host.layoutSubtreeIfNeeded()
        XCTAssertFalse(tapped) // rendering must not fire the action
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }
}
```

- [ ] **Step 4: Regenerate the project and run the test to verify it fails, then passes**

Run:
```bash
xcodegen generate
xcodebuild test -scheme YoruMimizuku -project YoruMimizuku.xcodeproj -destination 'platform=macOS' -only-testing:YoruMimizukuTests/SessionReauthBannerRenderTests 2>&1 | tail -15
```
Expected: the test compiles (banner exists) and PASSES. (If the banner file were missing it would fail to build — this test exists to lock the env-object contract and rendering.)

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Views/SessionReauthBanner.swift apps/macosTests/SessionReauthBannerRenderTests.swift project.yml
git ai-commit
```
Message: `Add macOS session re-auth banner`

---

### Task 3: macOS RootView wiring (keep account, present re-auth, rebuild on success)

**Files:**
- Modify: `apps/macos/Views/RootView.swift`

**Interfaces:**
- Consumes: `SessionReauth.onExpiry(...)` and `ReauthRequest` (Task 1); `SessionReauthBanner` (Task 2); existing `LoginViewModel`, `LiveLoginPerformer`, `AccountManager`.

Current relevant code (`apps/macos/Views/RootView.swift`):
- `body` wraps `Group { if let did = currentDID { AuthenticatedRootView(...).id(did)... } else { LoginView... } }` then modifiers including `.onReceive(...SessionExpiry.notification) { handleSessionExpired() }` and the `isAddingAccount` sheet.
- `private func handleSessionExpired() { guard let did = currentDID else { return }; currentDID = (try? accountManager.removeAndAdvance(did: did)) ?? nil }`
- `refreshSessionOnWake()` logs `"Session expired while asleep; dropping the account"` in its `invalid_grant` branch.

- [ ] **Step 1: Add re-auth state and a dedicated login model**

In `RootView` (macOS), add these stored properties next to the existing `@State`/`@StateObject` declarations (near `isAddingAccount` / `loginModel`):

```swift
    /// The pending re-auth request for the expired current account (nil when the
    /// session is healthy). Persists across a sheet cancel so the banner stays.
    @State private var reauth: ReauthRequest?
    /// Drives the re-auth login sheet; separate from `isAddingAccount` so the two
    /// flows never interfere.
    @State private var isReauthSheetShown = false
    /// Bumped on each successful re-auth and folded into the authenticated
    /// subtree's `.id`, forcing an immediate rebuild + fresh load with new tokens.
    @State private var reauthGeneration = 0
    /// A login model dedicated to re-auth, pre-filled with the expired handle.
    @StateObject private var reauthLoginModel: LoginViewModel
```

And in `init()`, after the existing `_loginModel = StateObject(...)` line, initialize it (the manager local is already in scope as `manager`):

```swift
        _reauthLoginModel = StateObject(
            wrappedValue: LoginViewModel(performer: LiveLoginPerformer(accountManager: manager))
        )
```

- [ ] **Step 2: Wrap the body in a banner + generation-stamped id**

Replace the `body`'s outer `Group { ... }` so the banner sits above it and the authenticated subtree's id includes the generation. Change:

```swift
    var body: some View {
        Group {
            if let did = currentDID {
                AuthenticatedRootView(
                    ...
                )
                .id(did)
                .task(id: currentDID) { await loadAvatar() }
            } else {
                LoginView(model: loginModel) { did in
                    currentDID = did
                }
            }
        }
```

to:

```swift
    var body: some View {
        VStack(spacing: 0) {
            if reauth != nil {
                SessionReauthBanner(onReauth: { isReauthSheetShown = true })
            }
            Group {
                if let did = currentDID {
                    AuthenticatedRootView(
                        ...
                    )
                    .id("\(did)#\(reauthGeneration)")
                    .task(id: currentDID) { await loadAvatar() }
                } else {
                    LoginView(model: loginModel) { did in
                        currentDID = did
                    }
                }
            }
        }
```

(Leave the `AuthenticatedRootView(...)` argument list exactly as it is; only the wrapping `VStack`, the banner, and the `.id` string change.)

- [ ] **Step 3: Add the re-auth sheet next to the add-account sheet**

After the existing `.sheet(isPresented: $isAddingAccount) { ... }` modifier, add:

```swift
        .sheet(isPresented: $isReauthSheetShown) {
            LoginView(model: reauthLoginModel) { did in
                reauth = nil
                isReauthSheetShown = false
                reauthGeneration += 1
                accountAvatarURL = nil
                currentDID = did
            }
            .environmentObject(themeStore)
            .frame(minWidth: 420, minHeight: 360)
        }
```

(Match the environment objects / frame the existing add-account sheet uses in this file; if it injects more environment objects, mirror them.)

- [ ] **Step 4: Replace `handleSessionExpired()` to keep the account**

Replace the whole method:

```swift
    private func handleSessionExpired() {
        guard let request = SessionReauth.onExpiry(
            currentDID: currentDID,
            currentHandle: currentHandle,
            isPending: reauth != nil
        ) else { return }
        Self.log.notice("Session expired; prompting re-auth")
        reauth = request
        reauthLoginModel.reset()
        reauthLoginModel.handle = request.handle
        isReauthSheetShown = true
    }
```

(`currentHandle` is the existing computed property on this view. `Self.log` is the existing `Logger(subsystem: PerfSignpost.subsystem, category: "Session")`.)

- [ ] **Step 5: Reword the wake log line**

In `refreshSessionOnWake()`, change the `invalid_grant` branch log from:

```swift
                    Self.log.notice("Session expired while asleep; dropping the account")
```

to:

```swift
                    Self.log.notice("Session expired while asleep; prompting re-auth")
```

- [ ] **Step 6: Build the macOS app**

Run:
```bash
xcodegen generate
xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj -destination 'platform=macOS' 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add apps/macos/Views/RootView.swift
git ai-commit
```
Message: `Keep account and prompt re-auth on macOS session expiry`

---

### Task 4: iPadOS re-auth banner view + render test

**Files:**
- Create: `apps/ipados/Views/SessionReauthBanner.swift`
- Create: `apps/ipadosTests/SessionReauthBannerRenderTests.swift`
- Modify: `project.yml` (add the banner source to the `YoruMimizukuPadTests` target)

**Interfaces:**
- Consumes: `ThemeStore`.
- Produces: `struct SessionReauthBanner: View { init(onReauth: @escaping () -> Void) }` (iPad copy).

- [ ] **Step 1: Write the iPad banner view**

Create `apps/ipados/Views/SessionReauthBanner.swift` (UIKit-hosted twin of the macOS banner; identical body, no `NS*` types):

```swift
import SwiftUI
import YoruMimizukuKit

/// iPad twin of the macOS session-expiry banner. Shown above the timeline while
/// the current account awaits re-authentication.
struct SessionReauthBanner: View {
    let onReauth: () -> Void
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.accent)
            Text("セッションが期限切れです")
                .font(.app(.caption))
                .foregroundStyle(theme.primaryText)
            Spacer(minLength: 8)
            Button("再ログイン", action: onReauth)
                .font(.app(.caption))
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.surface)
        .overlay(alignment: .bottom) { Divider().overlay(theme.divider) }
    }
}
```

- [ ] **Step 2: Add the banner source to the iPad test target**

In `project.yml`, under `targets: YoruMimizukuPadTests: sources:`, add:

```yaml
      - apps/ipados/Views/SessionReauthBanner.swift
```

- [ ] **Step 3: Write the render test**

Create `apps/ipadosTests/SessionReauthBannerRenderTests.swift`:

```swift
import XCTest
import SwiftUI
import YoruMimizukuKit
@testable import YoruMimizuku

@MainActor
final class SessionReauthBannerRenderTests: XCTestCase {
    func testBannerRendersWithThemeStore() {
        var tapped = false
        let banner = SessionReauthBanner(onReauth: { tapped = true })
            .environmentObject(ThemeStore())
        let host = UIHostingController(rootView: banner)
        host.view.frame = CGRect(x: 0, y: 0, width: 480, height: 44)
        host.view.layoutIfNeeded()
        XCTAssertFalse(tapped)
        XCTAssertGreaterThan(host.sizeThatFits(in: CGSize(width: 480, height: 200)).height, 0)
    }
}
```

(The iPad app module is also named `YoruMimizuku` in `@testable import`; match whatever the existing `apps/ipadosTests` files import — check `apps/ipadosTests/SettingsRenderTests.swift`.)

- [ ] **Step 4: Regenerate and run the test**

Run:
```bash
xcodegen generate
xcodebuild test -scheme YoruMimizukuPad -project YoruMimizuku.xcodeproj -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -only-testing:YoruMimizukuPadTests/SessionReauthBannerRenderTests 2>&1 | tail -15
```
Expected: PASS. (If the pinned simulator name differs locally, use the one the existing snapshot tests use.)

- [ ] **Step 5: Commit**

```bash
git add apps/ipados/Views/SessionReauthBanner.swift apps/ipadosTests/SessionReauthBannerRenderTests.swift project.yml
git ai-commit
```
Message: `Add iPad session re-auth banner`

---

### Task 5: iPad RootView wiring

**Files:**
- Modify: `apps/ipados/Views/RootView.swift`

**Interfaces:**
- Consumes: `SessionReauth`, `ReauthRequest` (Task 1); `SessionReauthBanner` (Task 4).

Current relevant code (`apps/ipados/Views/RootView.swift`): mirrors macOS — `body` has `Group { if let did = currentDID { AuthenticatedRootView(...).id(did)... } else { LoginView... } }`, `.onReceive(...SessionExpiry.notification) { handleSessionExpired() }`, the `isAddingAccount` sheet, and `handleSessionExpired()` which does `remove(did:)` + switch to `allDIDs().first`. There is no `os.Logger` in this file yet.

- [ ] **Step 1: Import os and add a Session logger + re-auth state**

At the top of the file, add `import os` (after `import YoruMimizukuKit`). Add a static logger and the re-auth state to `RootView`:

```swift
    private static let log = Logger(subsystem: PerfSignpost.subsystem, category: "Session")

    @State private var reauth: ReauthRequest?
    @State private var isReauthSheetShown = false
    @State private var reauthGeneration = 0
    @StateObject private var reauthLoginModel: LoginViewModel
```

In `init()`, after `_loginModel = StateObject(...)`:

```swift
        _reauthLoginModel = StateObject(wrappedValue: LoginViewModel(performer: LiveLoginPerformer(accountManager: manager)))
```

- [ ] **Step 2: Wrap body in banner + generation id**

Change the `body`'s outer `Group { ... }` to a `VStack(spacing: 0)` with the banner above it, and stamp the id (same shape as macOS Task 3 Step 2):

```swift
        VStack(spacing: 0) {
            if reauth != nil {
                SessionReauthBanner(onReauth: { isReauthSheetShown = true })
            }
            Group {
                if let did = currentDID {
                    AuthenticatedRootView(
                        ...
                    )
                    .id("\(did)#\(reauthGeneration)")
                    .task(id: currentDID) { await loadAvatar() }
                } else {
                    LoginView(model: loginModel) { did in
                        currentDID = did
                    }
                }
            }
        }
```

(Keep the `AuthenticatedRootView(...)` arguments unchanged.)

- [ ] **Step 3: Add the re-auth sheet**

After the existing `.sheet(isPresented: $isAddingAccount) { ... }` block, add (mirroring the environment objects that block injects):

```swift
        .sheet(isPresented: $isReauthSheetShown) {
            LoginView(model: reauthLoginModel) { did in
                reauth = nil
                isReauthSheetShown = false
                reauthGeneration += 1
                accountAvatarURL = nil
                currentDID = did
            }
            .environmentObject(theme)
            .environmentObject(displaySettings)
            .environmentObject(fontSettings)
            .environmentObject(notificationSettings)
        }
```

- [ ] **Step 4: Replace `handleSessionExpired()`**

Replace the whole method (it currently removes + advances) with:

```swift
    private func handleSessionExpired() {
        guard let request = SessionReauth.onExpiry(
            currentDID: currentDID,
            currentHandle: currentHandle,
            isPending: reauth != nil
        ) else { return }
        Self.log.notice("Session expired; prompting re-auth")
        reauth = request
        reauthLoginModel.reset()
        reauthLoginModel.handle = request.handle
        isReauthSheetShown = true
    }
```

(`currentHandle` is the existing computed property returning `account?.handle ?? account?.did ?? ""`.)

- [ ] **Step 5: Build the iPad app**

Run:
```bash
xcodegen generate
xcodebuild build -scheme YoruMimizukuPad -project YoruMimizuku.xcodeproj -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add apps/ipados/Views/RootView.swift
git ai-commit
```
Message: `Keep account and prompt re-auth on iPad session expiry`

---

### Task 6: Full verification + wiki update

**Files:**
- Modify: `docs/wiki/behaviors/accounts.md` (or `oauth-flow.md` — whichever documents session expiry) and `docs/wiki/log.md`

- [ ] **Step 1: Run the full core test suite**

Run: `cd core && swift test 2>&1 | tail -5`
Expected: all tests pass (including the new `SessionReauthTests`).

- [ ] **Step 2: Build both apps green**

Run:
```bash
xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj -destination 'platform=macOS' 2>&1 | tail -3
xcodebuild build -scheme YoruMimizukuPad -project YoruMimizuku.xcodeproj -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **` for both.

- [ ] **Step 3: Update the wiki**

Read `docs/wiki/conventions.md`, then update the behavior page that documents accounts/session expiry (`docs/wiki/behaviors/accounts.md`; if session expiry is described in `oauth-flow.md`, update there instead). Replace the "on expiry the account is dropped" description with the new behavior: the account is kept, a handle-pre-filled re-auth sheet is auto-presented, a banner is the cancel fallback, and both the reactive and wake paths are logged under `category: "Session"`. Update the page's `sources:` (add `docs/superpowers/specs/2026-07-13-session-reauth-design.md`) and `updated:`. If the page has a `features:` block, keep every platform status uniform (macOS + iOS both get this; it is shared logic + per-app wiring). Add a `## 2026-07-13 ingest` entry at the top of `docs/wiki/log.md`.

- [ ] **Step 4: Lint, regenerate matrix and index**

Run:
```bash
mise run wiki:lint
mise run wiki:matrix
mise run wiki:index
```
Expected: lint passes; matrix/index regenerate. Fix anything lint reports.

- [ ] **Step 5: Commit**

```bash
git add docs/wiki
git ai-commit
```
Message: `Document session re-auth behavior`

---

## Self-Review notes

- **Spec coverage:** §5.1 → Task 3/5 Step 4 (helper + handler); §5.2 → Task 3/5 Steps 2–3 (sheet + generation id); §5.3 (banner state model) → Task 2/4 (banner) + Task 3/5 Steps 1–3; §6 (observability) → Task 3 Step 4–5, Task 5 Steps 1 & 4; §7 (Approach A, no schema change) → no `PersistedAccount` task exists (correct); §8 (testing) → Task 1 unit tests + Task 2/4 render tests + Task 6 builds.
- **Type consistency:** `SessionReauth.onExpiry(currentDID:currentHandle:isPending:)` and `ReauthRequest(did:handle:)` are used identically in Tasks 1, 3, 5. `SessionReauthBanner(onReauth:)` identical in Tasks 2, 4 (macOS) and their consumers (Tasks 3, 5). The subtree id string `"\(did)#\(reauthGeneration)"` is identical in Tasks 3 and 5.
- **No schema change:** `PersistedAccount` and `AccountManager` are untouched (Approach A).
