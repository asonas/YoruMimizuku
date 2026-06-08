import XCTest
@testable import YoruMimizukuKit

final class UnreadCounterTests: XCTestCase {
    func testNoMarkerMeansZero() {
        XCTAssertEqual(UnreadCounter.unread(ids: ["a", "b", "c"], since: nil), 0)
    }

    func testMarkerAtTopMeansZero() {
        XCTAssertEqual(UnreadCounter.unread(ids: ["a", "b", "c"], since: "a"), 0)
    }

    func testMarkerBelowTopCountsItemsAbove() {
        XCTAssertEqual(UnreadCounter.unread(ids: ["x", "y", "a", "b"], since: "a"), 2)
    }

    func testMarkerNotFoundMeansAllAreNew() {
        XCTAssertEqual(UnreadCounter.unread(ids: ["x", "y", "z"], since: "gone"), 3)
    }

    func testEmptyListIsZero() {
        XCTAssertEqual(UnreadCounter.unread(ids: [], since: "a"), 0)
    }
}
