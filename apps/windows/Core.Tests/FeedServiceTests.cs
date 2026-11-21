namespace YoruMimizuku.Core.Tests;

public class FeedServiceTests
{
    private const string FeedBody = """
        {
          "cursor": "next-page",
          "feed": [
            {
              "post": {
                "uri": "at://did:plc:alice/app.bsky.feed.post/aaa",
                "cid": "bafyreialice",
                "author": { "did": "did:plc:alice", "handle": "alice.bsky.social", "displayName": "Alice" },
                "record": { "$type": "app.bsky.feed.post", "text": "hi", "createdAt": "2026-06-04T12:00:00.000Z" },
                "indexedAt": "2026-06-04T12:00:01.000Z"
              }
            }
          ]
        }
        """;

    private const string ThreadBody = """
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
                "record": { "text": "親", "createdAt": "2026-06-04T12:00:00.000Z" },
                "indexedAt": "2026-06-04T12:00:01.000Z"
              }
            }
          }
        }
        """;

    // A cursor holding '+', which a query string would otherwise decode as a space.
    private const string PlusCursor = "1718000000000+bafy/x=y&z";

    [Fact]
    public async Task GetTimelineSendsAGetAndDecodesThePage()
    {
        var http = new StubHttp(FeedBody);

        var page = await new FeedService(http.Xrpc()).GetTimelineAsync();

        Assert.Equal("alice.bsky.social", Assert.Single(page.Feed).Post.Author.Handle);
        Assert.Equal("next-page", page.Cursor);
        Assert.Equal(HttpMethod.Get, http.Last.Method);
        Assert.Equal("https://pds.example/xrpc/app.bsky.feed.getTimeline", http.Last.Uri.GetLeftPart(UriPartial.Path));
        Assert.Equal("50", http.Last.Query["limit"]);
        Assert.Null(http.Last.Query["cursor"]);
    }

    [Fact]
    public async Task GetTimelineSendsTheCursorUnchanged()
    {
        var http = new StubHttp(FeedBody);

        await new FeedService(http.Xrpc()).GetTimelineAsync(PlusCursor, limit: 20);

        Assert.Equal(PlusCursor, http.Last.Query["cursor"]);
        Assert.Equal("20", http.Last.Query["limit"]);
    }

    [Fact]
    public async Task GetAuthorFeedSendsTheActorAndFilterAndDecodes()
    {
        var http = new StubHttp(FeedBody);

        var page = await new FeedService(http.Xrpc()).GetAuthorFeedAsync("did:plc:alice");

        Assert.Single(page.Feed);
        Assert.Equal("next-page", page.Cursor);
        Assert.Equal("/xrpc/app.bsky.feed.getAuthorFeed", http.Last.Path);
        Assert.Equal("did:plc:alice", http.Last.Query["actor"]);
        Assert.Equal("posts_and_author_threads", http.Last.Query["filter"]);
        Assert.Equal("50", http.Last.Query["limit"]);
        Assert.Null(http.Last.Query["cursor"]);
    }

    [Fact]
    public async Task GetAuthorFeedSendsTheCursorUnchanged()
    {
        var http = new StubHttp(FeedBody);

        await new FeedService(http.Xrpc()).GetAuthorFeedAsync("did:plc:alice", PlusCursor);

        Assert.Equal(PlusCursor, http.Last.Query["cursor"]);
    }

    [Fact]
    public async Task GetPostThreadAsksForAncestorsAndRepliesAndDecodes()
    {
        var http = new StubHttp(ThreadBody);

        var thread = await new FeedService(http.Xrpc()).GetPostThreadAsync("at://did:plc:bob/app.bsky.feed.post/reply");

        Assert.Equal("bob.bsky.social", thread.Thread.Post.Author.Handle);
        Assert.Equal("alice.bsky.social", thread.Thread.ParentPost?.Author.Handle);
        Assert.Equal("/xrpc/app.bsky.feed.getPostThread", http.Last.Path);
        Assert.Equal("at://did:plc:bob/app.bsky.feed.post/reply", http.Last.Query["uri"]);
        Assert.Equal("6", http.Last.Query["depth"]);
        Assert.Equal("80", http.Last.Query["parentHeight"]);
    }
}
