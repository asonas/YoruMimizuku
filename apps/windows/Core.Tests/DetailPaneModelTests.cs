namespace YoruMimizuku.Core.Tests;

// Ported from core/Tests/YoruMimizukuKitTests/DetailPaneModelTests.swift as of
// 410a31f (ADR 0026, with back / forward). Polling is the view's job on Windows,
// so the Swift polling case has no counterpart here.
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

    [Fact]
    public void OpeningTheShownPageAgainKeepsItAndAddsNoHistory()
    {
        var pane = new DetailPaneModel<Page>();
        Open(pane, Conversation(1));
        var shown = pane.Current;

        Open(pane, Conversation(1));

        Assert.Same(shown, pane.Current);
        Assert.False(pane.CanGoBack);
    }

    [Fact]
    public void BackAndForwardMoveThroughOpenedPages()
    {
        var pane = new DetailPaneModel<Page>();
        Open(pane, Conversation(1));
        Open(pane, new DetailEntry.Author("did:plc:alice"));

        pane.GoBack();
        Assert.Equal("at://a/1", pane.Current?.Name);
        Assert.True(pane.CanGoForward);

        pane.GoForward();
        Assert.Equal("did:plc:alice", pane.Current?.Name);
        Assert.False(pane.CanGoForward);
    }

    [Fact]
    public void GoingBackShowsTheSamePageInstance()
    {
        var pane = new DetailPaneModel<Page>();
        Open(pane, Conversation(1));
        var first = pane.Current;
        Open(pane, Conversation(2));

        pane.GoBack();

        Assert.Same(first, pane.Current);
    }

    [Fact]
    public void OpeningAfterGoingBackDropsTheForwardPages()
    {
        var pane = new DetailPaneModel<Page>();
        Open(pane, Conversation(1));
        Open(pane, Conversation(2));
        pane.GoBack();

        Open(pane, Conversation(3));

        Assert.Equal("at://a/3", pane.Current?.Name);
        Assert.False(pane.CanGoForward);
        pane.GoBack();
        Assert.Equal("at://a/1", pane.Current?.Name);
    }

    [Fact]
    public void CloseEmptiesThePaneAndItsHistory()
    {
        var pane = new DetailPaneModel<Page>();
        Open(pane, Conversation(1));
        Open(pane, Conversation(2));

        pane.Close();

        Assert.Null(pane.Current);
        Assert.False(pane.CanGoBack);
        Assert.False(pane.CanGoForward);
    }

    [Fact]
    public void HistoryKeepsTheLatestThirtyPages()
    {
        var pane = new DetailPaneModel<Page>();
        for (var n = 1; n <= 31; n++) Open(pane, Conversation(n));

        while (pane.CanGoBack) pane.GoBack();

        Assert.Equal("at://a/2", pane.Current?.Name);
    }

    [Fact]
    public void ChangedIsRaisedOnlyWhenTheShownPageChanges()
    {
        var pane = new DetailPaneModel<Page>();
        var changes = 0;
        pane.Changed += () => changes++;

        Open(pane, Conversation(1));
        Open(pane, Conversation(1));
        pane.GoBack();
        pane.GoForward();
        Assert.Equal(1, changes);

        Open(pane, Conversation(2));
        pane.GoBack();
        pane.GoForward();
        pane.Close();
        pane.Close();
        Assert.Equal(5, changes);
    }
}
