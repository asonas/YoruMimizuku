namespace YoruMimizuku.Core.Tests;

public class ThreadNodeTests
{
    private static ThreadViewPost Node(string uri, params ThreadViewPost[] replies) =>
        new(
            new PostView(
                uri,
                $"cid-{uri}",
                new ProfileViewBasic($"did:plc:{uri}", $"{uri}.example", null, null, false),
                new PostRecord($"t-{uri}", "2026-06-04T12:00:00.000Z", []),
                0,
                0,
                0,
                "2026-06-04T12:00:01.000Z",
                null,
                null,
                []),
            null,
            replies);

    [Fact]
    public void EmptyRepliesReturnEmptyTree()
    {
        Assert.Empty(ThreadNode.ChildTree(Node("anchor"), maxDepth: 3));
    }

    [Fact]
    public void MultipleChildrenPreserveServerOrder()
    {
        var tree = ThreadNode.ChildTree(Node("anchor", Node("b"), Node("c")), maxDepth: 3);

        Assert.Equal(["b", "c"], tree.Select(n => n.Post.Id));
        Assert.Equal([0, 0], tree.Select(n => n.Depth));
    }

    [Fact]
    public void NestedChildrenIncrementDepth()
    {
        var tree = ThreadNode.ChildTree(Node("anchor", Node("b", Node("c"))), maxDepth: 3);

        var b = Assert.Single(tree);
        Assert.Equal(0, b.Depth);
        var c = Assert.Single(b.Replies);
        Assert.Equal("c", c.Post.Id);
        Assert.Equal("t-c", c.Post.Body);
        Assert.Equal(1, c.Depth);
    }

    [Fact]
    public void MaxDepthTruncationLeavesRepliesEmpty()
    {
        // anchor -> b(0) -> c(1) -> d(2); with maxDepth 1, c sits at the cap so d is not built.
        var tree = ThreadNode.ChildTree(Node("anchor", Node("b", Node("c", Node("d")))), maxDepth: 1);

        Assert.Equal("b", tree[0].Post.Id);
        Assert.Equal("c", tree[0].Replies[0].Post.Id);
        Assert.Equal(1, tree[0].Replies[0].Depth);
        Assert.Empty(tree[0].Replies[0].Replies);
    }
}
