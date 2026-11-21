using System;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
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
        RenderReplies();
    }

    private void Render()
    {
        var post = _vm.Focused;
        if (post is null) return;
        FocusedAuthor.Text = post.AuthorDisplayName;
        FocusedHandle.Text = "@" + post.AuthorHandle;
        FocusedTime.Text = post.RelativeTime;
        PostBody.Fill(FocusedBody, post.Segments, _workspace);
        FocusedAvatar.ProfilePicture = post.AvatarUrl is { Length: > 0 } url ? new BitmapImage(new Uri(url)) : null;
        LikeGlyph.Glyph = post.LikeGlyph;
        LikeGlyph.Foreground = post.LikeBrush;
        LikeCount.Text = post.LikeCount.ToString();

        if (post.ReplyParent is { } parent)
        {
            ParentAuthor.Text = parent.AuthorDisplayName;
            PostBody.Fill(ParentBody, parent.Segments, _workspace);
            ParentCard.Tag = parent;
            ParentCard.Visibility = Visibility.Visible;
        }
        else
        {
            ParentCard.Visibility = Visibility.Collapsed;
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

    /// Replies to the anchor as this page's account, then reloads the thread so the
    /// reply shows up under it.
    private async void OnFocusedReplyClick(object sender, RoutedEventArgs e)
    {
        if (_vm.Focused is not { } post) return;
        var dialog = new ComposerDialog(_vm.Account, replyParentUri: post.Id) { XamlRoot = XamlRoot };
        if (!await dialog.ShowComposeAsync()) return;
        await LoadAsync();
    }

    /// The parent and every reply re-anchor the pane: each opens its own conversation
    /// in place of this one, as on macOS.
    private void OnParentTapped(object sender, TappedRoutedEventArgs e)
    {
        if (sender is Border { Tag: ReplyParentDto parent })
        {
            _workspace.OpenConversation(parent.Id, parent.AuthorDisplayName);
        }
    }

    // -- Descendant reply tree --

    /// Render the conversation's child reply tree below the focused post,
    /// mirroring the macOS ConversationView: each reply is indented by depth,
    /// carries a left connector line, and opens its own conversation when tapped.
    private void RenderReplies()
    {
        RepliesHost.Children.Clear();
        foreach (var node in _vm.ReplyTree) AddReplyNode(node);
    }

    private void AddReplyNode(ThreadNodeDto node)
    {
        RepliesHost.Children.Add(BuildReplyRow(node));
        foreach (var child in node.Replies) AddReplyNode(child);
    }

    private FrameworkElement BuildReplyRow(ThreadNodeDto node)
    {
        var content = new StackPanel { Spacing = 2 };

        // Avatar, name and handle, then the time in its own column so a long name
        // is cut off instead of the time.
        var header = new Grid { ColumnSpacing = 6 };
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.Children.Add(new PersonPicture
        {
            Width = 24,
            Height = 24,
            ProfilePicture = node.Post.AvatarUrl is { Length: > 0 } a ? new BitmapImage(new Uri(a)) : null
        });
        var names = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
        names.Children.Add(new TextBlock
        {
            Text = node.Post.AuthorDisplayName,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            VerticalAlignment = VerticalAlignment.Center
        });
        names.Children.Add(new TextBlock
        {
            Text = "@" + node.Post.AuthorHandle,
            FontSize = 12,
            Opacity = 0.6,
            VerticalAlignment = VerticalAlignment.Center
        });
        Grid.SetColumn(names, 1);
        header.Children.Add(names);
        var time = new TextBlock
        {
            Text = Services.RelativeTime.Format(node.Post.CreatedAt),
            FontSize = 12,
            FontFamily = new FontFamily("Consolas"),
            Foreground = (Brush)Application.Current.Resources["AppTertiaryTextBrush"],
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(time, 2);
        header.Children.Add(time);
        content.Children.Add(header);
        // Selection off: a selectable RichTextBlock takes the press, so a tap on the
        // text would not reach the row.
        var body = new RichTextBlock { TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = false };
        PostBody.Fill(body, node.Post.Segments, _workspace);
        content.Children.Add(body);

        // A Border, not a Button: a Button captures the pointer, so the links in the
        // body would never get their click.
        var row = new Border
        {
            Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
            BorderBrush = (Brush)Application.Current.Resources["AppHairlineBrush"],
            BorderThickness = new Thickness(1, 0, 0, 0),
            Margin = new Thickness(node.Depth * 16, 0, 0, 0),
            Padding = new Thickness(10, 4, 4, 4),
            Child = content
        };
        HighlightOnHover(row);
        row.Tapped += (_, _) => _workspace.OpenConversation(node.Post.Id, node.Post.AuthorDisplayName);
        return row;
    }

    private static void HighlightOnHover(Border row)
    {
        var idle = row.Background;
        row.PointerEntered += (_, _) => row.Background = (Brush)Application.Current.Resources["AppRowHoverBrush"];
        row.PointerExited += (_, _) => row.Background = idle;
    }

    private async void OnConversationKeyDown(object sender, KeyRoutedEventArgs e)
    {
        switch (e.Key)
        {
            case VirtualKey.L:
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
        var permalink = await App.Client.PostPermalinkAsync(post.Id, post.AuthorHandle);
        if (permalink.Url is not { Length: > 0 } url) return;
        var data = new DataPackage();
        data.SetText(url);
        Clipboard.SetContent(data);
        Services.ToastCenter.Shared.Show(XamlRoot, "リンクをコピーしました");
    }

    private async Task OpenPermalinkAsync(PostItem post)
    {
        var permalink = await App.Client.PostPermalinkAsync(post.Id, post.AuthorHandle);
        if (permalink.Url is { Length: > 0 } url && System.Uri.TryCreate(url, System.UriKind.Absolute, out var uri))
        {
            await Launcher.LaunchUriAsync(uri);
        }
    }

}
