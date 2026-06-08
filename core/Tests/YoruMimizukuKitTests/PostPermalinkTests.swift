import XCTest
@testable import YoruMimizukuKit

final class PostPermalinkTests: XCTestCase {
    private func post(id: String, handle: String) -> PostDisplay {
        PostDisplay(
            id: id,
            authorDisplayName: "Test",
            authorHandle: handle,
            body: "hello",
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    func testValidHandleBuildsHandleURL() {
        let p = post(id: "at://did:plc:me/app.bsky.feed.post/3kabc123", handle: "alice.bsky.social")
        XCTAssertEqual(
            PostPermalink.url(for: p),
            URL(string: "https://bsky.app/profile/alice.bsky.social/post/3kabc123")
        )
    }

    func testRawPostFieldsBuildHandleURL() {
        XCTAssertEqual(
            PostPermalink.url(
                id: "at://did:plc:me/app.bsky.feed.post/3kabc123",
                authorHandle: "alice.bsky.social"
            ),
            URL(string: "https://bsky.app/profile/alice.bsky.social/post/3kabc123")
        )
    }

    func testInvalidHandleFallsBackToDID() {
        let p = post(id: "at://did:plc:me/app.bsky.feed.post/3kabc123", handle: "handle.invalid")
        XCTAssertEqual(
            PostPermalink.url(for: p),
            URL(string: "https://bsky.app/profile/did:plc:me/post/3kabc123")
        )
    }

    func testEmptyHandleFallsBackToDID() {
        let p = post(id: "at://did:plc:me/app.bsky.feed.post/3kabc123", handle: "")
        XCTAssertEqual(
            PostPermalink.url(for: p),
            URL(string: "https://bsky.app/profile/did:plc:me/post/3kabc123")
        )
    }

    func testNonATURIIDReturnsNil() {
        let p = post(id: "https://example.com/not-at-uri", handle: "alice.bsky.social")
        XCTAssertNil(PostPermalink.url(for: p))
    }

    func testMissingRkeyReturnsNil() {
        let p = post(id: "at://did:plc:me/app.bsky.feed.post", handle: "alice.bsky.social")
        XCTAssertNil(PostPermalink.url(for: p))
    }
}
