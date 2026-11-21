using System.Text.Json;

namespace YoruMimizuku.Core.Tests;

public class SearchResponseTests
{
    private const string Fixture = """
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
    """;

    [Fact]
    public void DecodesPostsCursorAndHitsTotal()
    {
        var response = SearchResponse.FromJson(JsonElement.Parse(Fixture));

        Assert.Equal("next-page", response.Cursor);
        Assert.Equal(42, response.HitsTotal);
        var post = Assert.Single(response.Posts);
        Assert.Equal("alice.bsky.social", post.Author.Handle);
        Assert.Equal(new FacetFeature.Tag("swift"), Assert.Single(post.Record.Facets[0].Features));
    }

    [Fact]
    public void DecodesWithoutOptionalFields()
    {
        var response = SearchResponse.FromJson(JsonElement.Parse("""{ "posts": [] }"""));

        Assert.Empty(response.Posts);
        Assert.Null(response.Cursor);
        Assert.Null(response.HitsTotal);
    }
}
