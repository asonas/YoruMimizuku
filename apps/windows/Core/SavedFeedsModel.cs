namespace YoruMimizuku.Core;

public enum SavedFeedKind { Feed, List }

/// <summary>
/// The window's pinned feeds and lists. Pins are managed on the server (they sync
/// across devices), so a load replaces them. A failed load keeps the sources already
/// shown, and a load that a newer load or <see cref="Clear"/> overtook is dropped.
/// Port of the load half of the Swift <c>SavedFeedsModel</c>; used from one thread.
/// </summary>
public sealed class SavedFeedsModel<TSource>
{
    /// <summary>Bumped by every load and clear, so an overtaken load is dropped.</summary>
    private int _generation;

    /// <summary>Raised when <see cref="Sources"/> is replaced.</summary>
    public event Action? Changed;

    public IReadOnlyList<TSource> Sources { get; private set; } = [];

    public async Task LoadAsync(Func<Task<IReadOnlyList<TSource>>> load)
    {
        var generation = ++_generation;
        IReadOnlyList<TSource> loaded;
        try
        {
            loaded = await load();
        }
        catch (Exception)
        {
            return;
        }
        if (generation != _generation) return;
        Sources = loaded;
        Changed?.Invoke();
    }

    /// <summary>Drop the sources, and any load still in flight (the account changed).</summary>
    public void Clear()
    {
        _generation++;
        if (Sources.Count == 0) return;
        Sources = [];
        Changed?.Invoke();
    }
}

/// <summary>
/// A feed or list the account pinned (<c>savedFeedsPrefV2</c>), as the sidebar shows it.
/// <paramref name="Id"/> is the feed generator's or list's AT-URI;
/// <paramref name="IsCuratedList"/> marks a list of people chosen by hand. Port of the
/// Swift <c>SavedFeedSource</c>.
/// </summary>
public sealed record SavedFeedSource(
    string Id,
    SavedFeedKind Kind,
    string Title,
    string? Description,
    string? CreatorHandle,
    string? AvatarUrl,
    string? CreatorDid,
    bool IsCuratedList)
{
    /// <summary>
    /// The pinned feeds and lists in the order the account keeps them. The following
    /// timeline is the app's home tab, so it is skipped here, as are unpinned items,
    /// unknown kinds, items the server no longer resolves (a deleted feed or list), and
    /// repeats of a URI already listed.
    /// </summary>
    public static IReadOnlyList<SavedFeedSource> Pinned(
        IEnumerable<SavedFeedItem> items, IEnumerable<FeedGeneratorView> feeds, IEnumerable<ListView> lists)
    {
        var feedsByUri = feeds.DistinctBy(f => f.Uri).ToDictionary(f => f.Uri);
        var listsByUri = lists.DistinctBy(l => l.Uri).ToDictionary(l => l.Uri);
        return items
            .Where(item => item.Pinned && item.Type is "feed" or "list")
            .DistinctBy(item => item.Value)
            .Select(item => item.Type switch
            {
                "feed" when feedsByUri.TryGetValue(item.Value, out var feed) => new SavedFeedSource(
                    feed.Uri, SavedFeedKind.Feed, feed.DisplayName, feed.Description, feed.Creator.Handle,
                    feed.Avatar, feed.Creator.Did, false),
                "list" when listsByUri.TryGetValue(item.Value, out var list) => new SavedFeedSource(
                    list.Uri, SavedFeedKind.List, list.Name, list.Description, list.Creator.Handle,
                    list.Avatar, list.Creator.Did, list.Purpose == "app.bsky.graph.defs#curatelist"),
                _ => null,
            })
            .OfType<SavedFeedSource>()
            .ToList();
    }
}
