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
/// The window's detail pane: one page at a time, as in the desktop prototype
/// (ADR 0022, no back / forward history). Opening another page replaces the shown
/// one, and the timeline stays in its own column. Port of the Swift
/// DetailPaneModel.
/// </summary>
public sealed class DetailPaneModel<TPage> where TPage : class
{
    private DetailEntry? _entry;

    /// <summary>Raised when the shown page changes.</summary>
    public event Action? Changed;

    public TPage? Current { get; private set; }

    /// <summary>Show <paramref name="entry"/>, making its page only when it is not
    /// the page already shown.</summary>
    public void Open(DetailEntry entry, Func<TPage> makePage)
    {
        if (_entry == entry) return;
        _entry = entry;
        Current = makePage();
        Changed?.Invoke();
    }

    /// <summary>Empty the pane.</summary>
    public void Close()
    {
        if (Current is null) return;
        _entry = null;
        Current = null;
        Changed?.Invoke();
    }
}
