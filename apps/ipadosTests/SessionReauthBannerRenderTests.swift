import XCTest
import SwiftUI
import YoruMimizukuKit

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
