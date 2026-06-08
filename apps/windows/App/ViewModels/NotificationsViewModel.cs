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

    public async Task LoadAsync()
    {
        IsLoading = true;
        ErrorMessage = null;
        try
        {
            var groups = await BridgeClient.Shared.NotificationsLoadAsync();
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
