namespace YoruMimizuku.Core.Tests;

// Ported from core/Tests/YoruMimizukuKitTests/DetailPaneModelTests.swift (one page
// at a time, ADR 0022). The Swift cases about previews and the レコード tab have no
// Windows counterpart yet, and polling belongs to the view on Windows.
public class DetailPaneModelTests
{
    private sealed class Page(string name)
    {
        public string Name { get; } = name;
    }

    private static DetailEntry Conversation(int n) => new DetailEntry.Conversation($"at://a/{n}");

    private static void Open(DetailPaneModel<Page> pane, DetailEntry entry) =>
        pane.Open(entry, () => new Page(entry switch
        {
            DetailEntry.Conversation c => c.AnchorUri,
            DetailEntry.Author a => a.Actor,
            _ => throw new ArgumentOutOfRangeException(nameof(entry)),
        }));

    /// Reopening the shown conversation keeps its loaded page rather than
    /// rebuilding it.
    [Fact]
    public void OpeningTheShownPageAgainKeepsThePage()
    {
        var pane = new DetailPaneModel<Page>();
        Open(pane, Conversation(1));
        var shown = pane.Current;

        Open(pane, Conversation(1));

        Assert.Same(shown, pane.Current);
    }

    /// One page at a time, as in the desktop prototype: opening another
    /// replaces it.
    [Fact]
    public void OpeningAnotherPageReplacesTheShownOne()
    {
        var pane = new DetailPaneModel<Page>();
        Open(pane, Conversation(1));

        Open(pane, new DetailEntry.Author("did:plc:alice"));

        Assert.Equal("did:plc:alice", pane.Current?.Name);
    }

    [Fact]
    public void CloseEmptiesThePane()
    {
        var pane = new DetailPaneModel<Page>();
        Open(pane, Conversation(1));

        pane.Close();

        Assert.Null(pane.Current);
    }

    [Fact]
    public void ChangedIsRaisedOnlyWhenTheShownPageChanges()
    {
        var pane = new DetailPaneModel<Page>();
        var changes = 0;
        pane.Changed += () => changes++;

        Open(pane, Conversation(1));
        Open(pane, Conversation(1));
        Assert.Equal(1, changes);

        Open(pane, Conversation(2));
        pane.Close();
        pane.Close();
        Assert.Equal(3, changes);
    }
}
