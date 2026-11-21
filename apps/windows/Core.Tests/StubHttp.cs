using System.Collections.Specialized;
using System.Net;
using System.Text;
using System.Text.Json;
using System.Web;

namespace YoruMimizuku.Core.Tests;

/// <summary>A request as it reached the HTTP boundary, with its body read at send time.</summary>
internal sealed record SentRequest(HttpMethod Method, Uri Uri, string? ContentType, byte[]? Body, string? Authorization = null)
{
    public string Path => Uri.AbsolutePath;

    /// <summary>The query as a server reads it: a bare '+' decodes to a space.</summary>
    public NameValueCollection Query => HttpUtility.ParseQueryString(Uri.Query);

    public JsonElement Json => JsonDocument.Parse(Body!).RootElement;
}

/// <summary>Answers every request through <paramref name="respond"/> and records what was sent.</summary>
internal sealed class StubHttp(Func<SentRequest, HttpResponseMessage> respond) : HttpMessageHandler
{
    private readonly List<SentRequest> requests = [];

    public IReadOnlyList<SentRequest> Requests
    {
        get
        {
            lock (requests) return requests.ToList();
        }
    }

    /// <summary>Answers every request with <paramref name="json"/>.</summary>
    public StubHttp(string json) : this(_ => Json(json)) { }

    public SentRequest Last => Requests[^1];

    public SentRequest Single(string nsid) => Requests.Single(r => r.Path == "/xrpc/" + nsid);

    /// <summary>A client acting as <c>did:plc:me</c> on <c>https://pds.example</c>.</summary>
    public XrpcClient Xrpc() => new("did:plc:me", new Uri("https://pds.example"), new HttpClient(this));

    public static HttpResponseMessage Json(string json, HttpStatusCode status = HttpStatusCode.OK) =>
        new(status) { Content = new StringContent(json, Encoding.UTF8, "application/json") };

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var body = request.Content is null ? null : await request.Content.ReadAsByteArrayAsync(cancellationToken);
        var sent = new SentRequest(
            request.Method, request.RequestUri!, request.Content?.Headers.ContentType?.MediaType, body,
            request.Headers.Authorization?.ToString());
        lock (requests) requests.Add(sent);
        return respond(sent);
    }
}
