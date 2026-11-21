using System.Net;

namespace YoruMimizuku.Core.Tests;

/// The live loader's contract, from apps/macos/Timeline/LiveSavedFeedsLoaders.swift.
public class SavedFeedsServiceTests
{
    private const string Feed = "at://did:plc:x/app.bsky.feed.generator/talk";
    private const string Close = "at://did:plc:me/app.bsky.graph.list/close";
    private const string Gone = "at://did:plc:me/app.bsky.graph.list/gone";

    private static string Preferences(params (string Type, string Value, bool Pinned)[] items) =>
        $$"""
        {
          "preferences": [
            { "$type": "app.bsky.actor.defs#savedFeedsPrefV2", "items": [
              {{string.Join(",", items.Select((item, i) =>
                  $$"""{ "id": "{{i}}", "type": "{{item.Type}}", "value": "{{item.Value}}", "pinned": {{(item.Pinned ? "true" : "false")}} }"""))}}
            ] }
          ]
        }
        """;

    private const string Generators = $$"""
        { "feeds": [ {
          "uri": "{{Feed}}", "cid": "bafy", "did": "did:web:feeds.example",
          "creator": { "did": "did:plc:x", "handle": "discuss.feeds.example" },
          "displayName": "話題の議論", "indexedAt": "2026-11-20T00:00:00.000Z"
        } ] }
        """;

    private static string List(string uri, string name) => $$"""
        { "list": {
          "uri": "{{uri}}", "cid": "bafy", "name": "{{name}}", "purpose": "app.bsky.graph.defs#curatelist",
          "creator": { "did": "did:plc:me", "handle": "me.example" }, "indexedAt": "2026-11-20T00:00:00.000Z"
        }, "items": [] }
        """;

    private const string InvalidRequest = """{ "error": "InvalidRequest", "message": "List not found" }""";

    private const string Page = """
        { "cursor": "next", "feed": [ { "post": {
          "uri": "at://did:plc:alice/app.bsky.feed.post/aaa", "cid": "bafyreialice",
          "author": { "did": "did:plc:alice", "handle": "alice.bsky.social" },
          "record": { "text": "hi", "createdAt": "2026-06-04T12:00:00.000Z" },
          "indexedAt": "2026-06-04T12:00:01.000Z"
        } } ] }
        """;

    [Fact]
    public async Task LoadPinnedReadsThePrefsThenNamesEachPinnedFeedOnceAndEachList()
    {
        var http = new StubHttp(request => request.Path switch
        {
            "/xrpc/app.bsky.actor.getPreferences" => StubHttp.Json(Preferences(
                ("timeline", "following", true), ("feed", Feed, true), ("list", Close, true),
                ("feed", Feed, true), ("feed", "at://did:plc:y/app.bsky.feed.generator/old", false))),
            "/xrpc/app.bsky.feed.getFeedGenerators" => StubHttp.Json(Generators),
            "/xrpc/app.bsky.graph.getList" => StubHttp.Json(List(Close, "近しい人")),
            _ => throw new InvalidOperationException(request.Path),
        });

        var sources = await new SavedFeedsService(http.Xrpc()).LoadPinnedAsync();

        Assert.Equal([Feed, Close], sources.Select(s => s.Id));
        Assert.Equal(["話題の議論", "近しい人"], sources.Select(s => s.Title));
        Assert.Equal([Feed], http.Single("app.bsky.feed.getFeedGenerators").Query.GetValues("feeds") ?? []);
        var list = http.Single("app.bsky.graph.getList");
        Assert.Equal(Close, list.Query["list"]);
        Assert.Equal("1", list.Query["limit"]);
    }

    [Fact]
    public async Task AListTheAppviewCannotResolveIsSkippedAndNoFeedsMeansNoGeneratorRequest()
    {
        var http = new StubHttp(request => request.Path switch
        {
            "/xrpc/app.bsky.actor.getPreferences" => StubHttp.Json(Preferences(("list", Gone, true), ("list", Close, true))),
            "/xrpc/app.bsky.graph.getList" when request.Query["list"] == Gone =>
                StubHttp.Json(InvalidRequest, HttpStatusCode.BadRequest),
            "/xrpc/app.bsky.graph.getList" => StubHttp.Json(List(Close, "近しい人")),
            _ => throw new InvalidOperationException(request.Path),
        });

        var sources = await new SavedFeedsService(http.Xrpc()).LoadPinnedAsync();

        Assert.Equal([Close], sources.Select(s => s.Id));
        Assert.DoesNotContain(http.Requests, r => r.Path == "/xrpc/app.bsky.feed.getFeedGenerators");
    }

    [Theory]
    [InlineData(HttpStatusCode.BadRequest, """{ "error": "use_dpop_nonce" }""")]
    [InlineData(HttpStatusCode.BadGateway, """{ "error": "UpstreamFailure" }""")]
    public async Task AnyOtherListFailureAbortsTheLoad(HttpStatusCode status, string body)
    {
        var http = new StubHttp(request => request.Path switch
        {
            "/xrpc/app.bsky.actor.getPreferences" => StubHttp.Json(Preferences(("list", Close, true))),
            _ => StubHttp.Json(body, status),
        });

        var error = await Assert.ThrowsAsync<HttpRequestException>(
            () => new SavedFeedsService(http.Xrpc()).LoadPinnedAsync());

        Assert.Equal(status, error.StatusCode);
    }

    [Fact]
    public async Task AFeedPageComesFromGetFeedAndAListPageFromGetListFeed()
    {
        var http = new StubHttp(Page);
        var service = new SavedFeedsService(http.Xrpc());
        var page = await service.GetPageAsync(SavedFeedKind.Feed, Feed, cursor: "c1");
        await service.GetPageAsync(SavedFeedKind.List, Close);

        Assert.Equal("next", page.Cursor);
        Assert.Single(page.Feed);
        var feedRequest = http.Single("app.bsky.feed.getFeed");
        Assert.Equal(Feed, feedRequest.Query["feed"]);
        Assert.Equal("50", feedRequest.Query["limit"]);
        Assert.Equal("c1", feedRequest.Query["cursor"]);
        var listRequest = http.Single("app.bsky.feed.getListFeed");
        Assert.Equal(Close, listRequest.Query["list"]);
        Assert.Equal("50", listRequest.Query["limit"]);
        Assert.Null(listRequest.Query["cursor"]);
    }
}
