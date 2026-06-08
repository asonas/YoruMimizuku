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

    func testDecodesFullAncestorChain() throws {
        let body = Data(##"""
        {
          "thread": {
            "$type": "app.bsky.feed.defs#threadViewPost",
            "post": {
              "uri": "at://did:plc:c/app.bsky.feed.post/leaf",
              "cid": "cidc",
              "author": { "did": "did:plc:c", "handle": "carol.bsky.social" },
              "record": { "text": "孫", "createdAt": "2026-06-04T12:10:00.000Z" },
              "indexedAt": "2026-06-04T12:10:01.000Z"
            },
            "parent": {
              "$type": "app.bsky.feed.defs#threadViewPost",
              "post": {
                "uri": "at://did:plc:b/app.bsky.feed.post/mid",
                "cid": "cidb",
                "author": { "did": "did:plc:b", "handle": "bob.bsky.social" },
                "record": { "text": "子", "createdAt": "2026-06-04T12:05:00.000Z" },
                "indexedAt": "2026-06-04T12:05:01.000Z"
              },
              "parent": {
                "$type": "app.bsky.feed.defs#threadViewPost",
                "post": {
                  "uri": "at://did:plc:a/app.bsky.feed.post/root",
                  "cid": "cida",
                  "author": { "did": "did:plc:a", "handle": "alice.bsky.social" },
                  "record": { "text": "親", "createdAt": "2026-06-04T12:00:00.000Z" },
                  "indexedAt": "2026-06-04T12:00:01.000Z"
                }
              }
            }
          }
        }
        """##.utf8)

        let response = try JSONDecoder().decode(ThreadResponse.self, from: body)

        XCTAssertEqual(response.thread.post.author.handle, "carol.bsky.social")
        XCTAssertEqual(response.thread.parent?.post.author.handle, "bob.bsky.social")
        XCTAssertEqual(response.thread.parent?.parent?.post.author.handle, "alice.bsky.social")
        XCTAssertNil(response.thread.parent?.parent?.parent)
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

    func testDecodesChildRepliesSkippingNotFoundAndBlocked() throws {
        let body = Data(##"""
        {
          "thread": {
            "$type": "app.bsky.feed.defs#threadViewPost",
            "post": {
              "uri": "at://did:plc:a/app.bsky.feed.post/anchor",
              "cid": "cida",
              "author": { "did": "did:plc:a", "handle": "alice.bsky.social" },
              "record": { "text": "起点", "createdAt": "2026-06-04T12:00:00.000Z" },
              "indexedAt": "2026-06-04T12:00:01.000Z"
            },
            "replies": [
              {
                "$type": "app.bsky.feed.defs#threadViewPost",
                "post": {
                  "uri": "at://did:plc:b/app.bsky.feed.post/b",
                  "cid": "cidb",
                  "author": { "did": "did:plc:b", "handle": "bob.bsky.social" },
                  "record": { "text": "返信B", "createdAt": "2026-06-04T12:05:00.000Z" },
                  "indexedAt": "2026-06-04T12:05:01.000Z"
                },
                "replies": [
                  {
                    "$type": "app.bsky.feed.defs#threadViewPost",
                    "post": {
                      "uri": "at://did:plc:c/app.bsky.feed.post/c",
                      "cid": "cidc",
                      "author": { "did": "did:plc:c", "handle": "carol.bsky.social" },
                      "record": { "text": "返信C", "createdAt": "2026-06-04T12:06:00.000Z" },
                      "indexedAt": "2026-06-04T12:06:01.000Z"
                    }
                  }
                ]
              },
              {
                "$type": "app.bsky.feed.defs#notFoundPost",
                "uri": "at://did:plc:ghost/app.bsky.feed.post/gone",
                "notFound": true
              },
              {
                "$type": "app.bsky.feed.defs#threadViewPost",
                "post": {
                  "uri": "at://did:plc:d/app.bsky.feed.post/d",
                  "cid": "cidd",
                  "author": { "did": "did:plc:d", "handle": "dave.bsky.social" },
                  "record": { "text": "返信D", "createdAt": "2026-06-04T12:07:00.000Z" },
                  "indexedAt": "2026-06-04T12:07:01.000Z"
                }
              }
            ]
          }
        }
        """##.utf8)

        let response = try JSONDecoder().decode(ThreadResponse.self, from: body)

        // notFound child dropped: B and D remain, in server order.
        XCTAssertEqual(response.thread.replies.count, 2)
        XCTAssertEqual(response.thread.replies[0].post.author.handle, "bob.bsky.social")
        XCTAssertEqual(response.thread.replies[1].post.author.handle, "dave.bsky.social")
        // Nested reply under B.
        XCTAssertEqual(response.thread.replies[0].replies.count, 1)
        XCTAssertEqual(response.thread.replies[0].replies[0].post.author.handle, "carol.bsky.social")
        // A leaf reply has no children.
        XCTAssertTrue(response.thread.replies[1].replies.isEmpty)
    }
}
