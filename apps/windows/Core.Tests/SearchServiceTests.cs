namespace YoruMimizuku.Core.Tests;

public class SearchServiceTests
{
    private const string SearchBody = """
        {
          "cursor": "next",
          "posts": [
            {
              "uri": "at://did:plc:alice/app.bsky.feed.post/aaa",
              "cid": "bafyreialice",
              "author": { "did": "did:plc:alice", "handle": "alice.bsky.social", "displayName": "Alice" },
              "record": { "$type": "app.bsky.feed.post", "text": "hi #swift", "createdAt": "2026-06-04T12:00:00.000Z" },
              "indexedAt": "2026-06-04T12:00:01.000Z"
            }
          ]
        }
        """;

    [Fact]
    public async Task SendsTheQueryAndLimitAndDecodes()
    {
        var http = new StubHttp(SearchBody);

        var response = await new SearchService(http.Xrpc())
            .SearchPostsAsync(new SearchPostsRequest("#swift from:alice.bsky.social"), CancellationToken.None);

        Assert.Single(response.Posts);
        Assert.Equal("next", response.Cursor);
        Assert.Equal("https://pds.example/xrpc/app.bsky.feed.searchPosts", http.Last.Uri.GetLeftPart(UriPartial.Path));
        Assert.Equal("#swift from:alice.bsky.social", http.Last.Query["q"]);
        Assert.Equal("25", http.Last.Query["limit"]);
        Assert.Null(http.Last.Query["cursor"]);
        Assert.Null(http.Last.Query["sort"]);
    }

    [Fact]
    public async Task IncludesCursorAndSortWhenSet()
    {
        var http = new StubHttp(SearchBody);

        await new SearchService(http.Xrpc())
            .SearchPostsAsync(new SearchPostsRequest("cats", Cursor: "page-2", Sort: "latest"), CancellationToken.None);

        Assert.Equal("page-2", http.Last.Query["cursor"]);
        Assert.Equal("latest", http.Last.Query["sort"]);
    }

    // A query string decodes a literal '+' as a space. The Swift core leaves '+' unescaped
    // in the cursor, so the server reads a different cursor than the one it sent.
    [Fact]
    public async Task CursorWithPlusReachesTheServerUnchanged()
    {
        var http = new StubHttp(SearchBody);

        await new SearchService(http.Xrpc())
            .SearchPostsAsync(new SearchPostsRequest("cats", Cursor: "1718000000000+bafy/x=y&z"), CancellationToken.None);

        Assert.Equal("1718000000000+bafy/x=y&z", http.Last.Query["cursor"]);
    }
}
