namespace YoruMimizuku.Core;

/// <summary>One <c>app.bsky.feed.searchPosts</c> call.</summary>
public sealed record SearchPostsRequest(string Query, string? Cursor = null, int Limit = 25, string? Sort = null);

/// <summary>Runs <c>searchPosts</c> as one account. The network side of filter loading.</summary>
public interface IPostSearch
{
    Task<SearchResponse> SearchPostsAsync(SearchPostsRequest request, CancellationToken cancellationToken);
}

/// <summary>Post search over the account's PDS.</summary>
public sealed class SearchService(XrpcClient xrpc) : IPostSearch
{
    public Task<SearchResponse> SearchPostsAsync(SearchPostsRequest request, CancellationToken cancellationToken) =>
        xrpc.QueryAsync(
            "app.bsky.feed.searchPosts",
            [("q", request.Query), ("limit", XrpcClient.Number(request.Limit)), ("cursor", request.Cursor), ("sort", request.Sort)],
            SearchResponse.FromJson,
            cancellationToken);
}
