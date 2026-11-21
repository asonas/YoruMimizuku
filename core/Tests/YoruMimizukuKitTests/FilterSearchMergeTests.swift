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

    // #11: which subqueries a page fetches, and from which cursor.
    func testFirstPageFetchesEverySubqueryFromTheStart() {
        XCTAssertEqual(CompositeCursor.pageFetches(cursor: nil, subqueryCount: 2), [.fetch(cursor: nil), .fetch(cursor: nil)])
    }

    func testLaterPageSkipsExhaustedSubqueries() {
        let cursor = CompositeCursor(cursors: ["a", nil]).encoded()
        XCTAssertEqual(CompositeCursor.pageFetches(cursor: cursor, subqueryCount: 2), [.fetch(cursor: "a"), .exhausted])
    }

    func testCursorFromADifferentFilterStartsOver() {
        let cursor = CompositeCursor(cursors: ["a", "b"]).encoded()
        XCTAssertEqual(
            CompositeCursor.pageFetches(cursor: cursor, subqueryCount: 3),
            [.fetch(cursor: nil), .fetch(cursor: nil), .fetch(cursor: nil)]
        )
    }

    // A filter edited down to one term gets back a cursor from when it had several.
    func testSingleQueryDropsACursorFromSeveralTerms() {
        let composite = CompositeCursor(cursors: ["a", "b"]).encoded()
        XCTAssertNil(CompositeCursor.singleQueryCursor(composite))
        XCTAssertEqual(CompositeCursor.singleQueryCursor("25"), "25")
        XCTAssertNil(CompositeCursor.singleQueryCursor(nil))
    }

    // A server cursor that happens to look like our JSON is still the server's.
    func testSingleQueryKeepsAServerCursorThatLooksLikeJSON() {
        let serverCursor = #"{"cursors":["next"]}"#
        XCTAssertEqual(CompositeCursor.singleQueryCursor(serverCursor), serverCursor)
    }
}
