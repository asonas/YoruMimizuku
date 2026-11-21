using System.Net;
using YoruMimizuku.Core.OAuth;

namespace YoruMimizuku.Core.Tests;

public class DPoPSenderTests
{
    private static readonly Uri Par = new("https://auth.test/oauth/par");
    private static readonly Uri Timeline = new("https://pds.test/xrpc/app.bsky.feed.getTimeline");
    private const string NonceChallenge = """{"error":"use_dpop_nonce"}""";

    private readonly DPoPKey _key = DPoPKey.Generate();
    private readonly DPoPNonces _nonces = new();

    private Task<HttpResponseMessage> SendAsync(ScriptedHandler server, HttpMethod method, Uri uri, string? accessToken = null) =>
        DPoPSender.SendAsync(
            new HttpMessageInvoker(server).SendAsync,
            new HttpRequestMessage(method, uri) { Content = method == HttpMethod.Post ? new StringContent("a=1") : null },
            _key, _nonces, accessToken, CancellationToken.None);

    [Fact]
    public async Task SendsOnceWithAProofWhenTheServerAccepts()
    {
        var server = new ScriptedHandler(ScriptedHandler.Json(HttpStatusCode.OK, "{}"));

        var response = await SendAsync(server, HttpMethod.Post, Par);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var sent = Assert.Single(server.Sent);
        Assert.True(sent.Proof!.SignatureValid);
        Assert.Null(sent.Proof.Claim("nonce"));
        Assert.Null(sent.Authorization);
    }

    [Fact]
    public async Task RetriesOnceWithTheNonceFromAnAuthorizationServerChallenge()
    {
        var server = new ScriptedHandler(
            ScriptedHandler.Json(HttpStatusCode.BadRequest, NonceChallenge, ("DPoP-Nonce", "as-nonce")),
            ScriptedHandler.Json(HttpStatusCode.Created, "{}"));

        var response = await SendAsync(server, HttpMethod.Post, Par);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.Equal(2, server.Sent.Count);
        Assert.Null(server.Sent[0].Proof!.Claim("nonce"));
        Assert.Equal("as-nonce", server.Sent[1].Proof!.Claim("nonce"));
        Assert.NotEqual(server.Sent[0].Proof!.Claim("jti"), server.Sent[1].Proof!.Claim("jti"));
        Assert.Equal(["a=1", "a=1"], server.Sent.Select(s => s.Body));
    }

    [Fact]
    public async Task RetriesOnAResourceServerChallengeCarriedOnlyInWwwAuthenticate()
    {
        var challenge = new HttpResponseMessage(HttpStatusCode.Unauthorized);
        challenge.Headers.TryAddWithoutValidation("WWW-Authenticate", "DPoP algs=\"ES256\", error=\"use_dpop_nonce\"");
        challenge.Headers.TryAddWithoutValidation("DPoP-Nonce", "pds-nonce");
        var server = new ScriptedHandler(challenge, ScriptedHandler.Json(HttpStatusCode.OK, "{}"));

        var response = await SendAsync(server, HttpMethod.Get, Timeline, accessToken: "access-1");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("pds-nonce", server.Sent[1].Proof!.Claim("nonce"));
        Assert.All(server.Sent, sent => Assert.Equal("DPoP access-1", sent.Authorization));
        Assert.All(server.Sent, sent => Assert.NotNull(sent.Proof!.Claim("ath")));
    }

    [Fact]
    public async Task DoesNotRetryAChallengeThatCarriesNoNonce()
    {
        var server = new ScriptedHandler(
            ScriptedHandler.Json(HttpStatusCode.BadRequest, NonceChallenge),
            ScriptedHandler.Json(HttpStatusCode.OK, "{}"));

        var response = await SendAsync(server, HttpMethod.Post, Par);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Single(server.Sent);
    }

    [Fact]
    public async Task ReusesTheLastNonceOnlyForTheServerThatGaveIt()
    {
        var server = new ScriptedHandler(
            ScriptedHandler.Json(HttpStatusCode.OK, "{}", ("DPoP-Nonce", "as-nonce")),
            ScriptedHandler.Json(HttpStatusCode.OK, "{}"),
            ScriptedHandler.Json(HttpStatusCode.OK, "{}"));

        await SendAsync(server, HttpMethod.Post, Par);
        await SendAsync(server, HttpMethod.Post, new Uri("https://auth.test/oauth/token"));
        await SendAsync(server, HttpMethod.Get, Timeline, accessToken: "access-1");

        Assert.Equal("as-nonce", server.Sent[1].Proof!.Claim("nonce"));
        Assert.Null(server.Sent[2].Proof!.Claim("nonce"));
    }
}
