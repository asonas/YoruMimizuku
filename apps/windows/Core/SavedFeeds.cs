using System.Text.Json;

namespace YoruMimizuku.Core;

// XRPC models for the account's pinned feeds and lists. Port of the Swift
// BlueskyCore SavedFeeds models.

/// <summary>
/// <c>app.bsky.actor.getPreferences</c>, reduced to the saved feeds the account keeps in
/// <c>app.bsky.actor.defs#savedFeedsPrefV2</c>, in the account's order (empty when it has
/// never saved any). Other preference kinds are skipped: some use <c>items</c> with other shapes.
/// </summary>
public sealed record PreferencesResponse(IReadOnlyList<SavedFeedItem> SavedFeeds)
{
    public static PreferencesResponse FromJson(JsonElement json) =>
        new(json.RequiredArray("preferences", p => p)
            .Where(p => p.OptionalString("$type") == "app.bsky.actor.defs#savedFeedsPrefV2")
            .Select(p => p.RequiredArray("items", SavedFeedItem.FromJson))
            .FirstOrDefault() ?? []);
}

/// <summary>
/// <c>app.bsky.actor.defs#savedFeed</c>. <paramref name="Type"/> is <c>timeline</c>,
/// <c>feed</c> or <c>list</c> today; it stays a string so a new kind is skipped rather than failing.
/// </summary>
public sealed record SavedFeedItem(string Id, string Type, string Value, bool Pinned)
{
    public static SavedFeedItem FromJson(JsonElement json) =>
        new(json.RequiredString("id"), json.RequiredString("type"), json.RequiredString("value"),
            json.OptionalBool("pinned") ?? throw new JsonException("Missing 'pinned'."));
}

/// <summary><c>app.bsky.feed.getFeedGenerators</c>.</summary>
public sealed record FeedGeneratorsResponse(IReadOnlyList<FeedGeneratorView> Feeds)
{
    public static FeedGeneratorsResponse FromJson(JsonElement json) =>
        new(json.RequiredArray("feeds", FeedGeneratorView.FromJson));
}

/// <summary><c>app.bsky.feed.defs#generatorView</c>, the fields the sidebar shows.</summary>
public sealed record FeedGeneratorView(
    string Uri, ProfileViewBasic Creator, string DisplayName, string? Description, string? Avatar)
{
    public static FeedGeneratorView FromJson(JsonElement json) =>
        new(json.RequiredString("uri"), ProfileViewBasic.FromJson(json.Required("creator")),
            json.RequiredString("displayName"), json.OptionalString("description"), json.OptionalString("avatar"));
}

/// <summary><c>app.bsky.graph.getList</c>, read only for the list itself.</summary>
public sealed record ListResponse(ListView List)
{
    public static ListResponse FromJson(JsonElement json) => new(ListView.FromJson(json.Required("list")));
}

/// <summary>
/// <c>app.bsky.graph.defs#listView</c>, the fields the sidebar shows. <paramref name="Purpose"/>
/// is <c>app.bsky.graph.defs#curatelist</c>, <c>#modlist</c> or <c>#referencelist</c>.
/// </summary>
public sealed record ListView(
    string Uri, string Name, string? Description, string? Avatar, ProfileViewBasic Creator, string? Purpose)
{
    public static ListView FromJson(JsonElement json) =>
        new(json.RequiredString("uri"), json.RequiredString("name"), json.OptionalString("description"),
            json.OptionalString("avatar"), ProfileViewBasic.FromJson(json.Required("creator")),
            json.OptionalString("purpose"));
}
