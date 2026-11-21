namespace YoruMimizuku.Core.Tests;

public class AtUriTests
{
    [Fact]
    public void RkeyExtractsLastPathComponent()
    {
        Assert.Equal("3kabc123", AtUri.Parse("at://did:plc:me/app.bsky.feed.like/3kabc123")?.Rkey);
    }

    [Fact]
    public void RepoExtractsAuthority()
    {
        Assert.Equal("did:plc:me", AtUri.Parse("at://did:plc:me/app.bsky.feed.post/3kabc123")?.Repo);
    }

    [Theory]
    [InlineData("not-an-at-uri")]
    [InlineData("at://did:plc:me/app.bsky.feed.like")]
    [InlineData("")]
    public void ReturnsNullWhenMalformed(string value)
    {
        Assert.Null(AtUri.Parse(value));
    }
}
