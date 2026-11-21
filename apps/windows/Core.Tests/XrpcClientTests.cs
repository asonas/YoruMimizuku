using System.Net;

namespace YoruMimizuku.Core.Tests;

public class XrpcClientTests
{
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
