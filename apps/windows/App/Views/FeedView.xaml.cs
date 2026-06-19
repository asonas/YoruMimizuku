using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Documents;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.ApplicationModel.DataTransfer;
using Windows.System;
using YoruMimizuku.App.Interop;
using YoruMimizuku.App.ViewModels;

namespace YoruMimizuku.App.Views;

public sealed partial class FeedView : UserControl
{
    public TimelineViewModel Vm { get; }
    private readonly WorkspaceViewModel _workspace;
    private readonly DispatcherTimer _refreshTimer = new() { Interval = TimeSpan.FromSeconds(30) };
    private ScrollViewer? _scrollViewer;

    private List<string> _lightboxUrls = new();
    private int _lightboxIndex;

    public FeedView(TimelineViewModel vm, WorkspaceViewModel workspace)
    {
        Vm = vm;
        _workspace = workspace;
        InitializeComponent();
        _refreshTimer.Tick += async (_, _) => await Vm.RefreshAsync();
        Loaded += OnLoaded;
        Unloaded += (_, _) => _refreshTimer.Stop();
        KeyDown += OnFeedKeyDown;
    }

    public async Task LoadAsync()
    {
        await Vm.LoadAsync();
        _refreshTimer.Start();
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        _scrollViewer = FindScrollViewer(PostsList);
        if (_scrollViewer is not null) _scrollViewer.ViewChanged += OnViewChanged;
    }

    // -- Rich text + images per realized row --

    private void OnContainerContentChanging(ListViewBase sender, ContainerContentChangingEventArgs args)
    {
        if (args.InRecycleQueue || args.Item is not PostItem post) return;
        if (args.ItemContainer?.ContentTemplateRoot is not FrameworkElement root) return;
        if (root.FindName("BodyRich") is RichTextBlock rich) PopulateRich(rich, post);
        if (root.FindName("ImagesHost") is Grid host) PopulateImages(host, post);
        if (root.FindName("VideoHost") is Border videoHost) PopulateVideo(videoHost, post);
        if (root.FindName("MediaCurtain") is Border curtain) PopulateCurtain(curtain, post);
        if (root.FindName("LinkCardHost") is Border cardHost) PopulateLinkCard(cardHost, post);
        if (root.FindName("QuoteHost") is Border quoteHost) PopulateQuote(quoteHost, post);
        if (root.FindName("DeleteButton") is Button deleteButton)
        {
            deleteButton.Visibility =
                post.AuthorDid is { } did && did == _workspace.AccountDid
                    ? Visibility.Visible
                    : Visibility.Collapsed;
        }
    }

    private void PopulateRich(RichTextBlock rich, PostItem post)
    {
        rich.Blocks.Clear();
        var paragraph = new Paragraph();
        foreach (var seg in post.Segments)
        {
            switch (seg.Kind)
            {
                case "link" when TryUri(seg.Url, out var uri):
                    var link = new Hyperlink { NavigateUri = uri };
                    link.Inlines.Add(new Run { Text = seg.Text });
                    paragraph.Inlines.Add(link);
                    break;
                case "tag":
                    var tagLink = new Hyperlink();
                    tagLink.Inlines.Add(new Run { Text = seg.Text });
                    var tag = seg.Text.TrimStart('#');
                    tagLink.Click += (_, _) => _workspace.OpenHashtagFilter(tag);
                    paragraph.Inlines.Add(tagLink);
                    break;
                case "mention":
                    paragraph.Inlines.Add(new Run
                    {
                        Text = seg.Text,
                        Foreground = (Brush)Application.Current.Resources["AppAccentBrush"]
                    });
                    break;
                default:
                    paragraph.Inlines.Add(new Run { Text = seg.Text });
                    break;
            }
        }
        rich.Blocks.Add(paragraph);
    }

