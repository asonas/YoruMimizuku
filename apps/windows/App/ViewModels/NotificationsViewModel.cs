using System;
using System.Collections.ObjectModel;
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

    public async Task LoadAsync()
    {
        IsLoading = true;
        ErrorMessage = null;
        try
        {
            var groups = await BridgeClient.Shared.NotificationsLoadAsync();
            Items.Clear();
            foreach (var g in groups) Items.Add(g);
        }
        catch (Exception ex) { ErrorMessage = ex.Message; }
        finally { IsLoading = false; }
    }

    public Task RefreshAsync() => LoadAsync();
}
