import XCTest
@testable import BlueskyCore

final class RecordResponseTests: XCTestCase {
    /// `com.atproto.repo.getRecord` returns the record as stored; the レコード tab
    /// shows it verbatim, pretty-printed with sorted keys.
    func testAnyRecordValueRoundTripsToPrettyJSON() throws {
        let body = Data(##"""
        {
          "uri": "at://did:plc:alice/app.bsky.feed.post/3k",
          "cid": "bafy",
          "value": {
            "text": "hi",
            "$type": "app.bsky.feed.post",
            "langs": ["ja"],
            "createdAt": "2026-11-20T03:10:00.000Z",
            "embed": { "$type": "app.bsky.embed.images", "images": [{ "alt": "", "aspectRatio": { "width": 1600, "height": 1000 } }] },
            "reply": null,
            "labels": false,
            "score": 1.5
          }
        }
        """##.utf8)

        let response = try JSONDecoder().decode(RecordResponse.self, from: body)

        XCTAssertEqual(response.uri, "at://did:plc:alice/app.bsky.feed.post/3k")
        XCTAssertEqual(response.prettyValue, ##"""
        {
          "$type" : "app.bsky.feed.post",
          "createdAt" : "2026-11-20T03:10:00.000Z",
          "embed" : {
            "$type" : "app.bsky.embed.images",
            "images" : [
              {
                "alt" : "",
                "aspectRatio" : {
                  "height" : 1000,
                  "width" : 1600
                }
              }
            ]
          },
          "labels" : false,
          "langs" : [
            "ja"
          ],
          "reply" : null,
          "score" : 1.5,
          "text" : "hi"
        }
        """##)
    }

    /// Integers beyond a Double's 53-bit precision come back exactly as stored.
    func testLargeIntegersKeepTheirExactValue() throws {
        let body = Data(#"{"uri":"at://a/b/c","value":{"n":9007199254740993}}"#.utf8)

        let response = try JSONDecoder().decode(RecordResponse.self, from: body)

        XCTAssertTrue(response.prettyValue.contains("9007199254740993"), response.prettyValue)
    }
}
