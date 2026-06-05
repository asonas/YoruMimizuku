import Foundation

/// Response of `app.bsky.feed.getPostThread`: the requested post wrapped in a
/// thread node. The node carries the full ancestor chain via nested `parent`
/// links, so the whole reply tree above the focused post can be rendered at once.
public struct ThreadResponse: Decodable, Equatable, Sendable {
    public let thread: ThreadViewPost

    public init(thread: ThreadViewPost) {
        self.thread = thread
    }
}

/// A node in a post thread (`app.bsky.feed.defs#threadViewPost`). `parent` is the
/// next node up the reply tree (recursively carrying its own ancestors), or nil
/// when the parent is absent / not viewable (notFound / blocked) — those stub
/// shapes decode to nil rather than failing the whole thread.
public struct ThreadViewPost: Decodable, Equatable, Sendable {
    public let post: PostView
    private let parentRef: ParentNodeRef?

    /// The next node up the reply tree, if any.
    public var parent: ThreadViewPost? { parentRef?.node }

    /// The hydrated immediate parent post, if any. Convenience over `parent.post`.
    public var parentPost: PostView? { parent?.post }

    public init(post: PostView, parent: ThreadViewPost? = nil) {
        self.post = post
        self.parentRef = parent.map(ParentNodeRef.init)
    }

    /// Convenience initializer that wraps a bare parent post into a node. Kept so
    /// callers/tests can build a single-level thread without nesting by hand.
    public init(post: PostView, parentPost: PostView?) {
        self.init(post: post, parent: parentPost.map { ThreadViewPost(post: $0) })
    }

    enum CodingKeys: String, CodingKey { case post, parent }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.post = try container.decode(PostView.self, forKey: .post)
        // A notFound/blocked parent has no `post`, so its decode throws and we
        // collapse it (and anything above it) to nil; a real parent recurses.
        let parent = (try? container.decodeIfPresent(ThreadViewPost.self, forKey: .parent)) ?? nil
        self.parentRef = parent.map(ParentNodeRef.init)
    }
}

/// Reference box that breaks the otherwise-recursive value type (`ThreadViewPost`
/// holding a `ThreadViewPost`). Immutable, so it stays `Sendable`.
public final class ParentNodeRef: Equatable, Sendable {
    public let node: ThreadViewPost

    public init(_ node: ThreadViewPost) {
        self.node = node
    }

    public static func == (lhs: ParentNodeRef, rhs: ParentNodeRef) -> Bool {
        lhs.node == rhs.node
    }
}
