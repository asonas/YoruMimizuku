using System.Net;
using System.Text.Json;

namespace YoruMimizuku.Core.OAuth;

/// <summary>An account's tokens. ToString never prints them.</summary>
internal sealed record OAuthTokens(string AccessToken, string? RefreshToken, string Scope)
{
    public override string ToString() => "OAuthTokens { redacted }";
}

/// <summary>
/// Token-endpoint grants over a DPoP-bound channel. Every grant's answer must be for
/// <c>expectedDid</c> and carry the atproto scope, the refresh grant's included.
/// </summary>
internal static class TokenEndpoint
{
    public static Task<OAuthTokens> ExchangeCodeAsync(
        HttpMessageInvoker http, DPoPKey key, DPoPNonces nonces, AuthorizationServer server, OAuthClientConfig config,
        string code, string verifier, string expectedDid, CancellationToken cancellationToken) =>
        RequestAsync(http, key, nonces, server, expectedDid, cancellationToken,
            ("grant_type", "authorization_code"), ("code", code), ("code_verifier", verifier),
            ("redirect_uri", config.RedirectUri), ("client_id", config.ClientId));

    public static Task<OAuthTokens> RefreshAsync(
        HttpMessageInvoker http, DPoPKey key, DPoPNonces nonces, AuthorizationServer server, OAuthClientConfig config,
        string refreshToken, string expectedDid, CancellationToken cancellationToken) =>
        RequestAsync(http, key, nonces, server, expectedDid, cancellationToken,
            ("grant_type", "refresh_token"), ("refresh_token", refreshToken), ("client_id", config.ClientId));

    private static async Task<OAuthTokens> RequestAsync(
        HttpMessageInvoker http, DPoPKey key, DPoPNonces nonces, AuthorizationServer server, string expectedDid,
        CancellationToken cancellationToken, params (string Name, string Value)[] grant)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, server.TokenEndpoint)
        {
            Content = new FormUrlEncodedContent(grant.Select(p => KeyValuePair.Create(p.Name, p.Value))),
        };
        using var response = await DPoPSender.SendAsync(http.SendAsync, request, key, nonces, accessToken: null, cancellationToken);
        var body = await response.Content.ReadAsByteArrayAsync(cancellationToken);
        if (response.StatusCode != HttpStatusCode.OK) throw Refused((int)response.StatusCode, body);

        string sub;
        OAuthTokens tokens;
        try
        {
            using var document = JsonDocument.Parse(body);
            var json = document.RootElement;
            json.RequiredString("token_type");
            sub = json.RequiredString("sub");
            tokens = new OAuthTokens(json.RequiredString("access_token"), json.OptionalString("refresh_token"), json.OptionalString("scope") ?? "");
        }
        catch (JsonException)
        {
            throw OAuthException.Malformed("invalid token response");
        }
        if (sub != expectedDid)
            throw new OAuthException(OAuthErrorKind.SubjectMismatch, $"token is for {sub}, not {expectedDid}");
        if (!tokens.Scope.Split(' ').Contains("atproto"))
            throw new OAuthException(OAuthErrorKind.MissingAtprotoScope, "token lacks the atproto scope");
        return tokens;
    }

    private static OAuthException Refused(int status, byte[] body)
    {
        string? error = null, description = null;
        try
        {
            using var document = JsonDocument.Parse(body);
            error = JsonFields.Tolerant(() => document.RootElement.OptionalString("error"));
            description = JsonFields.Tolerant(() => document.RootElement.OptionalString("error_description"));
        }
        catch (JsonException)
        {
            // Not an RFC 6749 error body; the status alone describes the failure.
        }
        var detail = string.Join(" — ", new[] { error, description }.OfType<string>());
        return new OAuthException(
            OAuthErrorKind.TokenRequestFailed,
            detail.Length == 0 ? $"token request failed ({status})" : $"token request failed ({status}): {detail}",
            status, error);
    }
}
