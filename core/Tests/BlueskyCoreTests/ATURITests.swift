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

    func testRepoExtractsAuthority() {
        XCTAssertEqual(
            ATURI.repo("at://did:plc:me/app.bsky.feed.post/3kabc123"),
            "did:plc:me"
        )
    }

    func testRepoReturnsNilWhenMalformed() {
        XCTAssertNil(ATURI.repo("not-an-at-uri"))
        XCTAssertNil(ATURI.repo("at://did:plc:me/app.bsky.feed.post"))
        XCTAssertNil(ATURI.repo(""))
    }
}
