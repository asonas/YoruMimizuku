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
    private readonly NotificationsViewModel _notifications;
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
    // Only the primary window owns the app-wide singletons: the updater, notification polling, and OS toasts. Secondary windows (Ctrl+Shift+N)
    // are independent workspaces over the same session, mirroring macOS WindowGroup.
    private readonly bool _isPrimary;
    private static readonly System.Collections.Generic.List<MainWindow> OpenWindows = new();
    // Cached token-free account list for the footer switcher menu, refreshed when
    // the shell is entered / switched so the menu builds synchronously on open.
    private System.Collections.Generic.List<AccountSummaryDto> _accountSummaries = new();
    // The account this window's shell shows, and the same account while its session has
    // expired and waits to sign in again (ADR 0018). Entering the shell clears _reauth.
    private AccountDto? _account;
    private AccountDto? _reauth;

    public MainWindow() : this(true) { }

    public MainWindow(bool isPrimary)
    {
        _isPrimary = isPrimary;
        _notifications = new NotificationsViewModel(_workspace);
        OpenWindows.Add(this);
        InitializeComponent();
        Title = "YoruMimizuku";
        Views.MainWindowAccessor.Current = this;
        Activated += (_, args) =>
        {
            Views.MainWindowAccessor.Current = this;
            // Pins are managed on the server, so re-read them whenever the window comes
            // forward, as macOS does when the app becomes active.
            if (args.WindowActivationState != WindowActivationState.Deactivated) _ = _workspace.ReloadSavedFeedsAsync();
        };
        AppIcon.TrySetWindowIcon(this);
        if (isPrimary) NotificationAlerts.Shared.Register();
        Closed += (_, _) =>
        {
            OpenWindows.Remove(this);
            AppSettings.Shared.NotificationSettingsChanged -= OnNotificationSettingsChanged;
            App.Client.SessionExpired -= OnSessionExpired;
            if (!_isPrimary) return;
            // Persist where the user left the primary window so it relaunches at the
            // same place/size (including the maximized state).
            SaveWindowPlacement();
            UpdateService.Shared.Shutdown();
            NotificationAlerts.Shared.Unregister();
        };
        // The three panes need 900 DIPs, as on macOS: the sidebar's 210 plus the
        // timeline's and the detail pane's minimum widths.
        WindowPlacement.SetMinimumSize(this, 900, 540);
        _workspace.Changed += OnWorkspaceChanged;
        _workspace.FiltersChanged += SaveFilters;
        _workspace.SavedFeedsChanged += BuildTabs;
        _workspace.Detail.Changed += ShowDetail;
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
        App.Client.SessionExpired += OnSessionExpired;
        RootGrid.KeyDown += OnRootKeyDown;
        _ = InitializeAsync();
    }

    private async Task InitializeAsync()
    {
        try
        {
            ThemeService.Shared.ApplySaved();
            // Restore the persisted session (DPAPI): skip the login screen if an
            // account is already stored.
            var account = await App.Client.CurrentAccountAsync();
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
            AppLog.Write("startup failed", ex);
            ShowFatal($"起動に失敗しました。\n{ex.Message}\n\nログ: {AppLog.Path}");
        }
    }

    /// Show the login view over the shell. With <paramref name="reauth"/> it signs in again to
    /// that expired account: pre-filled with its handle, and キャンセル returns to the shell,
    /// which stays loaded behind it.
    private void ShowLogin(AccountDto? reauth = null)
    {
        var login = new LoginView(reauth?.Handle ?? reauth?.Did, canCancel: reauth is not null);
        login.Authenticated += OnAuthenticated;
        login.Cancelled += () =>
        {
            LoginHost.Content = null;
            LoginHost.Visibility = Visibility.Collapsed;
            ShellRoot.Visibility = Visibility.Visible;
        };
        LoginHost.Content = login;
        LoginHost.Visibility = Visibility.Visible;
        ShellRoot.Visibility = Visibility.Collapsed;
    }

    /// A call made as some account found its refresh token dead. If it is this window's
    /// account and no sign-in again is pending, keep the account and ask the user to sign
    /// in to it again (ADR 0018 §5.1). Raised on any thread.
    private void OnSessionExpired(string did) => DispatcherQueue.TryEnqueue(() =>
    {
        if (_account is not { } account || account.Did != did || _reauth is not null) return;
        AppLog.Write($"Session expired; prompting re-auth for {did}");
        _reauth = account;
        ReauthBar.IsOpen = true;
        ShowLogin(account);
    });

    private void OnReauthClick(object sender, RoutedEventArgs e)
    {
        if (_reauth is { } account) ShowLogin(account);
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
        var account = await App.Client.CurrentAccountAsync();
        EnterShell(account);
    }

    /// Build the shell for <paramref name="account"/>. Signing in again lands here too, so a
    /// fresh client and freshly loaded tabs replace the expired ones.
    private void EnterShell(AccountDto? account)
    {
        _account = account;
        _reauth = null;
        ReauthBar.IsOpen = false;
        // Detail pages were built on the previous client, so they go with it.
        _workspace.Detail.Close();
        _workspace.Account = account is null ? null : App.Client.ForAccount(account.Did);
        // Pins belong to the account, so the previous account's go, and the new one's load.
        _workspace.ClearSavedFeeds();
        _ = _workspace.ReloadSavedFeedsAsync();
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
        if (account is null || _workspace.Account is not { } client) return;
        AccountHandle.Text = account.Handle is { Length: > 0 } h ? "@" + h : account.Did;
        AccountFooter.Visibility = Visibility.Visible;
        try { _accountSummaries = await App.Client.AccountSummariesAsync(); }
        catch (Exception ex) { AppLog.Write("account summaries load failed", ex); }
        try
        {
            var avatar = await client.AvatarAsync();
            if (avatar.AvatarUrl is { Length: > 0 } url)
            {
                AccountAvatar.ProfilePicture = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri(url));
            }
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
            await App.Client.SwitchAccountAsync(did);
            var account = await App.Client.CurrentAccountAsync();
            EnterShell(account);
        }
        catch (Exception ex) { AppLog.Write("switch account failed", ex); }
    }

    /// Log out the current account and advance to the next stored one (re-entering
    /// the shell for it), or fall back to the login screen when none remain. The
    /// menu's ログアウト (mirrors macOS AccountManager.removeAndAdvance).
    private async Task LogOutAndAdvanceAsync()
    {
        try
        {
            if (_workspace.AccountDid is { Length: > 0 } did)
            {
                var next = await App.Client.RemoveAndAdvanceAsync(did);
                if (next.NextDid is { Length: > 0 })
                {
                    var account = await App.Client.CurrentAccountAsync();
                    EnterShell(account);
                    return;
                }
            }
        }
        catch (Exception ex) { AppLog.Write("log out failed", ex); }
        _notificationsTimer.Stop();
        _account = null;
        _reauth = null;
        ReauthBar.IsOpen = false;
        _workspace.Detail.Close();
        _workspace.Account = null;
        _workspace.ClearSavedFeeds();
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
        // The macOS sidebar's groups: home, notifications and pinned feeds; then リスト
        // (pinned lists, hidden with none); then the filters, led by フィルターを追加.
        var lastBeforeFilters = _workspace.Tabs.LastOrDefault(t => t.Kind != WorkspaceTabKind.Filter);
        var firstList = _workspace.Tabs.FirstOrDefault(t => t.SavedFeed?.Kind == Core.SavedFeedKind.List);
        foreach (var tab in _workspace.Tabs)
        {
            if (ReferenceEquals(tab, firstList)) Nav.MenuItems.Add(new NavigationViewItemHeader { Content = "リスト" });
            Nav.MenuItems.Add(MakeNavItem(tab));
            if (ReferenceEquals(tab, lastBeforeFilters))
            {
                Nav.MenuItems.Add(MakeAddFilterItem());
            }
        }
        var selected = Nav.MenuItems
            .OfType<NavigationViewItem>()
            .FirstOrDefault(i => ReferenceEquals(i.Tag, _workspace.Selected));
        // A search has no row, so no row is selected while it shows.
        Nav.SelectedItem = _workspace.Selected.Kind == WorkspaceTabKind.Search
            ? null
            : selected ?? Nav.MenuItems.OfType<NavigationViewItem>().FirstOrDefault();
        _syncing = false;
    }

    private NavigationViewItem MakeNavItem(WorkspaceTab tab)
    {
        var item = new NavigationViewItem { Tag = tab, Icon = IconFor(tab) };
        if (tab.SavedFeed is { } pin)
        {
            // Pins are managed in Bluesky, so the row has no edit or close button. Its
            // tooltip carries what the macOS header's info popover shows.
            item.Content = new TextBlock { Text = pin.Title, TextTrimming = TextTrimming.CharacterEllipsis };
            ToolTipService.SetToolTip(item, string.Join("\n", new[]
            {
                pin.Title,
                pin.Description,
                pin.CreatorHandle is { Length: > 0 } handle ? "@" + handle : null,
                pin.Id,
            }.Where(line => !string.IsNullOrWhiteSpace(line))));
            // Only the window account's own curated lists take people.
            if (pin.IsCuratedList && pin.CreatorDid == _workspace.AccountDid) AcceptAuthorDrops(item, pin);
            return item;
        }
        if (tab.Kind != WorkspaceTabKind.Filter)
        {
            item.Content = tab.Kind == WorkspaceTabKind.Notifications
                ? TitleWithBadge(tab.Title, _notifications.UnreadCount)
                : tab.Title;
            return item;
        }

        // Title plus edit and close buttons for filter tabs.
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var title = new TextBlock { Text = tab.Title, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center };
        Grid.SetColumn(title, 0);
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
        var close = new Button
        {
            Content = new FontIcon { Glyph = "\uE711", FontSize = 11 },
            Background = null,
            BorderThickness = new Thickness(0),
            Padding = new Thickness(4),
            VerticalAlignment = VerticalAlignment.Center
        };
        close.Click += (_, _) => _workspace.RemoveFilter(tab.Id);
        Grid.SetColumn(close, 2);
        grid.Children.Add(title);
        grid.Children.Add(close);
        item.Content = grid;
        return item;
    }

    /// <summary>
    /// A post's avatar dropped on the row adds its author to the list; the row is
    /// outlined while a drag hovers over it (the macOS sidebar's AuthorDropTarget).
    /// </summary>
    private void AcceptAuthorDrops(NavigationViewItem item, SavedFeedDto list)
    {
        item.AllowDrop = true;
        void Outline(bool on)
        {
            item.BorderBrush = on ? (Brush)Application.Current.Resources["AppAccentBrush"] : null;
            item.BorderThickness = new Thickness(on ? 2 : 0);
        }
        item.DragOver += (_, e) =>
        {
            if (!DraggedAuthor.IsIn(e.DataView)) return;
            e.AcceptedOperation = Windows.ApplicationModel.DataTransfer.DataPackageOperation.Copy;
            e.DragUIOverride.Caption = $"「{list.Title}」に追加";
            Outline(true);
        };
        item.DragLeave += (_, _) => Outline(false);
        item.Drop += async (_, e) =>
        {
            Outline(false);
            if (_workspace.Account is not { } account || await DraggedAuthor.ReadAsync(e.DataView) is not { } author) return;
            await ListMembershipMenu.AddDroppedAsync(item.XamlRoot, account.ListMembership, author, list.Id, list.Title);
        };
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

    private static IconElement IconFor(WorkspaceTab tab) => new FontIcon
    {
        Glyph = tab.Kind switch
        {
            WorkspaceTabKind.Home => "\uE80F",            // Home
            WorkspaceTabKind.Notifications => "\uEA8F",   // Ringer
            WorkspaceTabKind.SavedFeed when tab.SavedFeed?.Kind == Core.SavedFeedKind.List => "\uE8FD", // BulletedList
            WorkspaceTabKind.SavedFeed => "\uE909",       // World: a feed from the network
            WorkspaceTabKind.Filter => "\uE71C",          // Filter
            _ => "\uE80F"
        }
    };

    private async void OnNavSelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (_syncing) return;
        if (args.IsSettingsSelected)
        {
            _contentRequest++;
            // Settings take the timeline and detail columns together.
            Grid.SetColumnSpan(ContentHost, 2);
            DetailPane.Visibility = Visibility.Collapsed;
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
        if (_workspace.Account is not { } account) return;
        var request = ++_contentRequest;
        var tab = _workspace.Selected;
        _notifications.SetActive(tab.Kind == WorkspaceTabKind.Notifications);
        switch (tab.Kind)
        {
            case WorkspaceTabKind.Home:
                var feed = new FeedView(TimelineViewModel.Home(account), _workspace);
                await feed.LoadAsync();
                if (IsCurrentContentRequest(request, tab)) ShowTimeline(feed);
                break;
            case WorkspaceTabKind.Notifications:
                var notifications = new NotificationsView(_workspace, _notifications);
                await notifications.LoadAsync();
                if (IsCurrentContentRequest(request, tab)) ShowTimeline(notifications);
                break;
            case WorkspaceTabKind.SavedFeed when tab.SavedFeed is { } pin:
                // A new view per selection, and FeedView polls only while on screen, so
                // only the selected pin polls, as on macOS.
                var pinned = new FeedView(
                    new TimelineViewModel(account, cursor => account.SavedFeedLoadAsync(pin, cursor)), _workspace);
                await pinned.LoadAsync();
                if (IsCurrentContentRequest(request, tab)) ShowTimeline(pinned);
                break;
            case WorkspaceTabKind.Filter or WorkspaceTabKind.Search when tab.Filter is { } filter:
                var search = new FeedView(
                    new TimelineViewModel(account, cursor => account.SearchLoadAsync(filter.ToSearchJson(), cursor)),
                    _workspace);
                if (tab.Kind == WorkspaceTabKind.Search)
                {
                    // Windows timelines have no header, so the macOS header button sits
                    // beside 更新 and 投稿.
                    var save = new AppBarButton { Icon = new SymbolIcon(Symbol.Save), Label = "フィルターとして保存" };
                    ToolTipService.SetToolTip(save, "この検索をサイドバーのフィルターに残す");
                    save.Click += (_, _) => _workspace.SaveSearchAsFilter();
                    search.AddCommand(save);
                }
                await search.LoadAsync();
                if (IsCurrentContentRequest(request, tab)) ShowTimeline(search);
                break;
        }
    }

    private bool IsCurrentContentRequest(int request, WorkspaceTab tab) =>
        request == _contentRequest &&
        ReferenceEquals(tab, _workspace.Selected) &&
        (tab.Kind == WorkspaceTabKind.Search || _workspace.Tabs.Contains(tab));

    private void OnSearchSubmitted(AutoSuggestBox sender, AutoSuggestBoxQuerySubmittedEventArgs args) =>
        _workspace.OpenSearch(args.QueryText);

    /// Put a loaded timeline in its column, giving the detail pane back if settings
    /// had taken it.
    private void ShowTimeline(UIElement timeline)
    {
        Grid.SetColumnSpan(ContentHost, 1);
        DetailPane.Visibility = Visibility.Visible;
        ContentHost.Content = timeline;
    }

    // -- Detail pane --

    /// Show the page the detail pane now holds, or its empty state. Only the pane is
    /// rebuilt; the timeline column is never touched, so it keeps its scroll position.
    private void ShowDetail()
    {
        var page = _workspace.Detail.Current;
        DetailBar.Visibility = page is null ? Visibility.Collapsed : Visibility.Visible;
        DetailEmpty.Visibility = page is null ? Visibility.Visible : Visibility.Collapsed;
        DetailTitle.Text = page?.Title ?? "";
        DetailHost.Content = page is not null && _workspace.Account is { } account
            ? BuildDetailView(page, account)
            : null;
    }

    private UIElement BuildDetailView(DetailPage page, IAccountClient account)
    {
        switch (page)
        {
            case ConversationPage conversation:
                var thread = new ConversationView(new ThreadViewModel(account, conversation.AnchorUri), _workspace);
                _ = thread.LoadAsync();
                return thread;
            case AuthorPage author:
                var view = new AuthorView(author.Author, account, _workspace);
                _ = LoadAuthorAsync(author, view);
                return view;
            default:
                throw new ArgumentOutOfRangeException(nameof(page));
        }
    }

    /// An author opened from a mention has no name until its profile loads.
    private async Task LoadAuthorAsync(AuthorPage page, AuthorView view)
    {
        await view.LoadAsync();
        if (ReferenceEquals(_workspace.Detail.Current, page)) DetailTitle.Text = page.Title;
    }

    private void OnDetailCloseClick(object sender, RoutedEventArgs e) => _workspace.Detail.Close();

    private void OnRootKeyDown(object sender, KeyRoutedEventArgs e)
    {
        // Ctrl+F, the macOS 検索 ⌘F: focus the search box.
        if (IsKeyDown(VirtualKey.Control) && !IsKeyDown(VirtualKey.Shift))
        {
            switch (e.Key)
            {
                case VirtualKey.F:
                    SearchBox.Focus(FocusState.Keyboard);
                    e.Handled = true;
                    return;
                // Ctrl+R, the macOS 新着を読み込む ⌘R, as the timeline's 更新 button.
                case VirtualKey.R:
                    _ = ReloadTimelineAsync();
                    e.Handled = true;
                    return;
                // Ctrl+1…Ctrl+9, the macOS ⌘1…⌘9: the first nine sidebar rows, in the
                // order Ctrl+Shift+J/K cycles.
                case >= VirtualKey.Number1 and <= VirtualKey.Number9:
                    SelectRow(e.Key - VirtualKey.Number1);
                    e.Handled = true;
                    return;
            }
        }
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

    /// Select a sidebar row by position. The selected row selected again still shows
    /// its timeline, as clicking it does, so it leaves settings.
    private void SelectRow(int index)
    {
        if (index >= _workspace.Tabs.Count) return;
        var tab = _workspace.Tabs[index];
        if (!ReferenceEquals(tab, _workspace.Selected))
        {
            _workspace.Selected = tab; // fires Changed -> BuildTabs + ShowSelectedAsync
            return;
        }
        BuildTabs();
        _ = ShowSelectedAsync();
    }

    private Task ReloadTimelineAsync() => ContentHost.Content switch
    {
        FeedView feed => feed.Vm.RefreshAsync(),
        NotificationsView notifications => notifications.Vm.RefreshAsync(),
        _ => Task.CompletedTask,
    };

    /// Open another independent workspace window over the same session
    /// (Ctrl+Shift+N), the Windows analogue of a macOS WindowGroup window.
    private void OpenNewWindow()
    {
        var window = new MainWindow(isPrimary: false);
        window.Activate();
    }

    /// Bring the last active window to the front when the app is launched again.
    public static void BringToFront()
    {
        var window = OpenWindows.Find(w => w == MainWindowAccessor.Current) ?? OpenWindows.FirstOrDefault();
        window?.Activate();
    }

    private static bool IsCtrlShiftDown() => IsKeyDown(VirtualKey.Control) && IsKeyDown(VirtualKey.Shift);

    private static bool IsKeyDown(VirtualKey key) =>
        InputKeyboardSource.GetKeyStateForCurrentThread(key).HasFlag(CoreVirtualKeyStates.Down);

    /// Tell the user, once, why the switch to the C# core signed them out (Phase 4).
    /// It runs after the window's content has loaded, since a dialog needs its XamlRoot.
    public async void ShowSignInAgainNotice()
    {
        try
        {
            if (!RootGrid.IsLoaded)
            {
                var loaded = new TaskCompletionSource();
                RoutedEventHandler? onLoaded = null;
                onLoaded = (_, _) => { RootGrid.Loaded -= onLoaded; loaded.TrySetResult(); };
                RootGrid.Loaded += onLoaded;
                await loaded.Task;
            }
            await new ContentDialog
            {
                XamlRoot = RootGrid.XamlRoot,
                Title = "もう一度サインインしてください",
                Content = "サインイン情報の保存方法が変わったため、以前のサインイン情報は使えなくなりました。お手数ですが、もう一度サインインしてください。",
                CloseButtonText = "OK",
                DefaultButton = ContentDialogButton.Close
            }.ShowAsync();
        }
        catch (Exception ex) { AppLog.Write("sign-in notice failed", ex); }
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
