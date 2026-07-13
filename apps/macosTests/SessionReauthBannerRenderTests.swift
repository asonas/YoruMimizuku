import XCTest
import SwiftUI
import YoruMimizukuKit

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
