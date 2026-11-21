using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace YoruMimizuku.Core;

/// <summary>
/// XRPC calls to one signed-in account's PDS, acting as <see cref="Did"/>.
/// <para>
/// Authorization lives in <paramref name="http"/>'s handler chain, not here: a
/// <see cref="DelegatingHandler"/> for the account adds the DPoP proof, retries on a
/// nonce challenge and refreshes an expired token. So each account gets its own
/// <see cref="HttpClient"/>, and that client must only ever reach this PDS. Request
/// bodies are buffered, so the handler may send a request again.
/// </para>
/// A failed status throws <see cref="HttpRequestException"/> carrying the status code
/// and the server's error name and message; a body that does not decode throws
/// <see cref="JsonException"/>.
/// </summary>
public sealed class XrpcClient(string did, Uri pds, HttpClient http)
{
    /// <summary>The account the calls act as: the repo that writes go to.</summary>
    public string Did { get; } = did;

    /// <summary>The account's PDS, which every call goes to.</summary>
    public Uri Pds { get; } = pds;

    /// <summary>
    /// A GET of <paramref name="nsid"/>. Parameters with a null value are left out; a
    /// name may repeat for an array parameter. Every value is percent-encoded, '+'
    /// included, because a query string decodes a bare '+' as a space.
    /// </summary>
    internal async Task<T> QueryAsync<T>(
        string nsid,
        IEnumerable<(string Name, string? Value)> parameters,
        Func<JsonElement, T> parse,
        CancellationToken cancellationToken)
    {
        var query = string.Join("&", parameters
            .Where(p => p.Value is not null)
            .Select(p => p.Name + "=" + Uri.EscapeDataString(p.Value!)));
        using var request = new HttpRequestMessage(HttpMethod.Get, Endpoint(nsid, query));
        return Parse(await SendAsync(nsid, request, cancellationToken), parse);
    }

    /// <summary>A POST of <paramref name="body"/> to <paramref name="nsid"/>, decoding the output.</summary>
    internal async Task<T> ProcedureAsync<T>(
        string nsid, HttpContent body, Func<JsonElement, T> parse, CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, Endpoint(nsid, "")) { Content = body };
        return Parse(await SendAsync(nsid, request, cancellationToken), parse);
    }

    /// <summary>A POST of <paramref name="body"/> to <paramref name="nsid"/> whose output is not read.</summary>
    internal async Task ProcedureAsync(string nsid, HttpContent body, CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, Endpoint(nsid, "")) { Content = body };
        await SendAsync(nsid, request, cancellationToken);
    }

    internal static string Number(int value) => value.ToString(CultureInfo.InvariantCulture);

    internal static HttpContent Json(JsonNode body) => Bytes(Encoding.UTF8.GetBytes(body.ToJsonString()), "application/json");

    internal static HttpContent Bytes(byte[] data, string mimeType) =>
        new ByteArrayContent(data) { Headers = { ContentType = new MediaTypeHeaderValue(mimeType) } };

    private Uri Endpoint(string nsid, string query) =>
        new(Pds.AbsoluteUri.TrimEnd('/') + "/xrpc/" + nsid + (query.Length > 0 ? "?" + query : ""));

    private async Task<byte[]> SendAsync(string nsid, HttpRequestMessage request, CancellationToken cancellationToken)
    {
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        using var response = await http.SendAsync(request, cancellationToken);
        var body = await response.Content.ReadAsByteArrayAsync(cancellationToken);
        if (!response.IsSuccessStatusCode) throw Failure(nsid, response.StatusCode, body);
        return body;
    }

    private static T Parse<T>(byte[] body, Func<JsonElement, T> parse)
    {
        using var document = JsonDocument.Parse(body);
        return parse(document.RootElement);
    }

    internal static HttpRequestException Failure(string nsid, HttpStatusCode status, byte[] body)
    {
        var message = $"{nsid} failed with HTTP {(int)status}";
        try
        {
            using var document = JsonDocument.Parse(body);
            if (document.RootElement.OptionalString("error") is { } error)
            {
                message += $": {error}";
                if (document.RootElement.OptionalString("message") is { } detail) message += $" ({detail})";
            }
        }
        catch (JsonException)
        {
            // Not an XRPC error body; the status alone describes the failure.
        }
        return new HttpRequestException(message, null, status);
    }
}
