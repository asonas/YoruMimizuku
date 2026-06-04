import XCTest
@testable import BlueskyCore

final class SmokeTests: XCTestCase {
    func test_moduleVersionIsExposed() {
        XCTAssertEqual(BlueskyCore.version, "0.0.1")
    }
}
