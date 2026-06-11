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
            "indexedAt": "2026-06-04T12:00:01.000Z",
            "embed": {
              "$type": "app.bsky.embed.images#view",
              "images": [
                {
                  "thumb": "https://cdn.example/thumb1.jpg",
                  "fullsize": "https://cdn.example/full1.jpg",
                  "alt": "a cat",
                  "aspectRatio": { "width": 1600, "height": 900 }
                },
                {
                  "thumb": "https://cdn.example/thumb2.jpg",
                  "fullsize": "https://cdn.example/full2.jpg",
                  "alt": ""
                }
              ]
            }
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

    func testDecodesImageEmbed() throws {
        let response = try JSONDecoder().decode(TimelineResponse.self, from: fixture)
        let images = try XCTUnwrap(response.feed[0].post.embed?.images)

        XCTAssertEqual(images.count, 2)
        XCTAssertEqual(images[0].thumb, "https://cdn.example/thumb1.jpg")
        XCTAssertEqual(images[0].fullsize, "https://cdn.example/full1.jpg")
        XCTAssertEqual(images[0].alt, "a cat")
        XCTAssertEqual(images[1].alt, "")
    }

    func testDecodesImageAspectRatio() throws {
        let response = try JSONDecoder().decode(TimelineResponse.self, from: fixture)
        let images = try XCTUnwrap(response.feed[0].post.embed?.images)

        XCTAssertEqual(images[0].aspectRatio?.width, 1600)
        XCTAssertEqual(images[0].aspectRatio?.height, 900)
    }

    func testImageWithoutAspectRatioHasNilAspectRatio() throws {
        let response = try JSONDecoder().decode(TimelineResponse.self, from: fixture)
        let images = try XCTUnwrap(response.feed[0].post.embed?.images)

        XCTAssertNil(images[1].aspectRatio)
    }

    func testPostWithoutEmbedHasNilEmbed() throws {
        let response = try JSONDecoder().decode(TimelineResponse.self, from: fixture)
        XCTAssertNil(response.feed[1].post.embed)
    }

    func testDecodesReplyParent() throws {
        let json = Data(##"""
        {
          "post": {
            "uri": "at://did:plc:alice/app.bsky.feed.post/reply",
            "cid": "cid",
            "author": { "did": "did:plc:alice", "handle": "alice.bsky.social" },
            "record": { "$type": "app.bsky.feed.post", "text": "agreed!", "createdAt": "2026-06-04T12:00:00Z" },
            "indexedAt": "2026-06-04T12:00:01Z"
          },
          "reply": {
            "root": {
              "$type": "app.bsky.feed.defs#postView",
              "uri": "at://did:plc:bob/app.bsky.feed.post/root",
              "cid": "cidroot",
              "author": { "did": "did:plc:bob", "handle": "bob.bsky.social" },
              "record": { "$type": "app.bsky.feed.post", "text": "root", "createdAt": "2026-06-04T11:00:00Z" },
              "indexedAt": "2026-06-04T11:00:01Z"
            },
            "parent": {
              "$type": "app.bsky.feed.defs#postView",
              "uri": "at://did:plc:bob/app.bsky.feed.post/parent",
              "cid": "cidparent",
              "author": { "did": "did:plc:bob", "handle": "bob.bsky.social", "displayName": "Bob" },
              "record": { "$type": "app.bsky.feed.post", "text": "original question", "createdAt": "2026-06-04T11:30:00Z" },
              "indexedAt": "2026-06-04T11:30:01Z"
            }
          }
        }
        """##.utf8)
        let item = try JSONDecoder().decode(FeedViewPost.self, from: json)

        XCTAssertEqual(item.reply?.parent?.author.handle, "bob.bsky.social")
        XCTAssertEqual(item.reply?.parent?.record.text, "original question")
    }

    func testReplyWithNotFoundParentDecodesToNilParent() throws {
        let json = Data(##"""
        {
          "post": {
            "uri": "at://did:plc:alice/app.bsky.feed.post/reply",
            "cid": "cid",
            "author": { "did": "did:plc:alice", "handle": "alice.bsky.social" },
            "record": { "$type": "app.bsky.feed.post", "text": "reply", "createdAt": "2026-06-04T12:00:00Z" },
            "indexedAt": "2026-06-04T12:00:01Z"
          },
          "reply": {
            "parent": { "$type": "app.bsky.feed.defs#notFoundPost", "uri": "at://x", "notFound": true }
          }
        }
        """##.utf8)
        let item = try JSONDecoder().decode(FeedViewPost.self, from: json)

        XCTAssertNotNil(item.reply)
        XCTAssertNil(item.reply?.parent)
    }

    func testDecodesViewerLikeAndRepostState() throws {
        let json = Data(##"""
        {
          "uri": "at://did:plc:x/app.bsky.feed.post/x",
          "cid": "cid",
          "author": { "did": "did:plc:x", "handle": "x.bsky.social" },
          "record": { "$type": "app.bsky.feed.post", "text": "hi", "createdAt": "2026-06-04T12:00:00Z" },
          "indexedAt": "2026-06-04T12:00:01Z",
          "viewer": {
            "like": "at://did:plc:me/app.bsky.feed.like/abc",
            "repost": "at://did:plc:me/app.bsky.feed.repost/def"
          }
        }
        """##.utf8)
        let post = try JSONDecoder().decode(PostView.self, from: json)

        XCTAssertEqual(post.viewer?.like, "at://did:plc:me/app.bsky.feed.like/abc")
        XCTAssertEqual(post.viewer?.repost, "at://did:plc:me/app.bsky.feed.repost/def")
    }

    func testViewerStateOmitsUnsetFields() throws {
        let json = Data(##"""
        {
          "uri": "at://did:plc:x/app.bsky.feed.post/x",
          "cid": "cid",
          "author": { "did": "did:plc:x", "handle": "x.bsky.social" },
          "record": { "$type": "app.bsky.feed.post", "text": "hi", "createdAt": "2026-06-04T12:00:00Z" },
          "indexedAt": "2026-06-04T12:00:01Z",
          "viewer": { "threadMuted": false, "embeddingDisabled": false }
        }
        """##.utf8)
        let post = try JSONDecoder().decode(PostView.self, from: json)

        XCTAssertNotNil(post.viewer)
        XCTAssertNil(post.viewer?.like)
        XCTAssertNil(post.viewer?.repost)
    }

    func testNonImageEmbedDecodesToEmptyImages() throws {
        // A record embed (different shape) must not break decoding; images is empty.
        let json = Data(##"""
        {
          "uri": "at://did:plc:x/app.bsky.feed.post/x",
          "cid": "cid",
          "author": { "did": "did:plc:x", "handle": "x.bsky.social" },
          "record": { "$type": "app.bsky.feed.post", "text": "quote", "createdAt": "2026-06-04T12:00:00Z" },
          "indexedAt": "2026-06-04T12:00:01Z",
          "embed": { "$type": "app.bsky.embed.record#view", "record": { "uri": "at://did:plc:y/app.bsky.feed.post/y" } }
        }
        """##.utf8)
        let post = try JSONDecoder().decode(PostView.self, from: json)
        XCTAssertEqual(post.embed?.images, [])
    }

    func testDecodesExternalEmbed() throws {
        let json = Data(##"""
        {
          "uri": "at://did:plc:x/app.bsky.feed.post/x",
          "cid": "cid",
          "author": { "did": "did:plc:x", "handle": "x.bsky.social" },
          "record": { "$type": "app.bsky.feed.post", "text": "link", "createdAt": "2026-06-04T12:00:00Z" },
          "indexedAt": "2026-06-04T12:00:01Z",
          "embed": {
            "$type": "app.bsky.embed.external#view",
            "external": {
              "uri": "https://www.ableton.com/ja/blog/satsuki/",
              "title": "Satsuki on her new EP",
              "description": "An interview with the artist.",
              "thumb": "https://cdn.bsky.app/img/feed_thumbnail/plain/did:plc:x/bafkthumb@jpeg"
            }
          }
        }
        """##.utf8)
        let post = try JSONDecoder().decode(PostView.self, from: json)
        let external = try XCTUnwrap(post.embed?.external)

        XCTAssertEqual(external.uri, "https://www.ableton.com/ja/blog/satsuki/")
        XCTAssertEqual(external.title, "Satsuki on her new EP")
        XCTAssertEqual(external.description, "An interview with the artist.")
        XCTAssertEqual(external.thumb, "https://cdn.bsky.app/img/feed_thumbnail/plain/did:plc:x/bafkthumb@jpeg")
        XCTAssertEqual(post.embed?.images, [])
    }

    func testExternalEmbedWithoutThumbDecodes() throws {
        let json = Data(##"""
        {
          "uri": "at://did:plc:x/app.bsky.feed.post/x",
          "cid": "cid",
          "author": { "did": "did:plc:x", "handle": "x.bsky.social" },
          "record": { "$type": "app.bsky.feed.post", "text": "link", "createdAt": "2026-06-04T12:00:00Z" },
          "indexedAt": "2026-06-04T12:00:01Z",
          "embed": {
            "$type": "app.bsky.embed.external#view",
            "external": {
              "uri": "https://example.com/article",
              "title": "Article",
              "description": ""
            }
          }
        }
        """##.utf8)
        let post = try JSONDecoder().decode(PostView.self, from: json)
        let external = try XCTUnwrap(post.embed?.external)

        XCTAssertEqual(external.uri, "https://example.com/article")
        XCTAssertNil(external.thumb)
    }

    func testImageEmbedHasNilExternal() throws {
        let response = try JSONDecoder().decode(TimelineResponse.self, from: fixture)
        XCTAssertNil(response.feed[0].post.embed?.external)
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

    func testDecodesRecordFacetsForLinkTagAndMention() throws {
        let json = Data(##"""
        {
          "$type": "app.bsky.feed.post",
          "text": "see https://example.com #swift cc @bob.bsky.social",
          "createdAt": "2026-06-04T12:00:00Z",
          "facets": [
            {
              "index": { "byteStart": 4, "byteEnd": 23 },
              "features": [
                { "$type": "app.bsky.richtext.facet#link", "uri": "https://example.com" }
              ]
            },
            {
              "index": { "byteStart": 24, "byteEnd": 30 },
              "features": [
                { "$type": "app.bsky.richtext.facet#tag", "tag": "swift" }
              ]
            },
            {
              "index": { "byteStart": 34, "byteEnd": 50 },
              "features": [
                { "$type": "app.bsky.richtext.facet#mention", "did": "did:plc:bob" }
              ]
            }
          ]
        }
        """##.utf8)
        let record = try JSONDecoder().decode(PostRecord.self, from: json)

        XCTAssertEqual(record.facets.count, 3)
        XCTAssertEqual(record.facets[0].byteStart, 4)
        XCTAssertEqual(record.facets[0].byteEnd, 23)
        XCTAssertEqual(record.facets[0].features, [.link(uri: "https://example.com")])
        XCTAssertEqual(record.facets[1].features, [.tag(tag: "swift")])
        XCTAssertEqual(record.facets[2].features, [.mention(did: "did:plc:bob")])
    }

    func testRecordWithoutFacetsDecodesToEmpty() throws {
        let json = Data(##"""
        { "$type": "app.bsky.feed.post", "text": "plain", "createdAt": "2026-06-04T12:00:00Z" }
        """##.utf8)
        let record = try JSONDecoder().decode(PostRecord.self, from: json)
        XCTAssertEqual(record.facets, [])
    }

    func testUnknownFacetFeatureIsDropped() throws {
        let json = Data(##"""
        {
          "$type": "app.bsky.feed.post",
          "text": "x",
          "createdAt": "2026-06-04T12:00:00Z",
          "facets": [
            {
              "index": { "byteStart": 0, "byteEnd": 1 },
              "features": [ { "$type": "app.bsky.richtext.facet#unknownFuture", "foo": "bar" } ]
            }
          ]
        }
        """##.utf8)
        let record = try JSONDecoder().decode(PostRecord.self, from: json)
        XCTAssertEqual(record.facets.count, 1)
        XCTAssertEqual(record.facets[0].features, [])
    }
}
