using System.Text.Json;
using System.Text.Json.Nodes;

namespace YoruMimizuku.Core;

/// <summary>How a term's value becomes a <c>searchPosts</c> query fragment.</summary>
public enum FilterTermKind { Keyword, User, Hashtag, Mention }

/// <summary>
/// <see cref="And"/> joins the terms into one query; <see cref="Or"/> searches each term
/// on its own and merges the results, because the search API has no boolean OR.
/// </summary>
public enum FilterCombinator { And, Or }

/// <summary>What dropping a person on a filter did.</summary>
public enum AuthorDropResult
{
    Added,
    AlreadyIncluded,
    /// <summary>
    /// The filter joins its conditions with AND and already names a person; a second
    /// <c>from:</c> could never match, so nothing is changed.
    /// </summary>
    WouldMatchNothing,
}

/// <summary>One condition row of a saved filter.</summary>
public sealed record FilterTerm(Guid Id, FilterTermKind Kind, string Value);

/// <summary>
/// A saved search shown as a timeline tab. The JSON shape is the one the WinUI app
/// already stores per account, so its existing files load unchanged.
/// </summary>
public sealed record SavedFilter(
    Guid Id,
    string Name,
    IReadOnlyList<FilterTerm> Terms,
    FilterCombinator Combinator,
    DateTimeOffset CreatedAt)
{
    /// <summary>
    /// The <c>searchPosts</c> queries this filter runs: one joined query for AND, one
    /// per term for OR. Empty when no term has a usable value.
    /// </summary>
    public IReadOnlyList<string> Subqueries
    {
        get
        {
            var fragments = Terms.Select(Fragment).OfType<string>().ToList();
            if (fragments.Count == 0) return [];
            return Combinator == FilterCombinator.And ? [string.Join(" ", fragments)] : fragments;
        }
    }

    /// <summary>The label used when the user leaves the name blank.</summary>
    public string FallbackName => string.Join(Combinator == FilterCombinator.Or ? " | " : " ", Subqueries);

    /// <summary>A one-line description of what the filter searches.</summary>
    public string Summary => Combinator == FilterCombinator.Or
        ? "OR: " + string.Join(", ", Subqueries)
        : Subqueries.FirstOrDefault() ?? "";

    /// <summary>
    /// This filter with a <c>from:</c> condition for <paramref name="handle"/> appended (a
    /// person dropped on it), or this filter unchanged when it already covers the person
    /// or is an AND filter that names someone else. Port of the Swift
    /// <c>WorkspaceModel.addAuthor(handle:toFilter:)</c>.
    /// </summary>
    public (AuthorDropResult Result, SavedFilter Filter) AddingAuthor(string handle)
    {
        var clean = (handle.StartsWith('@') ? handle[1..] : handle).Trim();
        // Read people from the same fragments the search sends, so @, blank rows and a
        // from: typed into a keyword count as the search counts them.
        var fragments = Terms.Select(Fragment).OfType<string>().Select(f => f.ToLowerInvariant()).ToList();
        var wanted = "from:" + clean.ToLowerInvariant();
        if (Combinator == FilterCombinator.And)
        {
            // One query: any person named anywhere already narrows it.
            var named = fragments
                .SelectMany(f => f.Split(' ', StringSplitOptions.RemoveEmptyEntries))
                .Where(word => word.StartsWith("from:", StringComparison.Ordinal))
                .ToHashSet();
            if (named.Contains(wanted)) return (AuthorDropResult.AlreadyIncluded, this);
            if (named.Count > 0) return (AuthorDropResult.WouldMatchNothing, this);
        }
        // One query per row: only a row of just this person covers them.
        else if (fragments.Contains(wanted)) return (AuthorDropResult.AlreadyIncluded, this);
        return (AuthorDropResult.Added, this with { Terms = [.. Terms, new FilterTerm(Guid.NewGuid(), FilterTermKind.User, clean)] });
    }

    /// <summary>
    /// The fragment for one term, or null when the value is blank once trimmed and
    /// stripped of its leading <c>@</c> or <c>#</c>, so "@" alone yields no <c>from:</c>.
    /// </summary>
    private static string? Fragment(FilterTerm term)
    {
        var value = term.Value.Trim();
        var (prefix, strip) = term.Kind switch
        {
            FilterTermKind.Keyword => ("", ""),
            FilterTermKind.User => ("from:", "@"),
            FilterTermKind.Hashtag => ("#", "#"),
            FilterTermKind.Mention => ("mentions:", "@"),
            _ => throw new ArgumentOutOfRangeException(nameof(term), term.Kind, null),
        };
        if (strip.Length > 0 && value.StartsWith(strip, StringComparison.Ordinal)) value = value[strip.Length..];
        return value.Length == 0 ? null : prefix + value;
    }

    /// <summary>
    /// The filter a toolbar search runs and, when kept, saves: the typed text, trimmed, as
    /// one keyword term and as the name. Null when the text is blank. Port of the Swift
    /// <c>WorkspaceModel.openSearch(query:)</c>.
    /// </summary>
    public static SavedFilter? ForSearch(string text)
    {
        var query = text.Trim();
        if (query.Length == 0) return null;
        return new SavedFilter(Guid.NewGuid(), query, [new FilterTerm(Guid.NewGuid(), FilterTermKind.Keyword, query)],
            FilterCombinator.And, DateTimeOffset.UtcNow);
    }

    public static SavedFilter FromJson(JsonElement json) =>
        new(
            ParseGuid(json, "Id"),
            json.RequiredString("Name"),
            json.RequiredArray("Terms", term => new FilterTerm(
                ParseGuid(term, "Id"),
                ParseName<FilterTermKind>(term, "Kind"),
                term.RequiredString("Value"))),
            ParseName<FilterCombinator>(json, "Combinator"),
            json.Required("CreatedAt").TryGetDateTimeOffset(out var createdAt)
                ? createdAt
                : throw new JsonException("'CreatedAt' is not a date."));

    public JsonObject ToJson() =>
        new()
        {
            ["Id"] = Id,
            ["Name"] = Name,
            ["Terms"] = new JsonArray(Terms.Select(term => (JsonNode)new JsonObject
            {
                ["Id"] = term.Id,
                ["Kind"] = term.Kind.ToString(),
                ["Value"] = term.Value,
            }).ToArray()),
            ["Combinator"] = Combinator.ToString(),
            ["CreatedAt"] = CreatedAt,
        };

    private static Guid ParseGuid(JsonElement json, string name) =>
        Guid.TryParse(json.RequiredString(name), out var id) ? id : throw new JsonException($"'{name}' is not a GUID.");

    private static T ParseName<T>(JsonElement json, string name) where T : struct, Enum
    {
        var value = json.RequiredString(name);
        foreach (var candidate in Enum.GetValues<T>())
        {
            if (string.Equals(candidate.ToString(), value, StringComparison.OrdinalIgnoreCase)) return candidate;
        }
        throw new JsonException($"'{name}' has unknown value '{value}'.");
    }
}
