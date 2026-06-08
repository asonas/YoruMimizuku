import Foundation
import BlueskyCore

/// A node in the conversation's child reply tree (below the anchor post). It is a
/// pure, value-typed display model: `post` is UI-ready, `replies` are the node's
/// own children (already capped by the builder), and `depth` is the render depth
/// where 0 is a direct reply of the anchor. Built by `childTree(of:maxDepth:)`.
public struct ThreadNode: Identifiable, Equatable, Sendable {
    public let post: PostDisplay
    public let replies: [ThreadNode]
    public let depth: Int

    public var id: String { post.id }

    public init(post: PostDisplay, replies: [ThreadNode], depth: Int) {
        self.post = post
        self.replies = replies
        self.depth = depth
    }

    /// Map the anchor's descendant `ThreadViewPost`s into a depth-tagged tree,
    /// preserving server order. Recursion stops once a node sits at `maxDepth`:
    /// such a node keeps `replies: []` so the view can show a "さらに表示" cue and
    /// re-anchor deeper. `maxDepth` is the deepest rendered depth (0-based), so
    /// `maxDepth: 3` renders depths 0, 1, 2, 3.
    public static func childTree(of node: ThreadViewPost, maxDepth: Int) -> [ThreadNode] {
        build(replies: node.replies, depth: 0, maxDepth: maxDepth)
    }

    private static func build(replies: [ThreadViewPost], depth: Int, maxDepth: Int) -> [ThreadNode] {
        replies.map { child in
            let deeper = depth < maxDepth
                ? build(replies: child.replies, depth: depth + 1, maxDepth: maxDepth)
                : []
            // A reply node needs no replyParent: its ancestor context is the anchor itself,
            // expressed by tree position (depth) rather than a per-post parent chain.
            return ThreadNode(
                post: PostDisplay(postView: child.post),
                replies: deeper,
                depth: depth
            )
        }
    }
}
