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
    private SavedFilterStore? _filterStore;
    // Last unread count we already alerted on, so a steady or falling count does
    // not re-toast. Starts at 0; the first load anchors unread to 0 (see
    // NotificationsViewModel), so only genuinely new activity raises it.
    private int _lastNotifiedUnread;
    // Only the primary window owns the app-wide singletons: bridge init, the
    // updater, notification polling, and OS toasts. Secondary windows (Ctrl+Shift+N)
    // are independent workspaces over the same session, mirroring macOS WindowGroup.
    private readonly bool _isPrimary;
    private static readonly System.Collections.Generic.List<MainWindow> OpenWindows = new();
    // Cached token-free account list for the footer switcher menu, refreshed when
    // the shell is entered / switched so the menu builds synchronously on open.
    private System.Collections.Generic.List<AccountSummaryDto> _accountSummaries = new();

    public MainWindow() : this(true) { }

    public MainWindow(bool isPrimary)
    {
        _isPrimary = isPrimary;
        OpenWindows.Add(this);
        InitializeComponent();
        Title = "YoruMimizuku";
        Views.MainWindowAccessor.Current = this;
        Activated += (_, _) => Views.MainWindowAccessor.Current = this;
        AppIcon.TrySetWindowIcon(this);
        if (isPrimary) NotificationAlerts.Shared.Register();
        Closed += (_, _) =>
        {
            OpenWindows.Remove(this);
            AppSettings.Shared.NotificationSettingsChanged -= OnNotificationSettingsChanged;
            if (!_isPrimary) return;
            // Persist where the user left the primary window so it relaunches at the
            // same place/size (including the maximized state).
            SaveWindowPlacement();
            UpdateService.Shared.Shutdown();
            NotificationAlerts.Shared.Unregister();
        };
        _workspace.Changed += OnWorkspaceChanged;
        _workspace.FiltersChanged += SaveFilters;
        _notifications.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName != nameof(NotificationsViewModel.UnreadCount)) return;
            BuildTabs();
            if (!_isPrimary) return;
            var unread = _notifications.UnreadCount;
            if (unread > _lastNotifiedUnread && unread > 0)
            {
                NotificationAlerts.Shared.NotifyNewActivity(unread, this);
            }
            _lastNotifiedUnread = unread;
        };
        _notificationsTimer.Interval = TimeSpan.FromSeconds(AppSettings.Shared.NotificationPollIntervalSeconds);
        _notificationsTimer.Tick += async (_, _) => await _notifications.RefreshAsync();
        AppSettings.Shared.NotificationSettingsChanged += OnNotificationSettingsChanged;
        RootGrid.KeyDown += OnRootKeyDown;
        _ = InitializeAsync();
    }

    private async Task InitializeAsync()
    {
        try
        {
            ThemeService.Shared.ApplySaved();
            // The bridge runtime is a process-wide singleton; only the primary
            // window initializes it. Secondary windows reuse the live session.
            if (_isPrimary)
            {
                await BridgeClient.Shared.InitializeAsync(App.Service, App.ClientId, App.RedirectUri, App.Scope);
            }

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

    /// Restore the persisted window placement (position, size, maximized state)
    /// via Win32 SetWindowPlacement. Called once at launch before Activate so the
    /// window appears at its remembered geometry instead of the WinUI default.
    public void RestoreSavedWindowPlacement()
    {
        WindowPlacement.Apply(this, AppSettings.Shared.WindowPlacement);
    }

    private void SaveWindowPlacement()
    {
        if (WindowPlacement.Capture(this) is { } placement)
        {
            AppSettings.Shared.WindowPlacement = placement;
        }
    }

    private async void OnAuthenticated(string did)
    {
        LoginHost.Content = null;
        var account = await BridgeClient.Shared.CurrentAccountAsync();
        EnterShell(account);
    }

    private void EnterShell(AccountDto? account)
    {
        _workspace.AccountDid = account?.Did;
        _filterStore = account is null ? null : new SavedFilterStore(account.Did);
        _workspace.LoadFilters(_filterStore?.Load() ?? Array.Empty<SavedFilterModel>());
        LoginHost.Visibility = Visibility.Collapsed;
        ShellRoot.Visibility = Visibility.Visible;
        BuildTabs();
        _ = ShowSelectedAsync();
        _ = LoadAccountFooterAsync(account);
        if (_isPrimary) _notificationsTimer.Start();
    }

    /// React to a live notification-settings change: re-apply the poll interval
    /// (primary window owns the timer) and rebuild tabs so the badge respects the
    /// show/hide preference.
    private void OnNotificationSettingsChanged()
    {
        if (_isPrimary)
        {
            var wasRunning = _notificationsTimer.IsEnabled;
            _notificationsTimer.Stop();
            _notificationsTimer.Interval = TimeSpan.FromSeconds(AppSettings.Shared.NotificationPollIntervalSeconds);
            if (wasRunning) _notificationsTimer.Start();
        }
        BuildTabs();
    }

    private async Task LoadAccountFooterAsync(AccountDto? account)
    {
        if (account is null) return;
        AccountHandle.Text = account.Handle is { Length: > 0 } h ? "@" + h : account.Did;
        AccountFooter.Visibility = Visibility.Visible;
        try { _accountSummaries = await BridgeClient.Shared.AccountSummariesAsync(); }
        catch (Exception ex) { AppLog.Write("account summaries load failed", ex); }
        try
        {
            var avatar = await BridgeClient.Shared.AvatarAsync();
            if (avatar.AvatarUrl is { Length: > 0 } url)
            {
                AccountAvatar.ProfilePicture = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri(url));
            }
        }
        catch (BridgeException be) when (be.SessionExpired)
        {
            // The stored refresh token is no longer valid — drop the dead session
            // and advance to the next account, or return to login when none remain
            // (the Windows counterpart to macOS SessionExpiry).
            AppLog.Write("session expired restoring account; logging out");
            await LogOutAndAdvanceAsync();
        }
        catch (Exception ex) { AppLog.Write("avatar load failed", ex); }
    }

    // -- Account switcher (footer menu) --

    /// Build the footer account menu from the cached summaries: each stored account
    /// (active one checked), then "アカウントを追加…" and "ログアウト". Mirrors the
    /// macOS sidebar account switcher.
    private void OnAccountMenuOpening(object sender, object e)
    {
        if (sender is not MenuFlyout menu) return;
        menu.Items.Clear();
        foreach (var summary in _accountSummaries)
        {
            var item = new MenuFlyoutItem
            {
                Text = summary.Handle is { Length: > 0 } h ? "@" + h : summary.Did,
                Tag = summary.Did
            };
            if (summary.Did == _workspace.AccountDid)
            {
                item.Icon = new FontIcon { Glyph = "" }; // checkmark on the active account
            }
            item.Click += OnSwitchAccountClick;
            menu.Items.Add(item);
        }
        if (_accountSummaries.Count > 0) menu.Items.Add(new MenuFlyoutSeparator());
        var add = new MenuFlyoutItem { Text = "アカウントを追加…" };
        add.Click += OnAddAccountClick;
        menu.Items.Add(add);
        var logout = new MenuFlyoutItem { Text = "ログアウト" };
        logout.Click += OnLogOutClick;
        menu.Items.Add(logout);
    }

    private async void OnSwitchAccountClick(object sender, RoutedEventArgs e)
    {
        if (sender is MenuFlyoutItem { Tag: string did } && did != _workspace.AccountDid)
        {
            await SwitchToAccountAsync(did);
        }
    }

    private async void OnAddAccountClick(object sender, RoutedEventArgs e)
    {
        // Show the login view while keeping the current account stored; a successful
        // login adds the new account, makes it current, and re-enters the shell via
        // OnAuthenticated. Cancelling leaves the current account intact on relaunch.
        await Task.CompletedTask;
        ShowLogin();
    }

    private async void OnLogOutClick(object sender, RoutedEventArgs e) => await LogOutAndAdvanceAsync();

    /// Switch the active account and rebuild the shell for it.
    private async Task SwitchToAccountAsync(string did)
    {
        try
        {
            await BridgeClient.Shared.SwitchAccountAsync(did);
            var account = await BridgeClient.Shared.CurrentAccountAsync();
            EnterShell(account);
        }
        catch (Exception ex) { AppLog.Write("switch account failed", ex); }
    }

    /// Log out the current account and advance to the next stored one (re-entering
    /// the shell for it), or fall back to the login screen when none remain. Shared
    /// by the menu's ログアウト and the session-expiry handler (mirrors macOS
    /// AccountManager.removeAndAdvance).
    private async Task LogOutAndAdvanceAsync()
    {
        try
        {
            if (_workspace.AccountDid is { Length: > 0 } did)
            {
                var next = await BridgeClient.Shared.RemoveAndAdvanceAsync(did);
                if (next.NextDid is { Length: > 0 })
                {
                    var account = await BridgeClient.Shared.CurrentAccountAsync();
                    EnterShell(account);
                    return;
                }
            }
        }
        catch (Exception ex) { AppLog.Write("log out failed", ex); }
        _notificationsTimer.Stop();
        _workspace.AccountDid = null;
        _accountSummaries = new();
        AccountFooter.Visibility = Visibility.Collapsed;
        ShowLogin();
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
        if (unread <= 0 || !AppSettings.Shared.ShowsUnreadBadges) return new TextBlock { Text = title };
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
            case VirtualKey.N:
                OpenNewWindow();
                e.Handled = true;
                break;
        }
    }

    /// Open another independent workspace window over the same session
    /// (Ctrl+Shift+N), the Windows analogue of a macOS WindowGroup window.
    private void OpenNewWindow()
    {
        var window = new MainWindow(isPrimary: false);
        window.Activate();
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
