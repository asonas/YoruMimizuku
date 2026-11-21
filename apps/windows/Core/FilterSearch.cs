using System.Globalization;
using System.Text.Json;

namespace YoruMimizuku.Core;

/// <summary>A page of a saved filter's results and the cursor for the next one, null at the end.</summary>
public sealed record FilterPage(IReadOnlyList<PostView> Posts, string? Cursor);

/// <summary>Loads a saved filter's results page by page through <see cref="IPostSearch"/>.</summary>
public static class FilterSearch
{
    /// <summary>
    /// A single query (AND, or OR with one usable term) is one search whose server cursor
    /// passes through. Several queries (OR) are searched together, merged newest first
    /// without duplicates, and paged by a cursor holding one server cursor per query.
    /// Any failed search fails the page, so a retry repeats it from the same cursor.
    /// </summary>
    public static async Task<FilterPage> LoadPageAsync(
        IPostSearch search, SavedFilter filter, string? cursor, CancellationToken cancellationToken = default)
    {
        var queries = filter.Subqueries;
        if (queries.Count == 0) return new FilterPage([], null);
        if (queries.Count == 1)
        {
            var response = await search.SearchPostsAsync(Latest(queries[0], cursor), cancellationToken);
            return new FilterPage(response.Posts, response.Cursor);
        }

        // Null on the first page. On a later page a null entry marks an exhausted query.
        var cursors = DecodeCursors(cursor, queries.Count);
        var responses = await Task.WhenAll(queries.Select((query, i) =>
            cursors is not null && cursors[i] is null
                ? Task.FromResult(Exhausted)
                : search.SearchPostsAsync(Latest(query, cursors?[i]), cancellationToken)));

        var posts = responses
            .SelectMany(response => response.Posts)
            .DistinctBy(post => post.Uri)
            .OrderByDescending(post => CreatedAt(post))
            .ToList();
        return new FilterPage(posts, EncodeCursors(responses.Select(response => response.Cursor).ToArray()));
    }

    private static readonly SearchResponse Exhausted = new([], null, null);

    private static SearchPostsRequest Latest(string query, string? cursor) => new(query, cursor, Sort: "latest");

    private static string? EncodeCursors(string?[] cursors) =>
        cursors.Any(c => c is not null) ? JsonSerializer.Serialize(cursors) : null;

    /// <summary>
    /// The per-query cursors, or null to start over: on the first page, and when the cursor
    /// was not made for this many queries because the filter changed since.
    /// </summary>
    private static string?[]? DecodeCursors(string? cursor, int count)
    {
        if (cursor is null) return null;
        try
        {
            return JsonSerializer.Deserialize<string?[]>(cursor) is { } cursors && cursors.Length == count ? cursors : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static DateTimeOffset CreatedAt(PostView post) =>
        DateTimeOffset.TryParse(post.Record.CreatedAt, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var date)
            ? date
            : DateTimeOffset.UnixEpoch;
}
