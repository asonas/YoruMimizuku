using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
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

    private async void OnParentClick(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string uri })
        {
            await _vm.ReanchorAsync(uri);
            Render();
        }
    }
}
