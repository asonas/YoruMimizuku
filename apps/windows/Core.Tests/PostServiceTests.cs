namespace YoruMimizuku.Core.Tests;

public class PostServiceTests
{
    private const string PostsBody = """
        {
          "posts": [
            {
              "uri": "at://did:plc:me/app.bsky.feed.post/mine",
              "cid": "cidpost",
              "author": { "did": "did:plc:me", "handle": "me.bsky.social", "displayName": "Me" },
              "record": { "$type": "app.bsky.feed.post", "text": "hello world", "createdAt": "2026-06-04T12:00:00.000Z" },
              "replyCount": 0, "repostCount": 1, "likeCount": 2,
              "indexedAt": "2026-06-04T12:00:00.000Z"
            }
          ]
        }
        """;

    [Fact]
    public async Task GetPostsSendsEveryUriAndDecodes()
    {
        var http = new StubHttp(PostsBody);
        string[] uris = ["at://did:plc:me/app.bsky.feed.post/mine", "at://did:plc:you/app.bsky.feed.post/yours"];

        var response = await new PostService(http.Xrpc()).GetPostsAsync(uris, CancellationToken.None);

        Assert.Equal("hello world", Assert.Single(response.Posts).Record.Text);
        Assert.Equal(HttpMethod.Get, http.Last.Method);
        Assert.Equal("/xrpc/app.bsky.feed.getPosts", http.Last.Path);
        Assert.Equal(uris, http.Last.Query.GetValues("uris")!);
    }

    [Fact]
    public async Task GetPostsWithNoUrisSendsNothing()
    {
        var http = new StubHttp(PostsBody);

        var response = await new PostService(http.Xrpc()).GetPostsAsync([], CancellationToken.None);

        Assert.Empty(response.Posts);
        Assert.Empty(http.Requests);
    }
}
