using YoruMimizuku.Core.OAuth;
using YoruMimizuku.Core.Tests;
using static YoruMimizuku.Core.Tests.FakeAtproto;

namespace YoruMimizuku.App.Interop.Tests;

public class CoreClientTests
{
    private readonly FakeAtproto _server = new();
    private readonly CoreClient _core;

    public CoreClientTests() => _core = new CoreClient(new InMemorySecureStorage(), _server, OAuthClientConfig.YoruMimizuku);

    private async Task<AccountDto> SignInAsync()
    {
        var begin = await _core.LoginBeginAsync("alice.test");
        return await _core.LoginCompleteAsync(begin.PendingId, _server.Approve(new Uri(begin.AuthUrl)));
    }

    /// The login view's two steps: open AuthUrl in WebView2, watch for CallbackScheme, hand the callback back by pendingId.
    [Fact]
    public async Task SignInByPendingIdMakesTheAccountCurrent()
    {
        var begin = await _core.LoginBeginAsync("alice.test");
        Assert.Equal("as.ason", begin.CallbackScheme);

        var account = await _core.LoginCompleteAsync(begin.PendingId, _server.Approve(new Uri(begin.AuthUrl)));

        Assert.Equal(new AccountDto(AliceDid, "alice.test"), account);
        Assert.Equal(account, await _core.CurrentAccountAsync());
        await Assert.ThrowsAsync<InvalidOperationException>(
            () => _core.LoginCompleteAsync(begin.PendingId, _server.Approve(new Uri(begin.AuthUrl))));
    }

    /// The window signs the account out when a request reports the refresh token is dead.
    [Fact]
    public async Task ARevokedSessionIsFlaggedAsExpired()
    {
        await SignInAsync();
        _server.ExpireAccessTokens();
        _server.RevokeRefreshTokens();

        var error = await Assert.ThrowsAsync<BridgeException>(() => _core.ForAccount(AliceDid).TimelineLoadAsync());

        Assert.True(error.SessionExpired);
    }
}
