using System.Collections.Generic;
using System.Threading.Tasks;
using YoruMimizuku.App.Interop;
using YoruMimizuku.App.Mvvm;

namespace YoruMimizuku.App.ViewModels;

/// <summary>
/// Observable view model for one timeline/thread row. Wraps a bridge
/// <see cref="PostDisplayDto"/> and applies optimistic like/repost state in place
/// (mirroring PostDisplay.applyOptimistic* in YoruMimizukuKit) before the network
/// round-trip confirms it.
/// </summary>
public sealed class PostItem : ObservableObject
{
    public string Id { get; }
    public string Cid { get; }
    public string AuthorDisplayName { get; }
    public string AuthorHandle { get; }
    public string? AvatarUrl { get; }
    public string Body { get; }
    public IReadOnlyList<RichSegmentDto> Segments { get; }
    public string CreatedAt { get; }
    public string? ContextLabel { get; }
    public IReadOnlyList<PostImageDto> Images { get; }
    public ReplyParentDto? ReplyParent { get; }
    public int ReplyCount { get; }
    public bool HasImages => Images.Count > 0;
    public bool IsReply => ReplyParent is not null;

    private int _repostCount;
    public int RepostCount { get => _repostCount; private set => SetProperty(ref _repostCount, value); }

    private int _likeCount;
    public int LikeCount { get => _likeCount; private set => SetProperty(ref _likeCount, value); }

    private string? _viewerLikeUri;
    public bool IsLiked { get => _viewerLikeUri is not null; }

    private string? _viewerRepostUri;
    public bool IsReposted { get => _viewerRepostUri is not null; }

    public PostItem(PostDisplayDto dto)
    {
        Id = dto.Id;
        Cid = dto.Cid;
        AuthorDisplayName = dto.AuthorDisplayName;
        AuthorHandle = dto.AuthorHandle;
        AvatarUrl = dto.AvatarUrl;
        Body = dto.Body;
        Segments = dto.Segments;
        CreatedAt = dto.CreatedAt;
        ContextLabel = dto.ContextLabel;
        Images = dto.Images;
        ReplyParent = dto.ReplyParent;
        ReplyCount = dto.ReplyCount;
        _repostCount = dto.RepostCount;
        _likeCount = dto.LikeCount;
        _viewerLikeUri = dto.ViewerLikeUri;
        _viewerRepostUri = dto.ViewerRepostUri;
    }

    public async Task ToggleLikeAsync()
    {
        if (IsLiked)
        {
            var record = _viewerLikeUri!;
            _viewerLikeUri = null; LikeCount = System.Math.Max(0, LikeCount - 1); OnPropertyChanged(nameof(IsLiked));
            if (record != "pending:like") { try { await BridgeClient.Shared.UnlikeAsync(record); } catch { } }
        }
        else
        {
            _viewerLikeUri = "pending:like"; LikeCount += 1; OnPropertyChanged(nameof(IsLiked));
            try { var r = await BridgeClient.Shared.LikeAsync(Id, Cid); _viewerLikeUri = r.RecordUri; }
            catch { _viewerLikeUri = null; LikeCount = System.Math.Max(0, LikeCount - 1); OnPropertyChanged(nameof(IsLiked)); }
        }
    }

    public async Task ToggleRepostAsync()
    {
        if (IsReposted)
        {
            var record = _viewerRepostUri!;
            _viewerRepostUri = null; RepostCount = System.Math.Max(0, RepostCount - 1); OnPropertyChanged(nameof(IsReposted));
            if (record != "pending:repost") { try { await BridgeClient.Shared.UnrepostAsync(record); } catch { } }
        }
        else
        {
            _viewerRepostUri = "pending:repost"; RepostCount += 1; OnPropertyChanged(nameof(IsReposted));
            try { var r = await BridgeClient.Shared.RepostAsync(Id, Cid); _viewerRepostUri = r.RecordUri; }
            catch { _viewerRepostUri = null; RepostCount = System.Math.Max(0, RepostCount - 1); OnPropertyChanged(nameof(IsReposted)); }
        }
    }
}
