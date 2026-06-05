import Foundation
import BlueskyCore

extension PostDisplay {
    /// Map a single hydrated `PostView` into the UI-facing `PostDisplay`. Counts
    /// default to zero; the record's ISO8601 `createdAt` is parsed (with or
    /// without fractional seconds). Shared by the feed and thread mappers.
    public init(postView post: PostView, replyParent: ReplyParent? = nil, contextLabel: String? = nil) {
        let author = post.author
        let images = (post.embed?.images ?? []).map { image in
            PostImage(
                thumbURL: URL(string: image.thumb),
                fullsizeURL: URL(string: image.fullsize),
                alt: image.alt
            )
        }
        self.init(
            id: post.uri,
            cid: post.cid,
            authorDisplayName: author.displayName ?? author.handle,
            authorHandle: author.handle,
            avatarURL: author.avatar.flatMap(URL.init(string:)),
            body: post.record.text,
            bodySegments: RichText.segments(text: post.record.text, facets: post.record.facets),
            createdAt: Self.parseISO8601(post.record.createdAt) ?? Date(timeIntervalSince1970: 0),
            contextLabel: contextLabel,
            images: images,
            replyParent: replyParent,
            replyCount: post.replyCount ?? 0,
            repostCount: post.repostCount ?? 0,
            likeCount: post.likeCount ?? 0,
            viewerLikeURI: post.viewer?.like,
            viewerRepostURI: post.viewer?.repost
        )
    }

    /// Map a `BlueskyCore` feed item into the UI-facing `PostDisplay`. A repost
    /// `reason` becomes the context label. The timeline only carries the immediate
    /// parent; deeper ancestry needs a thread fetch.
    public init(_ feedViewPost: FeedViewPost) {
        let contextLabel = feedViewPost.reason.map { reason in
            "Reposted by \(reason.by.displayName ?? reason.by.handle)"
        }
        let replyParent = feedViewPost.reply?.parent.map { parent in
            ReplyParent(PostDisplay(postView: parent))
        }
        self.init(postView: feedViewPost.post, replyParent: replyParent, contextLabel: contextLabel)
    }

    /// Map a `app.bsky.feed.getPostThread` node into a `PostDisplay`, recursively
    /// building the full `replyParent` chain so the conversation view can render
    /// every ancestor up to the thread root in one pass.
    public init(_ threadViewPost: ThreadViewPost) {
        let replyParent = threadViewPost.parent.map { parent in
            ReplyParent(PostDisplay(parent))
        }
        self.init(postView: threadViewPost.post, replyParent: replyParent)
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
