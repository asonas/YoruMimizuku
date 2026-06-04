import XCTest
@testable import BlueskyCore

final class TimelineResponseTests: XCTestCase {
    /// Trimmed `app.bsky.feed.getTimeline` response: one plain post and one that
    /// surfaced via a repost (carrying a `reason`).
    private let fixture = Data(##"""
    {
      "cursor": "next-page",
      "feed": [
        {
          "post": {
            "uri": "at://did:plc:alice/app.bsky.feed.post/aaa",
            "cid": "bafyreialice",
            "author": {
              "did": "did:plc:alice",
              "handle": "alice.bsky.social",
              "displayName": "Alice",
              "avatar": "https://cdn.example/alice.jpg"
            },
            "record": {
              "$type": "app.bsky.feed.post",
              "text": "hello timeline",
              "createdAt": "2026-06-04T12:00:00.000Z"
            },
            "replyCount": 1,
            "repostCount": 2,
            "likeCount": 3,
            "indexedAt": "2026-06-04T12:00:01.000Z"
          }
        },
        {
          "post": {
            "uri": "at://did:plc:carol/app.bsky.feed.post/ccc",
            "cid": "bafyrecarol",
            "author": {
              "did": "did:plc:carol",
              "handle": "carol.bsky.social"
            },
            "record": {
              "$type": "app.bsky.feed.post",
              "text": "reposted thing",
              "createdAt": "2026-06-04T11:00:00.000Z"
            },
            "indexedAt": "2026-06-04T11:30:00.000Z"
          },
          "reason": {
            "$type": "app.bsky.feed.defs#reasonRepost",
            "by": {
              "did": "did:plc:bob",
              "handle": "bob.bsky.social",
              "displayName": "Bob"
            },
            "indexedAt": "2026-06-04T11:45:00.000Z"
          }
        }
      ]
    }
    """##.utf8)

    func testDecodesTimelineWithCursorAndTwoItems() throws {
        let response = try JSONDecoder().decode(TimelineResponse.self, from: fixture)

        XCTAssertEqual(response.cursor, "next-page")
        XCTAssertEqual(response.feed.count, 2)
    }

    func testDecodesPlainPostFields() throws {
        let response = try JSONDecoder().decode(TimelineResponse.self, from: fixture)
        let item = response.feed[0]

        XCTAssertNil(item.reason)
        XCTAssertEqual(item.post.uri, "at://did:plc:alice/app.bsky.feed.post/aaa")
        XCTAssertEqual(item.post.cid, "bafyreialice")
        XCTAssertEqual(item.post.author.handle, "alice.bsky.social")
        XCTAssertEqual(item.post.author.displayName, "Alice")
        XCTAssertEqual(item.post.author.avatar, "https://cdn.example/alice.jpg")
        XCTAssertEqual(item.post.record.text, "hello timeline")
        XCTAssertEqual(item.post.record.createdAt, "2026-06-04T12:00:00.000Z")
        XCTAssertEqual(item.post.replyCount, 1)
        XCTAssertEqual(item.post.repostCount, 2)
        XCTAssertEqual(item.post.likeCount, 3)
    }

    func testDecodesRepostReasonAndOptionalAuthorFields() throws {
        let response = try JSONDecoder().decode(TimelineResponse.self, from: fixture)
        let item = response.feed[1]

        XCTAssertNil(item.post.author.displayName)
        XCTAssertNil(item.post.author.avatar)
        XCTAssertNil(item.post.replyCount)
        XCTAssertEqual(item.reason?.by.handle, "bob.bsky.social")
        XCTAssertEqual(item.reason?.by.displayName, "Bob")
        XCTAssertEqual(item.reason?.indexedAt, "2026-06-04T11:45:00.000Z")
    }
}
