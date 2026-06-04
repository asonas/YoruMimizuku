import Foundation
import BlueskyCore

extension PostDisplay {
    /// Map a `BlueskyCore` feed item into the UI-facing `PostDisplay`. A repost
    /// `reason` becomes the context label; missing counts default to zero; the
    /// record's ISO8601 `createdAt` is parsed (with or without fractional seconds).
    public init(_ feedViewPost: FeedViewPost) {
        let post = feedViewPost.post
        let author = post.author
        let contextLabel = feedViewPost.reason.map { reason in
            "Reposted by \(reason.by.displayName ?? reason.by.handle)"
        }
        let images = (post.embed?.images ?? []).map { image in
            PostImage(
                thumbURL: URL(string: image.thumb),
                fullsizeURL: URL(string: image.fullsize),
                alt: image.alt
            )
        }
        // The parent is mapped on its own (no nested reason/reply); the timeline
        // only carries the immediate parent, deeper ancestry needs a thread fetch.
        let replyParent = feedViewPost.reply?.parent.map { parent in
            ReplyParent(PostDisplay(FeedViewPost(post: parent)))
        }
        self.init(
            id: post.uri,
            authorDisplayName: author.displayName ?? author.handle,
            authorHandle: author.handle,
            avatarURL: author.avatar.flatMap(URL.init(string:)),
            body: post.record.text,
            createdAt: Self.parseISO8601(post.record.createdAt) ?? Date(timeIntervalSince1970: 0),
            contextLabel: contextLabel,
            images: images,
            replyParent: replyParent,
            replyCount: post.replyCount ?? 0,
            repostCount: post.repostCount ?? 0,
            likeCount: post.likeCount ?? 0
        )
    }

    /// Parse an atproto timestamp, tolerating both fractional and whole-second forms.
    static func parseISO8601(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
