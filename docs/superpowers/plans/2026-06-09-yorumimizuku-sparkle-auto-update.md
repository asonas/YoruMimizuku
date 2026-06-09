# Sparkle Auto-Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add macOS-only Sparkle 2 update checks with a non-modal gear-dot reminder and a settings-tab install flow.

**Architecture:** Sparkle stays in `apps/macos`; no updater code enters `BlueskyCore`, `YoruMimizukuKit`, iPadOS, or Windows. A Sparkle-free `UpdateBadgeState` holds testable badge/version logic, while `UpdateController` owns `SPUStandardUpdaterController` and publishes SwiftUI state. Release tasks produce a notarized/stapled app ZIP for Sparkle plus the existing DMG path.

**Tech Stack:** SwiftUI, Sparkle 2 via SwiftPM, XcodeGen `project.yml`, XCTest app test target, mise release tasks, GitHub Releases, GitHub Pages appcast.

---

## File Structure

- Create `apps/macos/Update/UpdateBadgeState.swift`: pure badge state and version display formatter.
- Create `apps/macos/Update/UpdateController.swift`: `@MainActor ObservableObject` Sparkle wrapper and delegate glue.
- Create `apps/macos/Views/UpdateSettingsView.swift`: settings pane for current version, manual check, automatic-check toggle, and update availability.
- Create `apps/macosTests/UpdateBadgeStateTests.swift`: XCTest coverage for the pure state.
- Modify `project.yml`: add Sparkle package/dependency, macOS Info.plist keys, and `YoruMimizukuTests`.
- Modify `apps/macos/YoruMimizukuApp.swift`: instantiate and inject `UpdateController`.
- Modify `apps/macos/Views/SettingsView.swift`: add `.update`.
- Modify `apps/macos/Views/SidebarView.swift`: draw the gear-dot reminder.
- Modify `mise.toml`: split app notarization, Sparkle ZIP, appcast generation, and publish steps.
- Modify `docs/wiki/behaviors/auto-updates.md` and `docs/wiki/platforms/macos.md` only if implementation decisions differ from this plan.

## Task 1: Pure Badge State

**Files:**
- Create: `apps/macos/Update/UpdateBadgeState.swift`
- Create: `apps/macosTests/UpdateBadgeStateTests.swift`
- Modify: `project.yml`

- [ ] **Step 1: Add a macOS app test target**

Add this target to `project.yml` so app-layer pure logic can be tested without moving it into the core package:

```yaml
  YoruMimizukuTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - apps/macosTests
    dependencies:
      - target: YoruMimizuku
    settings:
      base:
        SWIFT_VERSION: "6.0"
```

Add it to the `YoruMimizuku` scheme test action:

```yaml
    test:
      targets:
        - YoruMimizukuTests
```

Run:

```bash
xcodegen generate
xcodebuild test -scheme YoruMimizuku -project YoruMimizuku.xcodeproj -destination 'platform=macOS'
```

Expected: FAIL because `apps/macosTests` does not exist yet or contains no tests after the target is added. Continue by adding the test file.

- [ ] **Step 2: Write failing tests for `UpdateBadgeState`**

Create `apps/macosTests/UpdateBadgeStateTests.swift`:

```swift
import XCTest
@testable import YoruMimizuku

final class UpdateBadgeStateTests: XCTestCase {
    func testBackgroundFoundUpdateShowsBadge() {
        var state = UpdateBadgeState()

        state.scheduledUpdateFound()

        XCTAssertTrue(state.updateAvailable)
    }

    func testDismissedOrInstalledUpdateClearsBadge() {
        var state = UpdateBadgeState(updateAvailable: true)

        state.updateSessionFinished()

        XCTAssertFalse(state.updateAvailable)
    }

    func testVersionDisplayIncludesBuildNumber() {
        XCTAssertEqual(
            UpdateBadgeState.versionDisplay(shortVersion: "0.6.0", build: "4"),
            "0.6.0 (4)"
        )
    }

    func testVersionDisplayOmitsEmptyBuildNumber() {
        XCTAssertEqual(
            UpdateBadgeState.versionDisplay(shortVersion: "0.6.0", build: ""),
            "0.6.0"
        )
    }
}
```

Run:

```bash
xcodebuild test -scheme YoruMimizuku -project YoruMimizuku.xcodeproj -destination 'platform=macOS' -only-testing:YoruMimizukuTests/UpdateBadgeStateTests
```

