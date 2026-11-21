using System.Net.Http.Headers;
using System.Text.Json;

namespace YoruMimizuku.Core.OAuth;

/// <summary>An authorization server's metadata, with every endpoint already a usable URL.</summary>
internal sealed record AuthorizationServer(string Issuer, Uri AuthorizationEndpoint, Uri TokenEndpoint, Uri? ParEndpoint);

/// <summary>Where an account lives: its DID, its PDS and the PDS's authorization server.</summary>
internal sealed record DiscoveredAccount(string Did, Uri Pds, AuthorizationServer Server);

/// <summary>The discovery chain: handle or DID → DID → DID document → PDS → authorization server.</summary>
internal static class OAuthDiscovery
{
    private const string HandleResolver = "https://bsky.social";
    private const string PlcDirectory = "https://plc.directory";

    public static async Task<DiscoveredAccount> DiscoverAsync(HttpMessageInvoker http, string handleOrDid, CancellationToken cancellationToken)
    {
        var did = handleOrDid.StartsWith("did:", StringComparison.Ordinal)
            ? handleOrDid
            : await GetJsonAsync(http, new Uri($"{HandleResolver}/xrpc/com.atproto.identity.resolveHandle?handle={Uri.EscapeDataString(handleOrDid)}"),
                json => json.RequiredString("did"), cancellationToken);
        var pds = await ResolvePdsAsync(http, did, cancellationToken);
        var issuer = await GetJsonAsync(http, new Uri(pds.AbsoluteUri.TrimEnd('/') + "/.well-known/oauth-protected-resource"),
            json => json.RequiredArray("authorization_servers", server => server.GetString()).FirstOrDefault(), cancellationToken)
            ?? throw OAuthException.Malformed("no authorization_servers listed");
        return new DiscoveredAccount(did, pds, await FetchAuthorizationServerAsync(http, issuer, cancellationToken));
    }

    /// <summary>The issuer's metadata, which must name that same issuer.</summary>
    public static async Task<AuthorizationServer> FetchAuthorizationServerAsync(HttpMessageInvoker http, string issuer, CancellationToken cancellationToken)
    {
        if (!Uri.TryCreate(issuer, UriKind.Absolute, out var issuerUrl)) throw OAuthException.Malformed($"invalid authorization server issuer: {issuer}");
        var server = await GetJsonAsync(http, new Uri(issuerUrl.AbsoluteUri.TrimEnd('/') + "/.well-known/oauth-authorization-server"), json =>
            new AuthorizationServer(
                json.RequiredString("issuer"),
                Endpoint(json, "authorization_endpoint"),
                Endpoint(json, "token_endpoint"),
                json.OptionalString("pushed_authorization_request_endpoint") is null ? null : Endpoint(json, "pushed_authorization_request_endpoint")),
            cancellationToken);
        if (server.Issuer != issuer) throw OAuthException.Malformed($"issuer mismatch: expected {issuer}, got {server.Issuer}");
        return server;
    }

    private static async Task<Uri> ResolvePdsAsync(HttpMessageInvoker http, string did, CancellationToken cancellationToken)
    {
        Uri? document = null;
        if (did.StartsWith("did:plc:", StringComparison.Ordinal))
            document = new Uri($"{PlcDirectory}/{did}");
        else if (did.StartsWith("did:web:", StringComparison.Ordinal))
            Uri.TryCreate($"https://{did["did:web:".Length..]}/.well-known/did.json", UriKind.Absolute, out document);
        if (document is null) throw new OAuthException(OAuthErrorKind.UnsupportedDidMethod, $"Unsupported DID method: {did}");

        var endpoint = await GetJsonAsync(http, document, json => json
            .ArrayDroppingInvalid("service", service => new Service(
                service.RequiredString("id"), service.RequiredString("type"), service.RequiredString("serviceEndpoint")))
            .FirstOrDefault(service => service.Id.EndsWith("#atproto_pds", StringComparison.Ordinal) || service.Type == "AtprotoPersonalDataServer")
            ?.Endpoint, cancellationToken);
        return Uri.TryCreate(endpoint, UriKind.Absolute, out var pds)
            ? pds
            : throw new OAuthException(OAuthErrorKind.PdsNotFound, $"PDS not found for {did}");
    }

    private static Uri Endpoint(JsonElement json, string name) =>
        Uri.TryCreate(json.RequiredString(name), UriKind.Absolute, out var url) && url.Scheme is "https" or "http"
            ? url
            : throw new JsonException($"invalid {name}");

    private static async Task<T> GetJsonAsync<T>(HttpMessageInvoker http, Uri url, Func<JsonElement, T> parse, CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        using var response = await http.SendAsync(request, cancellationToken);
        if (!response.IsSuccessStatusCode)
            throw new OAuthException(OAuthErrorKind.DiscoveryFailed, $"OAuth discovery failed ({(int)response.StatusCode}): {url}", (int)response.StatusCode);
        try
        {
            using var document = JsonDocument.Parse(await response.Content.ReadAsByteArrayAsync(cancellationToken));
            return parse(document.RootElement);
        }
        catch (JsonException)
        {
            throw OAuthException.Malformed(url.AbsoluteUri);
        }
    }

    private sealed record Service(string Id, string Type, string Endpoint);
}
