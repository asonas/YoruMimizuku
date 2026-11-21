namespace YoruMimizuku.Core.Tests;

public class PostPermalinkTests
{
    private const string Id = "at://did:plc:me/app.bsky.feed.post/3kabc123";

    [Fact]
    public void AValidHandleBuildsTheHandleUrl()
    {
        Assert.Equal(
            new Uri("https://bsky.app/profile/alice.bsky.social/post/3kabc123"),
            PostPermalink.Url(Id, "alice.bsky.social"));
    }

    [Theory]
    [InlineData("handle.invalid")]
    [InlineData("")]
    public void AnUnusableHandleFallsBackToTheDid(string handle)
    {
        Assert.Equal(new Uri("https://bsky.app/profile/did:plc:me/post/3kabc123"), PostPermalink.Url(Id, handle));
    }

    [Theory]
    [InlineData("https://example.com/not-at-uri")]
    [InlineData("at://did:plc:me/app.bsky.feed.post")]
    public void AnIdThatIsNotAPostAddressHasNoPermalink(string id)
    {
        Assert.Null(PostPermalink.Url(id, "alice.bsky.social"));
    }
}
