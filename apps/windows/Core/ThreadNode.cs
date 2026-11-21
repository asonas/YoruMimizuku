namespace YoruMimizuku.Core;

/// <summary>
/// A node of a conversation's reply tree below the anchor post. <paramref name="Depth"/>
/// is 0 for a direct reply of the anchor. A node's position in the tree stands for its
/// parent, so <see cref="PostDisplay.ReplyParent"/> is not set.
/// </summary>
public sealed record ThreadNode(PostDisplay Post, IReadOnlyList<ThreadNode> Replies, int Depth)
{
    /// <summary>
    /// The anchor's replies as a tree in server order. <paramref name="maxDepth"/> is the
    /// deepest depth built, so 3 builds depths 0 to 3; a node at that depth keeps no
    /// replies, and the view offers to open it as the new anchor.
    /// </summary>
    public static IReadOnlyList<ThreadNode> ChildTree(ThreadViewPost anchor, int maxDepth) =>
        Build(anchor.Replies, 0, maxDepth);

    private static IReadOnlyList<ThreadNode> Build(IReadOnlyList<ThreadViewPost> replies, int depth, int maxDepth) =>
        replies
            .Select(child => new ThreadNode(
                PostDisplay.From(child.Post),
                depth < maxDepth ? Build(child.Replies, depth + 1, maxDepth) : [],
                depth))
            .ToList();
}
