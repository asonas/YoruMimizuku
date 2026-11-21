using System.Text.Json;
using static YoruMimizuku.Core.JsonFields;

namespace YoruMimizuku.Core;

/// <summary>Response of <c>app.bsky.feed.getPostThread</c>.</summary>
public sealed record ThreadResponse(ThreadViewPost Thread)
{
    public static ThreadResponse FromJson(JsonElement json) =>
        new(ThreadViewPost.FromJson(json.Required("thread")));
}

/// <summary>
/// A node of a post thread. <paramref name="Parent"/> is the next node up, carrying its
/// own ancestors; <paramref name="Replies"/> are the direct replies in server order.
/// A notFound or blocked parent reads as null (cutting the chain there), and such
/// replies are dropped.
/// </summary>
public sealed record ThreadViewPost(PostView Post, ThreadViewPost? Parent, IReadOnlyList<ThreadViewPost> Replies)
{
    public PostView? ParentPost => Parent?.Post;

    public static ThreadViewPost FromJson(JsonElement json)
    {
        var post = PostView.FromJson(json.Required("post"));
        var parent = json.Optional("parent") is { } parentJson ? Tolerant(() => FromJson(parentJson)) : null;
        return new ThreadViewPost(post, parent, json.ArrayDroppingInvalid("replies", FromJson));
    }
}
