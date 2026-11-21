using System.Net;

namespace YoruMimizuku.Core.Tests;

public class XrpcClientTests
{
    /// Sends a request again after a 401, as an authorizing handler does on a DPoP nonce challenge.
    private sealed class ResendOnUnauthorized : DelegatingHandler
    {
        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var response = await base.SendAsync(request, cancellationToken);
            if (response.StatusCode != HttpStatusCode.Unauthorized) return response;
            response.Dispose();
            return await base.SendAsync(request, cancellationToken);
        }
    }

    [Fact]
    public async Task AnAuthorizingHandlerCanSendARequestBodyAgain()
    {
        StubHttp? http = null;
        http = new StubHttp(request => http!.Requests.Count % 2 == 1
            ? StubHttp.Json("""{"error":"use_dpop_nonce"}""", HttpStatusCode.Unauthorized)
            : StubHttp.Json(request.Path.EndsWith("uploadBlob", StringComparison.Ordinal)
                ? """{"blob":{"$type":"blob","ref":{"$link":"bafycid"},"mimeType":"image/png","size":3}}"""
                : """{"uri":"at://did:plc:me/app.bsky.feed.post/new","cid":"bafynew"}"""));
        var xrpc = new XrpcClient(
            "did:plc:me", new Uri("https://pds.example"), new HttpClient(new ResendOnUnauthorized { InnerHandler = http }));

        await new PostService(xrpc).CreatePostAsync(new PostDraft("photo", [new DraftImage([1, 2, 3], "image/png", "")]));

        var sent = http.Requests;
        Assert.Equal(4, sent.Count);
        Assert.Equal([1, 2, 3], sent[1].Body);
        Assert.Equal(sent[0].Body, sent[1].Body);
        Assert.Equal("photo", sent[3].Json.GetProperty("record").GetProperty("text").GetString());
        Assert.Equal(sent[2].Body, sent[3].Body);
    }

    [Fact]
    public async Task AFailedStatusThrowsAnHttpRequestExceptionThatLoadFailureClassifies()
    {
        var http = new StubHttp(_ => StubHttp.Json("{}", HttpStatusCode.InternalServerError));

        var error = await Assert.ThrowsAsync<HttpRequestException>(() => new FeedService(http.Xrpc()).GetTimelineAsync());

        Assert.Equal(HttpStatusCode.InternalServerError, error.StatusCode);
        Assert.Equal(LoadFailureKind.Server, LoadFailure.From(error).Kind);
    }

    [Fact]
    public async Task TheServersErrorNameAndMessageReachTheException()
    {
        var http = new StubHttp(_ =>
            StubHttp.Json("""{"error":"InvalidRequest","message":"bad cursor"}""", HttpStatusCode.BadRequest));

        var error = await Assert.ThrowsAsync<HttpRequestException>(() => new FeedService(http.Xrpc()).GetTimelineAsync());

        Assert.Equal(HttpStatusCode.BadRequest, error.StatusCode);
        Assert.Contains("InvalidRequest", error.Message);
        Assert.Contains("bad cursor", error.Message);
    }
}
