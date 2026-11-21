using System.Text.Json;
using System.Text.Json.Nodes;

namespace YoruMimizuku.Core;

/// <summary>
/// One of the viewer's curated lists and the list item that puts a given actor on it
/// (null when the actor is not on it). Port of the Swift <c>CuratedListMembership</c>.
/// </summary>
public sealed record CuratedListMembership(string ListUri, string Name, string? ItemUri);

/// <summary>Reads and edits who is on the viewer's curated lists. Port of the Swift <c>ListMembershipEditing</c>.</summary>
public interface IListMembershipEditor
{
    /// <summary>The viewer's curated lists, each with <paramref name="actorDid"/>'s list item if any.</summary>
    Task<IReadOnlyList<CuratedListMembership>> ListsWithMembershipAsync(string actorDid, CancellationToken cancellationToken = default);

    /// <summary>Creates a list item; returns its AT-URI.</summary>
    Task<string> AddAsync(string actorDid, string listUri, CancellationToken cancellationToken = default);

    Task RemoveAsync(string itemUri, CancellationToken cancellationToken = default);
}

/// <summary>
/// <c>app.bsky.graph.getListsWithMembership</c>: the session user's own lists, each with
/// the list item that puts the asked-about actor on it (null when absent).
/// </summary>
public sealed record ListsWithMembershipResponse(IReadOnlyList<ListWithMembership> ListsWithMembership)
{
    public static ListsWithMembershipResponse FromJson(JsonElement json) =>
        new(json.RequiredArray("listsWithMembership", ListWithMembership.FromJson));
}

/// <summary>A list, and the list item's AT-URI (its rkey is what removing the actor deletes).</summary>
public sealed record ListWithMembership(ListView List, string? ListItemUri)
{
    public static ListWithMembership FromJson(JsonElement json) =>
        new(ListView.FromJson(json.Required("list")), json.Optional("listItem")?.RequiredString("uri"));
}

/// <summary>
/// The window account's curated lists: reads them with
/// <c>app.bsky.graph.getListsWithMembership</c> and adds or removes people with
/// <c>app.bsky.graph.listitem</c> records in the account's repo. Lists are public
/// records, so whoever is put on one can see it. Port of the Swift
/// <c>LiveListMembershipEditor</c>.
/// </summary>
public sealed class ListMembershipService(XrpcClient xrpc, TimeProvider? clock = null) : IListMembershipEditor
{
    private const string CurateList = "app.bsky.graph.defs#curatelist";
    private const string ListItem = "app.bsky.graph.listitem";

    public async Task<IReadOnlyList<CuratedListMembership>> ListsWithMembershipAsync(
        string actorDid, CancellationToken cancellationToken = default)
    {
        // One page of up to 100 lists covers what a person curates by hand.
        var response = await xrpc.QueryAsync(
            "app.bsky.graph.getListsWithMembership",
            [("actor", actorDid), ("purposes", "curatelist"), ("limit", "100")],
            ListsWithMembershipResponse.FromJson,
            cancellationToken);
        return response.ListsWithMembership
            .Where(entry => entry.List.Purpose == CurateList)
            .Select(entry => new CuratedListMembership(entry.List.Uri, entry.List.Name, entry.ListItemUri))
            .ToList();
    }

    public async Task<string> AddAsync(string actorDid, string listUri, CancellationToken cancellationToken = default)
    {
        var record = new JsonObject
        {
            ["$type"] = ListItem,
            ["subject"] = actorDid,
            ["list"] = listUri,
            ["createdAt"] = RepoRecords.Timestamp(clock),
        };
        return (await xrpc.CreateRecordAsync(ListItem, record, cancellationToken)).Uri;
    }

    public Task RemoveAsync(string itemUri, CancellationToken cancellationToken = default) =>
        xrpc.DeleteRecordAsync(ListItem, itemUri, cancellationToken);
}
