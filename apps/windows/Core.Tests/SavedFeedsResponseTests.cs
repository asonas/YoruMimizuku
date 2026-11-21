using System.Text.Json;

namespace YoruMimizuku.Core.Tests;

/// Ported from core/Tests/BlueskyCoreTests/SavedFeedsModelsTests.swift.
public class SavedFeedsResponseTests
{
    private static JsonElement Parse(string json) => JsonDocument.Parse(json).RootElement;

    [Fact]
    public void PreferencesDecodeSavedFeedsAndSkipOtherPreferenceKinds()
    {
        var body = Parse("""
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
        """);

        var response = PreferencesResponse.FromJson(body);

        Assert.Equal(["timeline", "feed", "list", "feed", "somethingNew"], response.SavedFeeds.Select(i => i.Type));
        Assert.Equal("at://did:plc:x/app.bsky.feed.generator/talk", response.SavedFeeds[1].Value);
        Assert.Equal([true, true, true, false, true], response.SavedFeeds.Select(i => i.Pinned));
    }

    [Fact]
    public void PreferencesWithoutSavedFeedsDecodeToAnEmptyList()
    {
        var body = Parse("""{"preferences":[{"$type":"app.bsky.actor.defs#adultContentPref","enabled":true}]}""");

        var response = PreferencesResponse.FromJson(body);

        Assert.Empty(response.SavedFeeds);
    }

    [Fact]
    public void FeedGeneratorsDecodeNameDescriptionCreatorAndAvatar()
    {
        var body = Parse("""
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
        """);

        var feed = Assert.Single(FeedGeneratorsResponse.FromJson(body).Feeds);

        Assert.Equal("at://did:plc:x/app.bsky.feed.generator/talk", feed.Uri);
        Assert.Equal("話題の議論", feed.DisplayName);
        Assert.Equal("フォロー中の人が返信した会話", feed.Description);
        Assert.Equal("discuss.feeds.example", feed.Creator.Handle);
        Assert.Equal("https://cdn.example/a.jpg", feed.Avatar);
    }

    [Fact]
    public void ListDecodesNameAndCreator()
    {
        var body = Parse("""
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
        """);

        var list = ListResponse.FromJson(body).List;

        Assert.Equal("近しい人", list.Name);
        Assert.Null(list.Description);
        Assert.Equal("me.example", list.Creator.Handle);
    }
}
