import XCTest
@testable import BlueskyCore

final class SearchResponseTests: XCTestCase {
    private let fixture = Data(##"""
    {
      "cursor": "next-page",
      "hitsTotal": 42,
      "posts": [
        {
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
            "text": "hello #swift",
            "createdAt": "2026-06-04T12:00:00.000Z",
            "facets": [
              {
                "index": { "byteStart": 6, "byteEnd": 12 },
                "features": [ { "$type": "app.bsky.richtext.facet#tag", "tag": "swift" } ]
              }
            ]
          },
          "replyCount": 1,
          "repostCount": 2,
          "likeCount": 3,
          "indexedAt": "2026-06-04T12:00:01.000Z"
        }
      ]
    }
    """##.utf8)

    func testDecodesPostsCursorAndHitsTotal() throws {
        let response = try JSONDecoder().decode(SearchResponse.self, from: fixture)

        XCTAssertEqual(response.cursor, "next-page")
        XCTAssertEqual(response.hitsTotal, 42)
        XCTAssertEqual(response.posts.count, 1)
        XCTAssertEqual(response.posts[0].author.handle, "alice.bsky.social")
        XCTAssertEqual(response.posts[0].record.facets.first?.features, [.tag(tag: "swift")])
    }

    func testDecodesWithoutOptionalFields() throws {
        let json = Data(##"{ "posts": [] }"##.utf8)
        let response = try JSONDecoder().decode(SearchResponse.self, from: json)

        XCTAssertTrue(response.posts.isEmpty)
        XCTAssertNil(response.cursor)
        XCTAssertNil(response.hitsTotal)
    }
}
