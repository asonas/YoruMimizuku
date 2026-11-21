using System.Collections.Concurrent;

namespace YoruMimizuku.Core.Tests;

public class FilterSearchTests
{
    private static SavedFilter Filter(FilterCombinator combinator, params string[] keywords) =>
        new(Guid.NewGuid(), "n",
            keywords.Select(k => new FilterTerm(Guid.NewGuid(), FilterTermKind.Keyword, k)).ToList(),
            combinator, DateTimeOffset.UnixEpoch);

    private static PostView Post(string id, string createdAt) =>
        new($"at://did:plc:x/app.bsky.feed.post/{id}", "cid-" + id,
            new ProfileViewBasic("did:plc:x", "x.bsky.social", null, null, false),
            new PostRecord(id, createdAt, []),
            null, null, null, createdAt, null, null, []);

    /// <summary>Answers each (query, cursor) with a fixed page and records every request.</summary>
    private sealed class FakeSearch : IPostSearch
    {
        private readonly Dictionary<(string, string?), SearchResponse> _pages = new();
        public ConcurrentQueue<SearchPostsRequest> Requests { get; } = new();

        public FakeSearch Page(string query, string? cursor, string? next, params PostView[] posts)
        {
            _pages[(query, cursor)] = new SearchResponse(posts, next, null);
            return this;
        }

        public Task<SearchResponse> SearchPostsAsync(SearchPostsRequest request, CancellationToken cancellationToken)
        {
            Requests.Enqueue(request);
            return _pages.TryGetValue((request.Query, request.Cursor), out var page)
                ? Task.FromResult(page)
                : Task.FromException<SearchResponse>(new HttpRequestException($"no page for {request.Query}"));
        }
    }

    [Fact]
    public async Task AndFilterRunsOneLatestSearchAndPassesItsCursorThrough()
    {
        var search = new FakeSearch()
            .Page("cats dogs", null, "server-1", Post("a", "2026-06-04T12:00:00Z"))
            .Page("cats dogs", "server-1", null, Post("b", "2026-06-04T11:00:00Z"));
        var filter = Filter(FilterCombinator.And, "cats", "dogs");

        var first = await FilterSearch.LoadPageAsync(search, filter, null);
        var second = await FilterSearch.LoadPageAsync(search, filter, first.Cursor);

        Assert.Equal("server-1", first.Cursor);
        Assert.Equal(["cid-a"], first.Posts.Select(p => p.Cid));
        Assert.Equal(["cid-b"], second.Posts.Select(p => p.Cid));
        Assert.Null(second.Cursor);
        Assert.All(search.Requests, r => Assert.Equal("latest", r.Sort));
    }

    [Fact]
    public async Task FilterWithoutQueriesLoadsNothing()
    {
        var search = new FakeSearch();

        var page = await FilterSearch.LoadPageAsync(search, Filter(FilterCombinator.Or, "  "), null);

        Assert.Empty(page.Posts);
        Assert.Null(page.Cursor);
        Assert.Empty(search.Requests);
    }

    [Fact]
    public async Task OrFilterMergesNewestFirstWithoutDuplicates()
    {
        var search = new FakeSearch()
            .Page("cats", null, null, Post("p1", "2026-06-04T12:00:00.000Z"), Post("p3", "2026-06-04T10:00:00Z"))
            .Page("dogs", null, null, Post("p2", "2026-06-04T11:00:00Z"), Post("p1", "2026-06-04T12:00:00.000Z"));

        var page = await FilterSearch.LoadPageAsync(search, Filter(FilterCombinator.Or, "cats", "dogs"), null);

        Assert.Equal(["cid-p1", "cid-p2", "cid-p3"], page.Posts.Select(p => p.Cid));
        Assert.Null(page.Cursor);
    }

    [Fact]
    public async Task OrFilterNextPageContinuesEachSubqueryFromItsOwnCursor()
    {
        var search = new FakeSearch()
            .Page("cats", null, "cats-2", Post("c1", "2026-06-04T12:00:00Z"))
            .Page("dogs", null, "dogs-2", Post("d1", "2026-06-04T11:00:00Z"))
            .Page("cats", "cats-2", null, Post("c2", "2026-06-03T12:00:00Z"))
            .Page("dogs", "dogs-2", "dogs-3", Post("d2", "2026-06-03T11:00:00Z"));
        var filter = Filter(FilterCombinator.Or, "cats", "dogs");

        var first = await FilterSearch.LoadPageAsync(search, filter, null);
        var second = await FilterSearch.LoadPageAsync(search, filter, first.Cursor);

        Assert.Equal(["cid-c2", "cid-d2"], second.Posts.Select(p => p.Cid));
        Assert.NotNull(second.Cursor);
        Assert.Equal(
            new (string, string?)[] { ("cats", null), ("cats", "cats-2"), ("dogs", null), ("dogs", "dogs-2") },
            search.Requests.Select(r => (r.Query, r.Cursor)).Order());
    }

    [Fact]
    public async Task OrFilterStopsSearchingExhaustedSubqueriesAndEndsWhenAllAre()
    {
        var search = new FakeSearch()
            .Page("cats", null, null, Post("c1", "2026-06-04T12:00:00Z"))
            .Page("dogs", null, "dogs-2", Post("d1", "2026-06-04T11:00:00Z"))
            .Page("dogs", "dogs-2", null, Post("d2", "2026-06-03T11:00:00Z"));
        var filter = Filter(FilterCombinator.Or, "cats", "dogs");

        var first = await FilterSearch.LoadPageAsync(search, filter, null);
        var second = await FilterSearch.LoadPageAsync(search, filter, first.Cursor);

        Assert.Equal(["cid-d2"], second.Posts.Select(p => p.Cid));
        Assert.Null(second.Cursor);
        Assert.Equal(3, search.Requests.Count);
    }

    // The Swift loaders mean to restart when the cursor was made for a different number of
    // subqueries (the filter was edited), but they skip every subquery and end the feed.
    [Fact]
    public async Task OrCursorFromADifferentFilterStartsOver()
    {
        var search = new FakeSearch()
            .Page("cats", null, "cats-2", Post("c1", "2026-06-04T12:00:00Z"))
            .Page("dogs", null, "dogs-2", Post("d1", "2026-06-04T11:00:00Z"))
            .Page("birds", null, null, Post("b1", "2026-06-04T10:00:00Z"));
        var before = await FilterSearch.LoadPageAsync(search, Filter(FilterCombinator.Or, "cats", "dogs"), null);

        var page = await FilterSearch.LoadPageAsync(
            search, Filter(FilterCombinator.Or, "cats", "dogs", "birds"), before.Cursor);

        Assert.Equal(["cid-c1", "cid-d1", "cid-b1"], page.Posts.Select(p => p.Cid));
    }

    [Fact]
    public async Task OrFilterFailsThePageWhenOneSubqueryFails()
    {
        var search = new FakeSearch().Page("cats", null, "cats-2", Post("c1", "2026-06-04T12:00:00Z"));

        await Assert.ThrowsAsync<HttpRequestException>(
            () => FilterSearch.LoadPageAsync(search, Filter(FilterCombinator.Or, "cats", "dogs"), null));
    }
}
