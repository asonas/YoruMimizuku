import XCTest
import YoruMimizukuKit

final class CatalogRegistryTests: XCTestCase {
    @MainActor
    func testRegistryCoversEveryMacVariant() {
        for variant in CatalogVariant.allCases where variant.platforms.contains(.macOS) {
            XCTAssertNotNil(CatalogRegistry.view(for: variant), variant.id)
        }
    }
}
