using System.Net;
using System.Text;

namespace YoruMimizuku.Core.Tests;

/// <summary>Answers requests with queued responses in order and records what was sent.</summary>
internal sealed class ScriptedHandler(params HttpResponseMessage[] responses) : HttpMessageHandler
{
    private readonly Queue<HttpResponseMessage> _responses = new(responses);

    public List<ObservedRequest> Sent { get; } = [];

    public static HttpResponseMessage Json(HttpStatusCode status, string body, params (string Name, string Value)[] headers)
    {
        var response = new HttpResponseMessage(status) { Content = new StringContent(body, Encoding.UTF8, "application/json") };
        foreach (var (name, value) in headers) response.Headers.TryAddWithoutValidation(name, value);
        return response;
    }

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        Sent.Add(await ObservedRequest.CaptureAsync(request, cancellationToken));
        return _responses.Count > 0 ? _responses.Dequeue() : new HttpResponseMessage(HttpStatusCode.InternalServerError);
    }
}

/// <summary>A request as the server saw it: the proof decoded and the body read at send time.</summary>
internal sealed record ObservedRequest(HttpMethod Method, Uri Uri, string? Authorization, DecodedProof? Proof, string? Body)
{
    public static async Task<ObservedRequest> CaptureAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
        new(request.Method,
            request.RequestUri!,
            request.Headers.Authorization?.ToString(),
            request.Headers.TryGetValues("DPoP", out var proof) ? DecodedProof.Parse(proof.Single()) : null,
            request.Content is null ? null : await request.Content.ReadAsStringAsync(cancellationToken));
}
