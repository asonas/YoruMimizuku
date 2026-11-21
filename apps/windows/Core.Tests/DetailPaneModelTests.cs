namespace YoruMimizuku.Core.Tests;

// Ported from core/Tests/YoruMimizukuKitTests/DetailPaneModelTests.swift (one page
// at a time, ADR 0022). The Swift cases about previews have no Windows counterpart,
// and polling belongs to the view on Windows.
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

    private static void OpenRecord(DetailPaneModel<Page> pane, int n) =>
        pane.OpenRecord(new DetailEntry.Conversation($"at://a/{n}"), () => new Page($"at://a/{n}"));

    /// レコードを表示 opens the post on its レコード tab; any other page opens on its
    /// thread, and opening the shown post again means "show its thread".
    [Fact]
    public void OpeningARecordShowsTheRecordTabUntilAnotherPageOpens()
    {
        var pane = new DetailPaneModel<Page>();

        OpenRecord(pane, 1);
        Assert.Equal("at://a/1", pane.Current?.Name);
        Assert.Equal(DetailTab.Record, pane.Tab);

        Open(pane, Conversation(2));
        Assert.Equal(DetailTab.Thread, pane.Tab);

        OpenRecord(pane, 2);
        Open(pane, Conversation(2));
        Assert.Equal(DetailTab.Thread, pane.Tab);
    }

    /// Showing the record of the conversation already shown keeps its loaded page.
    [Fact]
    public void ShowingTheRecordOfTheShownConversationKeepsThePage()
    {
        var pane = new DetailPaneModel<Page>();
        Open(pane, Conversation(1));
        var shown = pane.Current;
        var changes = 0;
        pane.Changed += () => changes++;

        OpenRecord(pane, 1);

        Assert.Same(shown, pane.Current);
        Assert.Equal(DetailTab.Record, pane.Tab);
        Assert.Equal(1, changes);
    }

    /// The bar's スレッド / レコード switch, then the shown post opened again by URI
    /// (a quote or a reply marker): back to its thread.
    [Fact]
    public void OpeningTheShownPostAgainAfterTheSwitchReturnsToItsThread()
    {
        var pane = new DetailPaneModel<Page>();
        Open(pane, Conversation(1));
        pane.ShowTab(DetailTab.Record);

        Open(pane, Conversation(1));

        Assert.Equal(DetailTab.Thread, pane.Tab);
    }
}
