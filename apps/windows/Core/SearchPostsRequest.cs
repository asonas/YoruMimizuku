using System.Globalization;

namespace YoruMimizuku.Core;

/// <summary>One <c>app.bsky.feed.searchPosts</c> call.</summary>
public sealed record SearchPostsRequest(string Query, string? Cursor = null, int Limit = 25, string? Sort = null)
{
    /// <summary>
    /// The request URI on <paramref name="pds"/>. Every value is percent-encoded,
    /// '+' included, because a query string decodes a bare '+' as a space.
    /// </summary>
    public Uri ToUri(Uri pds)
    {
        var parameters = new List<string>
        {
            "q=" + Uri.EscapeDataString(Query),
            "limit=" + Limit.ToString(CultureInfo.InvariantCulture),
        };
        if (Cursor is not null) parameters.Add("cursor=" + Uri.EscapeDataString(Cursor));
        if (Sort is not null) parameters.Add("sort=" + Uri.EscapeDataString(Sort));
        return new Uri(pds.AbsoluteUri.TrimEnd('/') + "/xrpc/app.bsky.feed.searchPosts?" + string.Join("&", parameters));
    }
}

/// <summary>Runs <c>searchPosts</c> as one account. The network side of filter loading.</summary>
public interface IPostSearch
{
    Task<SearchResponse> SearchPostsAsync(SearchPostsRequest request, CancellationToken cancellationToken);
}
