import XCTest
@testable import YoruMimizukuKit

final class DesignMetricsTests: XCTestCase {
    // Values must equal today's magic numbers: this is a rename, not a redesign.
    func testConstantsMatchCurrentMagicNumbers() {
        XCTAssertEqual(DesignMetrics.actionBarTopGap, 6)
        XCTAssertEqual(DesignMetrics.actionBarItemSpacing, 26)
        XCTAssertEqual(DesignMetrics.mediaTopGap, 3)
        XCTAssertEqual(DesignMetrics.gridGutter, 5)
        XCTAssertEqual(DesignMetrics.gridTileHeight, 140)
        XCTAssertEqual(DesignMetrics.thumbnailCornerRadius, 10)
    }

    func testDensityDependentValues() {
        XCTAssertEqual(DesignMetrics.bodyStackSpacing(.compact), 2)
        XCTAssertEqual(DesignMetrics.bodyStackSpacing(.comfortable), 4)
        XCTAssertEqual(DesignMetrics.mediaMaxWidth(.compact), 320)
        XCTAssertEqual(DesignMetrics.mediaMaxWidth(.comfortable), 440)
    }
}
