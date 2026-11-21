using System.Globalization;

namespace YoruMimizuku.Core;

/// <summary>The sensitive-content warning that covers a post's media until the viewer reveals it.</summary>
public enum MediaWarning
{
    /// <summary>Adult or sexual content (<c>porn</c>, <c>sexual</c>, <c>nudity</c>).</summary>
    Adult,

    /// <summary>Graphic or disturbing media (<c>graphic-media</c>, legacy <c>gore</c>).</summary>
    Graphic,
}

/// <summary>An attached image: an inline thumbnail, the full size for the lightbox, and alt text.</summary>
/// <param name="AspectRatio">Width divided by height, when the embed reports it.</param>
public sealed record PostImage(Uri? ThumbUrl, Uri? FullsizeUrl, string Alt, double? AspectRatio);

/// <summary>An attached video: the poster, the HLS playlist, alt text and width divided by height.</summary>
public sealed record PostVideo(Uri? ThumbUrl, Uri? PlaylistUrl, string? Alt, double? AspectRatio);

/// <summary>
/// An external-link card. Only http and https links make a card, so tapping one never
/// hands a file or app URL to the system opener.
/// </summary>
public sealed record LinkCard(Uri Url, string Title, string Description, Uri? ThumbUrl)
{
    /// <summary>The source line under the card: the link's host without a leading <c>www.</c>.</summary>
    public string Host => Url.Host.StartsWith("www.", StringComparison.Ordinal) ? Url.Host[4..] : Url.Host;

    /// <summary>The card for an external embed, or null when its URI is not a web link.</summary>
    public static LinkCard? From(EmbedExternal external) =>
        DisplayUrl.Parse(external.Uri) is { Scheme: "http" or "https" } url
            ? new LinkCard(url, external.Title, external.Description, DisplayUrl.Parse(external.Thumb))
            : null;
}

/// <summary>
/// The post inside a quote card, with its own images and video poster. A quote nested
/// inside it is dropped. <paramref name="Id"/> is the quoted post's AT-URI.
/// </summary>
public sealed record QuotedPost(
    string Id,
    string Cid,
    string AuthorDisplayName,
    string AuthorHandle,
    Uri? AvatarUrl,
    string Body,
    DateTimeOffset CreatedAt,
    IReadOnlyList<PostImage> Images,
    PostVideo? Video)
{
    /// <summary>A recordWithMedia quote reports its media as a separate embed, so media is gathered across all of them.</summary>
    public static QuotedPost From(EmbedRecord record) =>
        new(
            record.Uri,
            record.Cid,
            DisplayName.Of(record.Author),
            record.Author.Handle,
            DisplayUrl.Parse(record.Author.Avatar),
            record.Value.Text,
            Timestamp.Parse(record.Value.CreatedAt),
            record.Embeds.SelectMany(e => e.Images).Select(PostDisplay.ToImage).ToList(),
            record.Embeds.Select(e => e.Video).OfType<EmbedVideo>().Select(PostDisplay.ToVideo).FirstOrDefault());
}

