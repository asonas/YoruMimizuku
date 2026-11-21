using System.Text.Json;
using System.Text.Json.Nodes;

namespace YoruMimizuku.Core.Tests;

public class SavedFilterTests
{
    private static SavedFilter Filter(FilterCombinator combinator, params (FilterTermKind Kind, string Value)[] terms) =>
        new(Guid.NewGuid(), "n", terms.Select(t => new FilterTerm(Guid.NewGuid(), t.Kind, t.Value)).ToList(),
            combinator, DateTimeOffset.UnixEpoch);

    [Fact]
    public void RendersEachKindAsASearchFragment()
    {
        var filter = Filter(FilterCombinator.Or,
            (FilterTermKind.Keyword, "  hello world "),
            (FilterTermKind.User, "@alice.bsky.social"),
            (FilterTermKind.Hashtag, "#swift"),
            (FilterTermKind.Mention, "bob.bsky.social"));

        Assert.Equal(
            ["hello world", "from:alice.bsky.social", "#swift", "mentions:bob.bsky.social"],
            filter.Subqueries);
    }

    [Fact]
    public void AndJoinsFragmentsIntoOneQuery()
    {
        var filter = Filter(FilterCombinator.And,
            (FilterTermKind.Hashtag, "swift"),
            (FilterTermKind.User, "alice.bsky.social"));

        Assert.Equal(["#swift from:alice.bsky.social"], filter.Subqueries);
    }

    [Fact]
    public void OrRunsOneQueryPerFragment()
    {
        var filter = Filter(FilterCombinator.Or,
            (FilterTermKind.User, "alice.bsky.social"),
            (FilterTermKind.User, "bob.bsky.social"));

        Assert.Equal(["from:alice.bsky.social", "from:bob.bsky.social"], filter.Subqueries);
    }

    [Fact]
    public void BlankTermsAreDropped()
    {
        var filter = Filter(FilterCombinator.And,
            (FilterTermKind.Keyword, "   "),
            (FilterTermKind.Hashtag, "swift"));

        Assert.Equal(["#swift"], filter.Subqueries);
    }

    [Fact]
    public void NoUsableTermsYieldNoQueries()
    {
        Assert.Empty(Filter(FilterCombinator.Or, (FilterTermKind.Keyword, "  ")).Subqueries);
        Assert.Empty(Filter(FilterCombinator.And).Subqueries);
    }

    [Fact]
    public void PrefixOnlyValuesYieldNoFragment()
    {
        var filter = Filter(FilterCombinator.Or,
            (FilterTermKind.User, "@"),
            (FilterTermKind.Mention, " @ "),
            (FilterTermKind.Hashtag, "#"));

        Assert.Empty(filter.Subqueries);
    }

    [Fact]
    public void FallbackNameAndSummaryFollowTheCombinator()
    {
        var or = Filter(FilterCombinator.Or,
            (FilterTermKind.User, "alice.bsky.social"),
            (FilterTermKind.User, "bob.bsky.social"));
        Assert.Equal("from:alice.bsky.social | from:bob.bsky.social", or.FallbackName);
        Assert.Equal("OR: from:alice.bsky.social, from:bob.bsky.social", or.Summary);

        var and = Filter(FilterCombinator.And,
            (FilterTermKind.Hashtag, "swift"),
            (FilterTermKind.User, "alice.bsky.social"));
        Assert.Equal("#swift from:alice.bsky.social", and.FallbackName);
        Assert.Equal("#swift from:alice.bsky.social", and.Summary);
    }

    // Written by the current App's SavedFilterStore (System.Text.Json, JsonStringEnumConverter)
    // from a SavedFilterModel; DisplayName and Summary are computed properties it also writes.
    private const string StoredByApp = """
    {
      "Id": "22222222-2222-2222-2222-222222222222",
      "Name": "Two users",
      "Terms": [
        { "Id": "33333333-3333-3333-3333-333333333333", "Kind": "User", "Value": "alice.bsky.social" },
        { "Id": "44444444-4444-4444-4444-444444444444", "Kind": "Hashtag", "Value": "#swift" }
      ],
      "Combinator": "Or",
      "CreatedAt": "2026-06-23T01:02:03.4567891+00:00",
      "DisplayName": "Two users",
      "Summary": "OR: from:alice.bsky.social, #swift"
    }
    """;

    [Fact]
    public void ReadsTheFilterTheAppStores()
    {
        var filter = SavedFilter.FromJson(JsonElement.Parse(StoredByApp));

        Assert.Equal(Guid.Parse("22222222-2222-2222-2222-222222222222"), filter.Id);
        Assert.Equal("Two users", filter.Name);
        Assert.Equal(FilterCombinator.Or, filter.Combinator);
        Assert.Equal(new DateTimeOffset(2026, 6, 23, 1, 2, 3, TimeSpan.Zero).AddTicks(4567891), filter.CreatedAt);
        Assert.Equal(
            [
                new FilterTerm(Guid.Parse("33333333-3333-3333-3333-333333333333"), FilterTermKind.User, "alice.bsky.social"),
                new FilterTerm(Guid.Parse("44444444-4444-4444-4444-444444444444"), FilterTermKind.Hashtag, "#swift"),
            ],
            filter.Terms);
    }

