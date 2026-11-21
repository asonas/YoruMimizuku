using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;

namespace YoruMimizuku.Core.OAuth;

/// <summary>The latest DPoP-Nonce each server sent, by origin; any key may use it.</summary>
internal sealed class DPoPNonces
{
    private readonly ConcurrentDictionary<string, string> _byOrigin = new();

    public string? For(Uri uri) => _byOrigin.TryGetValue(Origin(uri), out var nonce) ? nonce : null;

    public void Remember(Uri uri, HttpResponseMessage response)
    {
        if (response.Headers.TryGetValues("DPoP-Nonce", out var values) && values.FirstOrDefault() is { Length: > 0 } nonce)
            _byOrigin[Origin(uri)] = nonce;
    }

    private static string Origin(Uri uri) => uri.GetLeftPart(UriPartial.Authority);
}

/// <summary>
/// Sends a request with a DPoP proof, using the server's last nonce, and retries once
/// when the server answers a use_dpop_nonce challenge with a nonce it had not yet
/// given. The request is sent again as is, so its content is buffered first.
/// </summary>
internal static class DPoPSender
{
    public static async Task<HttpResponseMessage> SendAsync(
        Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send,
        HttpRequestMessage request,
        DPoPKey key,
        DPoPNonces nonces,
        string? accessToken,
        CancellationToken cancellationToken)
    {
        var uri = request.RequestUri!;
        if (request.Content is not null) await request.Content.LoadIntoBufferAsync(cancellationToken);
        if (accessToken is not null) request.Headers.Authorization = new AuthenticationHeaderValue("DPoP", accessToken);

        var sentNonce = nonces.For(uri);
        var response = await SendOnceAsync(sentNonce);
        if (!await IsNonceChallengeAsync(response, cancellationToken)) return response;
        var freshNonce = nonces.For(uri);
        if (freshNonce is null || freshNonce == sentNonce) return response;
        response.Dispose();
        return await SendOnceAsync(freshNonce);

        async Task<HttpResponseMessage> SendOnceAsync(string? nonce)
        {
            request.Headers.Remove("DPoP");
            request.Headers.TryAddWithoutValidation("DPoP", key.CreateProof(request.Method, uri, accessToken, nonce));
            var response = await send(request, cancellationToken);
            nonces.Remember(uri, response);
            return response;
        }
    }

    /// <summary>
    /// A 400 or 401 whose WWW-Authenticate DPoP challenge or JSON error body names
    /// use_dpop_nonce. The body is buffered so the caller can still read it.
    /// </summary>
    public static async Task<bool> IsNonceChallengeAsync(HttpResponseMessage response, CancellationToken cancellationToken)
    {
        if (response.StatusCode is not (HttpStatusCode.BadRequest or HttpStatusCode.Unauthorized)) return false;
        if (response.Headers.WwwAuthenticate.Any(challenge =>
                challenge.Scheme.Equals("DPoP", StringComparison.OrdinalIgnoreCase)
                && challenge.Parameter?.Contains("use_dpop_nonce", StringComparison.Ordinal) == true))
            return true;

        await response.Content.LoadIntoBufferAsync(cancellationToken);
        try
        {
            using var body = JsonDocument.Parse(await response.Content.ReadAsByteArrayAsync(cancellationToken));
            return body.RootElement.ValueKind == JsonValueKind.Object
                && body.RootElement.TryGetProperty("error", out var error)
                && error.ValueKind == JsonValueKind.String
                && error.GetString() == "use_dpop_nonce";
        }
        catch (JsonException)
        {
            return false;
        }
    }
}
