using System;
using System.Threading.Tasks;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml;
using Windows.System;
using YoruMimizuku.App.ViewModels;

namespace YoruMimizuku.App.Views;

public sealed partial class FeedView : UserControl
{
    public TimelineViewModel Vm { get; }
    private readonly WorkspaceViewModel _workspace;
    private readonly DispatcherTimer _refreshTimer = new() { Interval = TimeSpan.FromSeconds(30) };
    private ScrollViewer? _scrollViewer;

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

    private async void OnViewChanged(object? sender, ScrollViewerViewChangedEventArgs e)
    {
        if (_scrollViewer is null) return;
        // Near the bottom: append the next (older) page.
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

    private async void OnRepostClick(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: PostItem item }) await item.ToggleRepostAsync();
    }

    private void OnPostClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is PostItem item)
        {
            _workspace.OpenConversation(item.Id, item.AuthorDisplayName, item.Body);
        }
    }

    private void WireShortcuts()
    {
        AddAccelerator(VirtualKey.J, VirtualKeyModifiers.None, MoveFocusDown);
        AddAccelerator(VirtualKey.K, VirtualKeyModifiers.None, MoveFocusUp);
        AddAccelerator(VirtualKey.N, VirtualKeyModifiers.None, OpenComposer);
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

    private void AddAccelerator(VirtualKey key, VirtualKeyModifiers modifiers, Action action)
    {
        var accelerator = new KeyboardAccelerator { Key = key, Modifiers = modifiers };
        accelerator.Invoked += (_, e) => { e.Handled = true; action(); };
        KeyboardAccelerators.Add(accelerator);
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
