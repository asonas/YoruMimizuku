using System;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI;
using Microsoft.UI.Input;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml.Media;
using Windows.System;
using YoruMimizuku.App.Interop;
using YoruMimizuku.App.Services;
using YoruMimizuku.App.ViewModels;
using YoruMimizuku.App.Views;
using CoreVirtualKeyStates = Windows.UI.Core.CoreVirtualKeyStates;

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
    private int _contentRequest;
    private bool _restoringWindowWidth;
    private AppWindow? _appWindow;
    private SavedFilterStore? _filterStore;
    // Last unread count we already alerted on, so a steady or falling count does
    // not re-toast. Starts at 0; the first load anchors unread to 0 (see
    // NotificationsViewModel), so only genuinely new activity raises it.
    private int _lastNotifiedUnread;

    public MainWindow()
    {
        InitializeComponent();
        Title = "YoruMimizuku";
        Views.MainWindowAccessor.Current = this;
        AppIcon.TrySetWindowIcon(this);
        NotificationAlerts.Shared.Register();
        if (CurrentAppWindow() is not null)
        {
            _appWindow!.Changed += OnAppWindowChanged;
        }
        SizeChanged += OnWindowSizeChanged;
        Closed += (_, _) =>
        {
            SaveWindowWidth();
            UpdateService.Shared.Shutdown();
            NotificationAlerts.Shared.Unregister();
        };
        _workspace.Changed += OnWorkspaceChanged;
        _workspace.FiltersChanged += SaveFilters;
        _notifications.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName != nameof(NotificationsViewModel.UnreadCount)) return;
            BuildTabs();
            var unread = _notifications.UnreadCount;
            if (unread > _lastNotifiedUnread && unread > 0)
            {
                NotificationAlerts.Shared.NotifyNewActivity(unread, this);
            }
            _lastNotifiedUnread = unread;
        };
        _notificationsTimer.Tick += async (_, _) => await _notifications.RefreshAsync();
        RootGrid.KeyDown += OnRootKeyDown;
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

    private AppWindow? CurrentAppWindow()
    {
        try
        {
            if (_appWindow is not null) return _appWindow;
            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
            var id = Win32Interop.GetWindowIdFromWindow(hwnd);
            _appWindow = AppWindow.GetFromWindowId(id);
            if (_appWindow is not null)
            {
                _appWindow.Changed -= OnAppWindowChanged;
                _appWindow.Changed += OnAppWindowChanged;
            }
            return _appWindow;
        }
        catch (Exception ex)
        {
            AppLog.Write("resolve app window failed", ex);
            return null;
        }
    }

    public void RestoreSavedWindowWidth()
    {
        // TODO: This width-only restore path is still unreliable in WinUI 3.
        // Replace it with robust window placement restore (Win32 placement APIs, or
        // AppWindow placement persistence once exposed by this Windows App SDK).
        var width = AppSettings.Shared.WindowWidth;
        if (width is null || width < 480) return;
        if (CurrentAppWindow() is not { } appWindow) return;
        _restoringWindowWidth = true;
        appWindow.Resize(new Windows.Graphics.SizeInt32(
            (int)Math.Round(width.Value),
            Math.Max(appWindow.Size.Height, 480)));
        DispatcherQueue.TryEnqueue(() => _restoringWindowWidth = false);
    }

    private void SaveWindowWidth()
    {
        if (CurrentAppWindow() is not { } appWindow) return;
        AppSettings.Shared.WindowWidth = Math.Max(480, appWindow.Size.Width);
    }

    private void OnAppWindowChanged(AppWindow sender, AppWindowChangedEventArgs args)
    {
        if (!args.DidSizeChange || _restoringWindowWidth) return;
        AppSettings.Shared.WindowWidth = Math.Max(480, sender.Size.Width);
    }

    private void OnWindowSizeChanged(object sender, WindowSizeChangedEventArgs args)
    {
        if (_restoringWindowWidth) return;
        AppSettings.Shared.WindowWidth = Math.Max(480, args.Size.Width);
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
            _contentRequest++;
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
            if (!_workspace.Tabs.Contains(tab))
            {
                BuildTabs();
                await ShowSelectedAsync();
                return;
            }
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
        var request = ++_contentRequest;
        var tab = _workspace.Selected;
        _notifications.SetActive(tab.Kind == WorkspaceTabKind.Notifications);
        switch (tab.Kind)
        {
            case WorkspaceTabKind.Home:
                var feed = new FeedView(TimelineViewModel.Home(), _workspace);
                await feed.LoadAsync();
                if (IsCurrentContentRequest(request, tab)) ContentHost.Content = feed;
                break;
            case WorkspaceTabKind.Notifications:
                var notifications = new NotificationsView(_workspace, _notifications);
                await notifications.LoadAsync();
                if (IsCurrentContentRequest(request, tab)) ContentHost.Content = notifications;
                break;
            case WorkspaceTabKind.Filter when tab.Filter is { } filter:
                var search = new FeedView(
                    new TimelineViewModel(cursor => BridgeClient.Shared.SearchLoadAsync(filter.ToBridgeJson(), cursor)),
                    _workspace);
                await search.LoadAsync();
                if (IsCurrentContentRequest(request, tab)) ContentHost.Content = search;
                break;
            case WorkspaceTabKind.Conversation when tab.ConversationAnchor is { } anchor:
                var conversation = new ConversationView(new ThreadViewModel(anchor), _workspace);
                await conversation.LoadAsync();
                if (IsCurrentContentRequest(request, tab)) ContentHost.Content = conversation;
                break;
            case WorkspaceTabKind.Author when tab.Author is { } author:
                var authorView = new AuthorView(author, _workspace);
                await authorView.LoadAsync();
                if (IsCurrentContentRequest(request, tab)) ContentHost.Content = authorView;
                break;
        }
    }

    private bool IsCurrentContentRequest(int request, WorkspaceTab tab) =>
        request == _contentRequest &&
        ReferenceEquals(tab, _workspace.Selected) &&
        _workspace.Tabs.Contains(tab);

    private void OnRootKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (!IsCtrlShiftDown()) return;
        switch (e.Key)
        {
            case VirtualKey.J:
                _workspace.SelectNextTab();
                e.Handled = true;
                break;
            case VirtualKey.K:
                _workspace.SelectPreviousTab();
                e.Handled = true;
                break;
        }
    }

    private static bool IsCtrlShiftDown() =>
        InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Control).HasFlag(CoreVirtualKeyStates.Down) &&
        InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Shift).HasFlag(CoreVirtualKeyStates.Down);

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
