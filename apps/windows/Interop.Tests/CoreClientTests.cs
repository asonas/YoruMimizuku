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

    /// A dead refresh token is reported to the windows with the account's DID, and the account stays signed in
    /// so the window can ask the user to sign in to it again (ADR 0018).
    [Fact]
    public async Task ARevokedSessionIsReportedAndTheAccountIsKept()
    {
        await SignInAsync();
        var reported = new List<string>();
        _core.SessionExpired += reported.Add;
        _server.ExpireAccessTokens();
        _server.RevokeRefreshTokens();

        var error = await Assert.ThrowsAsync<CoreException>(() => _core.ForAccount(AliceDid).TimelineLoadAsync());

        Assert.True(error.SessionExpired);
        Assert.Equal(new[] { AliceDid }, reported);
        Assert.Equal(new AccountDto(AliceDid, "alice.test"), await _core.CurrentAccountAsync());
    }

    /// Signing in again as the expired account replaces its tokens in place: the client a view already holds
    /// works again, and the account is listed once.
    [Fact]
    public async Task SigningInAgainRevivesTheExpiredAccount()
    {
        await SignInAsync();
        var held = _core.ForAccount(AliceDid);
        _server.ExpireAccessTokens();
        _server.RevokeRefreshTokens();
        await Assert.ThrowsAsync<CoreException>(() => held.DeletePostAsync("at://did:plc:alice/app.bsky.feed.post/1"));

        await SignInAsync();

        await held.DeletePostAsync("at://did:plc:alice/app.bsky.feed.post/1");
        await _core.ForAccount(AliceDid).DeletePostAsync("at://did:plc:alice/app.bsky.feed.post/2");
        Assert.Equal(new[] { new AccountSummaryDto(AliceDid, "alice.test") }, await _core.AccountSummariesAsync());
    }

    /// A failure that is not an expired session reports nothing.
    [Fact]
    public async Task AnotherFailureIsNotReportedAsExpiry()
    {
        await SignInAsync();
        var reported = new List<string>();
        _core.SessionExpired += reported.Add;

        await Assert.ThrowsAsync<CoreException>(() => _core.ForAccount(AliceDid).TimelineLoadAsync());

        Assert.Empty(reported);
    }
}
