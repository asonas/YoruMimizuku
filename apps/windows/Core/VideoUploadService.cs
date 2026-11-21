using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace YoruMimizuku.Core;

/// <summary>
/// One state of a video processing job (<c>app.bsky.video.defs#jobStatus</c>).
/// <paramref name="Blob"/> is the processed video, set once the job is done.
/// </summary>
public sealed record VideoJobStatus(string JobId, string State, JsonNode? Blob, string? Error, string? Message)
{
    public bool IsFailed => State == "JOB_STATE_FAILED";

    /// <summary><c>getJobStatus</c> wraps the status in <c>jobStatus</c>; <c>uploadVideo</c> returns it bare.</summary>
    internal static VideoJobStatus FromJson(JsonElement json)
    {
        var status = json.Optional("jobStatus") ?? json;
        return new VideoJobStatus(
            status.RequiredString("jobId"),
            status.RequiredString("state"),
            status.Optional("blob") is { } blob ? JsonNode.Parse(blob.GetRawText()) : null,
            status.OptionalString("error"),
            status.OptionalString("message"));
    }
}

/// <summary>A video job that failed on the service or did not finish in time.</summary>
public sealed class VideoUploadException(string message) : Exception(message);

/// <summary>
/// Uploads a video to the Bluesky video service and waits until it is processed.
/// Unlike an image, which is one DPoP-bound <c>uploadBlob</c> to the PDS, a video goes
/// to another host with a Bearer service-auth token the PDS issued, so
/// <paramref name="http"/> must not carry the account's DPoP handler.
/// </summary>
/// <param name="delay">Waits between polls; tests replace it so they do not sleep.</param>
public sealed class VideoUploadService(
    HttpClient http,
    Uri? serviceUrl = null,
    Func<TimeSpan, CancellationToken, Task>? delay = null)
{
    public static readonly Uri DefaultServiceUrl = new("https://video.bsky.app");

    private readonly Uri service = serviceUrl ?? DefaultServiceUrl;
    private readonly Func<TimeSpan, CancellationToken, Task> wait = delay ?? Task.Delay;

    /// <summary>
    /// The service-auth audience that lets the video service upload the blob to the
    /// account's PDS: <c>did:web:&lt;PDS host&gt;</c>.
    /// </summary>
    public static string Audience(Uri pds) => "did:web:" + pds.Host;

    /// <summary>POSTs the raw bytes to <c>app.bsky.video.uploadVideo</c>, returning the new job.</summary>
    public async Task<VideoJobStatus> UploadVideoAsync(
        string serviceToken, string did, string name, byte[] data, string mimeType,
        CancellationToken cancellationToken = default)
    {
        using var request = Request(
            HttpMethod.Post,
            "app.bsky.video.uploadVideo",
            $"did={Uri.EscapeDataString(did)}&name={Uri.EscapeDataString(name)}",
            serviceToken);
        request.Content = XrpcClient.Bytes(data, mimeType);
        return await SendAsync("app.bsky.video.uploadVideo", request, cancellationToken);
    }

    /// <summary>One poll of the job's state (<c>app.bsky.video.getJobStatus</c>).</summary>
    public async Task<VideoJobStatus> GetJobStatusAsync(
        string jobId, string serviceToken, CancellationToken cancellationToken = default)
    {
        using var request = Request(
            HttpMethod.Get, "app.bsky.video.getJobStatus", "jobId=" + Uri.EscapeDataString(jobId), serviceToken);
        return await SendAsync("app.bsky.video.getJobStatus", request, cancellationToken);
    }

    /// <summary>
    /// Polls until the processed blob is ready, waiting <paramref name="interval"/>
    /// (two seconds by default) between attempts. Throws <see cref="VideoUploadException"/>
    /// when the job fails or <paramref name="maxAttempts"/> polls pass without a blob.
    /// </summary>
    public async Task<JsonNode> PollUntilCompleteAsync(
        string jobId, string serviceToken, int maxAttempts = 90, TimeSpan? interval = null,
        CancellationToken cancellationToken = default)
    {
        for (var attempt = 0; attempt < maxAttempts; attempt++)
        {
            var status = await GetJobStatusAsync(jobId, serviceToken, cancellationToken);
            if (status.Blob is { } blob) return blob;
            if (status.IsFailed)
                throw new VideoUploadException($"Video processing failed: {status.Message ?? status.Error ?? status.State}");
            if (attempt < maxAttempts - 1) await wait(interval ?? TimeSpan.FromSeconds(2), cancellationToken);
        }
        throw new VideoUploadException("Video processing did not finish in time.");
    }

    private HttpRequestMessage Request(HttpMethod method, string nsid, string query, string serviceToken)
    {
        var request = new HttpRequestMessage(method, new Uri(service, "/xrpc/" + nsid + "?" + query));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", serviceToken);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        return request;
    }

    private async Task<VideoJobStatus> SendAsync(string nsid, HttpRequestMessage request, CancellationToken cancellationToken)
    {
        using var response = await http.SendAsync(request, cancellationToken);
        var body = await response.Content.ReadAsByteArrayAsync(cancellationToken);
        if (!response.IsSuccessStatusCode) throw XrpcClient.Failure(nsid, response.StatusCode, body);
        using var document = JsonDocument.Parse(body);
        return VideoJobStatus.FromJson(document.RootElement);
    }
}
