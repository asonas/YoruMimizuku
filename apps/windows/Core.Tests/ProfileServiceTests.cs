namespace YoruMimizuku.Core.Tests;

public class ProfileServiceTests
{
    // A trimmed profileViewDetailed: the keys only the detailed view has are ignored.
    private const string ProfileBody = """
        {
          "did": "did:plc:alice",
          "handle": "alice.bsky.social",
          "displayName": "Alice",
          "avatar": "https://cdn.example/alice.jpg",
          "description": "hello",
          "followersCount": 10,
          "followsCount": 20,
          "postsCount": 30
        }
        """;

    [Fact]
    public async Task GetProfileSendsTheActorAndDecodes()
    {
        var http = new StubHttp(ProfileBody);

        var profile = await new ProfileService(http.Xrpc()).GetProfileAsync("alice.bsky.social");

        Assert.Equal("alice.bsky.social", profile.Handle);
        Assert.Equal("https://cdn.example/alice.jpg", profile.Avatar);
        Assert.Equal(HttpMethod.Get, http.Last.Method);
        Assert.Equal("/xrpc/app.bsky.actor.getProfile", http.Last.Path);
        Assert.Equal("alice.bsky.social", http.Last.Query["actor"]);
    }

    [Fact]
    public async Task GetAvatarReadsTheAccountsOwnProfile()
    {
        var http = new StubHttp(ProfileBody);

        var avatar = await new ProfileService(http.Xrpc()).GetAvatarAsync();

        Assert.Equal("https://cdn.example/alice.jpg", avatar);
        Assert.Equal("did:plc:me", http.Last.Query["actor"]);
    }
}
