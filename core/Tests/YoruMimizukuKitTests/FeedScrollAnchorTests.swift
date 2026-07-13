import XCTest
@testable import YoruMimizukuKit

final class FeedScrollAnchorTests: XCTestCase {
    func testNoVisibleRowsMeansNil() {
        XCTAssertNil(FeedScrollAnchor.topVisibleID(order: ["a", "b", "c"], visible: []))
    }

    func testReturnsFirstVisibleInDisplayOrder() {
        XCTAssertEqual(
            FeedScrollAnchor.topVisibleID(order: ["a", "b", "c", "d"], visible: ["c", "b"]),
            "b"
        )
    }

    func testIgnoresVisibleIDsNotInOrder() {
        XCTAssertEqual(
            FeedScrollAnchor.topVisibleID(order: ["a", "b", "c"], visible: ["gone", "c"]),
            "c"
        )
    }

    func testAllOffscreenExceptTopKeepsTop() {
        XCTAssertEqual(
            FeedScrollAnchor.topVisibleID(order: ["a", "b", "c"], visible: ["a"]),
            "a"
        )
    }
}
