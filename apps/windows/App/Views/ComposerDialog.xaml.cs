using System;
using System.IO;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Storage;
using Windows.Storage.FileProperties;
using Windows.Storage.Pickers;
using YoruMimizuku.App.Interop;
using YoruMimizuku.App.Services;
using YoruMimizuku.App.ViewModels;

namespace YoruMimizuku.App.Views;

public sealed partial class ComposerDialog : ContentDialog
{
    private readonly ComposerViewModel _vm;
    private bool _posted;

    public ComposerDialog(IAccountClient account, string? replyParentUri = null, (string Uri, string Cid)? quote = null, string? quotePreview = null)
    {
        _vm = new ComposerViewModel(account, replyParentUri, quote);
        InitializeComponent();
        if (replyParentUri is not null) Title = "返信";
        else if (quote is not null) Title = "引用投稿";
        if (quotePreview is not null)
        {
            QuotePreviewText.Text = quotePreview;
            QuotePreview.Visibility = Visibility.Visible;
        }
        PrimaryButtonClick += OnPrimaryClick;
        Closing += OnClosing;
        UpdateCounter();
    }

    /// <summary>
    /// Show the composer; returns true if a post was created. Closing it with unsaved
    /// text or media (キャンセル, Esc) asks first, and reopens the same draft when the
    /// user keeps editing: WinUI shows one ContentDialog at a time, so the
    /// confirmation runs between two showings rather than over the composer.
    /// </summary>
    public async Task<bool> ShowComposeAsync()
    {
        while (true)
        {
            await ShowAsync();
            if (_posted) return true;
            if (!_vm.HasUnsavedContent || await ConfirmDiscardAsync()) return false;
        }
    }

