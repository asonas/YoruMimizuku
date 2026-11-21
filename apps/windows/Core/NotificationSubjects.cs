namespace YoruMimizuku.Core;

/// <summary>Fills in the post that a like or repost row is about.</summary>
public static class NotificationSubjects
{
    private const int MaxUrisPerRequest = 25;

    /// <summary>
    /// Fetches the subject post of every like and repost row, each URI once and at most 25
    /// per request, in order, and attaches its text and first image thumbnail. Rows whose
    /// post is not returned, and all other rows, come back unchanged. A failed request
    /// throws; whether to show the rows without snippets is the caller's choice.
    /// </summary>
    public static async Task<IReadOnlyList<NotificationGroup>> HydrateAsync(
        IReadOnlyList<NotificationGroup> groups,
        IPostsService posts,
        CancellationToken cancellationToken = default)
    {
        var uris = groups
            .Where(g => g.Reason is NotificationReason.Like or NotificationReason.Repost)
            .Select(g => g.SubjectUri)
            .OfType<string>()
            .Distinct()
            .ToList();

        var subjects = new Dictionary<string, PostView>();
        foreach (var batch in uris.Chunk(MaxUrisPerRequest))
        {
            var response = await posts.GetPostsAsync(batch, cancellationToken);
            foreach (var post in response.Posts) subjects[post.Uri] = post;
        }

        return groups
            .Select(g => g.SubjectUri is { } uri && subjects.TryGetValue(uri, out var post)
                ? g with
                {
                    SubjectText = post.Record.Text,
                    SubjectImageUrl = DisplayUrl.Parse(post.Embed?.Images.FirstOrDefault()?.Thumb),
                }
                : g)
            .ToList();
    }
}