Expected: FAIL with `cannot find 'UpdateBadgeState' in scope`.

- [ ] **Step 3: Implement `UpdateBadgeState` minimally**

Create `apps/macos/Update/UpdateBadgeState.swift`:

```swift
import Foundation

struct UpdateBadgeState: Equatable {
    private(set) var updateAvailable: Bool

    init(updateAvailable: Bool = false) {
        self.updateAvailable = updateAvailable
    }

    mutating func scheduledUpdateFound() {
        updateAvailable = true
    }

    mutating func updateSessionFinished() {
        updateAvailable = false
    }

    static func versionDisplay(shortVersion: String?, build: String?) -> String {
        let version = shortVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        let build = build?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (version?.isEmpty == false ? version : nil, build?.isEmpty == false ? build : nil) {
        case let (.some(version), .some(build)):
            return "\(version) (\(build))"
        case let (.some(version), .none):
            return version
        case (.none, let .some(build)):
            return build
        case (.none, .none):
            return "Unknown"
        }
    }
}
```

Run:

```bash
xcodebuild test -scheme YoruMimizuku -project YoruMimizuku.xcodeproj -destination 'platform=macOS' -only-testing:YoruMimizukuTests/UpdateBadgeStateTests
```

Expected: PASS.

- [ ] **Step 4: Run the app test target**

Run:

```bash
xcodebuild test -scheme YoruMimizuku -project YoruMimizuku.xcodeproj -destination 'platform=macOS'
```

Expected: PASS for `YoruMimizukuTests`; app launches in test host without Sparkle code yet.

## Task 2: Sparkle Package and Configuration

**Files:**
- Modify: `project.yml`

- [ ] **Step 1: Add Sparkle package and dependency**

Modify `project.yml`:

```yaml
packages:
  BlueskyCore:
    path: core
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    from: 2.7.0
```

Add the package product to the macOS target dependencies:

```yaml
      - package: Sparkle
        product: Sparkle
```

- [ ] **Step 2: Add Sparkle Info.plist keys**

Add these under `targets.YoruMimizuku.info.properties`:

```yaml
        SUFeedURL: https://asonas.github.io/YoruMimizuku/appcast.xml
        SUPublicEDKey: "__REPLACE_WITH_SPARKLE_PUBLIC_ED25519_KEY__"
        SUEnableAutomaticChecks: true
        SUScheduledCheckInterval: 86400
```

Keep the placeholder public key until `generate_keys` has been run once. Do not invent a key and do not commit a private key.

- [ ] **Step 3: Verify project generation**

Run:

```bash
xcodegen generate
xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj
```

Expected: If `SUPublicEDKey` is still a placeholder, compile should still succeed. Runtime update checks will not verify real updates until the key is replaced.

## Task 3: Update Controller

**Files:**
- Create: `apps/macos/Update/UpdateController.swift`
- Modify: `apps/macos/YoruMimizukuApp.swift`

- [ ] **Step 1: Implement Sparkle wrapper**

Create `apps/macos/Update/UpdateController.swift`:

```swift
import Foundation
import Sparkle

@MainActor
final class UpdateController: NSObject, ObservableObject {
    @Published private(set) var updateAvailable = false
    @Published private(set) var canCheckForUpdates = false

    private var badgeState = UpdateBadgeState() {
        didSet { updateAvailable = badgeState.updateAvailable }
    }

    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: self
    )

    override init() {
        super.init()
        canCheckForUpdates = updaterController.updater.canCheckForUpdates
    }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set {
            updaterController.updater.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
        }
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

extension UpdateController: SPUUpdaterDelegate {}

extension UpdateController: SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        if immediateFocus { return true }
        badgeState.scheduledUpdateFound()
        return false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if !handleShowingUpdate {
            badgeState.scheduledUpdateFound()
        }
    }

    func standardUserDriverWillFinishUpdateSession() {
        badgeState.updateSessionFinished()
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        badgeState.updateSessionFinished()
    }
}
```

If Sparkle's Swift signatures differ in the installed package version, adjust only the delegate method signatures to match Sparkle's generated interface; keep the behavior unchanged.

- [ ] **Step 2: Inject controller from the app entry point**

Modify `apps/macos/YoruMimizukuApp.swift`:

```swift
import SwiftUI

@main
struct YoruMimizukuApp: App {
    @StateObject private var updateController = UpdateController()

    init() {
        MetricsSubscriber.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(updateController)
                .modifier(DebugPerfOverlay())
        }
        .defaultSize(width: 940, height: 720)
        .windowStyle(.hiddenTitleBar)
    }
}
```

