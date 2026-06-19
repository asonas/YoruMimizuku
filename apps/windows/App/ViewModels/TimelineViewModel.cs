using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
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

    // Failed-state, classified through the shared LoadFailure (carried on the
    // BridgeException) so the feed can show a tailored title + message + retry,
    // matching macOS FeedView.failedState.
    private string? _failureTitle;
    public string? FailureTitle { get => _failureTitle; private set => SetProperty(ref _failureTitle, value); }

    private string? _failureMessage;
    public string? FailureMessage { get => _failureMessage; private set => SetProperty(ref _failureMessage, value); }

    private bool _hasError;
    public bool HasError
    {
        get => _hasError;
        private set { if (SetProperty(ref _hasError, value)) OnPropertyChanged(nameof(ErrorVisibility)); }
    }

    public Visibility ErrorVisibility => HasError ? Visibility.Visible : Visibility.Collapsed;

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
        HasError = false;
        try
        {
            var page = await _loadPage(null);
            Posts.Clear();
            foreach (var dto in page.Posts) Posts.Add(new PostItem(dto));
            _cursor = page.Cursor;
            OnPropertyChanged(nameof(CanLoadMore));
            await ApplyThreadingAsync();
        }
        catch (Exception ex)
        {
            var (title, message) = DescribeFailure(ex);
            FailureTitle = title;
            FailureMessage = message;
            HasError = true;
        }
        finally { IsLoading = false; }
    }

    /// <summary>Retry the initial load (used by the failed-state 再試行 button).</summary>
    public Task RetryAsync() => LoadAsync();

    /// <summary>Map a thrown error to a friendly title/message, preferring the shared
    /// LoadFailure classification carried on a <see cref="BridgeException"/>.</summary>
    private static (string Title, string Message) DescribeFailure(Exception ex)
    {
        if (ex is BridgeException { Title: { } t } be)
        {
            return (t, be.FriendlyMessage ?? be.Message);
        }
        return ("読み込みに失敗しました", ex.Message);
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
            await ApplyThreadingAsync();
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
            await ApplyThreadingAsync();
        }
        catch { /* keep showing the current feed */ }
    }

    private bool Contains(string id)
    {
        foreach (var p in Posts) if (p.Id == id) return true;
        return false;
    }

    /// Regroup the current posts web-style: send each post's id, createdAt, and
    /// reply-parent id to the tested core (FeedThreading via yoru_feed_arrange),
    /// then reorder the collection in place with Move (preserving item containers
    /// and scroll) and stamp each row's connector flags.
    private async Task ApplyThreadingAsync()
    {
        if (Posts.Count == 0) return;
        var items = new List<object>(Posts.Count);
        foreach (var p in Posts)
        {
            items.Add(new { id = p.Id, createdAt = p.CreatedAt, replyParentId = p.ReplyParent?.Id });
        }

        List<ArrangeResultDto> arranged;
        try { arranged = await BridgeClient.Shared.FeedArrangeAsync(items); }
        catch { return; }
        if (arranged.Count != Posts.Count) return;

        var byId = new Dictionary<string, PostItem>(Posts.Count);
        foreach (var p in Posts) byId[p.Id] = p;

        for (var target = 0; target < arranged.Count; target++)
        {
            var a = arranged[target];
            if (!byId.TryGetValue(a.Id, out var item)) return;
            item.SetThreadConnectors(a.ConnectsToPrevious, a.ConnectsToNext);
            if (Posts[target].Id == a.Id) continue;
            var cur = IndexOf(a.Id);
            if (cur > target) Posts.Move(cur, target);
        }
    }

    private int IndexOf(string id)
    {
        for (var i = 0; i < Posts.Count; i++) if (Posts[i].Id == id) return i;
        return -1;
    }

    /// Optimistically remove the viewer's own post, then delete it through the
    /// bridge; restore the row at its original position if the delete fails.
    /// Mirrors the macOS TimelineViewModel.deletePost.
    public async Task DeletePostAsync(string id)
    {
        var index = IndexOf(id);
        if (index < 0) return;
        var removed = Posts[index];
        Posts.RemoveAt(index);
        try
        {
            await BridgeClient.Shared.DeletePostAsync(id);
        }
        catch
        {
            Posts.Insert(Math.Min(index, Posts.Count), removed);
        }
    }
}