/// <summary>
/// A post as a timeline, thread or author row shows it.
/// <paramref name="ReplyParent"/> is the post it answers: one level from a feed, the
/// whole ancestor chain from a thread. <paramref name="ContextLabel"/> names who
/// reposted it into the feed.
/// </summary>
public sealed record PostDisplay(
    string Id,
    string Cid,
    string AuthorDid,
    string AuthorDisplayName,
    string AuthorHandle,
    Uri? AvatarUrl,
    bool AuthorIsVerified,
    string Body,
    IReadOnlyList<RichTextSegment> Segments,
    DateTimeOffset CreatedAt,
    string? ContextLabel,
    MediaWarning? MediaWarning,
    IReadOnlyList<PostImage> Images,
    LinkCard? LinkCard,
    PostVideo? Video,
    QuotedPost? Quote,
    PostDisplay? ReplyParent,
    int ReplyCount,
    int RepostCount,
    int LikeCount,
    string? ViewerLikeUri,
    string? ViewerRepostUri)
{
    public bool IsLiked => ViewerLikeUri is not null;

    public bool IsReposted => ViewerRepostUri is not null;

    /// <summary>The web links in this post, in reading order: the body's links, then
    /// the link card. Each URL appears once. Port of the Swift
    /// <c>PostDisplay.webLinks</c>.</summary>
    public IReadOnlyList<Uri> WebLinks =>
        Segments.Where(s => s.Kind == RichTextSegmentKind.Link).Select(s => s.Url)
            .Append(LinkCard?.Url)
            .OfType<Uri>()
            .DistinctBy(u => u.AbsoluteUri)
            .ToList();

    /// <summary>At most this many links open at once, so a post stuffed with links
    /// cannot flood the browser.</summary>
    public const int LinkOpenLimit = 5;

    /// <summary>One hydrated post, without reply parent or context label. Missing counts read as zero.</summary>
    public static PostDisplay From(PostView post) =>
        new(
            post.Uri,
            post.Cid,
            post.Author.Did,
            DisplayName.Of(post.Author),
            post.Author.Handle,
            DisplayUrl.Parse(post.Author.Avatar),
            post.Author.IsVerified,
            post.Record.Text,
            RichText.Segments(post.Record.Text, post.Record.Facets),
            Timestamp.Parse(post.Record.CreatedAt),
            null,
            WarningFor(post.Labels),
            (post.Embed?.Images ?? []).Select(ToImage).ToList(),
            post.Embed?.External is { } external ? LinkCard.From(external) : null,
            post.Embed?.Video is { } video ? ToVideo(video) : null,
            post.Embed?.Record is { } record ? QuotedPost.From(record) : null,
            null,
            post.ReplyCount ?? 0,
            post.RepostCount ?? 0,
            post.LikeCount ?? 0,
            post.Viewer?.Like,
            post.Viewer?.Repost);

    /// <summary>A feed row: a repost becomes the context label, and the immediate parent (only) becomes the reply parent.</summary>
    public static PostDisplay From(FeedViewPost item) =>
        From(item.Post) with
        {
            ContextLabel = item.Reason is { } reason ? $"{DisplayName.Of(reason.By)} がリポスト" : null,
            ReplyParent = item.Reply?.Parent is { } parent ? From(parent) : null,
        };

    /// <summary>A thread node, with its whole ancestor chain up to the thread root.</summary>
    public static PostDisplay From(ThreadViewPost node) =>
        From(node.Post) with { ReplyParent = node.Parent is { } parent ? From(parent) : null };

    internal static PostImage ToImage(EmbedImage image) =>
        new(DisplayUrl.Parse(image.Thumb), DisplayUrl.Parse(image.Fullsize), image.Alt, Ratio(image.AspectRatio));

    internal static PostVideo ToVideo(EmbedVideo video) =>
        new(DisplayUrl.Parse(video.Thumbnail), DisplayUrl.Parse(video.Playlist), video.Alt, Ratio(video.AspectRatio));

    private static double? Ratio(ImageAspectRatio? ratio) =>
        ratio is { Height: > 0 } ? (double)ratio.Width / ratio.Height : null;

    private static readonly HashSet<string> AdultLabels = ["porn", "sexual", "nudity"];
    private static readonly HashSet<string> GraphicLabels = ["graphic-media", "gore"];

    /// <summary>A label with <c>neg</c> set retracts its value. Adult wins when both apply.</summary>
    private static MediaWarning? WarningFor(IReadOnlyList<Label> labels)
    {
        var active = labels.Where(l => l.Neg != true).Select(l => l.Val).ToHashSet();
        if (active.Overlaps(AdultLabels)) return Core.MediaWarning.Adult;
        if (active.Overlaps(GraphicLabels)) return Core.MediaWarning.Graphic;
        return null;
    }
}

internal static class DisplayName
{
    /// <summary>The trimmed display name, or the handle when the name is missing or blank.</summary>
    public static string Of(ProfileViewBasic profile) =>
        profile.DisplayName?.Trim() is { Length: > 0 } name ? name : profile.Handle;
}

internal static class DisplayUrl
{
    public static Uri? Parse(string? value) =>
        Uri.TryCreate(value, UriKind.Absolute, out var url) ? url : null;
}

internal static class Timestamp
{
    /// <summary>An atproto timestamp, with or without fractional seconds; the Unix epoch when unparseable.</summary>
    public static DateTimeOffset Parse(string value) =>
        DateTimeOffset.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var date)
            ? date
            : DateTimeOffset.UnixEpoch;
}
