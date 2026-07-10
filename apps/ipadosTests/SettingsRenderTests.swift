import XCTest
import SwiftUI
import UIKit
import YoruMimizukuKit

/// Renders the Phase-3 settings and filter-editor screens once, off any login, to
/// prove they construct and lay out without crashing. These views each read
/// several `@EnvironmentObject`s and are only ever presented as sheets in the real
/// app, so a missing or mis-wired environment object is a runtime crash the
/// instant the sheet opens — something a plain build cannot catch. Hosting them
/// here with the same stores `RootView` injects surfaces that crash in CI.
///
/// The test bundle compiles `SettingsView.swift` / `FilterEditorView.swift`
/// directly (listed in the `YoruMimizukuPadTests` sources), so no
/// `@testable import` is needed.
@MainActor
final class SettingsRenderTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SettingsRenderTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// Force the SwiftUI body to evaluate (which resolves every `@EnvironmentObject`)
    /// by hosting the view in a window and running a layout pass. A missing
    /// environment object or a body fault crashes the test process here.
    private func render(_ view: some View) {
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 834, height: 1112))
        window.rootViewController = host
        window.isHidden = false
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
    }

    func testSettingsViewRendersWithAllEnvironmentObjects() {
        let theme = ThemeStore(defaults: defaults)
        theme.reset()
        render(
            SettingsView()
                .environmentObject(theme)
                .environmentObject(DisplaySettingsStore(defaults: defaults))
                .environmentObject(FontSettingsStore(defaults: defaults))
                .environmentObject(NotificationSettingsStore(defaults: defaults))
        )
    }

    func testFilterEditorViewRenders() {
        let theme = ThemeStore(defaults: defaults)
        theme.reset()
        render(
            FilterEditorView(
                name: "Swift界隈",
                terms: [FilterTerm(kind: .keyword, value: "swift")],
                combinator: .and,
                isEditing: true,
                onSubmit: { _, _, _ in }
            )
            .environmentObject(theme)
        )
    }
}
