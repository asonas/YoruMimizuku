import XCTest
@testable import BlueskyCore

final class SavedFeedsModelsTests: XCTestCase {
    func testPreferencesDecodeSavedFeedsAndSkipOtherPreferenceKinds() throws {
        let body = Data(##"""
        {
          "preferences": [
            { "$type": "app.bsky.actor.defs#adultContentPref", "enabled": false },
            { "$type": "app.bsky.actor.defs#mutedWordsPref", "items": [{ "value": "spoiler", "targets": ["content"] }] },
            { "$type": "app.bsky.actor.defs#hiddenPostsPref", "items": ["at://did:plc:z/app.bsky.feed.post/1"] },
            {
              "$type": "app.bsky.actor.defs#savedFeedsPrefV2",
              "items": [
                { "id": "1", "type": "timeline", "value": "following", "pinned": true },
                { "id": "2", "type": "feed", "value": "at://did:plc:x/app.bsky.feed.generator/talk", "pinned": true },
                { "id": "3", "type": "list", "value": "at://did:plc:me/app.bsky.graph.list/close", "pinned": true },
                { "id": "4", "type": "feed", "value": "at://did:plc:y/app.bsky.feed.generator/old", "pinned": false },
                { "id": "5", "type": "somethingNew", "value": "x", "pinned": true }
              ]
            }
          ]
        }
        """##.utf8)

        let response = try JSONDecoder().decode(PreferencesResponse.self, from: body)

        XCTAssertEqual(response.savedFeeds.map(\.type), ["timeline", "feed", "list", "feed", "somethingNew"])
        XCTAssertEqual(response.savedFeeds[1].value, "at://did:plc:x/app.bsky.feed.generator/talk")
        XCTAssertEqual(response.savedFeeds.map(\.pinned), [true, true, true, false, true])
    }

    func testPreferencesWithoutSavedFeedsDecodeToAnEmptyList() throws {
        let body = Data(#"{"preferences":[{"$type":"app.bsky.actor.defs#adultContentPref","enabled":true}]}"#.utf8)

        let response = try JSONDecoder().decode(PreferencesResponse.self, from: body)

        XCTAssertEqual(response.savedFeeds, [])
    }

    func testFeedGeneratorsDecodeNameDescriptionCreatorAndAvatar() throws {
        let body = Data(##"""
        {
          "feeds": [
            {
              "uri": "at://did:plc:x/app.bsky.feed.generator/talk",
              "cid": "bafy",
              "did": "did:web:feeds.example",
              "creator": { "did": "did:plc:x", "handle": "discuss.feeds.example" },
              "displayName": "話題の議論",
              "description": "フォロー中の人が返信した会話",
              "avatar": "https://cdn.example/a.jpg",
              "indexedAt": "2026-11-20T00:00:00.000Z"
            }
          ]
        }
        """##.utf8)

        let response = try JSONDecoder().decode(FeedGeneratorsResponse.self, from: body)

        let feed = try XCTUnwrap(response.feeds.first)
        XCTAssertEqual(feed.uri, "at://did:plc:x/app.bsky.feed.generator/talk")
        XCTAssertEqual(feed.displayName, "話題の議論")
        XCTAssertEqual(feed.description, "フォロー中の人が返信した会話")
        XCTAssertEqual(feed.creator.handle, "discuss.feeds.example")
        XCTAssertEqual(feed.avatar, "https://cdn.example/a.jpg")
    }

    func testListDecodesNameAndCreator() throws {
        let body = Data(##"""
        {
          "list": {
            "uri": "at://did:plc:me/app.bsky.graph.list/close",
            "cid": "bafy",
            "name": "近しい人",
            "purpose": "app.bsky.graph.defs#curatelist",
            "creator": { "did": "did:plc:me", "handle": "me.example" },
            "indexedAt": "2026-11-20T00:00:00.000Z"
          },
          "items": []
        }
        """##.utf8)

        let response = try JSONDecoder().decode(ListResponse.self, from: body)

        XCTAssertEqual(response.list.name, "近しい人")
        XCTAssertNil(response.list.description)
        XCTAssertEqual(response.list.creator.handle, "me.example")
    }
}
