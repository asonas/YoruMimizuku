import XCTest
@testable import BlueskyCore

final class NotificationsResponseTests: XCTestCase {
    /// Trimmed `app.bsky.notification.listNotifications` response covering a like
    /// (record carries no text), a reply (record is a post with text), a follow
    /// (no reasonSubject), and an unknown reason that must not break decoding.
    private let fixture = Data(##"""
    {
      "cursor": "next-page",
      "notifications": [
        {
          "uri": "at://did:plc:bob/app.bsky.feed.like/aaa",
          "cid": "cidlike",
          "author": {
            "did": "did:plc:bob",
            "handle": "bob.bsky.social",
            "displayName": "Bob",
            "avatar": "https://cdn.example/bob.jpg"
          },
          "reason": "like",
          "reasonSubject": "at://did:plc:me/app.bsky.feed.post/mine",
          "record": { "$type": "app.bsky.feed.like", "createdAt": "2026-06-04T12:00:00.000Z" },
          "isRead": false,
          "indexedAt": "2026-06-04T12:00:01.000Z"
        },
        {
          "uri": "at://did:plc:carol/app.bsky.feed.post/bbb",
          "cid": "cidreply",
          "author": { "did": "did:plc:carol", "handle": "carol.bsky.social" },
          "reason": "reply",
          "reasonSubject": "at://did:plc:me/app.bsky.feed.post/mine",
          "record": { "$type": "app.bsky.feed.post", "text": "nice work!", "createdAt": "2026-06-04T11:00:00.000Z" },
          "isRead": true,
          "indexedAt": "2026-06-04T11:00:01.000Z"
        },
        {
          "uri": "at://did:plc:dave/app.bsky.graph.follow/ccc",
          "cid": "cidfollow",
          "author": { "did": "did:plc:dave", "handle": "dave.bsky.social", "displayName": "Dave" },
          "reason": "follow",
          "record": { "$type": "app.bsky.graph.follow", "createdAt": "2026-06-04T10:00:00.000Z" },
          "isRead": false,
          "indexedAt": "2026-06-04T10:00:01.000Z"
        },
        {
          "uri": "at://did:plc:eve/app.bsky.feed.post/ddd",
          "cid": "cidother",
          "author": { "did": "did:plc:eve", "handle": "eve.bsky.social" },
          "reason": "starterpack-joined",
          "record": { "$type": "app.bsky.feed.post", "createdAt": "2026-06-04T09:00:00.000Z" },
          "isRead": false,
          "indexedAt": "2026-06-04T09:00:01.000Z"
        }
      ]
    }
    """##.utf8)

    func testDecodesCursorAndAllItems() throws {
        let response = try JSONDecoder().decode(ListNotificationsResponse.self, from: fixture)
        XCTAssertEqual(response.cursor, "next-page")
        XCTAssertEqual(response.notifications.count, 4)
    }

    func testDecodesLikeNotification() throws {
        let item = try JSONDecoder().decode(ListNotificationsResponse.self, from: fixture).notifications[0]
        XCTAssertEqual(item.reason, .like)
        XCTAssertEqual(item.author.handle, "bob.bsky.social")
        XCTAssertEqual(item.author.avatar, "https://cdn.example/bob.jpg")
        XCTAssertEqual(item.reasonSubject, "at://did:plc:me/app.bsky.feed.post/mine")
        XCTAssertNil(item.record.text)
        XCTAssertFalse(item.isRead)
    }

    func testDecodesReplyNotificationText() throws {
        let item = try JSONDecoder().decode(ListNotificationsResponse.self, from: fixture).notifications[1]
        XCTAssertEqual(item.reason, .reply)
        XCTAssertEqual(item.record.text, "nice work!")
        XCTAssertTrue(item.isRead)
    }

    func testFollowHasNoReasonSubject() throws {
        let item = try JSONDecoder().decode(ListNotificationsResponse.self, from: fixture).notifications[2]
        XCTAssertEqual(item.reason, .follow)
        XCTAssertNil(item.reasonSubject)
    }

    func testUnknownReasonDecodesToOther() throws {
        let item = try JSONDecoder().decode(ListNotificationsResponse.self, from: fixture).notifications[3]
        XCTAssertEqual(item.reason, .other("starterpack-joined"))
    }
}
