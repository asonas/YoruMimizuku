using System.Collections.Generic;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
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
    public bool HasContext => !string.IsNullOrEmpty(ContextLabel);
    public bool IsReply => ReplyParent is not null;
    public string RelativeTime => Services.RelativeTime.Format(CreatedAt);
    public string ReplyMarkerText => ReplyParent is { } p ? $"@{p.AuthorHandle} への返信" : "";
    public string AuthorHandleAt => "@" + AuthorHandle;

    public ImageSource? Avatar => AvatarUrl is { Length: > 0 } u
        ? new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new System.Uri(u)) : null;

    public Visibility ContextVisibility => HasContext ? Visibility.Visible : Visibility.Collapsed;
    public Visibility ReplyVisibility => IsReply ? Visibility.Visible : Visibility.Collapsed;
    public Visibility ImagesVisibility => HasImages ? Visibility.Visible : Visibility.Collapsed;

    // Action-bar glyphs/brushes (Segoe MDL2): like heart, repost two-arrows.
    public string LikeGlyph => IsLiked ? "\uEB52" : "\uEB51";
    public Brush LikeBrush => Brush(IsLiked ? "AppLikeBrush" : "AppTertiaryTextBrush");
    public string RepostGlyph => "\uE8EE";
    public Brush RepostBrush => Brush(IsReposted ? "AppAccentBrush" : "AppTertiaryTextBrush");

    // Label for the repost menu's first item: cancel when already reposted, otherwise repost.
    public string RepostActionText => IsReposted ? "リポストを取り消す" : "リポスト";

    private static Brush Brush(string key) => (Brush)Application.Current.Resources[key];

    private void NotifyLike() { OnPropertyChanged(nameof(IsLiked)); OnPropertyChanged(nameof(LikeGlyph)); OnPropertyChanged(nameof(LikeBrush)); }
    private void NotifyRepost() { OnPropertyChanged(nameof(IsReposted)); OnPropertyChanged(nameof(RepostGlyph)); OnPropertyChanged(nameof(RepostBrush)); OnPropertyChanged(nameof(RepostActionText)); }

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
            _viewerLikeUri = null; LikeCount = System.Math.Max(0, LikeCount - 1); NotifyLike();
            if (record != "pending:like") { try { await BridgeClient.Shared.UnlikeAsync(record); } catch { } }
        }
        else
        {
            _viewerLikeUri = "pending:like"; LikeCount += 1; NotifyLike();
            try { var r = await BridgeClient.Shared.LikeAsync(Id, Cid); _viewerLikeUri = r.RecordUri; }
            catch { _viewerLikeUri = null; LikeCount = System.Math.Max(0, LikeCount - 1); NotifyLike(); }
        }
    }

    public async Task ToggleRepostAsync()
    {
        if (IsReposted)
        {
            var record = _viewerRepostUri!;
            _viewerRepostUri = null; RepostCount = System.Math.Max(0, RepostCount - 1); NotifyRepost();
            if (record != "pending:repost") { try { await BridgeClient.Shared.UnrepostAsync(record); } catch { } }
        }
        else
        {
            _viewerRepostUri = "pending:repost"; RepostCount += 1; NotifyRepost();
            try { var r = await BridgeClient.Shared.RepostAsync(Id, Cid); _viewerRepostUri = r.RecordUri; }
            catch { _viewerRepostUri = null; RepostCount = System.Math.Max(0, RepostCount - 1); NotifyRepost(); }
        }
    }
}
