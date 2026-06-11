import XCTest
import BlueskyCore
@testable import YoruMimizukuKit

/// End-to-end regression for the notifications pipeline using payloads shaped
/// like the live `app.bsky.notification.listNotifications` response (captured
/// 2026-06: profile `associated`/`labels` extras, reply records carrying
/// `reply` refs and image embeds, and post-2025 reason values). Guards against
/// a reply notification being dropped anywhere between decoding and grouping.
final class NotificationPipelineRegressionTests: XCTestCase {
    /// A page mirroring production data: a like from a followed user, a reply
    /// whose record has a `reply` ref plus an image embed and rich profile
    /// extras, and a `subscribed-post` (a reason newer than our closed enum).
    private let fixture = Data(##"""
    {
      "cursor": "2026-06-10T08:55:37.066Z",
      "notifications": [
        {
          "uri": "at://did:plc:liker/app.bsky.feed.like/3mnwxyz",
          "cid": "bafylike",
          "author": {
            "did": "did:plc:liker",
            "handle": "liker.bsky.social",
            "displayName": "Liker",
            "avatar": "https://cdn.bsky.app/img/avatar/plain/did:plc:liker/bafkavatar",
            "associated": { "chat": { "allowIncoming": "following" } },
            "labels": [],
            "createdAt": "2023-06-22T14:05:03.241Z"
          },
          "reason": "like",
          "reasonSubject": "at://did:plc:me/app.bsky.feed.post/3mnwc34o2ai2m",
          "record": {
            "$type": "app.bsky.feed.like",
            "createdAt": "2026-06-10T09:00:00.000Z",
            "subject": {
              "cid": "bafyparent",
              "uri": "at://did:plc:me/app.bsky.feed.post/3mnwc34o2ai2m"
            }
          },
          "isRead": false,
          "indexedAt": "2026-06-10T09:00:01.000Z"
        },
        {
          "uri": "at://did:plc:replier/app.bsky.feed.post/3mnwdnozac22s",
          "cid": "bafyreply",
          "author": {
            "did": "did:plc:replier",
            "handle": "replier.s01.ninja",
            "displayName": "Replier / G4",
            "avatar": "https://cdn.bsky.app/img/avatar/plain/did:plc:replier/bafkavatar2",
            "associated": {
              "chat": { "allowIncoming": "following" },
              "activitySubscription": { "allowSubscriptions": "followers" }
            },
            "labels": [],
            "createdAt": "2023-06-22T14:05:03.241Z"
          },
          "reason": "reply",
          "reasonSubject": "at://did:plc:me/app.bsky.feed.post/3mnwc34o2ai2m",
          "record": {
            "$type": "app.bsky.feed.post",
            "createdAt": "2026-06-10T08:55:21.213Z",
            "embed": {
              "$type": "app.bsky.embed.images",
              "images": [
                {
                  "alt": "",
                  "aspectRatio": { "height": 1206, "width": 1518 },
                  "image": {
                    "$type": "blob",
                    "ref": { "$link": "bafkreimage" },
                    "mimeType": "image/jpeg",
                    "size": 1807448
                  }
                }
              ]
            },
            "langs": ["ja"],
            "reply": {
              "parent": {
                "cid": "bafyparent",
                "uri": "at://did:plc:me/app.bsky.feed.post/3mnwc34o2ai2m"
              },
              "root": {
                "cid": "bafyparent",
                "uri": "at://did:plc:me/app.bsky.feed.post/3mnwc34o2ai2m"
              }
            },
            "text": ":eyes:"
          },
          "isRead": false,
          "indexedAt": "2026-06-10T08:55:37.066Z"
        },
        {
          "uri": "at://did:plc:subbed/app.bsky.feed.post/3mnwsub",
          "cid": "bafysub",
          "author": { "did": "did:plc:subbed", "handle": "subbed.bsky.social" },
          "reason": "subscribed-post",
          "record": {
            "$type": "app.bsky.feed.post",
            "createdAt": "2026-06-10T08:00:00.000Z",
            "text": "subscribed activity"
          },
          "isRead": false,
          "indexedAt": "2026-06-10T08:00:01.000Z"
        }
      ]
    }
    """##.utf8)

    func testReplySurvivesDecodeMapAndGrouping() throws {
        let response = try JSONDecoder().decode(ListNotificationsResponse.self, from: fixture)
        XCTAssertEqual(response.notifications.count, 3)

        let groups = NotificationGroup.group(response.notifications.map(NotificationDisplay.init))

        let reply = groups.first { $0.reason == .reply }
        XCTAssertNotNil(reply, "a reply notification must produce its own group")
        XCTAssertEqual(reply?.actors.first?.handle, "replier.s01.ninja")
        XCTAssertEqual(reply?.text, ":eyes:")
        XCTAssertEqual(reply?.subjectURI, "at://did:plc:me/app.bsky.feed.post/3mnwc34o2ai2m")
        // The page order (newest first) must be preserved: like, reply, then the
        // unknown-reason group.
        XCTAssertEqual(groups.map(\.reason), [.like, .reply, .other("subscribed-post")])
    }
}
