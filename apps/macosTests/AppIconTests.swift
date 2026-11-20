import AppKit
import XCTest

@MainActor
final class AppIconTests: XCTestCase {
    /// A renamed SVG would otherwise load as a blank placeholder and leave a
    /// button without its icon.
    func testEveryIconLoadsFromTheBundledFolder() {
        for icon in AppIcon.allCases {
            let image = AppIconImages.image(icon)
            XCTAssertFalse(image.representations.isEmpty, "\(icon.rawValue).svg did not load")
            XCTAssertTrue(image.isTemplate, "\(icon.rawValue) should take the foreground color")
        }
    }

    /// An SVG added without a case would never be reachable from the app.
    func testEveryBundledSVGHasACase() throws {
        let bundle = Bundle(for: Self.self)
        let urls = try XCTUnwrap(bundle.urls(forResourcesWithExtension: "svg", subdirectory: "icons"))
        let names = Set(urls.map { $0.deletingPathExtension().lastPathComponent })
        XCTAssertEqual(names, Set(AppIcon.allCases.map(\.rawValue)))
    }
}
