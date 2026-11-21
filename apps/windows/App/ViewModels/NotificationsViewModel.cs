using System;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading.Tasks;
using YoruMimizuku.App.Interop;
using YoruMimizuku.App.Mvvm;

namespace YoruMimizuku.App.ViewModels;

public sealed class NotificationsViewModel : ObservableObject
{
    public ObservableCollection<NotificationGroupDto> Items { get; } = new();

    private bool _isLoading;
    public bool IsLoading { get => _isLoading; private set => SetProperty(ref _isLoading, value); }

    private string? _errorMessage;
    public string? ErrorMessage { get => _errorMessage; private set => SetProperty(ref _errorMessage, value); }

    private int _unreadCount;
    public int UnreadCount { get => _unreadCount; private set => SetProperty(ref _unreadCount, value); }

    private string? _lastSeenTopId;
    private bool _isActive;

    // The window's workspace, not a fixed account: this view model lives as long
    // as the window, across its account switches, so it reads the window's
    // account on each load.
    private readonly WorkspaceViewModel _workspace;

    public NotificationsViewModel(WorkspaceViewModel workspace) { _workspace = workspace; }

    public async Task LoadAsync()
    {
        if (_workspace.Account is not { } account) return;
        IsLoading = true;
        ErrorMessage = null;
        try
        {
            var groups = await account.NotificationsLoadAsync();
            Items.Clear();
            foreach (var g in groups) Items.Add(g);
            OnItemsChanged();
        }
        catch (Exception ex) { ErrorMessage = ex.Message; }
        finally { IsLoading = false; }
    }

    public Task RefreshAsync() => LoadAsync();

    public void SetActive(bool active)
    {
        _isActive = active;
        if (active) MarkSeen();
    }

    public void MarkSeen()
    {
        _lastSeenTopId = Items.FirstOrDefault()?.Id;
        UnreadCount = 0;
    }

    private void OnItemsChanged()
    {
        if (_lastSeenTopId is null) _lastSeenTopId = Items.FirstOrDefault()?.Id;
        UnreadCount = _isActive
            ? 0
            : UnreadCounter.Count(Items.Select(i => i.Id), _lastSeenTopId);
        if (_isActive) _lastSeenTopId = Items.FirstOrDefault()?.Id;
    }
}
