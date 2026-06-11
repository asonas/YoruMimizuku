using System;
using System.IO;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Storage;
using Windows.Storage.Pickers;
using YoruMimizuku.App.ViewModels;

namespace YoruMimizuku.App.Views;

public sealed partial class ComposerDialog : ContentDialog
{
    private readonly ComposerViewModel _vm;
    private bool _posted;

    public ComposerDialog(string? replyParentUri = null, (string Uri, string Cid)? quote = null, string? quotePreview = null)
    {
        _vm = new ComposerViewModel(replyParentUri, quote);
        InitializeComponent();
        if (replyParentUri is not null) Title = "返信";
        else if (quote is not null) Title = "引用投稿";
        if (quotePreview is not null)
        {
            QuotePreviewText.Text = quotePreview;
            QuotePreview.Visibility = Visibility.Visible;
        }
        PrimaryButtonClick += OnPrimaryClick;
        UpdateCounter();
    }

    /// <summary>Show the composer; returns true if a post was created.</summary>
    public async Task<bool> ShowComposeAsync()
    {
        await ShowAsync();
        return _posted;
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
        await _vm.SubmitAsync();
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
