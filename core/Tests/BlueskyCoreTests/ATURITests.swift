import XCTest
@testable import BlueskyCore

final class ATURITests: XCTestCase {
    func testRkeyExtractsLastPathComponent() {
        XCTAssertEqual(
            ATURI.rkey("at://did:plc:me/app.bsky.feed.like/3kabc123"),
            "3kabc123"
        )
    }

    func testRkeyReturnsNilWhenMalformed() {
        XCTAssertNil(ATURI.rkey("not-an-at-uri"))
        XCTAssertNil(ATURI.rkey("at://did:plc:me/app.bsky.feed.like"))
        XCTAssertNil(ATURI.rkey(""))
    }

    func testRepoReturnsAuthority() {
        XCTAssertEqual(ATURI.repo("at://did:plc:alice/app.bsky.feed.post/aaa"), "did:plc:alice")
    }

    func testRepoReturnsNilForNonATURI() {
        XCTAssertNil(ATURI.repo("https://example.com"))
    }
}
