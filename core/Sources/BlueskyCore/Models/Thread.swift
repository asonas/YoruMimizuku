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

    /// The post's direct replies, in the order the server returned them. notFound /
    /// blocked children are dropped (they have no `post`), so this only carries
    /// viewable descendant nodes. Empty when the thread was fetched without
    /// descendants or the post has no viewable replies.
    public let replies: [ThreadViewPost]

    /// The next node up the reply tree, if any.
    public var parent: ThreadViewPost? { parentRef?.node }

    /// The hydrated immediate parent post, if any. Convenience over `parent.post`.
    public var parentPost: PostView? { parent?.post }

    public init(post: PostView, parent: ThreadViewPost? = nil, replies: [ThreadViewPost] = []) {
        self.post = post
        self.parentRef = parent.map(ParentNodeRef.init)
        self.replies = replies
    }

    /// Convenience initializer that wraps a bare parent post into a node. Kept so
    /// callers/tests can build a single-level thread without nesting by hand.
    public init(post: PostView, parentPost: PostView?) {
        self.init(post: post, parent: parentPost.map { ThreadViewPost(post: $0) })
    }

    enum CodingKeys: String, CodingKey { case post, parent, replies }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.post = try container.decode(PostView.self, forKey: .post)
        // A notFound/blocked parent has no `post`, so its decode throws and we
        // collapse it (and anything above it) to nil; a real parent recurses.
        let parent = (try? container.decodeIfPresent(ThreadViewPost.self, forKey: .parent)) ?? nil
        self.parentRef = parent.map(ParentNodeRef.init)
        // Replies are a union (threadViewPost | notFoundPost | blockedPost); the
        // non-viewable shapes have no `post` and decode to a nil box node, so we
        // drop them while preserving the server's ordering for the rest.
        let boxes = (try? container.decode([ReplyNodeBox].self, forKey: .replies)) ?? []
        self.replies = boxes.compactMap(\.node)
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

/// Wrapper that decodes one reply-list element tolerantly: a notFound / blocked
/// node has no `post`, so decoding it as `ThreadViewPost` throws and `node`
/// becomes nil rather than failing the whole reply list. Mirrors the
/// `FacetFeatureBox` idiom in `Timeline.swift`.
private struct ReplyNodeBox: Decodable {
    let node: ThreadViewPost?

    init(from decoder: Decoder) throws {
        self.node = try? ThreadViewPost(from: decoder)
    }
}
