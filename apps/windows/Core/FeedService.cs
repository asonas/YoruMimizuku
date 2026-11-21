namespace YoruMimizuku.Core;

/// <summary>The account's post feeds: the home timeline, an author's posts and a post's thread.</summary>
public sealed class FeedService(XrpcClient xrpc)
{
    /// <summary>A page of <c>app.bsky.feed.getTimeline</c>; <paramref name="cursor"/> null for the newest.</summary>
    public Task<TimelineResponse> GetTimelineAsync(
        string? cursor = null, int limit = 50, CancellationToken cancellationToken = default) =>
        xrpc.QueryAsync(
            "app.bsky.feed.getTimeline",
            [("limit", XrpcClient.Number(limit)), ("cursor", cursor)],
            TimelineResponse.FromJson,
            cancellationToken);

    /// <summary>
    /// A page of <c>app.bsky.feed.getAuthorFeed</c> for <paramref name="actor"/>, a DID or
    /// handle. The default filter shows the author's posts and their own threads.
    /// </summary>
    public Task<TimelineResponse> GetAuthorFeedAsync(
        string actor,
        string? cursor = null,
        int limit = 50,
        string filter = "posts_and_author_threads",
        CancellationToken cancellationToken = default) =>
        xrpc.QueryAsync(
            "app.bsky.feed.getAuthorFeed",
            [("actor", actor), ("limit", XrpcClient.Number(limit)), ("filter", filter), ("cursor", cursor)],
            TimelineResponse.FromJson,
            cancellationToken);

    /// <summary>
    /// <c>app.bsky.feed.getPostThread</c> for the post at <paramref name="uri"/>: up to 80
    /// ancestors and six levels of replies.
    /// </summary>
    public Task<ThreadResponse> GetPostThreadAsync(string uri, CancellationToken cancellationToken = default) =>
        xrpc.QueryAsync(
            "app.bsky.feed.getPostThread",
            [("uri", uri), ("depth", "6"), ("parentHeight", "80")],
            ThreadResponse.FromJson,
            cancellationToken);
}