    private async Task<bool> ConfirmDiscardAsync()
    {
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "下書きを破棄しますか？",
            Content = "入力した内容は失われます。",
            PrimaryButtonText = "破棄する",
            CloseButtonText = "編集を続ける",
            DefaultButton = ContentDialogButton.Close
        };
        return await dialog.ShowAsync() == ContentDialogResult.Primary;
    }

    /// While a post is on its way (a video can take a while), nothing closes the dialog.
    private void OnClosing(ContentDialog sender, ContentDialogClosingEventArgs args)
    {
        if (_vm.IsSubmitting) args.Cancel = true;
    }

    private void OnTextChanged(object sender, TextChangedEventArgs e)
    {
        _vm.Text = TextBox.Text;
        UpdateCounter();
    }

    private void UpdateCounter()
    {
        CounterText.Text = _vm.Remaining.ToString();
        IsPrimaryButtonEnabled = _vm.CanSubmit;
        AddImageButton.IsEnabled = _vm.CanAddImage;
        AddVideoButton.IsEnabled = _vm.CanAddVideo;
    }

    private async void OnAddImageClick(object sender, RoutedEventArgs e)
    {
        if (!_vm.CanAddImage) return;
        var picker = new FileOpenPicker();
        picker.FileTypeFilter.Add(".png");
        picker.FileTypeFilter.Add(".jpg");
        picker.FileTypeFilter.Add(".jpeg");

        // Unpackaged apps must associate the picker with the window handle.
        if (MainWindowAccessor.Current is { } window)
        {
            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(window);
            WinRT.Interop.InitializeWithWindow.Initialize(picker, hwnd);
        }

        var file = await picker.PickSingleFileAsync();
        if (file is null) return;
        var rawBytes = await File.ReadAllBytesAsync(file.Path);
        var rawMime = file.FileType.Equals(".png", StringComparison.OrdinalIgnoreCase) ? "image/png" : "image/jpeg";
        var (bytes, mime) = await Services.ImageProcessing.PrepareAsync(rawBytes, rawMime);
        var item = _vm.AddImage(bytes, mime);
        if (item is null) return;
        AddImageEntry(file, item);
        UpdateCounter();
    }

    private async void OnAddVideoClick(object sender, RoutedEventArgs e)
    {
        if (!_vm.CanAddVideo) return;
        var picker = new FileOpenPicker();
        picker.FileTypeFilter.Add(".mp4");
        picker.FileTypeFilter.Add(".m4v");
        picker.FileTypeFilter.Add(".mov");
        if (MainWindowAccessor.Current is { } window)
        {
            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(window);
            WinRT.Interop.InitializeWithWindow.Initialize(picker, hwnd);
        }

        var file = await picker.PickSingleFileAsync();
        if (file is null) return;
        var attachment = await VideoAttachment.LoadAsync(file);
        var attached = _vm.SetVideo(new ComposeVideoItem
        {
            Data = attachment.Data,
            MimeType = attachment.MimeType,
            Filename = attachment.Filename,
            Width = attachment.Width,
            Height = attachment.Height
        });
        if (!attached) return;

        VideoFilename.Text = attachment.Filename;
        VideoAlt.Text = "";
        VideoPoster.Source = await PosterAsync(file);
        VideoPreview.Visibility = Visibility.Visible;
        UpdateCounter();
    }

    /// The shell's thumbnail of the video; none when the system cannot make one.
    private static async Task<BitmapImage?> PosterAsync(StorageFile file)
    {
        try
        {
            using var thumbnail = await file.GetThumbnailAsync(ThumbnailMode.VideosView, 192);
            var bitmap = new BitmapImage();
            await bitmap.SetSourceAsync(thumbnail);
            return bitmap;
        }
        catch (Exception)
        {
            return null;
        }
    }

    private void OnVideoAltChanged(object sender, TextChangedEventArgs e)
    {
        if (_vm.Video is { } video) video.Alt = VideoAlt.Text;
    }

    private void OnRemoveVideoClick(object sender, RoutedEventArgs e)
    {
        _vm.RemoveVideo();
        VideoPreview.Visibility = Visibility.Collapsed;
        VideoPoster.Source = null;
        VideoFilename.Text = "";
        VideoAlt.Text = "";
        UpdateCounter();
    }

    /// One attachment entry: a thumbnail, an alt-text editor bound to the item's
    /// Alt, and a remove button — the Windows analogue of the macOS/iPadOS
    /// per-image alt fields.
    private void AddImageEntry(StorageFile file, ComposeImageItem item)
    {
        var panel = new StackPanel { Width = 132, Spacing = 4 };

        panel.Children.Add(new Image
        {
            Width = 132,
            Height = 90,
            Stretch = Microsoft.UI.Xaml.Media.Stretch.UniformToFill,
            Source = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri(file.Path))
        });

        var alt = new TextBox
        {
            PlaceholderText = "代替テキスト",
            TextWrapping = TextWrapping.Wrap,
            AcceptsReturn = false,
            FontSize = 12
        };
        alt.TextChanged += (_, _) => item.Alt = alt.Text;
        panel.Children.Add(alt);

        var remove = new Button { Content = "削除", HorizontalAlignment = HorizontalAlignment.Right };
        remove.Click += (_, _) =>
        {
            _vm.RemoveImage(item);
            ImagesList.Items.Remove(panel);
            UpdateCounter();
        };
        panel.Children.Add(remove);

        ImagesList.Items.Add(panel);
    }

    private async void OnPrimaryClick(ContentDialog sender, ContentDialogButtonClickEventArgs args)
    {
        var deferral = args.GetDeferral();
        args.Cancel = true; // keep the dialog open until the post resolves
        ErrorText.Visibility = Visibility.Collapsed;
        ProgressText.Text = _vm.SubmitStatusText;
        ProgressText.Visibility = Visibility.Visible;
        IsPrimaryButtonEnabled = false;
        IsSecondaryButtonEnabled = false;
        await _vm.SubmitAsync();
        ProgressText.Visibility = Visibility.Collapsed;
        IsSecondaryButtonEnabled = true;
        UpdateCounter();
        if (_vm.ErrorMessage is null)
        {
            _posted = true;
            Hide();
        }
        else
        {
            ErrorText.Text = _vm.ErrorMessage;
            ErrorText.Visibility = Visibility.Visible;
        }
        deferral.Complete();
    }
}

/// <summary>Holds the active window so unpackaged pickers can attach to its HWND.</summary>
public static class MainWindowAccessor
{
    public static Microsoft.UI.Xaml.Window? Current { get; set; }
}