- [ ] **Step 3: Verify build**

Run:

```bash
xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj
```

Expected: PASS. If delegate method signatures fail, fix signatures and rerun.

## Task 4: Settings Update Tab and Gear Dot

**Files:**
- Create: `apps/macos/Views/UpdateSettingsView.swift`
- Modify: `apps/macos/Views/SettingsView.swift`
- Modify: `apps/macos/Views/SidebarView.swift`

- [ ] **Step 1: Create update settings view**

Create `apps/macos/Views/UpdateSettingsView.swift`:

```swift
import SwiftUI

struct UpdateSettingsView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var updateController: UpdateController

    private var versionDisplay: String {
        UpdateBadgeState.versionDisplay(
            shortVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("アップデート")
                    .font(.app(.headline))
                    .foregroundStyle(theme.primaryText)

                VStack(alignment: .leading, spacing: 6) {
                    Text("現在のバージョン")
                        .font(.app(.caption))
                        .foregroundStyle(theme.secondaryText)
                    Text(versionDisplay)
                        .font(.app(.callout, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                }

                Toggle("起動時に自動で確認", isOn: Binding(
                    get: { updateController.automaticallyChecksForUpdates },
                    set: { updateController.automaticallyChecksForUpdates = $0 }
                ))

                Button {
                    updateController.checkForUpdates()
                } label: {
                    Label("今すぐ確認", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!updateController.canCheckForUpdates)

                if updateController.updateAvailable {
                    Label("利用可能なアップデートがあります。今すぐ確認からインストールできます。", systemImage: "arrow.down.circle.fill")
                        .font(.app(.callout))
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
```

- [ ] **Step 2: Add settings tab**

Modify `apps/macos/Views/SettingsView.swift`:

```swift
private enum SettingsTab: String, CaseIterable, Identifiable {
    case appearance
    case font
    case display
    case update
    ...
}
```

Add to `detail`:

```swift
        case .update:
            UpdateSettingsView()
```

Add title/icon:

```swift
        case .update: return "アップデート"
```

```swift
        case .update: return "arrow.down.circle"
```

- [ ] **Step 3: Draw gear dot**

Modify `apps/macos/Views/SidebarView.swift`:

```swift
    @EnvironmentObject private var updateController: UpdateController
```

Replace the gear button in `accountFooter`:

```swift
            ChromeIconButton(systemImage: "gearshape", help: "設定", action: onOpenSettings)
                .overlay(alignment: .topTrailing) {
                    if updateController.updateAvailable {
                        Circle()
                            .fill(theme.accent)
                            .frame(width: 6, height: 6)
                            .offset(x: 2, y: -2)
                    }
                }
```

- [ ] **Step 4: Verify build**

Run:

```bash
xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj
```

Expected: PASS and settings sheet has an update tab.

## Task 5: Release Pipeline

**Files:**
- Modify: `mise.toml`
- Optional create: `scripts/release/appcast-notes-template.md`

- [ ] **Step 1: Add Sparkle env variables**

Add to `[env]`:

```toml
SPARKLE_BIN = "/Applications/Sparkle.app/Contents/SharedSupport"
APPCAST_URL_PREFIX = "https://github.com/asonas/YoruMimizuku/releases/download"
APPCAST_PATH = "build/appcast.xml"
```

- [ ] **Step 2: Split app notarization**

Replace the current `notarize` dependency chain with:

```toml
[tasks."notarize-app"]
description = "Notarize and staple the exported .app for Sparkle and DMG packaging"
depends = ["export"]
run = """
set -euo pipefail
app="$BUILD_DIR/export/$APP_NAME.app"
zip="$BUILD_DIR/$APP_NAME-notary.zip"
ditto -c -k --keepParent "$app" "$zip"
xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
spctl -a -vvv -t exec "$app"
rm -f "$zip"
"""
```

Change `[tasks.dmg]` to depend on `notarize-app` instead of `export`, and keep the existing DMG signing/notarization steps.

- [ ] **Step 3: Add Sparkle ZIP and appcast tasks**

Add:

