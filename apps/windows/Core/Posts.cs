using System.Text.Json;

namespace YoruMimizuku.Core;

/// <summary>
/// Response of <c>app.bsky.feed.getPosts</c>. Deleted or blocked posts are left out, so
/// callers match posts by URI rather than by position or count.
/// </summary>
public sealed record GetPostsResponse(IReadOnlyList<PostView> Posts)
{
    public static GetPostsResponse FromJson(JsonElement json) =>
        new(json.RequiredArray("posts", PostView.FromJson));
}

/// <summary>The account's <c>app.bsky.feed.getPosts</c> call. The lexicon allows at most 25 URIs per call.</summary>
public interface IPostsService
{
    Task<GetPostsResponse> GetPostsAsync(IReadOnlyList<string> uris, CancellationToken cancellationToken);
}
