using System;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using YoruMimizuku.App.Interop;
using YoruMimizuku.App.Mvvm;

namespace YoruMimizuku.App.ViewModels;

/// <summary>
/// Drives a feed (home timeline or a saved-filter search). Mirrors the Swift
/// TimelineViewModel state machine: initial load, infinite-scroll loadMore via
/// the cursor, and head refresh that merges fresh posts on top (deduped).
/// </summary>
public sealed class TimelineViewModel : ObservableObject
{
    private readonly Func<string?, Task<TimelinePageDto>> _loadPage;

    public ObservableCollection<PostItem> Posts { get; } = new();

    private bool _isLoading;
    public bool IsLoading { get => _isLoading; private set => SetProperty(ref _isLoading, value); }

    private bool _isLoadingMore;
    public bool IsLoadingMore { get => _isLoadingMore; private set => SetProperty(ref _isLoadingMore, value); }

    private string? _errorMessage;
    public string? ErrorMessage { get => _errorMessage; private set => SetProperty(ref _errorMessage, value); }

    private string? _cursor;
    public bool CanLoadMore => _cursor is not null;

    public TimelineViewModel(Func<string?, Task<TimelinePageDto>> loadPage)
    {
        _loadPage = loadPage;
    }

    /// <summary>Home timeline feed.</summary>
    public static TimelineViewModel Home() => new(cursor => BridgeClient.Shared.TimelineLoadAsync(cursor));

    public async Task LoadAsync()
    {
        IsLoading = true;
        ErrorMessage = null;
        try
        {
            var page = await _loadPage(null);
            Posts.Clear();
            foreach (var dto in page.Posts) Posts.Add(new PostItem(dto));
            _cursor = page.Cursor;
            OnPropertyChanged(nameof(CanLoadMore));
        }
        catch (Exception ex) { ErrorMessage = ex.Message; }
        finally { IsLoading = false; }
    }

    public async Task LoadMoreAsync()
    {
        if (IsLoadingMore || _cursor is null) return;
        IsLoadingMore = true;
        try
        {
            var page = await _loadPage(_cursor);
            foreach (var dto in page.Posts)
            {
                if (!Contains(dto.Id)) Posts.Add(new PostItem(dto));
            }
            _cursor = page.Cursor;
            OnPropertyChanged(nameof(CanLoadMore));
        }
        catch { /* keep current rows; a later scroll retries */ }
        finally { IsLoadingMore = false; }
    }

    public async Task RefreshAsync()
    {
        try
        {
            var page = await _loadPage(null);
            var insertAt = 0;
            foreach (var dto in page.Posts)
            {
                if (Contains(dto.Id)) continue;
                Posts.Insert(insertAt++, new PostItem(dto));
            }
        }
        catch { /* keep showing the current feed */ }
    }

    private bool Contains(string id)
    {
        foreach (var p in Posts) if (p.Id == id) return true;
        return false;
    }
}
