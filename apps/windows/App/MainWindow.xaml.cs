using System;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI;
using Microsoft.UI.Xaml.Media;
using Windows.System;
using YoruMimizuku.App.Interop;
using YoruMimizuku.App.Services;
using YoruMimizuku.App.ViewModels;
using YoruMimizuku.App.Views;

namespace YoruMimizuku.App;

public sealed partial class MainWindow : Window
{
    private const string AddFilterTag = "__add_filter__";

    private readonly WorkspaceViewModel _workspace = new();
    private readonly NotificationsViewModel _notifications = new();
    private readonly DispatcherTimer _notificationsTimer = new() { Interval = TimeSpan.FromSeconds(30) };
    // Guards the NavigationView selection while we rebuild it in code, so the
    // programmatic selection does not re-enter OnNavSelectionChanged.
    private bool _syncing;
    private SavedFilterStore? _filterStore;

    public MainWindow()
    {
        InitializeComponent();
        Title = "YoruMimizuku";
        Views.MainWindowAccessor.Current = this;
        AppIcon.TrySetWindowIcon(this);
        _workspace.Changed += OnWorkspaceChanged;
        _workspace.FiltersChanged += SaveFilters;
        _notifications.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(NotificationsViewModel.UnreadCount)) BuildTabs();
        };
        _notificationsTimer.Tick += async (_, _) => await _notifications.RefreshAsync();
        WireShortcuts();
        _ = InitializeAsync();
    }

    private async Task InitializeAsync()
    {
        try
        {
            ThemeService.Shared.ApplySaved();
            await BridgeClient.Shared.InitializeAsync(App.Service, App.ClientId, App.RedirectUri, App.Scope);

            // Restore the persisted session (DPAPI): skip the login screen if an
            // account is already stored.
            var account = await BridgeClient.Shared.CurrentAccountAsync();
            if (account is not null)
            {
                EnterShell(account);
            }
            else
            {
                ShowLogin();
            }
        }
        catch (Exception ex)
        {
            AppLog.Write("Bridge init failed", ex);
            ShowFatal($"ブリッジの初期化に失敗しました。\n{ex.Message}\n\nログ: {AppLog.Path}");
        }
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
        var account = await BridgeClient.Shared.CurrentAccountAsync();
        EnterShell(account);
    }

    private void EnterShell(AccountDto? account)
    {
        _filterStore = account is null ? null : new SavedFilterStore(account.Did);
        _workspace.LoadFilters(_filterStore?.Load() ?? Array.Empty<SavedFilterModel>());
        LoginHost.Visibility = Visibility.Collapsed;
        ShellRoot.Visibility = Visibility.Visible;
        BuildTabs();
        _ = ShowSelectedAsync();
        _ = LoadAccountFooterAsync(account);
        _notificationsTimer.Start();
    }

    private async Task LoadAccountFooterAsync(AccountDto? account)
    {
        if (account is null) return;
        AccountHandle.Text = account.Handle is { Length: > 0 } h ? "@" + h : account.Did;
        AccountFooter.Visibility = Visibility.Visible;
        try
        {
            var avatar = await BridgeClient.Shared.AvatarAsync();
            if (avatar.AvatarUrl is { Length: > 0 } url)
            {
                AccountAvatar.ProfilePicture = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri(url));
            }
        }
        catch (Exception ex) { AppLog.Write("avatar load failed", ex); }
    }

    private void OnWorkspaceChanged()
    {
        BuildTabs();
        _ = ShowSelectedAsync();
    }

    private void BuildTabs()
    {
        _syncing = true;
        Nav.MenuItems.Clear();
        foreach (var tab in _workspace.Tabs)
        {
            Nav.MenuItems.Add(MakeNavItem(tab));
            if (tab.Kind == WorkspaceTabKind.Notifications)
            {
                Nav.MenuItems.Add(MakeAddFilterItem());
            }
        }
        var selected = Nav.MenuItems
            .OfType<NavigationViewItem>()
            .FirstOrDefault(i => ReferenceEquals(i.Tag, _workspace.Selected));
        Nav.SelectedItem = selected ?? Nav.MenuItems.OfType<NavigationViewItem>().FirstOrDefault();
        _syncing = false;
    }

    private NavigationViewItem MakeNavItem(WorkspaceTab tab)
    {
        var item = new NavigationViewItem { Tag = tab, Icon = IconFor(tab.Kind) };
        var closable = tab.Kind is WorkspaceTabKind.Conversation or WorkspaceTabKind.Filter or WorkspaceTabKind.Author;
        if (!closable)
        {
            item.Content = tab.Kind == WorkspaceTabKind.Notifications
                ? TitleWithBadge(tab.Title, _notifications.UnreadCount)
                : tab.Title;
            return item;
        }

        // Title plus a hover close button for conversation / filter tabs.
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        if (tab.Kind == WorkspaceTabKind.Filter)
        {
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        }
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var title = new TextBlock { Text = tab.Title, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center };
        Grid.SetColumn(title, 0);
        var closeColumn = 1;
        if (tab.Kind == WorkspaceTabKind.Filter)
        {
            var edit = new Button
            {
                Content = new FontIcon { Glyph = "\uE70F", FontSize = 11 },
                Background = null,
                BorderThickness = new Thickness(0),
                Padding = new Thickness(4),
                VerticalAlignment = VerticalAlignment.Center
            };
            edit.Click += async (_, _) =>
            {
                if (tab.Filter is { } filter) await OpenFilterEditorAsync(filter);
            };
            Grid.SetColumn(edit, 1);
            grid.Children.Add(edit);
            closeColumn = 2;
        }
        var close = new Button
        {
            Content = new FontIcon { Glyph = "\uE711", FontSize = 11 },
            Background = null,
            BorderThickness = new Thickness(0),
            Padding = new Thickness(4),
            VerticalAlignment = VerticalAlignment.Center
        };
        close.Click += (_, _) =>
        {
            if (tab.Kind == WorkspaceTabKind.Conversation) _workspace.CloseConversation(tab.Id);
            else if (tab.Kind == WorkspaceTabKind.Author) _workspace.CloseAuthor(tab.Id);
            else _workspace.RemoveFilter(tab.Id);
        };
        Grid.SetColumn(close, closeColumn);
        grid.Children.Add(title);
        grid.Children.Add(close);
        item.Content = grid;
        return item;
    }

    private static NavigationViewItem MakeAddFilterItem() => new()
    {
        Tag = AddFilterTag,
        Content = "フィルターを追加",
        Icon = new FontIcon { Glyph = "\uE710" }
    };

    private static UIElement TitleWithBadge(string title, int unread)
    {
        if (unread <= 0) return new TextBlock { Text = title };
        var grid = new Grid { ColumnSpacing = 8 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var text = new TextBlock { Text = title, VerticalAlignment = VerticalAlignment.Center };
        var badge = new Border
        {
            Background = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["AppAccentBrush"],
            CornerRadius = new CornerRadius(9),
            Padding = new Thickness(6, 1, 6, 1),
            MinWidth = 18,
            Child = new TextBlock
            {
                Text = unread > 99 ? "99+" : unread.ToString(),
                Foreground = new SolidColorBrush(Colors.White),
                FontSize = 11,
                HorizontalAlignment = HorizontalAlignment.Center
            }
        };
        Grid.SetColumn(text, 0);
        Grid.SetColumn(badge, 1);
        grid.Children.Add(text);
        grid.Children.Add(badge);
        return grid;
    }

    private static IconElement IconFor(WorkspaceTabKind kind) => new FontIcon
    {
        Glyph = kind switch
        {
            WorkspaceTabKind.Home => "\uE80F",            // Home
            WorkspaceTabKind.Notifications => "\uEA8F",   // Ringer
            WorkspaceTabKind.Filter => "\uE71C",          // Filter
            WorkspaceTabKind.Conversation => "\uE8BD",    // Message
            WorkspaceTabKind.Author => "\uE77B",          // Contact
            _ => "\uE80F"
        }
    };

    private async void OnNavSelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (_syncing) return;
        if (args.IsSettingsSelected)
        {
            ContentHost.Content = new SettingsView();
            return;
        }
        if (args.SelectedItem is NavigationViewItem { Tag: string tag } && tag == AddFilterTag)
        {
            await OpenFilterEditorAsync(null);
            BuildTabs();
            return;
        }
        if (args.SelectedItem is NavigationViewItem { Tag: WorkspaceTab tab })
        {
            if (ReferenceEquals(tab, _workspace.Selected))
            {
                await ShowSelectedAsync();
            }
            else
            {
                _workspace.Selected = tab; // fires Changed -> BuildTabs + ShowSelectedAsync
            }
        }
    }

    private async Task OpenFilterEditorAsync(SavedFilterModel? editing)
    {
        var dialog = new FilterEditorDialog(editing) { XamlRoot = ContentHost.XamlRoot };
        var result = await dialog.ShowAsync();
        if (result != ContentDialogResult.Primary || dialog.Result is not { } filter) return;
        if (editing is null) _workspace.AddFilter(filter);
        else _workspace.UpdateFilter(filter);
    }

    private void SaveFilters()
    {
        _filterStore?.Save(_workspace.Filters);
    }

    private async Task ShowSelectedAsync()
    {
        var tab = _workspace.Selected;
        _notifications.SetActive(tab.Kind == WorkspaceTabKind.Notifications);
        switch (tab.Kind)
        {
            case WorkspaceTabKind.Home:
                var feed = new FeedView(TimelineViewModel.Home(), _workspace);
                ContentHost.Content = feed;
                await feed.LoadAsync();
                break;
            case WorkspaceTabKind.Notifications:
                var notifications = new NotificationsView(_workspace, _notifications);
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
            case WorkspaceTabKind.Author when tab.Author is { } author:
                var authorView = new AuthorView(author, _workspace);
                ContentHost.Content = authorView;
                await authorView.LoadAsync();
                break;
        }
    }

    private void WireShortcuts()
    {
        AddAccelerator(VirtualKey.J, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift,
            () => _workspace.SelectNextTab());
        AddAccelerator(VirtualKey.K, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift,
            () => _workspace.SelectPreviousTab());
    }

    private void AddAccelerator(VirtualKey key, VirtualKeyModifiers modifiers, Action action)
    {
        var accelerator = new KeyboardAccelerator { Key = key, Modifiers = modifiers };
        accelerator.Invoked += (_, e) => { e.Handled = true; action(); };
        RootGrid.KeyboardAccelerators.Add(accelerator);
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
}
