using System.Buffers;
using System.Collections.Concurrent;
using System.Text;

namespace YoruMimizuku.Core;

/// <summary>
/// Link cards for bare URLs, read from each page's Open Graph tags. Each URL is fetched
/// at most once: the result, a miss included, is kept for the loader's lifetime, and
/// concurrent requests for one URL share the fetch.
/// <para>
/// <paramref name="http"/> must not be an account's client: these requests go to any
/// site a post links to and must never carry the account's authorization.
/// </para>
/// </summary>
public sealed class LinkPreviewLoader(HttpClient http)
{
    // The tags live in <head>; this covers any sane head without holding a huge page.
    private const int MaxHtmlBytes = 1_000_000;
    private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(10);
    private const string UserAgent = "YoruMimizuku (+https://tangled.org/asonas.tngl.sh/YoruMimizuku)";

    private readonly ConcurrentDictionary<Uri, Lazy<Task<LinkCard?>>> previews = new();

    /// <summary>The card for <paramref name="url"/>, or null when it is not an http(s) HTML page with a title.</summary>
    public Task<LinkCard?> PreviewAsync(Uri url) =>
        previews.GetOrAdd(url, key => new Lazy<Task<LinkCard?>>(() => LoadAsync(key))).Value;

    private async Task<LinkCard?> LoadAsync(Uri url)
    {
        if (url.Scheme != Uri.UriSchemeHttp && url.Scheme != Uri.UriSchemeHttps) return null;
        var buffer = ArrayPool<byte>.Shared.Rent(MaxHtmlBytes);
        try
        {
            using var timeout = new CancellationTokenSource(Timeout);
            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            request.Headers.Accept.ParseAdd("text/html,application/xhtml+xml");
            request.Headers.UserAgent.ParseAdd(UserAgent);
            using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, timeout.Token);
            if (!response.IsSuccessStatusCode) return null;
            if (response.Content.Headers.ContentType?.MediaType is { } type
                && !type.Contains("html", StringComparison.OrdinalIgnoreCase)) return null;
            await using var stream = await response.Content.ReadAsStreamAsync(timeout.Token);
            var length = await stream.ReadAtLeastAsync(
                buffer.AsMemory(0, MaxHtmlBytes), MaxHtmlBytes, throwOnEndOfStream: false, timeout.Token);
            return Ogp.Parse(Encoding.UTF8.GetString(buffer, 0, length), url);
        }
        catch (Exception error) when (error is HttpRequestException or OperationCanceledException or IOException)
        {
            return null;
        }
        finally
        {
            ArrayPool<byte>.Shared.Return(buffer);
        }
    }
}
