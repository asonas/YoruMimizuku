import XCTest
import SwiftUI
import AppKit
import YoruMimizukuKit

/// The feed's table keeps the height a row reports on its first measurement, so a
/// row must pick its arrangement from the width it is offered, on that first pass.
final class PostRowLayoutTests: XCTestCase {
    @MainActor
    private func firstMeasuredHeight(_ variant: CatalogVariant, width: CGFloat) -> CGFloat {
        let sandbox = UserDefaults(suiteName: "as.ason.YoruMimizuku.post-row-layout-tests")!
        defer { UserDefaults.standard.removePersistentDomain(forName: "as.ason.YoruMimizuku.post-row-layout-tests") }
        let theme = ThemeStore(defaults: sandbox)
        theme.reset()
        let host = NSHostingView(
            rootView: PostRowView(post: CatalogFixtures.post(for: variant), density: .comfortable, now: CatalogFixtures.now)
                .environmentObject(theme)
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true))
        return host.fittingSize.height
    }

    @MainActor
    func testWideRowMovesMediaBesideTheTextOnItsFirstMeasurement() {
        for variant in [CatalogVariant.postRowLinkCard, .postRowTwoImages, .postRowSingleTallImage] {
            let narrow = firstMeasuredHeight(variant, width: 560)
            let wide = firstMeasuredHeight(variant, width: 1000)
            XCTAssertLessThan(wide, narrow, "\(variant) at 1000pt should sit in the rail, not stack under the text")
        }
    }
}
