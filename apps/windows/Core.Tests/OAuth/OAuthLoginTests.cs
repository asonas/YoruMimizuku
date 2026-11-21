using System.Net;
using System.Web;
using YoruMimizuku.Core.OAuth;

namespace YoruMimizuku.Core.Tests;

public class OAuthLoginTests
{
    private static readonly OAuthClientConfig Config = OAuthClientConfig.YoruMimizuku;
    private readonly FakeAtproto _server = new();

    private OAuthLogin Login() => new(new HttpMessageInvoker(_server), new DPoPNonces(), Config);

    private void Answer(string path, HttpStatusCode status, string body) =>
        _server.Intercept = sent => Task.FromResult(sent.Uri.AbsolutePath == path ? ScriptedHandler.Json(status, body) : null);

    [Fact]
    public async Task SignInPushesTheRequestAndExchangesTheCodeForTokens()
    {
        var login = Login();

        var pending = await login.BeginAsync("alice.test", CancellationToken.None);

        Assert.Equal((FakeAtproto.AliceDid, FakeAtproto.Pds, FakeAtproto.Issuer), (pending.Did, pending.Pds, pending.Issuer));
        Assert.Equal("https://auth.test/oauth/authorize", pending.AuthorizationUrl.GetLeftPart(UriPartial.Path));
        var authorize = HttpUtility.ParseQueryString(pending.AuthorizationUrl.Query);
        Assert.Equal(Config.ClientId, authorize["client_id"]);
        Assert.StartsWith("urn:ietf:params:oauth:request_uri:", authorize["request_uri"]);
        var par = _server.LastPar!;
        Assert.Equal("code", par["response_type"]);
        Assert.Equal(Config.ClientId, par["client_id"]);
        Assert.Equal(Config.RedirectUri, par["redirect_uri"]);
        Assert.Equal(Config.Scope, par["scope"]);
        Assert.Equal("S256", par["code_challenge_method"]);
        Assert.Equal("alice.test", par["login_hint"]);

        var tokens = await login.CompleteAsync(pending, _server.Approve(pending.AuthorizationUrl), CancellationToken.None);

        Assert.StartsWith("at-", tokens.AccessToken);
        Assert.StartsWith("rt-", tokens.RefreshToken);
        Assert.Equal("atproto transition:generic", tokens.Scope);
        var exchange = _server.LastTokenRequest!;
        Assert.Equal("authorization_code", exchange["grant_type"]);
        Assert.Equal(Config.ClientId, exchange["client_id"]);
        Assert.Equal(Config.RedirectUri, exchange["redirect_uri"]);
        // The PAR met the nonce challenge; the token request reused that nonce.
        Assert.Equal(1, _server.NonceChallenges);
    }

    [Fact]
    public async Task ADidSignsInWithoutResolvingAHandle()
    {
        var login = Login();

        var pending = await login.BeginAsync(FakeAtproto.AliceDid, CancellationToken.None);
        await login.CompleteAsync(pending, _server.Approve(pending.AuthorizationUrl), CancellationToken.None);

        Assert.DoesNotContain(_server.Requests, sent => sent.Uri.Host == "bsky.social");
    }

    [Fact]
    public async Task ADidWebAccountFindsItsPdsInItsWellKnownDocument()
    {
        var login = Login();

        var pending = await login.BeginAsync(FakeAtproto.WebDid, CancellationToken.None);
        await login.CompleteAsync(pending, _server.Approve(pending.AuthorizationUrl, signedInAs: FakeAtproto.WebDid), CancellationToken.None);

        Assert.Equal(FakeAtproto.Pds, pending.Pds);
    }

    [Theory]
    [InlineData("unknown handle", OAuthErrorKind.DiscoveryFailed)]
    [InlineData("unsupported DID method", OAuthErrorKind.UnsupportedDidMethod)]
    [InlineData("DID document without a PDS", OAuthErrorKind.PdsNotFound)]
    [InlineData("no authorization server", OAuthErrorKind.MalformedDocument)]
    [InlineData("metadata names another issuer", OAuthErrorKind.MalformedDocument)]
    [InlineData("empty authorization endpoint", OAuthErrorKind.MalformedDocument)]
    [InlineData("no PAR endpoint", OAuthErrorKind.ParNotSupported)]
    [InlineData("PAR rejected", OAuthErrorKind.AuthorizationRequestFailed)]
    [InlineData("PAR answer not JSON", OAuthErrorKind.MalformedDocument)]
    public async Task BeginReportsWhereDiscoveryOrThePushedRequestFailed(string scenario, OAuthErrorKind kind)
    {
        var account = "alice.test";
        switch (scenario)
        {
            case "unknown handle": account = "nobody.test"; break;
            case "unsupported DID method": account = "did:example:alice"; break;
            case "DID document without a PDS": account = FakeAtproto.NoPdsDid; break;
            case "no authorization server": _server.AuthorizationServers.Clear(); break;
            case "metadata names another issuer": _server.EditMetadata = m => m["issuer"] = "https://evil.test"; break;
            case "empty authorization endpoint": _server.EditMetadata = m => m["authorization_endpoint"] = ""; break;
            case "no PAR endpoint": _server.EditMetadata = m => m.Remove("pushed_authorization_request_endpoint"); break;
            case "PAR rejected": Answer("/oauth/par", HttpStatusCode.BadRequest, """{"error":"invalid_request"}"""); break;
            case "PAR answer not JSON": Answer("/oauth/par", HttpStatusCode.Created, "not json"); break;
        }

        var error = await Assert.ThrowsAsync<OAuthException>(() => Login().BeginAsync(account, CancellationToken.None));

        Assert.Equal(kind, error.Kind);
    }

