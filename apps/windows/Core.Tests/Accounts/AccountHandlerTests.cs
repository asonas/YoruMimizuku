using System.Net;
using System.Text;
using System.Text.Json;
using YoruMimizuku.Core.Accounts;
using YoruMimizuku.Core.OAuth;
using static YoruMimizuku.Core.Tests.FakeAtproto;

namespace YoruMimizuku.Core.Tests;

public class AccountHandlerTests
{
    private readonly FakeAtproto _server = new();
    private readonly InMemorySecureStorage _storage = new();
    private readonly AccountManager _accounts;

    public AccountHandlerTests() => _accounts = AccountTestSupport.Manager(_server, _storage);

    /// <summary>A client wired the way the services' XrpcClient is: one per account.</summary>
    private HttpClient Client(string did, AccountManager? accounts = null) =>
        new(new AccountHandler(accounts ?? _accounts, did) { InnerHandler = _server });

    private static async Task<string> ActingDidAsync(HttpClient client, string nsid = "app.bsky.feed.getTimeline")
    {
        using var response = await client.GetAsync($"https://pds.test/xrpc/{nsid}");
        response.EnsureSuccessStatusCode();
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        return body.RootElement.GetProperty("did").GetString()!;
    }

    [Fact]
    public async Task PdsRequestsActAsTheAccountWithAProofBoundToItsKey()
    {
        await _accounts.SignInAsync(_server);
        var client = Client(AliceDid);
        var challengesAfterSignIn = _server.NonceChallenges;

        Assert.Equal(AliceDid, await ActingDidAsync(client));
        Assert.Equal(AliceDid, await ActingDidAsync(client));

        // The PDS's nonce challenge is met once, then reused.
        Assert.Equal(1, _server.NonceChallenges - challengesAfterSignIn);
    }

    [Fact]
    public async Task RequestsToAnotherHostCarryNoCredentials()
    {
        await _accounts.SignInAsync(_server);

        await Client(AliceDid).GetAsync("https://cdn.test/img/avatar.jpg");

        var sent = _server.Requests[^1];
        Assert.Equal("cdn.test", sent.Uri.Host);
        Assert.Null(sent.Authorization);
        Assert.Null(sent.Proof);
    }

    [Fact]
    public async Task EachClientActsAsItsOwnAccountWhicheverIsCurrent()
    {
        await _accounts.SignInAsync(_server);
        await _accounts.SignInAsync(_server, "bob.test", BobDid);
        var alice = Client(AliceDid);
        var bob = Client(BobDid);

        Assert.Equal(AliceDid, await ActingDidAsync(alice));
        _accounts.SwitchTo(AliceDid);
        Assert.Equal(BobDid, await ActingDidAsync(bob));
    }

    [Fact]
    public async Task AnExpiredTokenIsRefreshedAndTheRequestRetried()
    {
        await _accounts.SignInAsync(_server);
        _server.ExpireAccessTokens();

        Assert.Equal(AliceDid, await ActingDidAsync(Client(AliceDid)));

        Assert.Equal(1, _server.RefreshCount);
        var grant = _server.LastTokenRequest!;
        Assert.Equal("refresh_token", grant["grant_type"]);
        Assert.Equal(OAuthClientConfig.YoruMimizuku.ClientId, grant["client_id"]);
        Assert.Null(grant["code"]);
        Assert.Null(grant["redirect_uri"]);
    }

    [Fact]
    public async Task RequestsRejectedTogetherShareOneRefreshAcrossClients()
    {
        await _accounts.SignInAsync(_server);
        var timeline = Client(AliceDid);
        var notifications = Client(AliceDid);
        _server.ExpireAccessTokens();
        // Hold the first refresh until both requests have been refused, so both ask for one.
        _server.BeforeRefresh = () => UntilAsync(() => _server.RejectedTokens >= 2);

        var acting = await Task.WhenAll(
            ActingDidAsync(timeline, "app.bsky.feed.getTimeline"),
            ActingDidAsync(notifications, "app.bsky.notification.listNotifications"));

        Assert.Equal([AliceDid, AliceDid], acting);
        Assert.Equal(1, _server.RefreshCount);
    }

