using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using YoruMimizuku.App.Interop;
using YoruMimizuku.App.Mvvm;

namespace YoruMimizuku.App.ViewModels;

/// <summary>
/// Loads a single post's thread. <see cref="Anchor"/> can be re-pointed at an
/// ancestor and reloaded, matching the macOS conversation re-anchor behaviour.
/// </summary>
public sealed class ThreadViewModel : ObservableObject
{
    public string Anchor { get; private set; }

    private PostItem? _focused;
    public PostItem? Focused { get => _focused; private set => SetProperty(ref _focused, value); }

    /// The descendant reply tree below the focused post (depth-tagged), mirroring
    /// the macOS conversation view's child tree.
    public IReadOnlyList<ThreadNodeDto> ReplyTree { get; private set; } = Array.Empty<ThreadNodeDto>();

    private bool _isLoading;
    public bool IsLoading { get => _isLoading; private set => SetProperty(ref _isLoading, value); }

    private string? _errorMessage;
    public string? ErrorMessage { get => _errorMessage; private set => SetProperty(ref _errorMessage, value); }

    public ThreadViewModel(string anchor) { Anchor = anchor; }

    public async Task LoadAsync()
    {
        IsLoading = true;
        ErrorMessage = null;
        try
        {
            var thread = await BridgeClient.Shared.ThreadLoadAsync(Anchor);
            Focused = new PostItem(thread.Focus);
            ReplyTree = thread.Replies;
        }
        catch (Exception ex) { ErrorMessage = ex.Message; }
        finally { IsLoading = false; }
    }

    public async Task ReanchorAsync(string uri)
    {
        Anchor = uri;
        OnPropertyChanged(nameof(Anchor));
        await LoadAsync();
    }
}
