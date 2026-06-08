import Foundation
import BlueskyCore

/// Builds the public bsky.app permalink for a post:
/// `https://bsky.app/profile/{handle-or-did}/post/{rkey}`.
///
/// The profile segment prefers the author handle, but falls back to the author
/// DID (extracted from the post's AT-URI `id`) when the handle is empty or the
/// sentinel `"handle.invalid"`. Returns nil when no rkey can be parsed or when
/// neither a usable handle nor a DID is available.
public enum PostPermalink {
    public static func url(for post: PostDisplay) -> URL? {
        guard let rkey = ATURI.rkey(post.id) else { return nil }
        let handle = post.authorHandle
        let usableHandle = (!handle.isEmpty && handle != "handle.invalid") ? handle : nil
        guard let profile = usableHandle ?? ATURI.repo(post.id) else { return nil }
        return URL(string: "https://bsky.app/profile/\(profile)/post/\(rkey)")
    }
}
