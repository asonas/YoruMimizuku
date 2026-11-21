using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json.Nodes;

namespace YoruMimizuku.App.ViewModels;

public enum FilterTermKind { Keyword, User, Hashtag, Mention }
public enum FilterCombinator { And, Or }

public sealed class FilterTermModel
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public FilterTermKind Kind { get; set; } = FilterTermKind.Keyword;
    public string Value { get; set; } = "";
}

/// <summary>
/// C# mirror of the Swift SavedFilter. Sent to the core as a SavedFilter JSON
/// object (the core computes the actual search subqueries), and persisted locally
/// per account.
/// </summary>
public sealed class SavedFilterModel
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    public List<FilterTermModel> Terms { get; set; } = new();
    public FilterCombinator Combinator { get; set; } = FilterCombinator.And;
    public DateTimeOffset CreatedAt { get; init; } = DateTimeOffset.UtcNow;

    public string DisplayName => string.IsNullOrWhiteSpace(Name) ? Summary : Name;

    public string Summary
    {
        get
        {
            var fragments = Terms.Select(Fragment).Where(f => f is not null).Cast<string>().ToList();
            if (fragments.Count == 0) return "";
            return Combinator == FilterCombinator.Or ? "OR: " + string.Join(", ", fragments) : string.Join(" ", fragments);
        }
    }

    private static string? Fragment(FilterTermModel term)
    {
        var v = term.Value.Trim();
        return term.Kind switch
        {
            FilterTermKind.Keyword => v.Length == 0 ? null : v,
            FilterTermKind.User => Strip('@', v) is { Length: > 0 } h ? "from:" + h : null,
            FilterTermKind.Hashtag => Strip('#', v) is { Length: > 0 } t ? "#" + t : null,
            FilterTermKind.Mention => Strip('@', v) is { Length: > 0 } m ? "mentions:" + m : null,
            _ => null
        };
    }

    private static string Strip(char ch, string s) => s.StartsWith(ch) ? s[1..] : s;

    public static SavedFilterModel From(Core.SavedFilter filter) => new()
    {
        Id = filter.Id,
        Name = filter.Name,
        Terms = filter.Terms.Select(t => new FilterTermModel
        {
            Id = t.Id,
            Kind = t.Kind switch
            {
                Core.FilterTermKind.User => FilterTermKind.User,
                Core.FilterTermKind.Hashtag => FilterTermKind.Hashtag,
                Core.FilterTermKind.Mention => FilterTermKind.Mention,
                _ => FilterTermKind.Keyword
            },
            Value = t.Value
        }).ToList(),
        Combinator = filter.Combinator == Core.FilterCombinator.Or ? FilterCombinator.Or : FilterCombinator.And,
        CreatedAt = filter.CreatedAt
    };

    /// <summary>Build the SavedFilter JSON object the core's search expects.</summary>
    public JsonObject ToSearchJson()
    {
        var terms = new JsonArray();
        foreach (var t in Terms)
        {
            terms.Add(new JsonObject
            {
                ["id"] = t.Id.ToString(),
                ["kind"] = t.Kind switch
                {
                    FilterTermKind.User => "user",
                    FilterTermKind.Hashtag => "hashtag",
                    FilterTermKind.Mention => "mention",
                    _ => "keyword"
                },
                ["value"] = t.Value
            });
        }
        // createdAt plays no part in a search, so it is not sent.
        return new JsonObject
        {
            ["id"] = Id.ToString(),
            ["name"] = Name,
            ["terms"] = terms,
            ["combinator"] = Combinator == FilterCombinator.Or ? "or" : "and"
        };
    }
}
