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
        WireShortcuts();
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
    private void OnComposeClick(object sender, RoutedEventArgs e) => OpenComposer();

    private async void OnLikeClick(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: PostItem item }) await item.ToggleLikeAsync();
    }

    private async void OnRepostMenuClick(object sender, RoutedEventArgs e)
    {
        if (sender is MenuFlyoutItem { Tag: PostItem item }) await item.ToggleRepostAsync();
    }

    private async void OnQuoteMenuClick(object sender, RoutedEventArgs e)
    {
        if (sender is MenuFlyoutItem { Tag: PostItem item }) await OpenQuoteComposer(item);
    }

    private void OnReplyClick(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: PostItem item })
        {
            _workspace.OpenConversation(item.Id, item.AuthorDisplayName, item.Body);
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

    private void WireShortcuts()
    {
        AddAccelerator(VirtualKey.J, VirtualKeyModifiers.None, MoveFocusDown);
        AddAccelerator(VirtualKey.K, VirtualKeyModifiers.None, MoveFocusUp);
        AddAccelerator(VirtualKey.N, VirtualKeyModifiers.None, OpenComposer);
        AddAccelerator(VirtualKey.Escape, VirtualKeyModifiers.None, CloseLightbox);
        AddAccelerator(VirtualKey.Left, VirtualKeyModifiers.None, () => { if (Lightbox.Visibility == Visibility.Visible) OnLightboxPrev(this, new RoutedEventArgs()); });
        AddAccelerator(VirtualKey.Right, VirtualKeyModifiers.None, () => { if (Lightbox.Visibility == Visibility.Visible) OnLightboxNext(this, new RoutedEventArgs()); });
    }

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

    private async Task OpenQuoteComposer(PostItem item)
    {
        var preview = $"{item.AuthorDisplayName}\n{item.Body}";
        var dialog = new ComposerDialog(quote: (item.Id, item.Cid), quotePreview: preview) { XamlRoot = XamlRoot };
        var posted = await dialog.ShowComposeAsync();
        if (posted) await Vm.RefreshAsync();
    }

    private void AddAccelerator(VirtualKey key, VirtualKeyModifiers modifiers, Action action)
    {
        var accelerator = new KeyboardAccelerator { Key = key, Modifiers = modifiers };
        accelerator.Invoked += (_, e) => { e.Handled = true; action(); };
        KeyboardAccelerators.Add(accelerator);
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
