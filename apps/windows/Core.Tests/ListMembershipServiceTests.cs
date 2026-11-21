using System.Net;
using System.Text.Json;

namespace YoruMimizuku.Core.Tests;

/// The live editor's contract, from apps/macos/Timeline/LiveListMembershipEditor.swift.
public class ListMembershipServiceTests
{
    private const string Close = "at://did:plc:me/app.bsky.graph.list/close";
    private const string Swift = "at://did:plc:me/app.bsky.graph.list/swift";
    private const string Mutes = "at://did:plc:me/app.bsky.graph.list/mutes";
    private const string Alice = "did:plc:alice";

    private sealed class FixedClock(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }

    /// A PDS and appview in one: the viewer's lists, and the list items its repo holds.
    /// Like the real PDS it accepts a second identical list item.
    private sealed class FakePds
    {
        public List<(string Uri, string Name, string Purpose)> Lists { get; } =
        [
            (Close, "近しい人", "app.bsky.graph.defs#curatelist"),
            (Swift, "Swift", "app.bsky.graph.defs#curatelist"),
            (Mutes, "ミュート", "app.bsky.graph.defs#modlist"),
        ];

        /// rkey → (subject, list)
        public Dictionary<string, (string Subject, string List)> Items { get; } = [];

        private int _next;

        public StubHttp Http { get; }

        public FakePds() => Http = new StubHttp(Respond);

        public string Put(string subject, string list)
        {
            var rkey = $"item{++_next}";
            Items[rkey] = (subject, list);
            return $"at://did:plc:me/app.bsky.graph.listitem/{rkey}";
        }

        private HttpResponseMessage Respond(SentRequest request)
        {
            switch (request.Path)
            {
                case "/xrpc/app.bsky.graph.getListsWithMembership":
                    var actor = request.Query["actor"];
                    var entries = Lists.Select(list =>
                    {
                        var item = Items.FirstOrDefault(i => i.Value.Subject == actor && i.Value.List == list.Uri).Key;
                        var listItem = item is null
                            ? ""
                            : $$""", "listItem": { "uri": "at://did:plc:me/app.bsky.graph.listitem/{{item}}", "subject": { "did": "{{actor}}", "handle": "alice.example" } }""";
                        return $$"""
                            { "list": { "uri": "{{list.Uri}}", "cid": "bafy", "name": "{{list.Name}}", "purpose": "{{list.Purpose}}",
                              "creator": { "did": "did:plc:me", "handle": "me.example" }, "indexedAt": "2026-11-20T00:00:00.000Z" }{{listItem}} }
                            """;
                    });
                    return StubHttp.Json($$"""{ "listsWithMembership": [ {{string.Join(",", entries)}} ] }""");
                case "/xrpc/com.atproto.repo.createRecord":
                    var record = request.Json.GetProperty("record");
                    var uri = Put(record.GetProperty("subject").GetString()!, record.GetProperty("list").GetString()!);
                    return StubHttp.Json($$"""{ "uri": "{{uri}}", "cid": "bafynew" }""");
                case "/xrpc/com.atproto.repo.deleteRecord":
                    Items.Remove(request.Json.GetProperty("rkey").GetString()!);
                    return StubHttp.Json("{}");
                default:
                    return StubHttp.Json("""{ "error": "MethodNotImplemented" }""", HttpStatusCode.NotFound);
            }
        }
    }

    private static ListMembershipService Service(FakePds pds) =>
        new(pds.Http.Xrpc(), new FixedClock(new DateTimeOffset(2026, 11, 20, 0, 0, 0, 123, TimeSpan.Zero)));

    [Fact]
    public async Task ListsAreTheViewersCuratedListsWithTheActorsListItem()
    {
        var pds = new FakePds();
        var item = pds.Put(Alice, Close);

        var lists = await Service(pds).ListsWithMembershipAsync(Alice);

        Assert.Equal(
            [new CuratedListMembership(Close, "近しい人", item), new CuratedListMembership(Swift, "Swift", null)],
            lists);
        var request = pds.Http.Single("app.bsky.graph.getListsWithMembership");
        Assert.Equal(Alice, request.Query["actor"]);
        Assert.Equal("curatelist", request.Query["purposes"]);
        Assert.Equal("100", request.Query["limit"]);
    }

    /// The record shape from ListItemRecordWrite (core/Tests/BlueskyCoreTests/ListMembershipModelsTests.swift).
    [Fact]
    public async Task AddingCreatesAListItemRecordInTheAccountsRepo()
    {
        var pds = new FakePds();

        var uri = await Service(pds).AddAsync(Alice, Close);

        var body = pds.Http.Single("com.atproto.repo.createRecord").Json;
        Assert.Equal("did:plc:me", body.GetProperty("repo").GetString());
        Assert.Equal("app.bsky.graph.listitem", body.GetProperty("collection").GetString());
        Assert.Equal(
            new Dictionary<string, string?>
            {
                ["$type"] = "app.bsky.graph.listitem",
                ["subject"] = Alice,
                ["list"] = Close,
                ["createdAt"] = "2026-11-20T00:00:00.123Z",
            },
            body.GetProperty("record").EnumerateObject().ToDictionary(p => p.Name, p => p.Value.GetString()));
        Assert.Equal("at://did:plc:me/app.bsky.graph.listitem/item1", uri);
    }

    [Fact]
    public async Task RemovingDeletesTheListItemByItsRkey()
    {
        var pds = new FakePds();
        var item = pds.Put(Alice, Close);

        await Service(pds).RemoveAsync(item);

        var body = pds.Http.Single("com.atproto.repo.deleteRecord").Json;
        Assert.Equal("did:plc:me", body.GetProperty("repo").GetString());
        Assert.Equal("app.bsky.graph.listitem", body.GetProperty("collection").GetString());
        Assert.Equal("item1", body.GetProperty("rkey").GetString());
        Assert.Empty(pds.Items);
    }

    /// The PDS accepts a second identical list item, so a change re-reads the server
    /// before it writes: adding someone another device already added, or adding twice,
    /// sends one createRecord at most.
    [Fact]
    public async Task AChangeReReadsTheServerSoTheListGetsNoDuplicateItem()
    {
        var pds = new FakePds();
        var model = new ListMembershipModel(Service(pds));
        await model.RefreshAsync(Alice);
        pds.Put(Alice, Close);

        Assert.False(await model.SetMembershipAsync(Alice, Close, true));
        Assert.True(await model.SetMembershipAsync(Alice, Swift, true));
        Assert.False(await model.SetMembershipAsync(Alice, Swift, true));

        Assert.Single(pds.Http.Requests, r => r.Path == "/xrpc/com.atproto.repo.createRecord");
        Assert.Equal(2, pds.Items.Count);
        Assert.Equal(4, pds.Http.Requests.Count(r => r.Path == "/xrpc/app.bsky.graph.getListsWithMembership"));
    }
}
