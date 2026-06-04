import XCTest
@testable import HoshidukiyoKit

final class DisplayDensityTests: XCTestCase {
    func test_hasCompactAndComfortableCases() {
        XCTAssertEqual(DisplayDensity.allCases, [.compact, .comfortable])
    }

    func test_defaultIsComfortable() {
        XCTAssertEqual(DisplayDensity.default, .comfortable)
    }

    func test_rawValuesAreStable() {
        XCTAssertEqual(DisplayDensity.compact.rawValue, "compact")
        XCTAssertEqual(DisplayDensity.comfortable.rawValue, "comfortable")
    }
}
