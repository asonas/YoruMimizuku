using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Threading.Tasks;
using YoruMimizuku.App.Interop;
using YoruMimizuku.App.Mvvm;

namespace YoruMimizuku.App.ViewModels;

/// <summary>One pending image attachment (raw bytes base64-encoded for the core).</summary>
public sealed class ComposeImageItem
{
    public byte[] Data { get; init; } = Array.Empty<byte>();
    public string MimeType { get; init; } = "image/jpeg";
    public string Alt { get; set; } = "";
}

/// <summary>The pending video attachment: the file's bytes, sent as-is.</summary>
public sealed class ComposeVideoItem
{
    public byte[] Data { get; init; } = Array.Empty<byte>();
    public string MimeType { get; init; } = "video/mp4";
    public string Filename { get; init; } = "video.mp4";
    public int? Width { get; init; }
    public int? Height { get; init; }
    public string Alt { get; set; } = "";
}

/// <summary>
/// Mirrors the Swift ComposerViewModel: text with a 300-grapheme limit, up to 4
/// images or one video, optional reply parent and quote, and submit via the core.
/// </summary>
public sealed class ComposerViewModel : ObservableObject
{
    public const int MaxGraphemes = 300;
    public const int MaxImages = 4;

    private readonly IAccountClient _account;
    private readonly string? _replyParentUri;
    private readonly (string Uri, string Cid)? _quote;

    public ObservableCollection<ComposeImageItem> Images { get; } = new();

    private ComposeVideoItem? _video;
    public ComposeVideoItem? Video
    {
        get => _video;
        private set { if (SetProperty(ref _video, value)) NotifyMediaChanged(); }
    }

    private string _text = "";
    public string Text
    {
        get => _text;
        set
        {
            if (!SetProperty(ref _text, value)) return;
            OnPropertyChanged(nameof(Remaining));
            OnPropertyChanged(nameof(CanSubmit));
            OnPropertyChanged(nameof(HasUnsavedContent));
        }
    }

    private bool _isSubmitting;
    public bool IsSubmitting
    {
        get => _isSubmitting;
        private set
        {
            if (!SetProperty(ref _isSubmitting, value)) return;
            OnPropertyChanged(nameof(CanSubmit));
            OnPropertyChanged(nameof(CanAddVideo));
        }
    }

    private string? _errorMessage;
    public string? ErrorMessage { get => _errorMessage; private set => SetProperty(ref _errorMessage, value); }

    public bool IsReply => _replyParentUri is not null;
    public bool IsQuote => _quote is not null;
    public int GraphemeCount => new StringInfo(Text).LengthInTextElements;
    public int Remaining => MaxGraphemes - GraphemeCount;
    /// <summary>Images and a video are mutually exclusive: a post has one kind of media.</summary>
    public bool CanAddImage => Video is null && Images.Count < MaxImages;
    public bool CanAddVideo => Video is null && Images.Count == 0 && !IsSubmitting;
    public bool CanSubmit => !IsSubmitting && Remaining >= 0 && (GraphemeCount > 0 || Images.Count > 0 || Video is not null || IsQuote);

    /// <summary>
    /// Whether closing the composer would lose something the user produced: non-blank
    /// text, images or a video. A reply or quote target alone does not count, since
    /// reopening the composer recreates it.
    /// </summary>
    public bool HasUnsavedContent => !string.IsNullOrWhiteSpace(Text) || Images.Count > 0 || Video is not null;

    /// <summary>What the dialog shows while submitting: a video waits for upload and processing first.</summary>
    public string SubmitStatusText => Video is null ? "投稿中…" : "動画をアップロード・処理中…";

    public event Action<PostResultDto>? Posted;

    public ComposerViewModel(IAccountClient account, string? replyParentUri = null, (string Uri, string Cid)? quote = null)
    {
        _account = account;
        _replyParentUri = replyParentUri;
        _quote = quote;
    }

    public ComposeImageItem? AddImage(byte[] data, string mimeType)
    {
        if (!CanAddImage) return null;
        var item = new ComposeImageItem { Data = data, MimeType = mimeType };
        Images.Add(item);
        NotifyMediaChanged();
        return item;
    }

    public void RemoveImage(ComposeImageItem item)
    {
        if (!Images.Remove(item)) return;
        NotifyMediaChanged();
    }

    /// <summary>Attaches <paramref name="video"/>; false when images or another video are already attached.</summary>
    public bool SetVideo(ComposeVideoItem video)
    {
        if (!CanAddVideo) return false;
        Video = video;
        return true;
    }

    public void RemoveVideo() => Video = null;

    private void NotifyMediaChanged()
    {
        OnPropertyChanged(nameof(CanAddImage));
        OnPropertyChanged(nameof(CanAddVideo));
        OnPropertyChanged(nameof(CanSubmit));
        OnPropertyChanged(nameof(HasUnsavedContent));
        OnPropertyChanged(nameof(SubmitStatusText));
    }

    public async Task SubmitAsync()
    {
        if (!CanSubmit) return;
        IsSubmitting = true;
        ErrorMessage = null;
        try
        {
            var images = new List<object>();
            foreach (var image in Images)
            {
                images.Add(new
                {
                    dataBase64 = Convert.ToBase64String(image.Data),
                    mimeType = image.MimeType,
                    alt = image.Alt
                });
            }
            var draft = new
            {
                text = Text,
                images = Video is null ? images : new List<object>(),
                video = Video is { } video
                    ? new
                    {
                        dataBase64 = Convert.ToBase64String(video.Data),
                        mimeType = video.MimeType,
                        alt = video.Alt,
                        filename = video.Filename,
                        width = video.Width,
                        height = video.Height
                    }
                    : null,
                replyParentURI = _replyParentUri,
                quote = _quote is { } q ? new { uri = q.Uri, cid = q.Cid } : null
            };
            var result = await _account.PostCreateAsync(draft);
            Posted?.Invoke(result);
        }
        catch (Exception ex) { ErrorMessage = ex.Message; }
        finally { IsSubmitting = false; }
    }
}
