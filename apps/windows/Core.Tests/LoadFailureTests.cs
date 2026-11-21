using System.Net;
using System.Net.Sockets;
using System.Text.Json;

namespace YoruMimizuku.Core.Tests;

public class LoadFailureTests
{
    /// Stands in for the server: answers every request with the handler's result.
    private sealed class StubServer(Func<CancellationToken, Task<HttpResponseMessage>> respond) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            respond(cancellationToken);
    }

    /// The exception a real HttpClient throws for a request that fails this way.
    private static async Task<Exception> FailureOf(HttpClient client)
    {
        using (client)
        {
            return await Assert.ThrowsAnyAsync<Exception>(async () =>
            {
                using var response = await client.GetAsync("http://pds.example/xrpc/app.bsky.feed.getTimeline");
                response.EnsureSuccessStatusCode();
            });
        }
    }

    private static Task<Exception> StatusFailure(HttpStatusCode status) =>
        FailureOf(new HttpClient(new StubServer(_ => Task.FromResult(new HttpResponseMessage(status)))));

    [Fact]
    public async Task RefusedConnectionClassifiesAsOffline()
    {
        var handler = new SocketsHttpHandler
        {
            ConnectCallback = (_, _) => throw new SocketException((int)SocketError.ConnectionRefused),
        };

        var failure = LoadFailure.From(await FailureOf(new HttpClient(handler)));

        Assert.Equal(LoadFailureKind.Offline, failure.Kind);
    }

    [Fact]
    public async Task TimeoutClassifiesAsOffline()
    {
        var silent = new StubServer(async cancellationToken =>
        {
            await Task.Delay(Timeout.Infinite, cancellationToken);
            return new HttpResponseMessage(HttpStatusCode.OK);
        });

        var failure = LoadFailure.From(await FailureOf(new HttpClient(silent) { Timeout = TimeSpan.FromMilliseconds(50) }));

        Assert.Equal(LoadFailureKind.Offline, failure.Kind);
    }

    [Theory]
    [InlineData(HttpRequestError.NameResolutionError)]
    [InlineData(HttpRequestError.ConnectionError)]
    [InlineData(HttpRequestError.ResponseEnded)]
    public void UnreachableNetworkErrorsClassifyAsOffline(HttpRequestError error)
    {
        Assert.Equal(LoadFailureKind.Offline, LoadFailure.From(new HttpRequestException(error)).Kind);
    }

    [Fact]
    public async Task Status429ClassifiesAsRateLimited()
    {
        Assert.Equal(LoadFailureKind.RateLimited, LoadFailure.From(await StatusFailure(HttpStatusCode.TooManyRequests)).Kind);
    }

    [Fact]
    public async Task ServerStatusClassifiesAsServer()
    {
        Assert.Equal(LoadFailureKind.Server, LoadFailure.From(await StatusFailure(HttpStatusCode.ServiceUnavailable)).Kind);
    }

    [Fact]
    public async Task OtherErrorsClassifyAsUnknown()
    {
        Assert.Equal(LoadFailureKind.Unknown, LoadFailure.From(new JsonException("bad payload")).Kind);
        Assert.Equal(LoadFailureKind.Unknown, LoadFailure.From(await StatusFailure(HttpStatusCode.NotFound)).Kind);
    }

    [Theory]
    [InlineData(LoadFailureKind.Offline, "オフラインのようです", "インターネット接続を確認して、もう一度お試しください。")]
    [InlineData(LoadFailureKind.RateLimited, "リクエストが多すぎます", "しばらく時間をおいてから再試行してください。")]
    [InlineData(LoadFailureKind.Server, "サーバーエラー", "サーバー側で問題が発生しました。時間をおいて再試行してください。")]
    [InlineData(LoadFailureKind.Unknown, "読み込みに失敗しました", "通信中に問題が発生しました。再試行してください。")]
    public void EachKindHasTheFriendlyTitleAndMessage(LoadFailureKind kind, string title, string message)
    {
        var failure = new LoadFailure(kind, "detail");

        Assert.Equal(title, failure.Title);
        Assert.Equal(message, failure.Message);
    }

    [Fact]
    public async Task DetailCarriesRawDescription()
    {
        var failure = LoadFailure.From(await StatusFailure(HttpStatusCode.TooManyRequests));

        Assert.Contains("429", failure.Detail);
    }
}
