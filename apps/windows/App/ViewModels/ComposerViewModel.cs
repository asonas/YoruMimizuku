using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Threading.Tasks;
using YoruMimizuku.App.Interop;
using YoruMimizuku.App.Mvvm;

namespace YoruMimizuku.App.ViewModels;

/// <summary>One pending image attachment (raw bytes base64-encoded for the bridge).</summary>
public sealed class ComposeImageItem
{
    public byte[] Data { get; init; } = Array.Empty<byte>();
    public string MimeType { get; init; } = "image/jpeg";
    public string Alt { get; set; } = "";
}

/// <summary>
/// Mirrors the Swift ComposerViewModel: text with a 300-grapheme limit, up to 4
/// images, optional reply parent and quote, and submit via the bridge.
/// </summary>
public sealed class ComposerViewModel : ObservableObject
{
    public const int MaxGraphemes = 300;
    public const int MaxImages = 4;

    private readonly string? _replyParentUri;
    private readonly (string Uri, string Cid)? _quote;

    public ObservableCollection<ComposeImageItem> Images { get; } = new();

    private string _text = "";
    public string Text
    {
        get => _text;
        set { if (SetProperty(ref _text, value)) { OnPropertyChanged(nameof(Remaining)); OnPropertyChanged(nameof(CanSubmit)); } }
    }

    private bool _isSubmitting;
    public bool IsSubmitting { get => _isSubmitting; private set { if (SetProperty(ref _isSubmitting, value)) OnPropertyChanged(nameof(CanSubmit)); } }

    private string? _errorMessage;
    public string? ErrorMessage { get => _errorMessage; private set => SetProperty(ref _errorMessage, value); }

    public bool IsReply => _replyParentUri is not null;
    public bool IsQuote => _quote is not null;
    public int GraphemeCount => new StringInfo(Text).LengthInTextElements;
    public int Remaining => MaxGraphemes - GraphemeCount;
    public bool CanAddImage => Images.Count < MaxImages;
    public bool CanSubmit => !IsSubmitting && Remaining >= 0 && (GraphemeCount > 0 || Images.Count > 0 || IsQuote);

    public event Action<PostResultDto>? Posted;

    public ComposerViewModel(string? replyParentUri = null, (string Uri, string Cid)? quote = null)
    {
        _replyParentUri = replyParentUri;
        _quote = quote;
    }

    public ComposeImageItem? AddImage(byte[] data, string mimeType)
    {
        if (!CanAddImage) return null;
        var item = new ComposeImageItem { Data = data, MimeType = mimeType };
        Images.Add(item);
        OnPropertyChanged(nameof(CanAddImage));
        OnPropertyChanged(nameof(CanSubmit));
        return item;
    }

    public void RemoveImage(ComposeImageItem item)
    {
        if (!Images.Remove(item)) return;
        OnPropertyChanged(nameof(CanAddImage));
        OnPropertyChanged(nameof(CanSubmit));
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
                images,
                replyParentURI = _replyParentUri,
                quote = _quote is { } q ? new { uri = q.Uri, cid = q.Cid } : null
            };
            var result = await BridgeClient.Shared.PostCreateAsync(draft);
            Posted?.Invoke(result);
        }
        catch (Exception ex) { ErrorMessage = ex.Message; }
        finally { IsSubmitting = false; }
    }
}
