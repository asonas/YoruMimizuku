using System.Text.Json;
using static YoruMimizuku.Core.JsonFields;

namespace YoruMimizuku.Core;

// XRPC models for feeds and posts. Only the fields the app renders are modeled;
// unknown keys are ignored. Each FromJson throws JsonException when a required
// field is missing, and falls back to null or empty where a field's shape varies.

/// <summary>Response of <c>app.bsky.feed.getTimeline</c> (and the other feed queries).</summary>
public sealed record TimelineResponse(IReadOnlyList<FeedViewPost> Feed, string? Cursor)
{
    public static TimelineResponse FromJson(JsonElement json) =>
        new(json.RequiredArray("feed", FeedViewPost.FromJson), json.OptionalString("cursor"));
}

/// <summary>One feed row: the post, the repost that surfaced it, and the post it answers.</summary>
public sealed record FeedViewPost(PostView Post, ReasonRepost? Reason, ReplyRef? Reply)
{
    /// <summary>
    /// <c>reason</c> is a union; only a repost is read. A custom feed's <c>reasonPin</c>
    /// and other kinds read as null. A reason without <c>$type</c> is still read as a
    /// repost when it has a repost's fields.
    /// </summary>
    public static FeedViewPost FromJson(JsonElement json)
    {
        var post = PostView.FromJson(json.Required("post"));
        ReasonRepost? reason = null;
        if (json.Optional("reason") is { } reasonJson)
        {
            reason = reasonJson.OptionalString("$type") switch
            {
                "app.bsky.feed.defs#reasonRepost" => ReasonRepost.FromJson(reasonJson),
                null => Tolerant(() => ReasonRepost.FromJson(reasonJson)),
                _ => null,
            };
        }
        var reply = json.Optional("reply") is { } replyJson ? ReplyRef.FromJson(replyJson) : null;
        return new FeedViewPost(post, reason, reply);
    }
}

/// <summary>The reply context. A parent that is not a viewable post (notFound, blocked) reads as null.</summary>
public sealed record ReplyRef(PostView? Parent)
{
    public static ReplyRef FromJson(JsonElement json) =>
        new(json.Optional("parent") is { } parent ? Tolerant(() => PostView.FromJson(parent)) : null);
}

/// <summary>The repost that put a post in the feed.</summary>
public sealed record ReasonRepost(ProfileViewBasic By, string IndexedAt)
{
    public static ReasonRepost FromJson(JsonElement json) =>
        new(ProfileViewBasic.FromJson(json.Required("by")), json.RequiredString("indexedAt"));
}

/// <summary>
/// A content label. <paramref name="Src"/> is the labeler's DID (the author's for a
/// self-label); <paramref name="Neg"/> is true when the label retracts an earlier one.
/// </summary>
public sealed record Label(string Val, string? Src, bool? Neg)
{
    public static Label FromJson(JsonElement json) =>
        new(json.RequiredString("val"), json.OptionalString("src"), json.OptionalBool("neg"));
}

/// <summary>A hydrated post (<c>app.bsky.feed.defs#postView</c>).</summary>
public sealed record PostView(
    string Uri,
    string Cid,
    ProfileViewBasic Author,
    PostRecord Record,
    int? ReplyCount,
    int? RepostCount,
    int? LikeCount,
    string IndexedAt,
    PostEmbed? Embed,
    PostViewerState? Viewer,
    IReadOnlyList<Label> Labels)
{
    public static PostView FromJson(JsonElement json) =>
        new(
            json.RequiredString("uri"),
            json.RequiredString("cid"),
            ProfileViewBasic.FromJson(json.Required("author")),
            PostRecord.FromJson(json.Required("record")),
            json.OptionalInt("replyCount"),
            json.OptionalInt("repostCount"),
            json.OptionalInt("likeCount"),
            json.RequiredString("indexedAt"),
            json.Optional("embed") is { } embed ? PostEmbed.FromJson(embed) : null,
            json.Optional("viewer") is { } viewer ? PostViewerState.FromJson(viewer) : null,
            Tolerant(() => json.OptionalArray("labels", Label.FromJson)) ?? []);
}

/// <summary>The AT-URIs of the viewer's own like and repost records, when set.</summary>
public sealed record PostViewerState(string? Like, string? Repost)
{
    public static PostViewerState FromJson(JsonElement json) =>
        new(json.OptionalString("like"), json.OptionalString("repost"));
}

/// <summary>
/// A post's view embed, read by key shape rather than <c>$type</c>: <c>images</c>,
/// <c>external</c>, a video (recognized by <c>playlist</c>), and a quoted post. A
/// <c>recordWithMedia</c> embed contributes its media and its quote. Kinds the app
/// does not render read as an empty embed.
/// </summary>
public sealed record PostEmbed(
    IReadOnlyList<EmbedImage> Images,
    EmbedExternal? External,
    EmbedVideo? Video,
    EmbedRecord? Record)
{
    public static PostEmbed FromJson(JsonElement json)
    {
        var media = json.Optional("media") is { } mediaJson ? Tolerant(() => FromJson(mediaJson)) : null;
        var images = Tolerant(() => json.OptionalArray("images", EmbedImage.FromJson)) ?? media?.Images ?? [];
        var external = Tolerant(() => json.Optional("external") is { } e ? EmbedExternal.FromJson(e) : null)
            ?? media?.External;
        var video = json.TryGetProperty("playlist", out _)
            ? Tolerant(() => EmbedVideo.FromJson(json))
            : media?.Video;
        // record#view holds the quoted viewRecord directly; recordWithMedia#view holds a
        // whole record#view, one `record` level further down.
        var record = json.Optional("record") is { } recordJson
            ? Tolerant(() => EmbedRecord.FromJson(recordJson))
                ?? Tolerant(() => recordJson.Optional("record") is { } inner ? EmbedRecord.FromJson(inner) : null)
            : null;
        return new PostEmbed(images, external, video, record);
    }
}

