namespace YoruMimizuku.Core;

/// <summary>What feed threading reads from one post of the page.</summary>
/// <param name="ReplyParentId">The AT-URI of the post it replies to, wherever that post is.</param>
public sealed record ThreadingPost(string Id, string AuthorDid, DateTimeOffset CreatedAt, string? ReplyParentId);

/// <summary>
/// One row after threading, with the flags for the thread line: a grouped parent sits
/// directly above (<paramref name="ConnectsToPrevious"/>), a grouped reply directly
/// below (<paramref name="ConnectsToNext"/>).
/// </summary>
public sealed record ThreadedFeedItem(string Id, bool ConnectsToPrevious, bool ConnectsToNext);

/// <summary>Groups self-threads in a feed page the way Bluesky's web client shows them.</summary>
public static class FeedThreading
{
    /// <summary>
    /// Rearranges a newest-first page: a reply chain by one author on the page becomes
    /// one block, oldest first, at the position of the block's newest member. A reply
    /// joins its parent's block only when both have the same author, so replies by
    /// others stay separate rows. Posts whose parent is not on the page stay where they
    /// are. A repeated id is emitted once.
    /// </summary>
    public static IReadOnlyList<ThreadedFeedItem> Arrange(IReadOnlyList<ThreadingPost> posts)
    {
        var byId = new Dictionary<string, ThreadingPost>();
        foreach (var post in posts) byId.TryAdd(post.Id, post);

        var members = new Dictionary<string, List<ThreadingPost>>();
        var seen = new HashSet<string>();
        foreach (var post in posts)
        {
            if (!seen.Add(post.Id)) continue;
            var key = GroupKey(post);
            if (!members.TryGetValue(key, out var group)) members[key] = group = [];
            group.Add(post);
        }

        var items = new List<ThreadedFeedItem>();
        var emitted = new HashSet<string>();
        foreach (var post in posts)
        {
            var key = GroupKey(post);
            if (!emitted.Add(key) || !members.TryGetValue(key, out var group)) continue;
            var ordered = group.OrderBy(p => p.CreatedAt).ThenBy(p => p.Id, StringComparer.Ordinal).ToList();
            for (var i = 0; i < ordered.Count; i++)
                items.Add(new ThreadedFeedItem(ordered[i].Id, i > 0, i < ordered.Count - 1));
        }
        return items;

        // The topmost ancestor on the page still written by the same author. The visited
        // set stops a malformed parent cycle.
        string GroupKey(ThreadingPost post)
        {
            var current = post;
            var visited = new HashSet<string> { post.Id };
            while (current.ReplyParentId is { } parentId
                   && byId.TryGetValue(parentId, out var parent)
                   && visited.Add(parentId)
                   && parent.AuthorDid == current.AuthorDid)
            {
                current = parent;
            }
            return current.Id;
        }
    }
}
