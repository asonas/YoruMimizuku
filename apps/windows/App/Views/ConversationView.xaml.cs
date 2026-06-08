using System;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.ApplicationModel.DataTransfer;
using Windows.System;
using YoruMimizuku.App.Interop;
using YoruMimizuku.App.ViewModels;

namespace YoruMimizuku.App.Views;

public sealed partial class ConversationView : UserControl
{
    private readonly ThreadViewModel _vm;
    private readonly WorkspaceViewModel _workspace;

    public ConversationView(ThreadViewModel vm, WorkspaceViewModel workspace)
    {
        _vm = vm;
        _workspace = workspace;
        InitializeComponent();
        KeyDown += OnConversationKeyDown;
    }

    public async Task LoadAsync()
    {
        Spinner.IsActive = true;
        await _vm.LoadAsync();
        Spinner.IsActive = false;
        Render();
    }

    private void Render()
    {
        var post = _vm.Focused;
        if (post is null) return;
        FocusedAuthor.Text = post.AuthorDisplayName;
        FocusedHandle.Text = post.AuthorHandle;
        FocusedBody.Text = post.Body;
        FocusedAvatar.ProfilePicture = post.AvatarUrl is { Length: > 0 } url ? new BitmapImage(new Uri(url)) : null;
        LikeGlyph.Glyph = post.LikeGlyph;
        LikeGlyph.Foreground = post.LikeBrush;
        LikeCount.Text = post.LikeCount.ToString();

        if (post.ReplyParent is { } parent)
        {
            ParentAuthor.Text = parent.AuthorDisplayName;
            ParentBody.Text = parent.Body;
            ParentButton.Tag = parent.Id;
            ParentButton.Visibility = Visibility.Visible;
        }
        else
        {
            ParentButton.Visibility = Visibility.Collapsed;
        }
    }

    private async void OnFocusedLikeClick(object sender, RoutedEventArgs e)
    {
        if (_vm.Focused is null) return;
        await _vm.Focused.ToggleLikeAsync();
        Render();
    }

    private async void OnFocusedCopyLinkClick(object sender, RoutedEventArgs e)
    {
        if (_vm.Focused is { } post) await CopyPermalinkAsync(post);
    }

    private void OnFocusedAvatarTapped(object sender, TappedRoutedEventArgs e)
    {
        if (_vm.Focused is { } post)
        {
            e.Handled = true;
            _workspace.OpenAuthor(post);
        }
    }

    private async void OnParentClick(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string uri })
        {
            await _vm.ReanchorAsync(uri);
            Render();
        }
    }

    private async void OnConversationKeyDown(object sender, KeyRoutedEventArgs e)
    {
        switch (e.Key)
        {
            case VirtualKey.F:
                await ToggleFocusedLikeAsync();
                e.Handled = true;
                break;
            case VirtualKey.O:
                await OpenFocusedPermalinkAsync();
                e.Handled = true;
                break;
        }
    }

    private async Task ToggleFocusedLikeAsync()
    {
        if (_vm.Focused is null) return;
        await _vm.Focused.ToggleLikeAsync();
        Render();
    }

    private async Task OpenFocusedPermalinkAsync()
    {
        if (_vm.Focused is { } post) await OpenPermalinkAsync(post);
    }

    private async Task CopyPermalinkAsync(PostItem post)
    {
        var permalink = await BridgeClient.Shared.PostPermalinkAsync(post.Id, post.AuthorHandle);
        if (permalink.Url is not { Length: > 0 } url) return;
        var data = new DataPackage();
        data.SetText(url);
        Clipboard.SetContent(data);
    }

    private async Task OpenPermalinkAsync(PostItem post)
    {
        var permalink = await BridgeClient.Shared.PostPermalinkAsync(post.Id, post.AuthorHandle);
        if (permalink.Url is { Length: > 0 } url && System.Uri.TryCreate(url, System.UriKind.Absolute, out var uri))
        {
            await Launcher.LaunchUriAsync(uri);
        }
    }

}