    [Fact]
    public async Task ALateRefusalOfAnOldTokenNeitherRefreshesNorRollsTheTokensBack()
    {
        await _accounts.SignInAsync(_server);
        var client = Client(AliceDid);
        await ActingDidAsync(client);
        var release = new TaskCompletionSource();
        _server.Intercept = async sent =>
        {
            if (sent.Uri.AbsolutePath.EndsWith("app.slow", StringComparison.Ordinal)) await release.Task;
            return null;
        };

        var late = ActingDidAsync(client, "app.slow");
        await UntilAsync(() => _server.Requests.Any(sent => sent.Uri.AbsolutePath.EndsWith("app.slow", StringComparison.Ordinal)));
        _server.ExpireAccessTokens();
        await ActingDidAsync(client);
        _server.ExpireAccessTokens();
        await ActingDidAsync(client);
        release.SetResult();

        Assert.Equal(AliceDid, await late);
        Assert.Equal(2, _server.RefreshCount);
        // The store kept the newest refresh token: a relaunch can still refresh.
        _server.ExpireAccessTokens();
        Assert.Equal(AliceDid, await ActingDidAsync(Client(AliceDid, AccountTestSupport.Manager(_server, _storage))));
    }

    [Fact]
    public async Task TheRotatedTokenIsSavedBeforeTheRetryEvenWhenTheRetryFails()
    {
        await _accounts.SignInAsync(_server);
        var client = Client(AliceDid);
        await ActingDidAsync(client);
        _server.ExpireAccessTokens();
        var savedBeforeRetry = false;
        _server.Intercept = sent =>
        {
            if (sent.Uri.AbsolutePath.EndsWith("app.retry", StringComparison.Ordinal) && _server.RefreshCount == 1)
            {
                var token = sent.Authorization!["DPoP ".Length..];
                savedBeforeRetry = Encoding.UTF8.GetString(_storage.Read("account." + AliceDid)!).Contains(token);
                return Task.FromResult<HttpResponseMessage?>(new HttpResponseMessage(HttpStatusCode.InternalServerError));
            }
            return Task.FromResult<HttpResponseMessage?>(null);
        };

        using var failed = await client.GetAsync("https://pds.test/xrpc/app.retry");

        Assert.Equal(HttpStatusCode.InternalServerError, failed.StatusCode);
        Assert.True(savedBeforeRetry);
        _server.Intercept = null;
        _server.ExpireAccessTokens();
        Assert.Equal(AliceDid, await ActingDidAsync(Client(AliceDid, AccountTestSupport.Manager(_server, _storage))));
    }

    [Fact]
    public async Task ADeadRefreshTokenSurfacesAsAnExpiredSessionWithoutTheToken()
    {
        await _accounts.SignInAsync(_server);
        _server.ExpireAccessTokens();
        _server.RevokeRefreshTokens();

        var error = await Assert.ThrowsAsync<OAuthException>(() => ActingDidAsync(Client(AliceDid)));

        Assert.True(error.IsSessionExpired);
        Assert.DoesNotContain(_server.LastTokenRequest!["refresh_token"]!, error.ToString());
    }

    [Fact]
    public async Task AFailedRefreshIsTriedAgainByTheNextRequest()
    {
        await _accounts.SignInAsync(_server);
        var client = Client(AliceDid);
        _server.ExpireAccessTokens();
        var failOnce = true;
        _server.Intercept = sent =>
        {
            if (sent.Uri.AbsolutePath != "/oauth/token" || !failOnce) return Task.FromResult<HttpResponseMessage?>(null);
            failOnce = false;
            return Task.FromResult<HttpResponseMessage?>(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable));
        };

        var error = await Assert.ThrowsAsync<OAuthException>(() => ActingDidAsync(client));

        Assert.Equal(503, error.Status);
        Assert.Equal(AliceDid, await ActingDidAsync(client));
    }

    [Fact]
    public async Task ARelaunchedAppSignsWithTheKeyRestoredFromDpapi()
    {
        if (!OperatingSystem.IsWindows()) return;
        var directory = Directory.CreateTempSubdirectory("yoru-accounts-").FullName;
        try
        {
            await AccountTestSupport.Manager(_server, new DpapiFileStorage(directory)).SignInAsync(_server);

            var relaunched = AccountTestSupport.Manager(_server, new DpapiFileStorage(directory));

            Assert.Equal(AliceDid, await ActingDidAsync(Client(AliceDid, relaunched)));
            _server.ExpireAccessTokens();
            Assert.Equal(AliceDid, await ActingDidAsync(Client(AliceDid, relaunched)));
            Assert.Equal(1, _server.RefreshCount);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public async Task ASignedOutAccountsClientNoLongerSends()
    {
        await _accounts.SignInAsync(_server);
        var client = Client(AliceDid);

        _accounts.RemoveAndAdvance(AliceDid);

        await Assert.ThrowsAsync<UnknownAccountException>(() => ActingDidAsync(client));
    }

    private static async Task UntilAsync(Func<bool> condition)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        while (!condition()) await Task.Delay(5, timeout.Token);
    }
}
