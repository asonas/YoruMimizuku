import Foundation

/// Response of `app.bsky.feed.getPosts`: the hydrated posts for the requested
/// URIs. The API may return fewer posts than requested (deleted/blocked), so the
/// caller must match by `uri` rather than assume order or count.
public struct GetPostsResponse: Decodable, Equatable, Sendable {
    public let posts: [PostView]

    public init(posts: [PostView]) {
        self.posts = posts
    }
}
