import XCTest
@testable import YoruMimizukuKit

final class FilterSearchMergeTests: XCTestCase {
    private func post(_ id: String, _ ageSeconds: TimeInterval) -> PostDisplay {
        PostDisplay(
            id: id, authorDisplayName: id, authorHandle: "\(id).bsky.social",
            body: id, createdAt: Date(timeIntervalSince1970: 10_000 - ageSeconds)
        )
    }

    func testMergeSortsNewestFirstAndDedupesById() {
        let a = [post("p1", 10), post("p3", 30)]
        let b = [post("p2", 20), post("p1", 10)] // p1 duplicated across subqueries
        let merged = FilterSearchMerge.merge([a, b])
        XCTAssertEqual(merged.map(\.id), ["p1", "p2", "p3"])
    }

    func testMergeEmpty() {
        XCTAssertTrue(FilterSearchMerge.merge([]).isEmpty)
        XCTAssertTrue(FilterSearchMerge.merge([[], []]).isEmpty)
    }

    func testCompositeCursorRoundTrips() throws {
        let cursor = CompositeCursor(cursors: ["a", nil, "c"])
        let encoded = try XCTUnwrap(cursor.encoded())
        XCTAssertEqual(CompositeCursor.decode(encoded), cursor)
    }

    func testCompositeCursorEncodesNilWhenAllExhausted() {
        XCTAssertNil(CompositeCursor(cursors: [nil, nil]).encoded())
    }

    func testCompositeCursorDecodeNilStringIsNil() {
        XCTAssertNil(CompositeCursor.decode(nil))
    }
}
