using System.Text.Json;

namespace YoruMimizuku.Core;

/// <summary>Response of <c>app.bsky.feed.searchPosts</c>.</summary>
public sealed record SearchResponse(IReadOnlyList<PostView> Posts, string? Cursor, int? HitsTotal)
{
    public static SearchResponse FromJson(JsonElement json) =>
        new(
            json.RequiredArray("posts", PostView.FromJson),
            json.OptionalString("cursor"),
            json.OptionalInt("hitsTotal"));
}
