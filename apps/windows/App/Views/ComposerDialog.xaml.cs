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

    public ComposerDialog(string? replyParentUri = null, (string Uri, string Cid)? quote = null)
    {
        _vm = new ComposerViewModel(replyParentUri, quote);
        InitializeComponent();
        if (replyParentUri is not null) Title = "返信";
        else if (quote is not null) Title = "引用投稿";
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
        var bytes = await File.ReadAllBytesAsync(file.Path);
        var mime = file.FileType.Equals(".png", StringComparison.OrdinalIgnoreCase) ? "image/png" : "image/jpeg";
        _vm.AddImage(bytes, mime);
        AddThumbnail(file);
        UpdateCounter();
    }

    private void AddThumbnail(StorageFile file)
    {
        var image = new Image { Width = 64, Height = 64, Stretch = Microsoft.UI.Xaml.Media.Stretch.UniformToFill };
        image.Source = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri(file.Path));
        ImagesList.Items.Add(image);
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