/// <summary>
/// A quoted post, with its own media embeds for the quote card. Non-post records and
/// the notFound, blocked and detached variants fail to parse, so the parent embed
/// reads them as no quote.
/// </summary>
public sealed record EmbedRecord(
    string Uri,
    string Cid,
    ProfileViewBasic Author,
    PostRecord Value,
    IReadOnlyList<PostEmbed> Embeds)
{
    public static EmbedRecord FromJson(JsonElement json) =>
        new(
            json.RequiredString("uri"),
            json.RequiredString("cid"),
            ProfileViewBasic.FromJson(json.Required("author")),
            PostRecord.FromJson(json.Required("value")),
            Tolerant(() => json.OptionalArray("embeds", PostEmbed.FromJson)) ?? []);
}

/// <summary>A video embed: the HLS playlist, plus the poster, alt text and aspect ratio.</summary>
public sealed record EmbedVideo(string Playlist, string? Thumbnail, string? Alt, ImageAspectRatio? AspectRatio)
{
    public static EmbedVideo FromJson(JsonElement json) =>
        new(
            json.RequiredString("playlist"),
            json.OptionalString("thumbnail"),
            json.OptionalString("alt"),
            json.Optional("aspectRatio") is { } ratio ? ImageAspectRatio.FromJson(ratio) : null);
}

/// <summary>An external link card: the target and its OGP title, description and thumbnail.</summary>
public sealed record EmbedExternal(string Uri, string Title, string Description, string? Thumb)
{
    public static EmbedExternal FromJson(JsonElement json) =>
        new(
            json.RequiredString("uri"),
            json.RequiredString("title"),
            json.RequiredString("description"),
            json.OptionalString("thumb"));
}

/// <summary>The pixel size of an embedded image or video, for layout before it loads.</summary>
public sealed record ImageAspectRatio(int Width, int Height)
{
    public static ImageAspectRatio FromJson(JsonElement json) =>
        new(json.RequiredInt("width"), json.RequiredInt("height"));
}

/// <summary>One image of an images embed.</summary>
public sealed record EmbedImage(string Thumb, string Fullsize, string Alt, ImageAspectRatio? AspectRatio)
{
    public static EmbedImage FromJson(JsonElement json) =>
        new(
            json.RequiredString("thumb"),
            json.RequiredString("fullsize"),
            json.RequiredString("alt"),
            json.Optional("aspectRatio") is { } ratio ? ImageAspectRatio.FromJson(ratio) : null);
}

/// <summary>
/// A minimal profile. <paramref name="IsVerified"/> is true when trusted verifiers
/// vouch for the account (<c>verification.verifiedStatus == "valid"</c>).
/// </summary>
public sealed record ProfileViewBasic(string Did, string Handle, string? DisplayName, string? Avatar, bool IsVerified)
{
    public static ProfileViewBasic FromJson(JsonElement json) =>
        new(
            json.RequiredString("did"),
            json.RequiredString("handle"),
            json.OptionalString("displayName"),
            json.OptionalString("avatar"),
            Tolerant(() => json.Optional("verification")?.OptionalString("verifiedStatus")) == "valid");
}

/// <summary>
/// The post record (<c>app.bsky.feed.post</c>). <paramref name="CreatedAt"/> stays a
/// string for the display layer to parse.
/// </summary>
public sealed record PostRecord(string Text, string CreatedAt, IReadOnlyList<Facet> Facets)
{
    public static PostRecord FromJson(JsonElement json) =>
        new(
            json.RequiredString("text"),
            json.RequiredString("createdAt"),
            Tolerant(() => json.OptionalArray("facets", Facet.FromJson)) ?? []);
}

/// <summary>
/// A rich-text range. <paramref name="ByteStart"/> and <paramref name="ByteEnd"/> are
/// UTF-8 byte offsets into the post text, not character offsets.
/// </summary>
public sealed record Facet(int ByteStart, int ByteEnd, IReadOnlyList<FacetFeature> Features)
{
    /// <summary>Features of an unknown type are dropped without failing the facet.</summary>
    public static Facet FromJson(JsonElement json)
    {
        var index = json.Required("index");
        return new Facet(
            index.RequiredInt("byteStart"),
            index.RequiredInt("byteEnd"),
            json.ArrayDroppingInvalid("features", FacetFeature.FromJson));
    }
}

/// <summary>What a facet's range means: a link, a mention of a DID, or a hashtag.</summary>
public abstract record FacetFeature
{
    private FacetFeature() { }

    public sealed record Link(string Uri) : FacetFeature;

    public sealed record Mention(string Did) : FacetFeature;

    public sealed record Tag(string Name) : FacetFeature;

    public static FacetFeature FromJson(JsonElement json) =>
        json.RequiredString("$type") switch
        {
            "app.bsky.richtext.facet#link" => new Link(json.RequiredString("uri")),
            "app.bsky.richtext.facet#mention" => new Mention(json.RequiredString("did")),
            "app.bsky.richtext.facet#tag" => new Tag(json.RequiredString("tag")),
            var type => throw new JsonException($"Unsupported facet feature: {type}"),
        };
}