    private void PopulateImages(Grid host, PostItem post)
    {
        host.Children.Clear();
        host.ColumnDefinitions.Clear();
        host.RowDefinitions.Clear();
        var images = post.Images;
        if (images.Count == 0) return;

        var single = images.Count == 1;
        var columns = single ? 1 : 2;
        for (var c = 0; c < columns; c++) host.ColumnDefinitions.Add(new ColumnDefinition());
        var rows = (int)Math.Ceiling(images.Count / (double)columns);
        for (var r = 0; r < rows; r++) host.RowDefinitions.Add(new RowDefinition());

        var fullsizeUrls = images.Select(i => i.FullsizeUrl ?? i.ThumbUrl ?? "").Where(u => u.Length > 0).ToList();

        for (var i = 0; i < images.Count; i++)
        {
            var image = images[i];
            var border = new Border
            {
                CornerRadius = new CornerRadius(10),
                BorderBrush = (Brush)Application.Current.Resources["AppHairlineBrush"],
                BorderThickness = new Thickness(1),
                Height = single ? 240 : 140,
                Background = (Brush)Application.Current.Resources["AppRowHoverBrush"]
            };
            if (TryUri(image.ThumbUrl, out var thumbUri))
            {
                border.Child = new Image { Source = new BitmapImage(thumbUri), Stretch = Stretch.UniformToFill };
            }
            var index = i;
            border.Tapped += (_, e) => { e.Handled = true; OpenLightbox(fullsizeUrls, index); };
            Grid.SetColumn(border, i % columns);
            Grid.SetRow(border, i / columns);
            host.Children.Add(border);
        }
    }

    // -- External link preview card --

    /// Mirrors macOS PostRowView: a post with its own external embed renders the
    /// card directly; otherwise a bare link in a text-only post resolves its OGP
    /// preview lazily (image posts skip the fallback to keep rows tight). The host
    /// is tagged with the post id so a recycled container drops a stale fetch.
    private void PopulateLinkCard(Border host, PostItem post)
    {
        host.Child = null;
        host.Visibility = Visibility.Collapsed;
        host.Tag = post.Id;
        if (post.LinkCard is { } card)
        {
            host.Child = BuildLinkCard(card);
            host.Visibility = Visibility.Visible;
        }
        else if (post.Images.Count == 0 && post.FirstLinkUrl is { Length: > 0 } link)
        {
            _ = LoadOgpAsync(host, post.Id, link);
        }
    }

    private async Task LoadOgpAsync(Border host, string postId, string url)
    {
        LinkCardDto? card = null;
        try { card = await BridgeClient.Shared.OgpLoadAsync(url); } catch { /* no card */ }
        if (card is null) return;
        if (host.Tag as string != postId) return; // container recycled to another post
        host.Child = BuildLinkCard(card);
        host.Visibility = Visibility.Visible;
    }