```toml
[tasks."sparkle-zip"]
description = "Create the Sparkle update ZIP from the notarized/stapled app"
depends = ["notarize-app"]
run = """
set -euo pipefail
version="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$BUILD_DIR/$APP_NAME.xcarchive/Info.plist" 2>/dev/null || echo "$MARKETING_VERSION")"
zip="$BUILD_DIR/$APP_NAME-$version.zip"
rm -f "$zip"
ditto -c -k --keepParent "$BUILD_DIR/export/$APP_NAME.app" "$zip"
echo "Sparkle ZIP ready: $zip"
"""

[tasks.appcast]
description = "Generate appcast.xml for the Sparkle ZIP"
depends = ["sparkle-zip"]
run = """
set -euo pipefail
mkdir -p "$BUILD_DIR/appcast"
cp "$BUILD_DIR"/*.zip "$BUILD_DIR/appcast/"
"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "$APPCAST_URL_PREFIX/v$(grep 'MARKETING_VERSION:' project.yml | head -1 | awk '{print $2}' | tr -d '\"')/" \
  "$BUILD_DIR/appcast"
cp "$BUILD_DIR/appcast/appcast.xml" "$APPCAST_PATH"
echo "Appcast ready: $APPCAST_PATH"
"""
```

If `generate_appcast` is not at `$SPARKLE_BIN/generate_appcast` for the local Sparkle installation, adjust `SPARKLE_BIN` only.

- [ ] **Step 4: Adjust release task**

Change:

```toml
[tasks.release]
description = "Build, sign, notarize and package distributable DMG and Sparkle ZIP"
depends = ["notarize", "appcast"]
run = 'echo "Release artifacts ready under $BUILD_DIR"'
```

Keep publishing to GitHub Releases and pushing `appcast.xml` to `gh-pages` manual; do not automate outward-facing pushes in this task.

- [ ] **Step 5: Verify release task graph syntax**

Run:

```bash
mise tasks
```

Expected: PASS and shows `notarize-app`, `sparkle-zip`, `appcast`, and `release`.

## Task 6: Documentation and Final Verification

**Files:**
- Modify: `docs/wiki/behaviors/auto-updates.md` if implementation differs.
- Modify: `docs/wiki/platforms/macos.md` if implementation differs.
- Modify: `README.md` only if release-key setup docs do not already exist.

- [ ] **Step 1: Update docs for actual key setup**

If `SUPublicEDKey` has been replaced with a real public key, add a short README section:

```markdown
### Sparkle signing key

Sparkle update signing uses an EdDSA key pair generated once with Sparkle's
`generate_keys`. The public key is committed in `project.yml` as `SUPublicEDKey`.
The private key is stored in the macOS Keychain and must never be committed or
logged. Forks must generate their own key pair and replace `SUPublicEDKey`.
```

- [ ] **Step 2: Run core and app tests**

Run:

```bash
cd core && swift test
xcodebuild test -scheme YoruMimizuku -project YoruMimizuku.xcodeproj -destination 'platform=macOS'
```

Expected: PASS.

- [ ] **Step 3: Run app builds**

Run:

```bash
xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj
xcodebuild build -scheme YoruMimizukuPad -project YoruMimizuku.xcodeproj -destination 'generic/platform=iOS Simulator'
```

Expected: PASS.

- [ ] **Step 4: Run wiki checks**

Run:

```bash
mise run wiki:lint
mise run wiki:matrix
mise run wiki:index
mise run wiki:lint
```

Expected: lint passes and support matrix/index are up to date.

## Manual Acceptance Checklist

Use a staging appcast before trusting production updates:

- Build an older Developer ID signed app with Sparkle configured to a staging feed.
- Publish a higher version ZIP to the staging feed.
- Launch the old app and wait for a scheduled check.
- Confirm no modal appears for the scheduled check.
- Confirm the settings gear shows the dot.
- Open Settings → アップデート → 今すぐ確認.
- Confirm Sparkle downloads, verifies, replaces, and relaunches.
- Confirm the relaunched app is the higher version.
- Confirm Gatekeeper accepts the replaced app while offline.

## Self-Review

- Spec coverage: covered app-side Sparkle wrapper, settings UX, gear dot, Info.plist keys, key management, release artifacts, appcast hosting, release task changes, and manual acceptance.
- Placeholder scan: `__REPLACE_WITH_SPARKLE_PUBLIC_ED25519_KEY__` is intentional because the key must be generated by the owner and must not be invented by an agent.
- Type consistency: `UpdateBadgeState`, `UpdateController`, `UpdateSettingsView`, and `YoruMimizukuTests` names are consistent across tasks.
