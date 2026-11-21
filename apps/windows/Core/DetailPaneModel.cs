namespace YoruMimizuku.Core;

/// <summary>What the detail pane shows: one conversation or one author page.
/// Two entries that are equal are the same page.</summary>
public abstract record DetailEntry
{
    private DetailEntry() { }

    public sealed record Conversation(string AnchorUri) : DetailEntry;

    public sealed record Author(string Actor) : DetailEntry;
}

/// <summary>A conversation's two views in the pane (the prototype's スレッド / レコード).</summary>
public enum DetailTab { Thread, Record }

/// <summary>
/// The window's detail pane: one page at a time, as in the desktop prototype
/// (ADR 0022, no back / forward history). Opening another page replaces the shown
/// one, and the timeline stays in its own column. Port of the Swift
/// DetailPaneModel.
/// </summary>
public sealed class DetailPaneModel<TPage> where TPage : class
{
    private DetailEntry? _entry;

    /// <summary>Raised when the shown page or its tab changes.</summary>
    public event Action? Changed;

    public TPage? Current { get; private set; }

    /// <summary>Which view of a conversation is shown. Every page opens on its thread.</summary>
    public DetailTab Tab { get; private set; }

    /// <summary>Show <paramref name="entry"/> on its thread, making its page only when
    /// it is not the page already shown: the shown post opened again means "show its
    /// thread".</summary>
    public void Open(DetailEntry entry, Func<TPage> makePage) => Show(entry, makePage, DetailTab.Thread);

    /// <summary>Show a conversation on its レコード tab (レコードを表示).</summary>
    public void OpenRecord(DetailEntry.Conversation entry, Func<TPage> makePage) => Show(entry, makePage, DetailTab.Record);

    /// <summary>The bar's スレッド / レコード switch.</summary>
    public void ShowTab(DetailTab tab)
    {
        if (Current is null || Tab == tab) return;
        Tab = tab;
        Changed?.Invoke();
    }

    /// <summary>Empty the pane.</summary>
    public void Close()
    {
        if (Current is null) return;
        _entry = null;
        Current = null;
        Tab = DetailTab.Thread;
        Changed?.Invoke();
    }

    private void Show(DetailEntry entry, Func<TPage> makePage, DetailTab tab)
    {
        if (_entry == entry && Tab == tab) return;
        if (_entry != entry)
        {
            _entry = entry;
            Current = makePage();
        }
        Tab = tab;
        Changed?.Invoke();
    }
}
