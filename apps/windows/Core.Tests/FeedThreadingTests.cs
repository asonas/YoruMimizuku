namespace YoruMimizuku.Core.Tests;

public class FeedThreadingTests
{
    private static ThreadingPost Post(string id, int createdAt, string author = "did:plc:a", string? parent = null) =>
        new(id, author, DateTimeOffset.FromUnixTimeSeconds(createdAt), parent);

    private static void AssertRows(
        IReadOnlyList<ThreadedFeedItem> items,
        string[] ids,
        bool[] connectsToPrevious,
        bool[] connectsToNext)
    {
        Assert.Equal(ids, items.Select(i => i.Id));
        Assert.Equal(connectsToPrevious, items.Select(i => i.ConnectsToPrevious));
        Assert.Equal(connectsToNext, items.Select(i => i.ConnectsToNext));
    }

    [Fact]
    public void PlainPostsKeepOrderWithoutConnections()
    {
        var items = FeedThreading.Arrange([Post("b", 200), Post("a", 100)]);

        AssertRows(items, ["b", "a"], [false, false], [false, false]);
    }

    [Fact]
    public void SelfThreadIsGroupedOldestFirst()
    {
        var items = FeedThreading.Arrange([Post("c3", 300, parent: "c2"), Post("c2", 200, parent: "c1"), Post("c1", 100)]);

        AssertRows(items, ["c1", "c2", "c3"], [false, true, true], [true, true, false]);
    }

    [Fact]
    public void GroupIsEmittedAtItsNewestMemberPosition()
    {
        var items = FeedThreading.Arrange([
            Post("x", 400),
            Post("c3", 300, parent: "c2"),
            Post("c2", 200, parent: "c1"),
            Post("y", 150),
            Post("c1", 100),
        ]);

        Assert.Equal(["x", "c1", "c2", "c3", "y"], items.Select(i => i.Id));
    }

    [Fact]
    public void ReplyWhoseParentIsNotInThePageStaysSingle()
    {
        var items = FeedThreading.Arrange([Post("o", 200), Post("r", 100, parent: "absent")]);

        AssertRows(items, ["o", "r"], [false, false], [false, false]);
    }

    [Fact]
    public void ParentAndReplyBySameAuthorConnect()
    {
        var items = FeedThreading.Arrange([Post("r", 200, parent: "p"), Post("p", 100)]);

        AssertRows(items, ["p", "r"], [false, true], [true, false]);
    }

    // The Swift bridge sent no authors, so Windows used to group this pair. Grouping
    // now requires the parent and the reply to share an author, as on macOS.
    [Fact]
    public void ReplyByAnotherAuthorDoesNotConnectToItsParent()
    {
        var items = FeedThreading.Arrange([Post("r", 200, author: "did:plc:b", parent: "p"), Post("p", 100)]);

        AssertRows(items, ["r", "p"], [false, false], [false, false]);
    }

    [Fact]
    public void DuplicatePostIdsAreEmittedOnce()
    {
        var items = FeedThreading.Arrange([Post("b", 200), Post("a", 100), Post("a", 100)]);

        Assert.Equal(["b", "a"], items.Select(i => i.Id));
    }

    [Fact]
    public void ParentCycleDoesNotHang()
    {
        // Two posts that (impossibly) name each other as parents must not loop; both render.
        var items = FeedThreading.Arrange([Post("b", 200, parent: "a"), Post("a", 100, parent: "b")]);

        Assert.Equal(["a", "b"], items.Select(i => i.Id).Order());
    }

    [Fact]
    public void MultiAuthorRepliesDoNotMergeIntoOneBlock()
    {
        // Root by A; replies to it by B and C. Each reply stays its own row.
        var items = FeedThreading.Arrange([
            Post("c", 300, author: "did:plc:c", parent: "root"),
            Post("b", 200, author: "did:plc:b", parent: "root"),
            Post("root", 100),
        ]);

        AssertRows(items, ["c", "b", "root"], [false, false, false], [false, false, false]);
    }

    [Fact]
    public void SelfThreadGroupsWhileForeignReplySplitsOff()
    {
        // A's root -> a2 stays one block; B's reply to a2 is its own row, emitted
        // first because its group comes first in page order.
        var items = FeedThreading.Arrange([
            Post("b", 300, author: "did:plc:b", parent: "a2"),
            Post("a2", 200, parent: "root"),
            Post("root", 100),
        ]);

        AssertRows(items, ["b", "root", "a2"], [false, false, true], [false, true, false]);
    }
}
