using System;
using System.Globalization;
using System.Linq;
using YoruMimizuku.Core;

namespace YoruMimizuku.App.Interop;

/// <summary>
/// The C# core's models as the DTOs the views consume, field for field as the
/// former Swift bridge encoded them (Interop.Tests pins that shape). URLs pass
/// through as the server wrote them; times are UTC ISO 8601 with milliseconds.
/// </summary>
internal static class CoreDtos
{
    public static PostDisplayDto Post(PostDisplay p) =>
        new(
            p.Id,
            p.Cid,
            p.AuthorDisplayName,
            p.AuthorHandle,
            Url(p.AvatarUrl),
            p.Body,
            p.Segments.Select(Segment).ToList(),
            Time(p.CreatedAt),
            p.ContextLabel,
            p.MediaWarning switch
            {
                MediaWarning.Adult => "adult",
                MediaWarning.Graphic => "graphic",
                _ => null,
            },
            p.Images.Select(Image).ToList(),
            p.LinkCard is { } card ? LinkCard(card) : null,
            p.Video is { } video ? Video(video) : null,
            p.Quote is { } quote ? Quote(quote) : null,
            p.ReplyParent is { } parent ? ReplyParent(parent) : null,
            p.ReplyCount,
            p.RepostCount,
            p.LikeCount,
            p.ViewerLikeUri,
            p.ViewerRepostUri,
            p.IsLiked,
            p.IsReposted);

    /// <summary>One level only: the parent's own parent is not carried.</summary>
    private static ReplyParentDto ReplyParent(PostDisplay p) =>
        new(p.Id, p.AuthorDisplayName, p.AuthorHandle, Url(p.AvatarUrl), p.Body, p.Segments.Select(Segment).ToList());

    public static ThreadNodeDto ThreadNode(ThreadNode node) =>
        new(Post(node.Post), node.Replies.Select(ThreadNode).ToList(), node.Depth);

    public static NotificationGroupDto NotificationGroup(NotificationGroup g) =>
        new(
            g.Id,
            g.Reason switch
            {
                NotificationReason.Like => "like",
                NotificationReason.Repost => "repost",
                NotificationReason.Follow => "follow",
                NotificationReason.Mention => "mention",
                NotificationReason.Reply => "reply",
                NotificationReason.Quote => "quote",
                _ => "other",
            },
            g.Actors.Select(a => new NotificationActorDto(a.DisplayName, a.Handle, Url(a.AvatarUrl))).ToList(),
            g.SubjectUri,
            g.SubjectText,
            Url(g.SubjectImageUrl),
            g.Text,
            Time(g.LatestCreatedAt),
            g.IsRead);

    /// <summary>The bridge never fills the bio.</summary>
    public static ProfileDto Profile(ProfileViewBasic p) => new(p.Did, p.Handle, p.DisplayName, p.Avatar, null);

    public static LinkCardDto LinkCard(LinkCard c) => new(c.Url.OriginalString, c.Title, c.Description, Url(c.ThumbUrl), c.Host);

    private static QuotedPostDto Quote(QuotedPost q) =>
        new(
            q.Id,
            q.Cid,
            q.AuthorDisplayName,
            q.AuthorHandle,
            Url(q.AvatarUrl),
            q.Body,
            Time(q.CreatedAt),
            q.Images.Select(Image).ToList(),
            q.Video is { } video ? Video(video) : null);

    private static RichSegmentDto Segment(RichTextSegment s) =>
        new(
            s.Kind switch
            {
                RichTextSegmentKind.Link => "link",
                RichTextSegmentKind.Tag => "tag",
                RichTextSegmentKind.Mention => "mention",
                _ => "text",
            },
            s.Text,
            Url(s.Url));

    private static PostImageDto Image(PostImage i) => new(Url(i.ThumbUrl), Url(i.FullsizeUrl), i.Alt);

    private static PostVideoDto Video(PostVideo v) => new(Url(v.ThumbUrl), v.Alt);

    private static string? Url(Uri? url) => url?.OriginalString;

    /// <summary>What Swift's ISO8601DateFormatter writes with fractional seconds.</summary>
    public static string Time(DateTimeOffset date) =>
        date.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture);
}
