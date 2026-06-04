import XCTest
@testable import BlueskyCore

final class ThreadResponseTests: XCTestCase {
    func testDecodesFocusedPostWithImmediateParent() throws {
        let body = Data(##"""
        {
          "thread": {
            "$type": "app.bsky.feed.defs#threadViewPost",
            "post": {
              "uri": "at://did:plc:bob/app.bsky.feed.post/reply",
              "cid": "bafyreibob",
              "author": { "did": "did:plc:bob", "handle": "bob.bsky.social", "displayName": "Bob" },
              "record": { "text": "返信です", "createdAt": "2026-06-04T12:05:00.000Z" },
              "indexedAt": "2026-06-04T12:05:01.000Z"
            },
            "parent": {
              "$type": "app.bsky.feed.defs#threadViewPost",
              "post": {
                "uri": "at://did:plc:alice/app.bsky.feed.post/root",
                "cid": "bafyreialice",
                "author": { "did": "did:plc:alice", "handle": "alice.bsky.social", "displayName": "Alice" },
                "record": { "text": "親の投稿", "createdAt": "2026-06-04T12:00:00.000Z" },
                "indexedAt": "2026-06-04T12:00:01.000Z"
              }
            }
          }
        }
        """##.utf8)

        let response = try JSONDecoder().decode(ThreadResponse.self, from: body)

        XCTAssertEqual(response.thread.post.author.handle, "bob.bsky.social")
        XCTAssertEqual(response.thread.parentPost?.author.handle, "alice.bsky.social")
        XCTAssertEqual(response.thread.parentPost?.record.text, "親の投稿")
    }

    func testParentIsNilForNotFoundOrAbsentParent() throws {
        let body = Data(##"""
        {
          "thread": {
            "$type": "app.bsky.feed.defs#threadViewPost",
            "post": {
              "uri": "at://did:plc:alice/app.bsky.feed.post/root",
              "cid": "bafyreialice",
              "author": { "did": "did:plc:alice", "handle": "alice.bsky.social" },
              "record": { "text": "起点", "createdAt": "2026-06-04T12:00:00.000Z" },
              "indexedAt": "2026-06-04T12:00:01.000Z"
            },
            "parent": {
              "$type": "app.bsky.feed.defs#notFoundPost",
              "uri": "at://did:plc:ghost/app.bsky.feed.post/gone",
              "notFound": true
            }
          }
        }
        """##.utf8)

        let response = try JSONDecoder().decode(ThreadResponse.self, from: body)

        XCTAssertEqual(response.thread.post.author.handle, "alice.bsky.social")
        XCTAssertNil(response.thread.parentPost)
    }
}
