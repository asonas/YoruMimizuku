import Foundation
import BlueskyCore

extension PostVideo {
    /// Map a hydrated video embed to its display form: parse the poster URL and
    /// flatten the integer aspect ratio to a width/height quotient.
    public init(_ video: EmbedVideo) {
        self.init(
            thumbURL: video.thumbnail.flatMap(URL.init(string:)),
            alt: video.alt,
            aspectRatio: video.aspectRatio.flatMap { ratio in
                ratio.height > 0 ? Double(ratio.width) / Double(ratio.height) : nil
            }
        )
    }
}

extension PostImage {
    /// Map one hydrated embed image to its display form, parsing the URLs and
    /// flattening the integer aspect ratio to a width/height quotient.
    init(_ image: EmbedImage) {
        self.init(
            thumbURL: URL(string: image.thumb),
            fullsizeURL: URL(string: image.fullsize),
            alt: image.alt,
            aspectRatio: image.aspectRatio.flatMap { ratio in
                ratio.height > 0 ? Double(ratio.width) / Double(ratio.height) : nil
            }
        )
    }
}

extension QuotedPost {
    /// Map a quoted record to its display form. The quoted post's own media is
    /// gathered across its `embeds` array (a recordWithMedia quote reports the
    /// media embed separately from the record one).
    public init(_ record: EmbedRecord) {
        let author = record.author
        self.init(
            id: record.uri,
            cid: record.cid,
            authorDisplayName: author.displayName ?? author.handle,
            authorHandle: author.handle,
            avatarURL: author.avatar.flatMap(URL.init(string:)),
            body: record.value.text,
            createdAt: PostDisplay.parseISO8601(record.value.createdAt) ?? Date(timeIntervalSince1970: 0),
            images: record.embeds.flatMap(\.images).map(PostImage.init),
            video: record.embeds.compactMap(\.video).first.map(PostVideo.init)
        )
    }
}

extension PostDisplay {
    /// Map a single hydrated `PostView` into the UI-facing `PostDisplay`. Counts
    /// default to zero; the record's ISO8601 `createdAt` is parsed (with or
    /// without fractional seconds). Shared by the feed and thread mappers.
    public init(postView post: PostView, replyParent: ReplyParent? = nil, contextLabel: String? = nil) {
        let author = post.author
        let images = (post.embed?.images ?? []).map(PostImage.init)
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
            linkCard: post.embed?.external.flatMap(LinkCard.init),
            video: post.embed?.video.map(PostVideo.init),
            quote: post.embed?.record.map(QuotedPost.init),
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
    ///
    /// The two formatters are created once and reused. `ISO8601DateFormatter` is
    /// expensive to construct — building a pair per call was a top app-code hot
    /// spot in Time Profiler, since the feed maps every post through here. A shared
    /// instance is safe to read concurrently: `ISO8601DateFormatter.date(from:)` is
    /// thread-safe, and the feed mapping that calls this runs off the main actor.
    static func parseISO8601(_ string: String) -> Date? {
        fractionalISO8601Formatter.date(from: string)
            ?? plainISO8601Formatter.date(from: string)
    }

    private nonisolated(unsafe) static let fractionalISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated(unsafe) static let plainISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
