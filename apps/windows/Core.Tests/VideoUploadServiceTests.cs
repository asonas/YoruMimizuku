using System.Net;

namespace YoruMimizuku.Core.Tests;

public class VideoUploadServiceTests
{
    private const string Blob = """{"$type":"blob","ref":{"$link":"bafyvideo"},"mimeType":"video/mp4","size":3}""";

    private static VideoUploadService Service(StubHttp http, List<TimeSpan>? waits = null) =>
        new(new HttpClient(http), delay: (wait, _) =>
        {
            waits?.Add(wait);
            return Task.CompletedTask;
        });

    [Fact]
    public async Task UploadPostsTheBytesToTheVideoServiceWithTheServiceToken()
    {
        var http = new StubHttp("""{"jobId":"job1","did":"did:plc:me","state":"JOB_STATE_CREATED"}""");

        var job = await Service(http).UploadVideoAsync("svc-token", "did:plc:me", "clip one.mp4", [1, 2, 3], "video/mp4");

        Assert.Equal("job1", job.JobId);
        var sent = http.Last;
        Assert.Equal(HttpMethod.Post, sent.Method);
        Assert.Equal("video.bsky.app", sent.Uri.Host);
        Assert.Equal("/xrpc/app.bsky.video.uploadVideo", sent.Path);
        Assert.Equal("did:plc:me", sent.Query["did"]);
        Assert.Equal("clip one.mp4", sent.Query["name"]);
        Assert.Equal("Bearer svc-token", sent.Authorization);
        Assert.Equal("video/mp4", sent.ContentType);
        Assert.Equal([1, 2, 3], sent.Body);
    }

    [Fact]
    public async Task PollWaitsBetweenStatusesUntilTheBlobIsReady()
    {
        var statuses = new Queue<string>([
            """{"jobStatus":{"jobId":"job1","state":"JOB_STATE_ENCODING","progress":40}}""",
            $$$"""{"jobStatus":{"jobId":"job1","state":"JOB_STATE_COMPLETED","blob":{{{Blob}}}}}""",
        ]);
        var http = new StubHttp(_ => StubHttp.Json(statuses.Dequeue()));
        var waits = new List<TimeSpan>();

        var blob = await Service(http, waits).PollUntilCompleteAsync("job1", "svc-token");

        Assert.Equal("bafyvideo", blob["ref"]!["$link"]!.GetValue<string>());
        Assert.Equal(2, http.Requests.Count);
        Assert.All(http.Requests, r =>
        {
            Assert.Equal("/xrpc/app.bsky.video.getJobStatus", r.Path);
            Assert.Equal("job1", r.Query["jobId"]);
            Assert.Equal("Bearer svc-token", r.Authorization);
        });
        Assert.Equal([TimeSpan.FromSeconds(2)], waits);
    }

    [Fact]
    public async Task PollThrowsWhenTheJobFails()
    {
        var http = new StubHttp("""{"jobStatus":{"jobId":"job1","state":"JOB_STATE_FAILED","message":"Video too long"}}""");

        var error = await Assert.ThrowsAsync<VideoUploadException>(() => Service(http).PollUntilCompleteAsync("job1", "t"));

        Assert.Contains("Video too long", error.Message);
    }

    [Fact]
    public async Task PollGivesUpAfterTheLastAttempt()
    {
        var http = new StubHttp("""{"jobStatus":{"jobId":"job1","state":"JOB_STATE_ENCODING"}}""");

        await Assert.ThrowsAsync<VideoUploadException>(() => Service(http).PollUntilCompleteAsync("job1", "t", maxAttempts: 3));

        Assert.Equal(3, http.Requests.Count);
    }

    [Fact]
    public async Task AFailedStatusCarriesTheHttpStatus()
    {
        var http = new StubHttp(_ => StubHttp.Json("""{"error":"RateLimitExceeded"}""", HttpStatusCode.TooManyRequests));

        var error = await Assert.ThrowsAsync<HttpRequestException>(
            () => Service(http).UploadVideoAsync("t", "did:plc:me", "a.mp4", [1], "video/mp4"));

        Assert.Equal(HttpStatusCode.TooManyRequests, error.StatusCode);
    }
}
