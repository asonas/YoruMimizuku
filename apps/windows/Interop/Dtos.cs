using System.Collections.Generic;
using System.Linq;
using System.Text.Json.Serialization;

namespace YoruMimizuku.App.Interop;

// The records the core hands the view models; CoreDtos maps the core's models to them.

public sealed record AccountDto(string Did, string? Handle);

public sealed record AccountSummaryDto(string Did, string? Handle);

public sealed record NextAccountDto(string? NextDid);

public sealed record RichSegmentDto(string Kind, string Text, string? Url);

/// <summary><paramref name="AspectRatio"/> is width divided by height, when the embed reports it.</summary>
public sealed record PostImageDto(string? ThumbUrl, string? FullsizeUrl, string Alt, double? AspectRatio = null);

public sealed record LinkCardDto(
    string Url,
    string Title,
    string Description,
    string? ThumbUrl,
    string? Host);

public sealed record PostVideoDto(string? ThumbUrl, string? Alt, string? PlaylistUrl = null, double? AspectRatio = null);

public sealed record QuotedPostDto(
    string Id,
    string Cid,
    string AuthorDisplayName,
    string AuthorHandle,
    string? AvatarUrl,
    string Body,
    string CreatedAt,
    List<PostImageDto> Images,
    PostVideoDto? Video);

/// <summary>What feed arrange reads from one post: <paramref name="AuthorDid"/> is the repo of its AT-URI.</summary>
public sealed record ArrangeItemDto(string Id, string AuthorDid, string CreatedAt, string? ReplyParentId);

public sealed record ArrangeResultDto(string Id, bool ConnectsToPrevious, bool ConnectsToNext);

public sealed record ReplyParentDto(
    string Id,
    string AuthorDisplayName,
    string AuthorHandle,
    string? AvatarUrl,
    string Body,
    List<RichSegmentDto> Segments);

public sealed record PostDisplayDto(
    string Id,
    string Cid,
    string AuthorDisplayName,
    string AuthorHandle,
    string? AvatarUrl,
    string Body,
    List<RichSegmentDto> Segments,
    string CreatedAt,
    string? ContextLabel,
    string? MediaWarning,
    List<PostImageDto> Images,
    LinkCardDto? LinkCard,
    PostVideoDto? Video,
    QuotedPostDto? Quote,
    ReplyParentDto? ReplyParent,
    int ReplyCount,
    int RepostCount,
    int LikeCount,
    string? ViewerLikeUri,
    string? ViewerRepostUri,
    bool IsLiked,
    bool IsReposted);

public sealed record TimelinePageDto(List<PostDisplayDto> Posts, string? Cursor);

public sealed record ThreadNodeDto(PostDisplayDto Post, List<ThreadNodeDto> Replies, int Depth);

public sealed record ConversationThreadDto(PostDisplayDto Focus, List<ThreadNodeDto> Replies);

public sealed record ProfileDto(string Did, string Handle, string? DisplayName, string? AvatarUrl, string? Bio);

public sealed record NotificationActorDto(string DisplayName, string Handle, string? AvatarUrl);

public sealed record NotificationGroupDto(
    string Id,
    string Reason,
    List<NotificationActorDto> Actors,
    string? SubjectUri,
    string? SubjectText,
    string? SubjectImageUrl,
    string? Text,
    string LatestCreatedAt,
    bool IsRead)
{
    [JsonIgnore]
    public NotificationActorDto? LeadActor => Actors.FirstOrDefault();
}

public sealed record PostResultDto(string Uri, string Cid);

public sealed record LoginBeginDto(string PendingId, string AuthUrl, string CallbackScheme);

public sealed record AvatarDto(string? AvatarUrl);

public sealed record RecordRefDto(string RecordUri);

public sealed record PermalinkDto(string? Url);
