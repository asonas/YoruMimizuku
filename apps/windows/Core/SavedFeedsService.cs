using System.Net;

namespace YoruMimizuku.Core;

/// <summary>
/// The account's pinned feeds and lists, and their timelines. Port of the Swift
/// <c>LiveSavedFeedsLoader</c> and <c>LiveSavedFeedLoader</c>.
/// </summary>
public sealed class SavedFeedsService(XrpcClient xrpc)
{
    /// <summary>
    /// The account's pins (<c>getPreferences</c>), named by <c>getFeedGenerators</c> (one
    /// request for every pinned feed) and <c>getList</c> (one request per pinned list). A
    /// list the appview answers InvalidRequest for (deleted or blocked) is skipped. Any
    /// other failure, including other 400s such as a DPoP nonce error, aborts the load so
    /// the sidebar keeps the pins it already shows.
    /// </summary>
    public async Task<IReadOnlyList<SavedFeedSource>> LoadPinnedAsync(CancellationToken cancellationToken = default)
    {
        var preferences = await xrpc.QueryAsync(
            "app.bsky.actor.getPreferences", [], PreferencesResponse.FromJson, cancellationToken);
        var pinned = preferences.SavedFeeds.Where(item => item.Pinned).ToList();

        var feedUris = pinned.Where(item => item.Type == "feed").Select(item => item.Value).Distinct().ToList();
        IReadOnlyList<FeedGeneratorView> feeds = feedUris.Count == 0
            ? []
            : (await xrpc.QueryAsync(
                "app.bsky.feed.getFeedGenerators",
                feedUris.Select(uri => ("feeds", (string?)uri)),
                FeedGeneratorsResponse.FromJson,
                cancellationToken)).Feeds;

        var lists = new List<ListView>();
        foreach (var uri in pinned.Where(item => item.Type == "list").Select(item => item.Value).Distinct())
        {
            try
            {
                lists.Add((await xrpc.QueryAsync(
                    "app.bsky.graph.getList",
                    [("list", uri), ("limit", "1")],
                    ListResponse.FromJson,
                    cancellationToken)).List);
            }
            catch (HttpRequestException error) when (
                error.StatusCode == HttpStatusCode.BadRequest && XrpcClient.ErrorName(error) == "InvalidRequest")
            {
                // An unresolvable list: skip it.
            }
        }

        return SavedFeedSource.Pinned(pinned, feeds, lists);
    }

    /// <summary>
    /// A page of the pinned feed (<c>app.bsky.feed.getFeed</c>) or list
    /// (<c>app.bsky.feed.getListFeed</c>) at <paramref name="uri"/>; both answer in the
    /// <c>getTimeline</c> shape.
    /// </summary>
    public Task<TimelineResponse> GetPageAsync(
        SavedFeedKind kind, string uri, string? cursor = null, CancellationToken cancellationToken = default) =>
        kind switch
        {
            SavedFeedKind.Feed => xrpc.QueryAsync(
                "app.bsky.feed.getFeed",
                [("feed", uri), ("limit", "50"), ("cursor", cursor)],
                TimelineResponse.FromJson,
                cancellationToken),
            _ => xrpc.QueryAsync(
                "app.bsky.feed.getListFeed",
                [("list", uri), ("limit", "50"), ("cursor", cursor)],
                TimelineResponse.FromJson,
                cancellationToken),
        };
}
