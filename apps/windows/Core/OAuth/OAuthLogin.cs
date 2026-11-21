using System.Buffers.Text;
using System.Net;
using System.Security.Cryptography;
using System.Text.Json;
using System.Web;

namespace YoruMimizuku.Core.OAuth;

/// <summary>
/// atproto OAuth sign-in in two steps around the browser, as WebView2 needs it.
/// <see cref="BeginAsync"/> discovers the account's authorization server, makes a DPoP
/// key and pushes the authorization request; <see cref="CompleteAsync"/> checks the
/// callback and exchanges its code for tokens bound to that key.
/// </summary>
internal sealed class OAuthLogin(HttpMessageInvoker http, DPoPNonces nonces, OAuthClientConfig config)
{
    public async Task<PendingLogin> BeginAsync(string handleOrDid, CancellationToken cancellationToken)
    {
        var account = await OAuthDiscovery.DiscoverAsync(http, handleOrDid, cancellationToken);
        var parEndpoint = account.Server.ParEndpoint
            ?? throw new OAuthException(OAuthErrorKind.ParNotSupported, $"PAR not supported by {account.Server.Issuer}");
        var key = DPoPKey.Generate();
        var pkce = Pkce.Generate();
        var state = Base64Url.EncodeToString(RandomNumberGenerator.GetBytes(16));

        using var request = new HttpRequestMessage(HttpMethod.Post, parEndpoint)
        {
            Content = new FormUrlEncodedContent(new Dictionary<string, string>
            {
                ["response_type"] = "code",
                ["client_id"] = config.ClientId,
                ["redirect_uri"] = config.RedirectUri,
                ["scope"] = config.Scope,
                ["state"] = state,
                ["code_challenge"] = pkce.Challenge,
                ["code_challenge_method"] = "S256",
                ["login_hint"] = handleOrDid,
            }),
        };
        using var response = await DPoPSender.SendAsync(http.SendAsync, request, key, nonces, accessToken: null, cancellationToken);
        if (response.StatusCode is not (HttpStatusCode.OK or HttpStatusCode.Created))
            throw new OAuthException(OAuthErrorKind.AuthorizationRequestFailed, $"authorization request failed ({(int)response.StatusCode})", (int)response.StatusCode);

        string requestUri;
        try
        {
            using var document = JsonDocument.Parse(await response.Content.ReadAsByteArrayAsync(cancellationToken));
            requestUri = document.RootElement.RequiredString("request_uri");
        }
        catch (JsonException)
        {
            throw OAuthException.Malformed("invalid PAR response");
        }

        var authorizationUrl = new UriBuilder(account.Server.AuthorizationEndpoint)
        {
            Query = $"client_id={Uri.EscapeDataString(config.ClientId)}&request_uri={Uri.EscapeDataString(requestUri)}",
        }.Uri;
        return new PendingLogin(handleOrDid, account, key, pkce, state, authorizationUrl);
    }

    public async Task<OAuthTokens> CompleteAsync(PendingLogin pending, string callbackUrl, CancellationToken cancellationToken)
    {
        if (!Uri.TryCreate(callbackUrl, UriKind.Absolute, out var callback)) throw OAuthException.Malformed("invalid callback URL");
        var answer = HttpUtility.ParseQueryString(callback.Query);
        if (answer["error"] is { } error)
            throw new OAuthException(OAuthErrorKind.AuthorizationDenied, $"authorization denied: {error}", error: error);
        var code = answer["code"] ?? throw new OAuthException(OAuthErrorKind.MissingAuthorizationCode, "missing authorization code");
        if (answer["state"] != pending.State) throw new OAuthException(OAuthErrorKind.StateMismatch, "OAuth state mismatch");
        if (answer["iss"] != pending.Issuer)
            throw new OAuthException(OAuthErrorKind.IssuerMismatch, $"callback iss is not {pending.Issuer}");

        return await TokenEndpoint.ExchangeCodeAsync(
            http, pending.Key, nonces, pending.Account.Server, config, code, pending.Pkce.Verifier, pending.Did, cancellationToken);
    }
}