    /// Builds the X-style large link card: a 1.91:1 hero image (when present) over
    /// a bordered text block with bold title, grey description, and a host line.
    private FrameworkElement BuildLinkCard(LinkCardDto card)
    {
        var stack = new StackPanel();

        if (TryUri(card.ThumbUrl, out var thumbUri))
        {
            stack.Children.Add(new Image
            {
                Source = new BitmapImage(thumbUri),
                Stretch = Stretch.UniformToFill,
                Height = 230,
                MaxWidth = 440
            });
            stack.Children.Add(new Border
            {
                Height = 1,
                Background = (Brush)Application.Current.Resources["AppHairlineBrush"]
            });
        }

        var text = new StackPanel { Spacing = 3, Padding = new Thickness(10, 8, 10, 8) };
        text.Children.Add(new TextBlock
        {
            Text = card.Title,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            Foreground = (Brush)Application.Current.Resources["AppTextBrush"],
            TextWrapping = TextWrapping.Wrap,
            MaxLines = 2,
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        if (!string.IsNullOrEmpty(card.Description))
        {
            text.Children.Add(new TextBlock
            {
                Text = card.Description,
                FontSize = 12,
                Foreground = (Brush)Application.Current.Resources["AppTertiaryTextBrush"],
                TextWrapping = TextWrapping.Wrap,
                MaxLines = 2,
                TextTrimming = TextTrimming.CharacterEllipsis
            });
        }
        if (!string.IsNullOrEmpty(card.Host))
        {
            var hostLine = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
            hostLine.Children.Add(new FontIcon
            {
                Glyph = "",
                FontSize = 11,
                Foreground = (Brush)Application.Current.Resources["AppTertiaryTextBrush"]
            });
            hostLine.Children.Add(new TextBlock
            {
                Text = card.Host,
                FontSize = 11,
                Foreground = (Brush)Application.Current.Resources["AppTertiaryTextBrush"],
                TextTrimming = TextTrimming.CharacterEllipsis
            });
            text.Children.Add(hostLine);
        }
        stack.Children.Add(text);

        var border = new Border
        {
            CornerRadius = new CornerRadius(12),
            BorderBrush = (Brush)Application.Current.Resources["AppHairlineBrush"],
            BorderThickness = new Thickness(1),
            Background = (Brush)Application.Current.Resources["AppRowHoverBrush"],
            MaxWidth = 440,
            Child = stack
        };
        if (TryUri(card.Url, out var cardUri))
        {
            border.Tapped += async (_, e) => { e.Handled = true; await Launcher.LaunchUriAsync(cardUri); };
            ToolTipService.SetToolTip(border, card.Url);
        }
        return border;
    }

    // -- Video poster (no inline playback) --

    private void PopulateVideo(Border host, PostItem post)
    {
        host.Child = null;
        host.Visibility = Visibility.Collapsed;
        if (!post.HasVideo) return;
        host.Child = BuildVideoPoster(post);
        host.Visibility = Visibility.Visible;
    }

    /// Mirrors macOS VideoPosterView: the poster image with a centered play badge;
    /// clicking opens the post in the browser (inline playback is post-1.0).
    private FrameworkElement BuildVideoPoster(PostItem post)
    {
        var grid = new Grid { MaxWidth = 440 };
        if (TryUri(post.Video!.ThumbUrl, out var thumb))
        {
            grid.Children.Add(new Image
            {
                Source = new BitmapImage(thumb),
                Stretch = Stretch.UniformToFill,
                MaxHeight = 280
            });
        }
        grid.Children.Add(new Border
        {
            Width = 52,
            Height = 52,
            CornerRadius = new CornerRadius(26),
            Background = new SolidColorBrush(Microsoft.UI.Colors.Black) { Opacity = 0.55 },
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Child = new FontIcon
            {
                Glyph = "",
                FontSize = 22,
                Foreground = new SolidColorBrush(Microsoft.UI.Colors.White)
            }
        });

        var border = new Border
        {
            CornerRadius = new CornerRadius(10),
            BorderBrush = (Brush)Application.Current.Resources["AppHairlineBrush"],
            BorderThickness = new Thickness(1),
            MaxWidth = 440,
            Child = grid
        };
        border.Tapped += async (_, e) => { e.Handled = true; await OpenPermalinkAsync(post); };
        ToolTipService.SetToolTip(border, "ブラウザで開く");
        return border;
    }

    // -- Quote post (record embed) card --

    private void PopulateQuote(Border host, PostItem post)
    {
        host.Child = null;
        host.Visibility = Visibility.Collapsed;
        if (post.Quote is not { } quote) return;
        host.Child = BuildQuoteCard(quote);
        host.Visibility = Visibility.Visible;
    }

    /// Mirrors macOS QuoteCardView: a bordered card with a compact author line,
    /// the quoted body, and the quoted post's media; tapping opens its conversation.
    private FrameworkElement BuildQuoteCard(QuotedPostDto quote)
    {
        var content = new StackPanel { Spacing = 4, Padding = new Thickness(10, 8, 10, 8) };

        var author = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 5 };
        author.Children.Add(new PersonPicture
        {
            Width = 18,
            Height = 18,
            ProfilePicture = quote.AvatarUrl is { Length: > 0 } a ? new BitmapImage(new Uri(a)) : null
        });
        author.Children.Add(new TextBlock
        {
            Text = quote.AuthorDisplayName,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            FontSize = 12,
            VerticalAlignment = VerticalAlignment.Center
        });
        author.Children.Add(new TextBlock
        {
            Text = "@" + quote.AuthorHandle,
            FontSize = 11,
            Foreground = (Brush)Application.Current.Resources["AppTertiaryTextBrush"],
            VerticalAlignment = VerticalAlignment.Center,
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        content.Children.Add(author);

        if (!string.IsNullOrEmpty(quote.Body))
        {
            content.Children.Add(new TextBlock
            {
                Text = quote.Body,
                Foreground = (Brush)Application.Current.Resources["AppTextBrush"],
                TextWrapping = TextWrapping.Wrap,
                MaxLines = 6,
                TextTrimming = TextTrimming.CharacterEllipsis
            });
        }

        if (quote.Video?.ThumbUrl is { Length: > 0 } && TryUri(quote.Video.ThumbUrl, out var qVideoThumb))
        {
            content.Children.Add(QuoteThumb(qVideoThumb, withPlayBadge: true));
        }
        else if (quote.Images.Count > 0)
        {
            var thumbs = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
            foreach (var image in quote.Images.Take(2))
            {
                if (TryUri(image.ThumbUrl, out var t)) thumbs.Children.Add(QuoteThumb(t, withPlayBadge: false));
            }
            if (thumbs.Children.Count > 0) content.Children.Add(thumbs);
        }

        var border = new Border
        {
            CornerRadius = new CornerRadius(12),
            BorderBrush = (Brush)Application.Current.Resources["AppHairlineBrush"],
            BorderThickness = new Thickness(1),
            Background = (Brush)Application.Current.Resources["AppRowHoverBrush"],
            MaxWidth = 440,
            Child = content,
            Tag = quote
        };
        border.Tapped += (_, e) =>
        {
            e.Handled = true;
            _workspace.OpenConversation(quote.Id, quote.AuthorDisplayName, quote.Body);
        };
        ToolTipService.SetToolTip(border, "@" + quote.AuthorHandle + " の会話を開く");
        return border;
    }

    private FrameworkElement QuoteThumb(Uri url, bool withPlayBadge)
    {
        var grid = new Grid { Width = 72, Height = 72 };
        grid.Children.Add(new Image { Source = new BitmapImage(url), Stretch = Stretch.UniformToFill });
        if (withPlayBadge)
        {
            grid.Children.Add(new FontIcon
            {
                Glyph = "",
                FontSize = 16,
                Foreground = new SolidColorBrush(Microsoft.UI.Colors.White),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            });
        }
        return new Border
        {
            CornerRadius = new CornerRadius(6),
            BorderBrush = (Brush)Application.Current.Resources["AppHairlineBrush"],
            BorderThickness = new Thickness(1),
            Child = grid
        };
    }

    // -- Sensitive media curtain (tap to reveal) --

    /// Covers the post's media with a tap-to-reveal curtain when it carries an
    /// adult/graphic content label, the Windows analogue of the macOS blur. (WinUI
    /// has no cheap subtree blur, so the media is covered rather than blurred —
    /// equivalent gating.)
    private void PopulateCurtain(Border curtain, PostItem post)
    {
        var gated = post.IsSensitive && (post.HasImages || post.HasVideo);
        if (!gated)
        {
            curtain.Visibility = Visibility.Collapsed;
            curtain.Child = null;
            return;
        }

        var stack = new StackPanel
        {
            Spacing = 4,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center
        };
        stack.Children.Add(new TextBlock
        {
            Text = post.MediaWarning == "graphic" ? "閲覧注意（過激なメディア）" : "閲覧注意（センシティブ）",
            FontSize = 12,
            FontWeight = Microsoft.UI.Text.FontWeights.Medium,
            Foreground = new SolidColorBrush(Microsoft.UI.Colors.White),
            HorizontalAlignment = HorizontalAlignment.Center
        });
        stack.Children.Add(new TextBlock
        {
            Text = "タップで表示",
            FontSize = 11,
            Foreground = new SolidColorBrush(Microsoft.UI.Colors.White) { Opacity = 0.8 },
            HorizontalAlignment = HorizontalAlignment.Center
        });
        curtain.Child = stack;
        curtain.Visibility = Visibility.Visible;
    }

    private void OnMediaCurtainTapped(object sender, TappedRoutedEventArgs e)
    {
        if (sender is Border curtain)
        {
            e.Handled = true;
            curtain.Visibility = Visibility.Collapsed;
        }
    }

    // -- Lightbox --

    private void OpenLightbox(List<string> urls, int index)
    {
        if (urls.Count == 0) return;
        _lightboxUrls = urls;
        _lightboxIndex = Math.Clamp(index, 0, urls.Count - 1);
        ShowLightboxImage();
        Lightbox.Visibility = Visibility.Visible;
        Lightbox.Focus(FocusState.Programmatic);
    }

    private void ShowLightboxImage()
    {
        if (TryUri(_lightboxUrls[_lightboxIndex], out var uri))
        {
            LightboxImage.Source = new BitmapImage(uri);
        }
        LightboxPrev.Visibility = _lightboxIndex > 0 ? Visibility.Visible : Visibility.Collapsed;
        LightboxNext.Visibility = _lightboxIndex < _lightboxUrls.Count - 1 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void OnLightboxPrev(object sender, RoutedEventArgs e)
    {
        if (_lightboxIndex > 0) { _lightboxIndex--; ShowLightboxImage(); }
    }

    private void OnLightboxNext(object sender, RoutedEventArgs e)
    {
        if (_lightboxIndex < _lightboxUrls.Count - 1) { _lightboxIndex++; ShowLightboxImage(); }
    }

    private void OnLightboxClose(object sender, RoutedEventArgs e) => CloseLightbox();
    private void OnLightboxTapped(object sender, TappedRoutedEventArgs e) => CloseLightbox();
    private void CloseLightbox()
    {
        Lightbox.Visibility = Visibility.Collapsed;
        LightboxImage.Source = null;
    }

    // -- Scrolling / refresh / compose --

    private async void OnViewChanged(object? sender, ScrollViewerViewChangedEventArgs e)
    {
        if (_scrollViewer is null) return;
        if (_scrollViewer.VerticalOffset >= _scrollViewer.ScrollableHeight - 600 && Vm.CanLoadMore)
        {
            await Vm.LoadMoreAsync();
        }
    }

    private async void OnRefreshClick(object sender, RoutedEventArgs e) => await Vm.RefreshAsync();
    private async void OnRetryClick(object sender, RoutedEventArgs e) => await Vm.RetryAsync();
    private void OnComposeClick(object sender, RoutedEventArgs e) => OpenComposer();

    private async void OnLikeClick(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: PostItem item }) await item.ToggleLikeAsync();
    }

    private async void OnCopyLinkClick(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: PostItem item }) await CopyPermalinkAsync(item);
    }

