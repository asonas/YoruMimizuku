import Foundation

/// Performs like / repost interactions against the network. The app wires a live
/// implementation backed by `PostService`; tests inject a fake. Abstracting the
/// side effect keeps the view models free of networking and Apple-framework
/// dependencies.
///
/// `like` / `repost` return the created record's AT-URI so the caller can store it
/// and later pass it to `removeLike` / `removeRepost` to undo the interaction.
public protocol PostInteracting: Sendable {
    func like(uri: String, cid: String) async throws -> String
    func removeLike(recordURI: String) async throws
    func repost(uri: String, cid: String) async throws -> String
    func removeRepost(recordURI: String) async throws
    /// Delete the viewer's own post (`app.bsky.feed.post`). `uri` is the post's
    /// AT-URI, which carries both the repo DID and the rkey the delete addresses.
    func deletePost(uri: String) async throws
}