    [Fact]
    public void WritesTheShapeTheAppStores()
    {
        var expected = JsonNode.Parse(StoredByApp)!.AsObject();
        expected.Remove("DisplayName");
        expected.Remove("Summary");

        var written = SavedFilter.FromJson(JsonElement.Parse(StoredByApp)).ToJson();

        Assert.True(JsonNode.DeepEquals(expected, written), written.ToJsonString());
    }

    [Fact]
    public void SearchesTheTypedTextAsOneKeywordNamedAfterIt()
    {
        var filter = SavedFilter.ForSearch("  rust from:alice #lang ");

        Assert.NotNull(filter);
        Assert.Equal("rust from:alice #lang", filter.Name);
        Assert.Equal([FilterTermKind.Keyword], filter.Terms.Select(t => t.Kind));
        Assert.Equal(["rust from:alice #lang"], filter.Subqueries);
    }

    [Fact]
    public void SearchesNothingForBlankText()
    {
        Assert.Null(SavedFilter.ForSearch(" \t\n"));
    }

    // Dropping a person on a filter: ports of the Swift WorkspaceModelTests.

    private static string[] UserValues(SavedFilter filter) =>
        filter.Terms.Where(t => t.Kind == FilterTermKind.User).Select(t => t.Value).ToArray();

    [Fact]
    public void DroppingAPersonOnAFilterAddsAFromTerm()
    {
        var (result, edited) = Filter(FilterCombinator.And, (FilterTermKind.Keyword, "swift")).AddingAuthor("@alice.example");

        Assert.Equal(AuthorDropResult.Added, result);
        Assert.Equal(["alice.example"], UserValues(edited));
        Assert.Equal("swift", edited.Terms[0].Value);
    }

    [Fact]
    public void DroppingSomeoneAlreadyInTheFilterChangesNothing()
    {
        var filter = Filter(FilterCombinator.Or, (FilterTermKind.User, "alice.example"));

        var (result, edited) = filter.AddingAuthor("Alice.example");

        Assert.Equal(AuthorDropResult.AlreadyIncluded, result);
        Assert.Same(filter, edited);
    }

    /// <summary>In an AND filter two from: terms can never both match, so the drop is refused.</summary>
    [Fact]
    public void DroppingASecondPersonOnAnAndFilterIsRefused()
    {
        var filter = Filter(FilterCombinator.And, (FilterTermKind.User, "alice.example"));

        var (result, edited) = filter.AddingAuthor("bob.example");

        Assert.Equal(AuthorDropResult.WouldMatchNothing, result);
        Assert.Same(filter, edited);
    }

    /// <summary>A filter saved from a toolbar search keeps from: inside a keyword term.</summary>
    [Fact]
    public void AFromInsideAKeywordCountsAsAPersonInAnAndFilter()
    {
        var filter = Filter(FilterCombinator.And, (FilterTermKind.Keyword, "swift from:alice.example"));

        Assert.Equal(AuthorDropResult.WouldMatchNothing, filter.AddingAuthor("bob.example").Result);
    }

    /// <summary>
    /// The drop compares people the way the search query names them: a leading @, a
    /// from: inside a keyword and blank rows follow the term's fragment.
    /// </summary>
    [Fact]
    public void TheDropComparesPeopleAsTheSearchQueryNamesThem()
    {
        var or = Filter(FilterCombinator.Or, (FilterTermKind.User, "@alice.example"));
        var saved = Filter(FilterCombinator.And, (FilterTermKind.Keyword, "from:alice.example swift"));
        var blank = Filter(FilterCombinator.And, (FilterTermKind.Keyword, "swift"), (FilterTermKind.User, "  "));

        Assert.Equal(AuthorDropResult.AlreadyIncluded, or.AddingAuthor("alice.example").Result);
        Assert.Equal(AuthorDropResult.AlreadyIncluded, saved.AddingAuthor("Alice.example").Result);
        Assert.Equal(AuthorDropResult.Added, blank.AddingAuthor("alice.example").Result);
    }

    /// <summary>
    /// An OR filter searches each row on its own, so a keyword row that also names the
    /// person does not stand in for a row of just that person.
    /// </summary>
    [Fact]
    public void AnOrFilterGainsAPersonOnlyNamedInsideAKeyword()
    {
        var filter = Filter(FilterCombinator.Or, (FilterTermKind.Keyword, "from:alice.example swift"));

        Assert.Equal(AuthorDropResult.Added, filter.AddingAuthor("alice.example").Result);
    }

    [Fact]
    public void DroppingASecondPersonOnAnOrFilterAddsThem()
    {
        var (result, edited) = Filter(FilterCombinator.Or, (FilterTermKind.User, "alice.example")).AddingAuthor("bob.example");

        Assert.Equal(AuthorDropResult.Added, result);
        Assert.Equal(["alice.example", "bob.example"], UserValues(edited));
    }

    [Fact]
    public void RejectsAnUnknownTermKind()
    {
        var json = StoredByApp.Replace("\"Kind\": \"User\"", "\"Kind\": \"List\"");

        Assert.Throws<JsonException>(() => SavedFilter.FromJson(JsonElement.Parse(json)));
    }
}
