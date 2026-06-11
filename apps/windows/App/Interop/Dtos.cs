using System.Collections.Generic;
using System.Linq;

namespace YoruMimizuku.App.Interop;

// C# mirrors of the bridge's JSON DTOs (see core/Sources/YoruMimizukuBridge).
// Property names match the Swift encoder output; deserialization is configured
// case-insensitive in BridgeClient.

public sealed record AccountDto(string Did, string? Handle);

public sealed record OptionalAccountDto(AccountDto? Account);

public sealed record RichSegmentDto(string Kind, string Text, string? Url);

public sealed record PostImageDto(string? ThumbUrl, string? FullsizeUrl, string Alt);

public sealed record LinkCardDto(
    string Url,
    string Title,
    string Description,
    string? ThumbUrl,
    string? Host);

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
    List<PostImageDto> Images,
    LinkCardDto? LinkCard,
    ReplyParentDto? ReplyParent,
    int ReplyCount,
    int RepostCount,
    int LikeCount,
    string? ViewerLikeUri,
    string? ViewerRepostUri,
    bool IsLiked,
    bool IsReposted);

public sealed record TimelinePageDto(List<PostDisplayDto> Posts, string? Cursor);

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
    public NotificationActorDto? LeadActor => Actors.FirstOrDefault();
}

public sealed record PostResultDto(string Uri, string Cid);

public sealed record LoginBeginDto(string PendingId, string AuthUrl, string CallbackScheme);

public sealed record AvatarDto(string? AvatarUrl);

public sealed record RecordRefDto(string RecordUri);

public sealed record PermalinkDto(string? Url);
