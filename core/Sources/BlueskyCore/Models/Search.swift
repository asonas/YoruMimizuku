import Foundation

/// Response of `app.bsky.feed.searchPosts`: a page of hydrated posts plus an
/// optional pagination cursor and total hit count. Only the fields YoruMimizuku
/// renders are modeled; unknown keys are ignored by `Decodable`. `PostView` is
/// shared with the timeline so the same `PostDisplay` mapper applies.
public struct SearchResponse: Decodable, Equatable, Sendable {
    public let posts: [PostView]
    public let cursor: String?
    public let hitsTotal: Int?

    public init(posts: [PostView], cursor: String? = nil, hitsTotal: Int? = nil) {
        self.posts = posts
        self.cursor = cursor
        self.hitsTotal = hitsTotal
    }
}
