namespace YoruMimizuku.Core;

/// <summary>What the detail pane shows: one conversation or one author page.
/// Two entries that are equal are the same page.</summary>
public abstract record DetailEntry
{
    private DetailEntry() { }

    public sealed record Conversation(string AnchorUri) : DetailEntry;

    public sealed record Author(string Actor) : DetailEntry;
}

/// <summary>
/// The window's detail pane (ADR 0026): one page at a time with a browser-style
/// back / forward history. Pages stay in the history, so going back shows the
/// same page, as it was left. Port of the Swift DetailPaneModel as of 410a31f.
/// </summary>
public sealed class DetailPaneModel<TPage> where TPage : class
{
    /// <summary>Older pages beyond this are dropped so a long reading session does
    /// not keep every visited thread and author feed in memory.</summary>
    public const int HistoryLimit = 30;

    private readonly List<(DetailEntry Entry, TPage Page)> _history = new();
    private int _index = -1;

    /// <summary>Raised when the shown page changes.</summary>
    public event Action? Changed;

    public TPage? Current => _index >= 0 ? _history[_index].Page : null;

    public bool CanGoBack => _index > 0;

    public bool CanGoForward => _index + 1 < _history.Count;

    /// <summary>Show <paramref name="entry"/>, making its page only when it is not
    /// the page already shown. Opening after going back drops the pages ahead.</summary>
    public void Open(DetailEntry entry, Func<TPage> makePage)
    {
        if (_index >= 0 && _history[_index].Entry == entry) return;
        _history.RemoveRange(_index + 1, _history.Count - _index - 1);
        _history.Add((entry, makePage()));
        if (_history.Count > HistoryLimit) _history.RemoveRange(0, _history.Count - HistoryLimit);
        _index = _history.Count - 1;
        Changed?.Invoke();
    }

    public void GoBack()
    {
        if (!CanGoBack) return;
        _index--;
        Changed?.Invoke();
    }

    public void GoForward()
    {
        if (!CanGoForward) return;
        _index++;
        Changed?.Invoke();
    }

    /// <summary>Empty the pane and forget its history.</summary>
    public void Close()
    {
        if (_history.Count == 0) return;
        _history.Clear();
        _index = -1;
        Changed?.Invoke();
    }
}
