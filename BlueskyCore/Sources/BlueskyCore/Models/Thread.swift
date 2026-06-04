import Foundation

/// Response of `app.bsky.feed.getPostThread`: the requested post wrapped in a
/// thread node. Only the focused post and its immediate parent are modeled —
/// climbing further up the tree is done by fetching the parent's own thread.
public struct ThreadResponse: Decodable, Equatable, Sendable {
    public let thread: ThreadViewPost

    public init(thread: ThreadViewPost) {
        self.thread = thread
    }
}

/// A node in a post thread (`app.bsky.feed.defs#threadViewPost`). `parentPost` is
/// the hydrated immediate parent, or nil when the parent is absent / not viewable
/// (notFound / blocked), so decoding never fails on those stub shapes.
public struct ThreadViewPost: Decodable, Equatable, Sendable {
    public let post: PostView
    public let parentPost: PostView?

    public init(post: PostView, parentPost: PostView? = nil) {
        self.post = post
        self.parentPost = parentPost
    }

    enum CodingKeys: String, CodingKey { case post, parent }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.post = try container.decode(PostView.self, forKey: .post)
        let parentNode = try? container.decodeIfPresent(ParentNode.self, forKey: .parent)
        self.parentPost = (parentNode ?? nil)?.post
    }
}

/// Decodes only the `post` of a parent thread node, yielding nil for notFound /
/// blocked parents that carry no hydrated post.
private struct ParentNode: Decodable {
    let post: PostView?

    private enum CodingKeys: String, CodingKey { case post }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.post = try? container.decodeIfPresent(PostView.self, forKey: .post)
    }
}
