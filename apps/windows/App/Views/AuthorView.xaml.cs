using System;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using YoruMimizuku.App.Interop;
using YoruMimizuku.App.ViewModels;

namespace YoruMimizuku.App.Views;

public sealed partial class AuthorView : UserControl
{
    private readonly AuthorViewModel _vm;
    private readonly IAccountClient _account;
    private readonly WorkspaceViewModel _workspace;
    private FeedView? _feed;

    public AuthorView(AuthorViewModel vm, IAccountClient account, WorkspaceViewModel workspace)
    {
        _vm = vm;
        _account = account;
        _workspace = workspace;
        InitializeComponent();
        RenderHeader();
    }

    public async Task LoadAsync()
    {
        _feed = new FeedView(_vm.FeedFor(_account, _workspace.Muted), _workspace);
        FeedHost.Content = _feed;
        await Task.WhenAll(_vm.LoadProfileAsync(_account), _feed.LoadAsync());
        RenderHeader();
    }

    private void RenderHeader()
    {
        DisplayNameText.Text = _vm.HeaderName;
        HandleText.Text = _vm.HeaderHandle;
        if (_vm.HeaderAvatarUrl is { Length: > 0 } avatarUrl)
        {
            Avatar.ProfilePicture = new BitmapImage(new Uri(avatarUrl));
        }
        if (_vm.Bio is { Length: > 0 } bio)
        {
            BioText.Text = bio;
            BioText.Visibility = Visibility.Visible;
        }
        else
        {
            BioText.Visibility = Visibility.Collapsed;
        }
    }
}
