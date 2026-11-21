using System.Text;
using YoruMimizuku.Core;
using YoruMimizuku.Core.Tests;

namespace YoruMimizuku.App.Interop.Tests;

public class CoreOperationsTests
{
    [Fact]
    public void PermalinkFallsBackToTheDidForAnInvalidHandle()
    {
        const string id = "at://did:plc:me/app.bsky.feed.post/3kabc123";

        Assert.Equal("https://bsky.app/profile/alice.bsky.social/post/3kabc123",
            CoreOperations.PostPermalink(id, "alice.bsky.social").Url);
        Assert.Equal("https://bsky.app/profile/did:plc:me/post/3kabc123",
            CoreOperations.PostPermalink(id, "handle.invalid").Url);
        Assert.Null(CoreOperations.PostPermalink("not-a-uri", "alice.bsky.social").Url);
    }

    [Fact]
    public async Task OgpCardResolvesTheImageAgainstThePage()
    {
        var http = new StubHttp(_ => new HttpResponseMessage
        {
            Content = new StringContent("""
                <html><head>
                <meta property="og:title" content="Satsuki">
                <meta property="og:description" content="An interview.">
                <meta property="og:image" content="/img/card.jpg">
                </head></html>
                """, Encoding.UTF8, "text/html"),
        });
        var previews = new LinkPreviewLoader(new HttpClient(http));

        var card = await CoreOperations.OgpLoadAsync(previews, "https://www.ableton.com/ja/blog/satsuki/");

        BridgeJson.Equal("""
            {
              "url": "https://www.ableton.com/ja/blog/satsuki/", "title": "Satsuki", "description": "An interview.",
              "thumbUrl": "https://www.ableton.com/img/card.jpg", "host": "ableton.com"
            }
            """, card!);
        Assert.Null(await CoreOperations.OgpLoadAsync(previews, "not a url"));
    }

    /// A reply by someone else stays its own row, which the bridge, sending no authors, grouped.
    [Fact]
    public void FeedArrangeGroupsOnlyTheAuthorsOwnReplies()
    {
        ArrangeItemDto[] page =
        [
            new("at://did:plc:alice/app.bsky.feed.post/a2", "did:plc:alice", "2026-06-04T12:05:00.000Z", "at://did:plc:alice/app.bsky.feed.post/a1"),
            new("at://did:plc:bob/app.bsky.feed.post/b1", "did:plc:bob", "2026-06-04T12:03:00.000Z", "at://did:plc:alice/app.bsky.feed.post/a1"),
            new("at://did:plc:alice/app.bsky.feed.post/a1", "did:plc:alice", "2026-06-04T12:00:00.000Z", null),
        ];

        var rows = CoreOperations.FeedArrange(page);

        Assert.Equal(
            [
                new ArrangeResultDto("at://did:plc:alice/app.bsky.feed.post/a1", false, true),
                new ArrangeResultDto("at://did:plc:alice/app.bsky.feed.post/a2", true, false),
                new ArrangeResultDto("at://did:plc:bob/app.bsky.feed.post/b1", false, false),
            ],
            rows);
    }
}