    private async void OnDeleteClick(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: PostItem item }) return;
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "投稿を削除",
            Content = "この投稿を削除しますか？",
            PrimaryButtonText = "削除",
            CloseButtonText = "キャンセル",
            DefaultButton = ContentDialogButton.Close
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            await Vm.DeletePostAsync(item.Id);
        }
    }

    private async void OnRepostMenuClick(object sender, RoutedEventArgs e)
    {
        if (sender is MenuFlyoutItem { Tag: PostItem item }) await item.ToggleRepostAsync();
    }

    private async void OnQuoteMenuClick(object sender, RoutedEventArgs e)
    {
        if (sender is MenuFlyoutItem { Tag: PostItem item }) await OpenQuoteComposer(item);
    }

    private async void OnReplyClick(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: PostItem item })
        {
            await OpenReplyComposer(item);
        }
    }

    private void OnAvatarTapped(object sender, TappedRoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: PostItem item })
        {
            e.Handled = true;
            _workspace.OpenAuthor(item);
        }
    }

    private void OnAuthorClick(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: PostItem item })
        {
            _workspace.OpenAuthor(item);
        }
    }

    private void OnReplyMarkerClick(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: PostItem { ReplyParent: { } parent } })
        {
            _workspace.OpenConversation(parent.Id, parent.AuthorDisplayName, parent.Body);
        }
    }

    private void OnPostClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is PostItem item)
        {
            _workspace.OpenConversation(item.Id, item.AuthorDisplayName, item.Body);
        }
    }

    // -- Keyboard --

    private async void OnFeedKeyDown(object sender, KeyRoutedEventArgs e)
    {
        switch (e.Key)
        {
            case VirtualKey.J:
                MoveFocusDown();
                e.Handled = true;
                break;
            case VirtualKey.K:
                MoveFocusUp();
                e.Handled = true;
                break;
            case VirtualKey.N:
                OpenComposer();
                e.Handled = true;
                break;
            case VirtualKey.F:
                await ToggleFocusedLikeAsync();
                e.Handled = true;
                break;
            case VirtualKey.O:
                await OpenFocusedPermalinkAsync();
                e.Handled = true;
                break;
            case VirtualKey.Escape:
                CloseLightbox();
                e.Handled = true;
                break;
            case VirtualKey.Left when Lightbox.Visibility == Visibility.Visible:
                OnLightboxPrev(this, new RoutedEventArgs());
                e.Handled = true;
                break;
            case VirtualKey.Right when Lightbox.Visibility == Visibility.Visible:
                OnLightboxNext(this, new RoutedEventArgs());
                e.Handled = true;
                break;
        }
    }

    private PostItem? FocusedPost => PostsList.SelectedItem as PostItem;

    private void MoveFocusDown()
    {
        if (Vm.Posts.Count == 0) return;
        var i = Math.Min(Vm.Posts.Count - 1, PostsList.SelectedIndex + 1);
        PostsList.SelectedIndex = i;
        PostsList.ScrollIntoView(Vm.Posts[i]);
    }

    private void MoveFocusUp()
    {
        if (Vm.Posts.Count == 0) return;
        var i = Math.Max(0, PostsList.SelectedIndex - 1);
        PostsList.SelectedIndex = i;
        PostsList.ScrollIntoView(Vm.Posts[i]);
    }

    private async void OpenComposer()
    {
        var dialog = new ComposerDialog { XamlRoot = XamlRoot };
        var posted = await dialog.ShowComposeAsync();
        if (posted) await Vm.RefreshAsync();
    }

    private async Task OpenReplyComposer(PostItem item)
    {
        var dialog = new ComposerDialog(replyParentUri: item.Id) { XamlRoot = XamlRoot };
        var posted = await dialog.ShowComposeAsync();
        if (posted) await Vm.RefreshAsync();
    }

    private async Task OpenQuoteComposer(PostItem item)
    {
        var preview = $"{item.AuthorDisplayName}\n{item.Body}";
        var dialog = new ComposerDialog(quote: (item.Id, item.Cid), quotePreview: preview) { XamlRoot = XamlRoot };
        var posted = await dialog.ShowComposeAsync();
        if (posted) await Vm.RefreshAsync();
    }

    private async Task ToggleFocusedLikeAsync()
    {
        if (FocusedPost is { } post) await post.ToggleLikeAsync();
    }

    private async Task OpenFocusedPermalinkAsync()
    {
        if (FocusedPost is { } post) await OpenPermalinkAsync(post);
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
        if (permalink.Url is { Length: > 0 } url && Uri.TryCreate(url, UriKind.Absolute, out var uri))
        {
            await Launcher.LaunchUriAsync(uri);
        }
    }

    private static bool TryUri(string? value, out Uri uri)
    {
        if (!string.IsNullOrEmpty(value) && Uri.TryCreate(value, UriKind.Absolute, out var parsed))
        {
            uri = parsed;
            return true;
        }
        uri = null!;
        return false;
    }

    private static ScrollViewer? FindScrollViewer(DependencyObject root)
    {
        if (root is ScrollViewer sv) return sv;
        var count = VisualTreeHelper.GetChildrenCount(root);
        for (var i = 0; i < count; i++)
        {
            var result = FindScrollViewer(VisualTreeHelper.GetChild(root, i));
            if (result is not null) return result;
        }
        return null;
    }
}