    [Theory]
    [InlineData("state of another request", OAuthErrorKind.StateMismatch)]
    [InlineData("iss of another server", OAuthErrorKind.IssuerMismatch)]
    [InlineData("no iss", OAuthErrorKind.IssuerMismatch)]
    [InlineData("access denied", OAuthErrorKind.AuthorizationDenied)]
    [InlineData("no code", OAuthErrorKind.MissingAuthorizationCode)]
    public async Task CompleteRejectsACallbackThatDoesNotAnswerThisRequest(string scenario, OAuthErrorKind kind)
    {
        var login = Login();
        var pending = await login.BeginAsync("alice.test", CancellationToken.None);
        var answer = $"state={Uri.EscapeDataString(pending.State)}&iss={Uri.EscapeDataString(FakeAtproto.Issuer)}";
        var callback = scenario switch
        {
            "state of another request" => _server.Approve(pending.AuthorizationUrl, state: "forged"),
            "iss of another server" => _server.Approve(pending.AuthorizationUrl, iss: "https://evil.test"),
            "no iss" => _server.Approve(pending.AuthorizationUrl, iss: null),
            "access denied" => $"as.ason:/callback?error=access_denied&error_description=nope&{answer}",
            _ => $"as.ason:/callback?{answer}",
        };

        var error = await Assert.ThrowsAsync<OAuthException>(() => login.CompleteAsync(pending, callback, CancellationToken.None));

        Assert.Equal(kind, error.Kind);
        Assert.Null(_server.LastTokenRequest);
    }

    [Fact]
    public async Task CompleteRejectsTokensForAnAccountOtherThanTheOneThatStartedSignIn()
    {
        var login = Login();
        var pending = await login.BeginAsync("alice.test", CancellationToken.None);

        var error = await Assert.ThrowsAsync<OAuthException>(() =>
            login.CompleteAsync(pending, _server.Approve(pending.AuthorizationUrl, signedInAs: FakeAtproto.BobDid), CancellationToken.None));

        Assert.Equal(OAuthErrorKind.SubjectMismatch, error.Kind);
    }

    [Theory]
    [InlineData("transition:generic")]
    [InlineData(null)]
    public async Task CompleteRejectsTokensWithoutTheAtprotoScope(string? scope)
    {
        _server.Scope = scope;
        var login = Login();
        var pending = await login.BeginAsync("alice.test", CancellationToken.None);

        var error = await Assert.ThrowsAsync<OAuthException>(() =>
            login.CompleteAsync(pending, _server.Approve(pending.AuthorizationUrl), CancellationToken.None));

        Assert.Equal(OAuthErrorKind.MissingAtprotoScope, error.Kind);
    }

    [Theory]
    [InlineData(HttpStatusCode.BadRequest, "{}", OAuthErrorKind.TokenRequestFailed, null)]
    [InlineData(HttpStatusCode.BadRequest, """{"error":"invalid_grant","error_description":"code expired"}""", OAuthErrorKind.TokenRequestFailed, "invalid_grant")]
    [InlineData(HttpStatusCode.OK, """{"access_token":"leaked-access","refresh_token":"leaked-refresh"}""", OAuthErrorKind.MalformedDocument, null)]
    public async Task CompleteReportsATokenEndpointFailureWithoutEchoingTokens(HttpStatusCode status, string body, OAuthErrorKind kind, string? oauthError)
    {
        var login = Login();
        var pending = await login.BeginAsync("alice.test", CancellationToken.None);
        var callback = _server.Approve(pending.AuthorizationUrl);
        Answer("/oauth/token", status, body);

        var error = await Assert.ThrowsAsync<OAuthException>(() => login.CompleteAsync(pending, callback, CancellationToken.None));

        Assert.Equal(kind, error.Kind);
        Assert.Equal(oauthError, error.Error);
        Assert.DoesNotContain("leaked", error.ToString());
    }
}
