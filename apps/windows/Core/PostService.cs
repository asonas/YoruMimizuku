namespace YoruMimizuku.Core;

/// <summary>Reading and writing posts as the account.</summary>
public sealed class PostService(XrpcClient xrpc) : IPostsService
{
    public async Task<GetPostsResponse> GetPostsAsync(IReadOnlyList<string> uris, CancellationToken cancellationToken)
    {
        if (uris.Count == 0) return new GetPostsResponse([]);
        return await xrpc.QueryAsync(
            "app.bsky.feed.getPosts",
            uris.Select(uri => ("uris", (string?)uri)),
            GetPostsResponse.FromJson,
            cancellationToken);
    }
}
