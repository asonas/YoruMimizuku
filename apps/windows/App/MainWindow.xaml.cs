using System;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.System;
using YoruMimizuku.App.Interop;
using YoruMimizuku.App.Services;
using YoruMimizuku.App.ViewModels;
using YoruMimizuku.App.Views;

namespace YoruMimizuku.App;

public sealed partial class MainWindow : Window
{
    private readonly WorkspaceViewModel _workspace = new();

    public MainWindow()
    {
        InitializeComponent();
        Title = "YoruMimizuku";
        Views.MainWindowAccessor.Current = this;
        _workspace.Changed += OnWorkspaceChanged;
        WireShortcuts();
        _ = InitializeAsync();
    }

    private async Task InitializeAsync()
    {
        try
        {
            await BridgeClient.Shared.InitializeAsync(App.Service, App.ClientId, App.RedirectUri, App.Scope);
            ShowLogin();
        }
        catch (Exception ex)
        {
            AppLog.Write("Bridge init failed", ex);
            ShowFatal($"ブリッジの初期化に失敗しました。\n{ex.Message}\n\nログ: {AppLog.Path}");
        }
    }

    private void ShowFatal(string message)
    {
        LoginHost.Content = new TextBlock
        {
            Text = message,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(24),
            VerticalAlignment = VerticalAlignment.Center
        };
        LoginHost.Visibility = Visibility.Visible;
        ShellRoot.Visibility = Visibility.Collapsed;
    }

    private async void OnWorkspaceChanged()
    {
        BuildTabs();
        await ShowSelectedAsync();
    }

    private void ShowLogin()
    {
        var login = new LoginView();
        login.Authenticated += OnAuthenticated;
        LoginHost.Content = login;
        LoginHost.Visibility = Visibility.Visible;
        ShellRoot.Visibility = Visibility.Collapsed;
    }

    private async void OnAuthenticated(string did)
    {
        LoginHost.Content = null;
        LoginHost.Visibility = Visibility.Collapsed;
        ShellRoot.Visibility = Visibility.Visible;
        BuildTabs();
        await ShowSelectedAsync();
    }

    private void BuildTabs()
    {
        Nav.MenuItems.Clear();
        foreach (var tab in _workspace.Tabs)
        {
            Nav.MenuItems.Add(new NavigationViewItem { Content = tab.Title, Tag = tab });
        }
        Nav.SelectedItem = Nav.MenuItems.FirstOrDefault();
    }

    private async void OnNavSelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.IsSettingsSelected)
        {
            ContentHost.Content = new SettingsView();
            return;
        }
        if (args.SelectedItem is NavigationViewItem { Tag: WorkspaceTab tab })
        {
            _workspace.Selected = tab;
            await ShowSelectedAsync();
        }
    }

    private async System.Threading.Tasks.Task ShowSelectedAsync()
    {
        var tab = _workspace.Selected;
        switch (tab.Kind)
        {
            case WorkspaceTabKind.Home:
                var feed = new FeedView(TimelineViewModel.Home(), _workspace);
                ContentHost.Content = feed;
                await feed.LoadAsync();
                break;
            case WorkspaceTabKind.Notifications:
                var notifications = new NotificationsView();
                ContentHost.Content = notifications;
                await notifications.LoadAsync();
                break;
            case WorkspaceTabKind.Filter when tab.Filter is { } filter:
                var search = new FeedView(
                    new TimelineViewModel(cursor => BridgeClient.Shared.SearchLoadAsync(filter.ToBridgeJson(), cursor)),
                    _workspace);
                ContentHost.Content = search;
                await search.LoadAsync();
                break;
            case WorkspaceTabKind.Conversation when tab.ConversationAnchor is { } anchor:
                var conversation = new ConversationView(new ThreadViewModel(anchor), _workspace);
                ContentHost.Content = conversation;
                await conversation.LoadAsync();
                break;
        }
    }

    private void WireShortcuts()
    {
        // Ctrl+Shift+J / Ctrl+Shift+K cycle the sidebar tabs.
        AddAccelerator(VirtualKey.J, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, () =>
        {
            _workspace.SelectNextTab();
            SyncNavSelection();
        });
        AddAccelerator(VirtualKey.K, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, () =>
        {
            _workspace.SelectPreviousTab();
            SyncNavSelection();
        });
    }

    private void SyncNavSelection()
    {
        var item = Nav.MenuItems
            .OfType<NavigationViewItem>()
            .FirstOrDefault(i => ReferenceEquals(i.Tag, _workspace.Selected));
        if (item is not null) Nav.SelectedItem = item;
    }

    private void AddAccelerator(VirtualKey key, VirtualKeyModifiers modifiers, Action action)
    {
        var accelerator = new KeyboardAccelerator { Key = key, Modifiers = modifiers };
        accelerator.Invoked += (_, e) => { e.Handled = true; action(); };
        if (RootGrid is { } grid) grid.KeyboardAccelerators.Add(accelerator);
    }
}
